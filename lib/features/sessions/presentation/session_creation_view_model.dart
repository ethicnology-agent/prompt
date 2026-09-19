import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../capabilities/capabilities.dart';
import '../../connection/connection.dart';
import '../../queue/queue.dart';
import '../../chat/chat.dart';
import '../data/sessions_repository.dart';
import '../data/worktree_repository.dart';
import '../domain/session_worktree.dart';
import '../domain/open_code_project.dart';
import '../domain/session_launch.dart';
import '../domain/session_load_result.dart';

enum SessionCreationPhase { idle, loading, ready, creating, failed }

enum SessionCreationFailure {
  connection,
  unsupportedBackend,
  catalog,
  invalidOptions,
  queueUnavailable,
  creationUncertain;

  String get message => switch (this) {
    connection =>
      'Cannot verify this private server. Your draft has been kept.',
    unsupportedBackend => 'This server has not enabled that engine.',
    catalog =>
      'Cannot load this engine’s folders and execution choices. Your draft has been kept.',
    invalidOptions => 'Choose an available model and agent for this engine.',
    queueUnavailable =>
      'Session created, but its first prompt could not be confirmed in the queue. Retry saving this same draft; no new session will be created.',
    creationUncertain =>
      'The session could not be confirmed. Check the session list before creating another; your draft has been kept.',
  };
}

class SessionCreationState {
  const SessionCreationState({
    this.phase = SessionCreationPhase.idle,
    this.sourceProfile,
    this.profile,
    this.backends = const [],
    this.projects = const [],
    this.capabilities,
    this.backend,
    this.directory = '',
    this.title = '',
    this.draft = '',
    this.options = const PromptExecutionOptions(),
    this.failure,
    this.worktreePhase = WorktreePhase.idle,
    this.worktrees = const [],
    this.worktreeFailure,
    this.canCreateWorktree = false,
    this.queuePending = false,
  });

  final SessionCreationPhase phase;
  final ServerProfile? sourceProfile;
  final ServerProfile? profile;
  final List<AgentBackend> backends;
  final List<OpenCodeProject> projects;
  final OpenCodeCapabilities? capabilities;
  final AgentBackend? backend;
  final String directory;
  final String title;
  final String draft;
  final PromptExecutionOptions options;
  final SessionCreationFailure? failure;
  final WorktreePhase worktreePhase;
  final List<SessionWorktree> worktrees;
  final WorktreeFailure? worktreeFailure;
  final bool canCreateWorktree;
  final bool queuePending;

  bool get optionsValid {
    final choices = capabilities;
    if (options.isEmpty) return true;
    if (choices == null) return false;
    final effort = options.reasoningEffort;
    if (effort != null &&
        !choices.models.any(
          (model) =>
              model.isProviderConnected &&
              model.providerId == options.modelProviderId &&
              model.id == options.modelId &&
              model.executionOptions?.supports(effort) == true,
        )) {
      return false;
    }
    if (options.permissionModeId != null &&
        !choices.permissionModes.any(
          (mode) => mode.id == options.permissionModeId,
        )) {
      return false;
    }
    return (!options.hasModel ||
            choices.models.any(
              (model) =>
                  model.isProviderConnected &&
                  model.providerId == options.modelProviderId &&
                  model.id == options.modelId,
            )) &&
        (options.agentName == null ||
            choices.agents.any((agent) => agent.name == options.agentName));
  }

  bool get canCreate =>
      phase == SessionCreationPhase.ready &&
      worktreePhase != WorktreePhase.creating &&
      profile != null &&
      optionsValid &&
      (directory.trim().startsWith('/') ||
          RegExp(r'^[A-Za-z]:[\\/]').hasMatch(directory.trim()));
}

/// Isolated creation state: choosing another engine never changes the active
/// conversation, its capabilities, its queue or the catalog view model.
class SessionCreationViewModel extends ValueNotifier<SessionCreationState> {
  SessionCreationViewModel({
    required this._connections,
    required this._sessions,
    required CapabilitiesRepository capabilities,
    WorktreeRepository? worktrees,
    this._attachmentPicker,
    this._queueLaunch,
  }) : _worktreeRepository = worktrees,
       _capabilityRepository = capabilities,
       super(const SessionCreationState());

  final ConnectionRepository _connections;
  final SessionsRepository _sessions;
  final CapabilitiesRepository _capabilityRepository;
  final WorktreeRepository? _worktreeRepository;
  final AttachmentPicker? _attachmentPicker;
  final Future<bool> Function(SessionLaunch)? _queueLaunch;
  final ValueNotifier<List<PromptAttachment>> attachments = ValueNotifier(
    const [],
  );
  SessionLaunch? _pendingLaunch;
  bool _picking = false;
  bool get isPickingAttachments => _picking;

  Future<AttachmentPickResult> pickAttachments() async {
    final profile = _profile;
    final picker = _attachmentPicker;
    if (!_editable ||
        _picking ||
        profile == null ||
        picker == null ||
        !profile.capabilities.supports(BackendFeature.attachments)) {
      return const AttachmentPickCancelled();
    }
    final constraints = profile.capabilities.attachmentConstraints;
    if (profile.capabilities.supports(BackendFeature.imageAttachments) &&
        constraints == null) {
      return const AttachmentPickRejected(
        'Image limits are unavailable. Reconnect before attaching images.',
      );
    }
    final revision = _revision;
    _picking = true;
    try {
      final result =
          constraints != null && picker is ConstrainedAttachmentPicker
          ? await picker.pickWithConstraints(constraints)
          : await picker.pick();
      if (result case AttachmentsPicked(:final attachments)) {
        String? error;
        final selected = [...this.attachments.value, ...attachments];
        if (!_current(revision)) {
          for (final attachment in attachments) {
            attachment.release();
          }
          return const AttachmentPickCancelled();
        }
        if (constraints != null) {
          error = attachmentConstraintError(selected, constraints);
        }
        if (selected.length > PromptAttachment.maxAttachmentCount ||
            selected.any(
              (item) => item.byteCount > PromptAttachment.maxBytesPerAttachment,
            ) ||
            selected.fold<int>(0, (sum, item) => sum + item.byteCount) >
                PromptAttachment.maxTotalBytes) {
          error = 'Select up to 5 attachments totaling 25 MiB or less.';
        }
        if (error != null) {
          for (final attachment in attachments) {
            attachment.release();
          }
          return AttachmentPickRejected(error);
        }
        this.attachments.value = List.unmodifiable(selected);
        _publish();
      }
      return result;
    } finally {
      _picking = false;
    }
  }

  void removeAttachment(PromptAttachment attachment) {
    if (!_editable) return;
    attachment.release();
    attachments.value = attachments.value
        .where((item) => !identical(item, attachment))
        .toList();
    _publish();
  }

  void releaseAttachments() {
    if (_disposed) return;
    for (final attachment in attachments.value) {
      attachment.release();
    }
    attachments.value = const [];
    _publish();
  }

  void cancelPreparation() {
    if (_phase == SessionCreationPhase.creating) return;
    _revision++;
    _pendingLaunch = null;
    releaseAttachments();
    _failure = null;
    _phase = _profile == null
        ? SessionCreationPhase.idle
        : SessionCreationPhase.ready;
    _publish();
  }

  int _worktreeRevision = 0;
  WorktreePhase _worktreePhase = WorktreePhase.idle;
  List<SessionWorktree> _worktrees = const [];
  WorktreeFailure? _worktreeFailure;
  bool _canCreateWorktree = false;
  int _revision = 0;
  bool _disposed = false;
  ServerProfile? _source;
  ServerProfile? _profile;
  AgentBackend? _backend;
  List<AgentBackend> _backends = const [];
  List<OpenCodeProject> _projects = const [];
  OpenCodeCapabilities? _capabilities;
  SessionCreationPhase _phase = SessionCreationPhase.idle;
  SessionCreationFailure? _failure;
  String _directory = '';
  String _title = '';
  String _draft = '';
  PromptExecutionOptions _options = const PromptExecutionOptions();
  final Map<AgentBackend, PromptExecutionOptions> _engineOptions = {};

  Future<void> initialize(
    ServerProfile source, {
    String directory = '',
    String title = '',
    String draft = '',
    PromptExecutionOptions options = const PromptExecutionOptions(),
  }) async {
    if (!_editable) return;
    releaseAttachments();
    _resetWorktrees();
    final revision = ++_revision;
    _source = source;
    _profile = null;
    _backends = const [];
    _projects = const [];
    _capabilities = null;
    _backend = source.backend;
    _directory = directory;
    _title = title;
    _draft = draft;
    _options = options;
    _engineOptions.clear();
    _engineOptions[source.backend] = options;
    _failure = null;
    _phase = SessionCreationPhase.loading;
    _publish();
    final result = await _connections.availableBackends(source);
    if (!_current(revision)) return;
    switch (result) {
      case Err<List<AgentBackend>, ConnectionFailure>():
        _fail(SessionCreationFailure.connection);
      case Ok<List<AgentBackend>, ConnectionFailure>(:final value):
        _backends = value;
        if (value.isEmpty) {
          _fail(SessionCreationFailure.unsupportedBackend);
          return;
        }
        await selectBackend(
          value.contains(source.backend) ? source.backend : value.first,
        );
    }
  }

  Future<void> selectBackend(AgentBackend backend) async {
    final source = _source;
    if (!_editable || source == null) {
      return;
    }
    if (!_backends.contains(backend)) {
      _fail(SessionCreationFailure.unsupportedBackend);
      return;
    }
    if (_backend != backend) releaseAttachments();
    if (_backend != null) _engineOptions[_backend!] = _options;
    _resetWorktrees();
    final revision = ++_revision;
    _backend = backend;
    _options = _engineOptions[backend] ?? const PromptExecutionOptions();
    _profile = null;
    _capabilities = null;
    _projects = const [];
    _failure = null;
    _phase = SessionCreationPhase.loading;
    _publish();
    final prepared = await _connections.prepareBackend(source, backend);
    if (!_current(revision)) return;
    if (prepared is! ConnectionSucceeded || prepared.profile == null) {
      _fail(SessionCreationFailure.connection);
      return;
    }
    final profile = prepared.profile!;
    final catalog = await _sessions.load(profile);
    if (!_current(revision)) return;
    final capabilities = await _capabilityRepository.load(profile);
    if (!_current(revision)) return;
    if (catalog is! SessionsLoaded || capabilities is! CapabilitiesLoaded) {
      _fail(SessionCreationFailure.catalog);
      return;
    }
    _profile = profile;
    _projects = List.unmodifiable(catalog.projects);
    if (_directory.trim().isEmpty) {
      final known = _projects.where((project) => project.directory.isNotEmpty);
      _directory =
          (known.where((project) => project.id != 'global').firstOrNull ??
                  known.firstOrNull)
              ?.directory ??
          '';
    }
    _capabilities = capabilities.capabilities;
    _phase = SessionCreationPhase.ready;
    _publish();
  }

  void updateDirectory(String value) {
    if (_editable) {
      _resetWorktrees();
      _directory = value;
      _publish();
    }
  }

  void updateTitle(String value) {
    if (_editable) {
      _title = value;
      _publish();
    }
  }

  void updateDraft(String value) {
    if (_editable) {
      _draft = value;
      _publish();
    }
  }

  void updateOptions(PromptExecutionOptions value) {
    if (!_editable) return;
    _options = value;
    if (_backend != null) _engineOptions[_backend!] = value;
    _publish();
  }

  Future<SessionLaunch?> create({bool submitDraft = false}) async {
    if (_disposed || !value.canCreate) return null;
    if (_pendingLaunch case final pending?) return _queueCreatedLaunch(pending);
    if (attachments.value.any((attachment) => attachment.isReleased)) {
      return null;
    }
    final revision = ++_revision;
    final profile = _profile!;
    final directory = _directory.trim();
    final title = _title;
    final draft = _draft;
    final options = _options;
    final selectedAttachments = List<PromptAttachment>.unmodifiable(
      attachments.value,
    );
    _failure = null;
    _phase = SessionCreationPhase.creating;
    _publish();
    final result = await _sessions.create(profile, directory, title: title);
    if (!_current(revision)) return null;
    switch (result) {
      case Err():
        _fail(SessionCreationFailure.creationUncertain);
        return null;
      case Ok(:final value):
        // Creation was accepted. Never repeat it if remembering local metadata
        // fails: the launch still carries the authoritative new session.
        try {
          await _connections.rememberActiveProfile(profile);
        } on Exception {
          /* The accepted session remains usable. */
        }
        if (!_current(revision)) return null;
        final launch = SessionLaunch(
          profile: profile,
          session: value,
          draft: draft,
          options: options,
          submitDraft: submitDraft,
          attachments: selectedAttachments,
        );
        return _queueCreatedLaunch(launch);
    }
  }

  Future<SessionLaunch?> _queueCreatedLaunch(SessionLaunch launch) async {
    _pendingLaunch = launch;
    _phase = SessionCreationPhase.creating;
    _publish();
    var accepted = !launch.submitDraft || _queueLaunch == null;
    if (!accepted &&
        !launch.attachments.any((attachment) => attachment.isReleased)) {
      try {
        accepted = await _queueLaunch(launch);
      } on Exception {
        accepted = false;
      }
    }
    if (_disposed) return null;
    if (!accepted) {
      _phase = SessionCreationPhase.ready;
      _failure = SessionCreationFailure.queueUnavailable;
      _publish();
      return null;
    }
    _pendingLaunch = null;
    attachments.value = const [];
    _phase = SessionCreationPhase.idle;
    _failure = null;
    _publish();
    return launch;
  }

  Future<void> refreshWorktrees() async {
    final profile = _profile;
    final repository = _worktreeRepository;
    if (!_editable || profile == null) return;
    final revision = ++_worktreeRevision;
    _canCreateWorktree = false;
    _worktreeFailure = null;
    if (repository == null || !profile.backend.isGateway) {
      _worktreePhase = WorktreePhase.unsupported;
      _worktreeFailure = WorktreeFailure.unsupported;
      _publish();
      return;
    }
    _worktreePhase = WorktreePhase.loading;
    _publish();
    final result = await repository.load(profile, _directory.trim());
    if (_disposed || revision != _worktreeRevision) return;
    switch (result) {
      case Ok(:final value):
        _worktrees = value.worktrees;
        _canCreateWorktree = value.canCreate;
        _worktreePhase = WorktreePhase.ready;
      case Err(:final failure):
        _worktreeFailure = failure;
        _worktreePhase = failure == WorktreeFailure.unsupported
            ? WorktreePhase.unsupported
            : WorktreePhase.failed;
    }
    _publish();
  }

  void selectWorktree(SessionWorktree worktree) {
    if (!_editable || !_worktrees.contains(worktree)) return;
    _directory = worktree.directory;
    _worktreeRevision++;
    _publish();
  }

  Future<void> createWorktree(String name) async {
    final profile = _profile;
    final repository = _worktreeRepository;
    if (!_editable ||
        profile == null ||
        repository == null ||
        !_canCreateWorktree ||
        _worktreePhase != WorktreePhase.ready) {
      return;
    }
    final revision = ++_worktreeRevision;
    _worktreePhase = WorktreePhase.creating;
    _worktreeFailure = null;
    _publish();
    final result = await repository.create(profile, _directory.trim(), name);
    if (_disposed || revision != _worktreeRevision) return;
    switch (result) {
      case Ok(:final value):
        _worktrees = List.unmodifiable([..._worktrees, value]);
        _directory = value.directory;
        _worktreePhase = WorktreePhase.ready;
      case Err(:final failure):
        _worktreeFailure = failure;
        _canCreateWorktree = false;
        _worktreePhase = WorktreePhase.failed;
    }
    _publish();
  }

  void _resetWorktrees() {
    _worktreeRevision++;
    _worktreePhase = WorktreePhase.idle;
    _worktrees = const [];
    _worktreeFailure = null;
    _canCreateWorktree = false;
  }

  bool get _editable =>
      !_disposed &&
      _pendingLaunch == null &&
      _phase != SessionCreationPhase.creating &&
      _worktreePhase != WorktreePhase.creating;
  bool _current(int revision) => !_disposed && revision == _revision;
  void _fail(SessionCreationFailure failure) {
    _failure = failure;
    _phase = SessionCreationPhase.failed;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    value = SessionCreationState(
      phase: _phase,
      sourceProfile: _source,
      profile: _profile,
      backends: _backends,
      projects: _projects,
      capabilities: _capabilities,
      backend: _backend,
      directory: _directory,
      title: _title,
      draft: _draft,
      options: _options,
      failure: _failure,
      worktreePhase: _worktreePhase,
      worktrees: _worktrees,
      worktreeFailure: _worktreeFailure,
      canCreateWorktree: _canCreateWorktree,
      queuePending: _pendingLaunch != null,
    );
  }

  @override
  void dispose() {
    releaseAttachments();
    _disposed = true;
    _revision++;
    attachments.dispose();
    super.dispose();
  }
}
