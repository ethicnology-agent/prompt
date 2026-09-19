import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/connection.dart';
import '../../queue/queue.dart';
import '../../sessions/sessions.dart';
import '../data/chat_repository.dart';
import '../data/attachment_picker.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_page_result.dart';
import '../domain/chat_message.dart';
import '../domain/conversation_state.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import '../domain/prompt_attachment.dart';
import '../domain/session_artifacts.dart';
import '../domain/session_execution_state.dart';

sealed class ConversationUiState {
  const ConversationUiState();
}

enum ExecutionOptionsLoadState { ready, loading, failed }

class ConversationLoading extends ConversationUiState {
  const ConversationLoading();
}

class ConversationReady extends ConversationUiState {
  const ConversationReady(this.messages);

  final List<ChatMessage> messages;
}

class ConversationError extends ConversationUiState {
  const ConversationError(this.failure);

  final ChatFailure failure;
}

class ConversationHistoryUiState {
  const ConversationHistoryUiState({
    required this.hasMore,
    required this.loadingOlder,
    required this.limitedByServer,
    this.failure,
  });

  const ConversationHistoryUiState.initial()
    : hasMore = false,
      loadingOlder = false,
      limitedByServer = false,
      failure = null;

  final bool hasMore;
  final bool loadingOlder;
  final bool limitedByServer;
  final ChatFailure? failure;
}

/// Drives one conversation screen: the read-only message transcript (via
/// [ChatRepository]) and the durable per-session send queue (via
/// [QueuePromptsRepository] and [QueueSendCoordinator]).
///
/// Every prompt the composer submits is durably enqueued first; this view
/// model never calls [ChatRepository.sendPrompt] directly, so a send is
/// always subject to the queue's dispatch and abort rules. Queue action
/// failures are reported on [queueErrors] rather than held as persistent
/// state, since they describe a single rejected command, not the queue's
/// current shape.
///
/// [queueRepositoryProvider] and [queueCoordinatorProvider] are resolved
/// lazily, on the first call to [open], rather than eagerly at construction.
/// The queue's storage opens a real database connection (a background
/// isolate and platform file lookup), which this view model's owner should
/// not pay for before a conversation is actually opened.
class ConversationViewModel {
  ConversationViewModel({
    required this._chatRepository,
    required this._sessionsRepository,
    required this._queueRepositoryProvider,
    required this._queueCoordinatorProvider,
    required this._attachmentPicker,
  });

  final ChatRepository _chatRepository;
  final SessionsRepository _sessionsRepository;
  final Future<QueuePromptsRepository> Function() _queueRepositoryProvider;
  final Future<QueueSendCoordinator> Function() _queueCoordinatorProvider;
  final AttachmentPicker _attachmentPicker;

  /// Mutable presentation metadata, separate from the route's session identity.
  final ValueNotifier<OpenCodeSession?> sessionMetadata = ValueNotifier(null);
  final ValueNotifier<bool> renamingSession = ValueNotifier(false);
  bool _renameInFlight = false;
  bool _deleteInFlight = false;

  Future<SessionMutationResult?> deleteSession({
    required OpenCodeSession expectedSession,
    required ServerProfile expectedProfile,
  }) async {
    final profile = _profile;
    final session = _session;
    if (_disposed ||
        profile == null ||
        session == null ||
        _deleteInFlight ||
        _renameInFlight ||
        !identical(_requestedSession, session) ||
        !identical(_requestedProfile, profile) ||
        !identical(expectedSession, session) ||
        !identical(expectedProfile, profile) ||
        !profile.capabilities.supports(BackendFeature.sessionDelete)) {
      return null;
    }
    _deleteInFlight = true;
    try {
      final result = await _sessionsRepository.delete(profile, session);
      if (!_disposed && result is Ok<void, SessionsFailure>) {
        _sessionInputMemories.remove((profile.id, session.id));
      }
      return result;
    } finally {
      _deleteInFlight = false;
    }
  }

  Future<SessionMutationResult?> renameSession(
    String title, {
    OpenCodeSession? expectedSession,
    ServerProfile? expectedProfile,
  }) async {
    final profile = _profile;
    final session = _session;
    if (_disposed ||
        profile == null ||
        session == null ||
        _renameInFlight ||
        _deleteInFlight ||
        !identical(_requestedSession, session) ||
        !identical(_requestedProfile, profile) ||
        (expectedSession != null && !identical(expectedSession, session)) ||
        (expectedProfile != null && !identical(expectedProfile, profile)) ||
        !profile.capabilities.supports(BackendFeature.sessionRename)) {
      return null;
    }
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 256) {
      return const Err(SessionsFailure.unexpectedResponse);
    }
    if (normalized == sessionMetadata.value?.title) return const Ok(null);
    final revision = _optionsLoadRevision;
    _renameInFlight = true;
    renamingSession.value = true;
    try {
      final result = await _sessionsRepository.rename(
        profile,
        session,
        normalized,
      );
      if (!_disposed &&
          revision == _optionsLoadRevision &&
          _profile == profile &&
          _session == session &&
          result is Ok<void, SessionsFailure>) {
        sessionMetadata.value = session.withTitle(normalized);
      }
      return result;
    } finally {
      _renameInFlight = false;
      if (!_disposed) renamingSession.value = false;
    }
  }

  QueuePromptsRepository? _queueRepository;
  QueueSendCoordinator? _queueCoordinator;

  // Drafts can contain private prompt text, so they remain memory-only. The
  // view model outlives individual conversation screens and keeps one buffer
  // per server session until the user submits it or the view model is disposed.
  final Map<(String, String), _SessionInputMemory> _sessionInputMemories = {};
  final ValueNotifier<ExecutionOptionsLoadState> executionOptionsLoad =
      ValueNotifier(ExecutionOptionsLoadState.ready);
  int _optionsLoadRevision = 0;

  PromptExecutionOptions executionOptionsFor(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    final remembered =
        _sessionInputMemories[(profile.id, session.id)]?.executionOptions;
    return remembered ??
        PromptExecutionOptions(
          modelProviderId: session.modelProviderId,
          modelId: session.modelId,
          agentName: session.agentName,
        );
  }

  void rememberExecutionOptions(
    ServerProfile profile,
    OpenCodeSession session,
    PromptExecutionOptions options,
  ) {
    final memory = _sessionInputMemories.putIfAbsent((
      profile.id,
      session.id,
    ), _SessionInputMemory.new);
    memory.executionOptions = options;
  }

  String draftFor(ServerProfile profile, OpenCodeSession session) =>
      _sessionInputMemories[(profile.id, session.id)]?.draft ?? '';

  void rememberDraft(
    ServerProfile profile,
    OpenCodeSession session,
    String draft,
  ) {
    final key = (profile.id, session.id);
    final memory = _sessionInputMemories.putIfAbsent(
      key,
      _SessionInputMemory.new,
    );
    memory.draft = draft;
    if (draft.isEmpty && memory.executionOptions == null) {
      _sessionInputMemories.remove(key);
    }
  }

  /// The read-only message transcript, refreshed by [open] and [reload].
  final ValueNotifier<ConversationUiState> messages = ValueNotifier(
    const ConversationLoading(),
  );

  /// The session's todos and file diffs, fetched on open and on demand.
  final ValueNotifier<SessionArtifactsState> artifacts = ValueNotifier(
    const SessionArtifactsLoading(),
  );

  /// The active session's durable queue, in dispatch order.
  final ValueNotifier<List<QueuedPrompt>> queue = ValueNotifier(
    const <QueuedPrompt>[],
  );

  /// Memory-only files selected for the active composer. They never enter the
  /// durable prompt queue because OpenCode currently offers no upload or
  /// durable file-reference protocol.
  final ValueNotifier<List<PromptAttachment>> attachments = ValueNotifier(
    const <PromptAttachment>[],
  );

  /// The active session's pending permission or question, for a
  /// non-dismissible approval dock/sheet to render. `null` whenever
  /// nothing needs a human decision. Mirrors
  /// [QueueSendCoordinator.currentPendingApproval]; see `pending_approval.
  /// dart` for why this must never be logged or persisted. Cleared in
  /// [leave] and [dispose] for the same reason [_liveConversationState]
  /// is.
  final ValueNotifier<PendingApproval?> pendingApproval = ValueNotifier(null);

  /// The active session's live SSE connection status, mirrored from
  /// [QueueSendCoordinator.connectionState] so the conversation UI can
  /// show a connection/reconnecting indicator without reaching past this
  /// view model into the coordinator itself.
  final ValueNotifier<SseConnectionState> connectionState = ValueNotifier(
    const SseSuspended(),
  );

  /// The server execution state, separate from the SSE transport state.
  final ValueNotifier<SessionExecutionState> executionState = ValueNotifier(
    const SessionExecutionUnknown(),
  );

  /// Whether a reconciliation is running over an already-visible transcript,
  /// so the UI can float a progress indicator instead of replacing it.
  final ValueNotifier<bool> refreshing = ValueNotifier(false);

  /// Pagination state translated into presentation-owned values.
  final ValueNotifier<ConversationHistoryUiState> history = ValueNotifier(
    const ConversationHistoryUiState.initial(),
  );

  final StreamController<String> _queueErrors =
      StreamController<String>.broadcast();

  final StreamController<String> _transcriptErrors =
      StreamController<String>.broadcast();

  /// User-facing messages for a refresh that failed while a transcript was
  /// already visible; the visible transcript is kept as-is.
  Stream<String> get transcriptErrors => _transcriptErrors.stream;

  /// User-facing messages for a rejected queue command (enqueue, remove, or
  /// send now). Each event describes one rejected command; it is not
  /// retained as state.
  Stream<String> get queueErrors => _queueErrors.stream;

  ServerProfile? _profile;
  OpenCodeSession? _session;
  OpenCodeSession? _requestedSession;
  ServerProfile? _requestedProfile;
  StreamSubscription<List<QueuedPrompt>>? _queueSubscription;

  /// The open session's live conversation state, as exposed by
  /// [QueueSendCoordinator.conversationStateUpdates]. Cleared in [leave]
  /// and [dispose] so a rebuild from a session this view model has since
  /// left can never reach [_applyLiveConversationState].
  ValueListenable<ConversationState>? _liveConversationState;
  VoidCallback? _liveConversationStateListener;
  Timer? _liveRenderTimer;
  ConversationState? _pendingLiveRender;

  /// The open session's live connection status, as exposed by
  /// [QueueSendCoordinator.connectionState]. Cleared in [leave] and
  /// [dispose] for the same reason as [_liveConversationState].
  ValueListenable<SseConnectionState>? _remoteConnectionState;
  VoidCallback? _remoteConnectionStateListener;
  SessionExecutionState? _lastSessionExecutionState;

  bool _disposed = false;
  VoidCallback? _historyListener;
  int _artifactGeneration = 0;

  /// Loads [session]'s transcript, activates queue coordination for it, and
  /// starts watching its durable queue. Tears down any previously open
  /// session first, mirroring [QueueSendCoordinator]'s single-active-session
  /// rule.
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    final optionsRevision = ++_optionsLoadRevision;
    executionOptionsLoad.value = ExecutionOptionsLoadState.loading;
    _requestedSession = session;
    _requestedProfile = profile;
    messages.value = const ConversationLoading();
    history.value = const ConversationHistoryUiState.initial();
    artifacts.value = const SessionArtifactsLoading();
    queue.value = const <QueuedPrompt>[];
    pendingApproval.value = null;
    refreshing.value = false;
    await _leaveCurrentSession();
    if (_disposed ||
        _requestedSession != session ||
        optionsRevision != _optionsLoadRevision) {
      return;
    }
    _profile = profile;
    _session = session;
    sessionMetadata.value = session;
    _attachHistoryListener();

    final queueRepository = _queueRepository ??=
        await _queueRepositoryProvider();
    final queueCoordinator = _queueCoordinator ??=
        await _queueCoordinatorProvider();
    if (_disposed ||
        _session != session ||
        optionsRevision != _optionsLoadRevision) {
      return;
    }

    final key = (profile.id, session.id);
    if (_sessionInputMemories[key]?.executionOptions == null) {
      final result = await queueRepository.latestExecutionOptions(
        profile: profile,
        session: session,
      );
      if (_disposed ||
          optionsRevision != _optionsLoadRevision ||
          _profile?.id != profile.id ||
          _session != session) {
        return;
      }
      // A selection made during the read (including an explicit default reset)
      // wins over older durable history.
      if (_sessionInputMemories[key]?.executionOptions == null) {
        switch (result) {
          case Ok<PromptExecutionOptions?, QueueFailure>(:final value):
            if (value != null) {
              rememberExecutionOptions(profile, session, value);
            }
          case Err<PromptExecutionOptions?, QueueFailure>():
            executionOptionsLoad.value = ExecutionOptionsLoadState.failed;
            messages.value = const ConversationError(
              ChatFailure.unexpectedResponse,
            );
            return;
        }
      }
    }
    executionOptionsLoad.value = ExecutionOptionsLoadState.ready;

    _queueSubscription = queueRepository
        .watchQueue(profile: profile, session: session)
        .listen((rows) {
          if (_disposed) {
            return;
          }
          queue.value = rows;
        });

    // Activate coordination first: it installs the repository's SSE journal
    // before the REST snapshot begins, so no event can fall between them.
    await queueCoordinator.activate(profile: profile, session: session);
    await _loadMessages();
    if (_disposed || _session != session) {
      return;
    }

    // Subscribed before the REST load below so no live event is ever
    // missed while it is in flight; any event reduced during that window
    // is still reconciled from the coordinator's authoritative snapshot
    // once the load finishes (see `_loadMessages`).
    final liveConversationState = queueCoordinator.conversationStateUpdates;
    void onLiveConversationStateChanged() {
      if (_disposed || _session != session) {
        // This session is no longer the one open in this view model
        // (left, or superseded by a faster-finishing `open` for another
        // session); never apply its live state to the visible transcript.
        return;
      }
      _scheduleLiveConversationRender(liveConversationState.value);
      pendingApproval.value =
          liveConversationState.value.pendingApprovals[session.id];
      final nextState = liveConversationState.value.sessionStates[session.id];
      if (nextState is SessionIdle &&
          _lastSessionExecutionState is! SessionIdle) {
        if (_lastSessionExecutionState is SessionBusy ||
            _lastSessionExecutionState is SessionRetrying) {
          unawaited(_loadMessages());
        }
        unawaited(_loadArtifacts());
      }
      _lastSessionExecutionState = nextState;
      executionState.value = nextState ?? const SessionExecutionUnknown();
    }

    _liveConversationState = liveConversationState;
    _liveConversationStateListener = onLiveConversationStateChanged;
    liveConversationState.addListener(onLiveConversationStateChanged);
    // `activate` may have already reduced a block (and its detail) before
    // this listener was attached; pick that up now rather than waiting
    // for the next SSE event to change it.
    _scheduleLiveConversationRender(liveConversationState.value);
    pendingApproval.value = queueCoordinator.currentPendingApproval;
    _lastSessionExecutionState = queueCoordinator.currentSessionState;
    executionState.value =
        queueCoordinator.currentSessionState ?? const SessionExecutionUnknown();

    // Mirrors the coordinator's connection status so the conversation UI
    // can render it, and — the moment a reconnect starts reconciling —
    // re-fetches the transcript over REST rather than trusting whatever
    // the live state accumulated across the drop. Queue dispatch is
    // separately held by the coordinator itself for the same window; see
    // `QueueSendCoordinator._maybeDispatch`.
    final remoteConnectionState = queueCoordinator.connectionState;
    void onRemoteConnectionStateChanged() {
      if (_disposed || _session != session) {
        return;
      }
      final next = remoteConnectionState.value;
      connectionState.value = next;
    }

    _remoteConnectionState = remoteConnectionState;
    _remoteConnectionStateListener = onRemoteConnectionStateChanged;
    remoteConnectionState.addListener(onRemoteConnectionStateChanged);
    connectionState.value = remoteConnectionState.value;

    // Artifacts enrich the conversation but must never delay its first frame.
    unawaited(_loadArtifacts());
  }

  /// Re-fetches the transcript for the currently open session.
  Future<void> reload() => _loadMessages();

  Future<void> loadOlderFromUserAction() async {
    final profile = _profile;
    final session = _session;
    if (profile == null ||
        session == null ||
        history.value.loadingOlder ||
        !history.value.hasMore) {
      return;
    }
    final result = await _chatRepository.loadOlder(profile, session);
    if (_disposed || _session != session) return;
    switch (result) {
      case ChatOlderLoaded():
        _mirrorHistory(_chatRepository.historyUpdates.value);
      case ChatLoaded():
        _mirrorHistory(_chatRepository.historyUpdates.value);
      case ChatLoadFailed(:final failure):
        _mirrorHistory(_chatRepository.historyUpdates.value, failure: failure);
        _transcriptErrors.add(failure.message);
    }
  }

  /// Reconciles every server-owned conversation surface from a direct user
  /// gesture without affecting the local send queue.
  Future<void> refreshFromUserAction() =>
      Future.wait([_loadMessages(), _loadArtifacts()]);

  /// Re-fetches todos and the session diff. [messageId] narrows the diff to
  /// the point OpenCode associates with that message when supplied.
  Future<void> reloadArtifacts({String? messageId}) =>
      _loadArtifacts(messageId: messageId);

  Future<SessionCreateResult?> fork() {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return Future.value(null);
    }
    return _sessionsRepository.fork(profile, session);
  }

  Future<SessionShareResult?> share() {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return Future.value(null);
    }
    return _sessionsRepository.share(profile, session);
  }

  Future<SessionsFailure?> unshare() async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return SessionsFailure.unexpectedResponse;
    }
    final result = await _sessionsRepository.unshare(profile, session);
    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
  }

  Future<SessionsFailure?> revert(String messageId) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null || messageId.isEmpty) {
      return SessionsFailure.unexpectedResponse;
    }
    final result = await _sessionsRepository.revert(
      profile,
      session,
      messageId,
    );
    return switch (result) {
      Ok(:final value) when value => await _refreshAfterRevert(messageId),
      Ok() => SessionsFailure.unexpectedResponse,
      Err(:final failure) => failure,
    };
  }

  Future<SessionsFailure?> _refreshAfterRevert(String messageId) async {
    await Future.wait([_loadMessages(), _loadArtifacts(messageId: messageId)]);
    return null;
  }

  void retryConnection() => _queueCoordinator?.retryConnection();

  Future<void> _loadMessages() async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return;
    }
    // Reloading an already-visible transcript keeps it on screen and only
    // reports progress, so the reader never loses their place — and the whole
    // transcript is not rebuilt from an empty state.
    final hadTranscript = messages.value is ConversationReady;
    if (hadTranscript) {
      refreshing.value = true;
    } else {
      messages.value = const ConversationLoading();
    }
    final result = await _chatRepository.load(profile, session);
    if (_disposed || _session != session) {
      return;
    }
    refreshing.value = false;
    switch (result) {
      case ChatLoaded(messages: final loadedMessages):
        messages.value = ConversationReady(loadedMessages);
        _mirrorHistory(_chatRepository.historyUpdates.value);
      case ChatOlderLoaded():
        _mirrorHistory(_chatRepository.historyUpdates.value);
      case ChatLoadFailed(:final failure):
        // A failed refresh must not discard a readable transcript.
        if (hadTranscript) {
          _transcriptErrors.add(failure.message);
        } else {
          messages.value = ConversationError(failure);
        }
        _mirrorHistory(_chatRepository.historyUpdates.value, failure: failure);
    }
  }

  Future<void> _loadArtifacts({String? messageId}) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return;
    }
    if (!profile.capabilities.supports(BackendFeature.sessionArtifacts)) {
      artifacts.value = const SessionArtifactsReady(todos: [], diffs: []);
      return;
    }
    final generation = ++_artifactGeneration;
    artifacts.value = const SessionArtifactsLoading();
    final result = await _chatRepository.loadArtifacts(
      profile,
      session,
      messageId: messageId,
    );
    if (_disposed || _session != session || generation != _artifactGeneration) {
      return;
    }
    artifacts.value = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => SessionArtifactsError(failure),
    };
  }

  /// Displays the already-consolidated repository projection.
  void _applyLiveConversationState(ConversationState liveState) {
    messages.value = ConversationReady(
      _chatRepository.conversationUpdates.value.messages,
    );
  }

  /// Coalesces bursty token/tool events into a visual update every 60ms. The
  /// coordinator still reduces each event immediately, so queue safety and
  /// approval handling are never delayed by this display optimisation.
  void _scheduleLiveConversationRender(ConversationState liveState) {
    _pendingLiveRender = liveState;
    if (_liveRenderTimer != null) {
      return;
    }
    _liveRenderTimer = Timer(const Duration(milliseconds: 60), () {
      _liveRenderTimer = null;
      final pending = _pendingLiveRender;
      _pendingLiveRender = null;
      if (pending != null && !_disposed && _session != null) {
        _applyLiveConversationState(pending);
      }
    });
  }

  /// Durably enqueues [text] for the open session. Never sends directly:
  /// dispatch timing is entirely owned by [QueueSendCoordinator].
  Future<bool> enqueuePrompt(
    String text, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    if (executionOptionsLoad.value != ExecutionOptionsLoadState.ready) {
      return false;
    }
    // The composer's selection is copied into the durable queue record, so
    // the memory-only buffers can be released as soon as it is stored.
    final selected = List<PromptAttachment>.of(attachments.value);
    final validation = _validateAttachmentSelection(selected);
    if (validation != null) {
      _queueErrors.add(validation);
      return false;
    }
    final queuedAttachments = [
      for (final attachment in selected)
        QueuedAttachment(
          name: attachment.name,
          mediaType: attachment.mediaType,
          bytes: Uint8List.fromList(attachment.bytes),
        ),
    ];
    final profile = _profile;
    final session = _session;
    final queueRepository = _queueRepository;
    if (profile == null || session == null || queueRepository == null) {
      return false;
    }
    final result = await queueRepository.enqueue(
      profile: profile,
      session: session,
      promptText: text,
      attachments: queuedAttachments,
      executionOptions: executionOptions,
    );
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    _releaseAttachments(selected);
    if (!_disposed) {
      attachments.value = attachments.value
          .where((attachment) => !selected.contains(attachment))
          .toList(growable: false);
    }
    return true;
  }

  /// Appends a queued prompt's text to the prompt directly above it and
  /// removes it, so both are delivered as a single turn instead of two
  /// separate deferred sends. Only plain prompts that are still editable can
  /// be merged; commands and in-flight prompts are rejected with a message.
  Future<void> mergeIntoPrevious(String promptId) async {
    final repository = _queueRepository;
    if (repository == null) {
      return;
    }
    final prompts = queue.value
        .where((prompt) => prompt.state != QueuedPromptState.acknowledged)
        .toList(growable: false);
    final index = prompts.indexWhere((prompt) => prompt.id == promptId);
    if (index <= 0) {
      _queueErrors.add('There is no earlier prompt to merge this one into.');
      return;
    }
    final source = prompts[index];
    final target = prompts[index - 1];
    if (source.pauseReason == QueuePauseReason.submissionUnknown ||
        target.pauseReason == QueuePauseReason.submissionUnknown) {
      _queueErrors.add(
        'Delivery is unconfirmed. Check the conversation before removing '
        'the local queue item; it cannot be merged.',
      );
      return;
    }
    if (!_canMerge(source) || !_canMerge(target)) {
      _queueErrors.add('Only queued prompts can be merged.');
      return;
    }
    if (source.attachments.isNotEmpty) {
      _queueErrors.add(
        'Attachments cannot be merged. Keep this prompt separate.',
      );
      return;
    }
    final merged = await repository.merge(
      targetId: target.id,
      sourceId: source.id,
    );
    if (merged case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  bool _canMerge(QueuedPrompt prompt) {
    return prompt.operationType == QueuedOperationType.prompt &&
        (prompt.state == QueuedPromptState.queued ||
            prompt.state == QueuedPromptState.paused ||
            prompt.state == QueuedPromptState.failed);
  }

  /// Invoked only by the composer's explicit attachment control.
  Future<AttachmentPickResult> pickAttachments() async {
    if (_disposed) {
      return const AttachmentPickCancelled();
    }
    final profile = _profile;
    final session = _session;
    final constraints = profile?.capabilities.attachmentConstraints;
    if (profile?.capabilities.supports(BackendFeature.imageAttachments) ==
            true &&
        constraints == null) {
      return const AttachmentPickRejected(
        'Image limits are unavailable. Reconnect before attaching images.',
      );
    }
    final picker = _attachmentPicker;
    final result = constraints != null && picker is ConstrainedAttachmentPicker
        ? await picker.pickWithConstraints(constraints)
        : await picker.pick();
    if (_disposed ||
        !identical(profile, _profile) ||
        !identical(session, _session)) {
      if (result case AttachmentsPicked(:final attachments)) {
        _releaseAttachments(attachments);
      }
      return const AttachmentPickCancelled();
    }
    if (result case AttachmentsPicked(:final attachments)) {
      final current = this.attachments.value;
      final validation = _validateAttachmentSelection([
        ...current,
        ...attachments,
      ]);
      if (validation != null) {
        _releaseAttachments(attachments);
        return AttachmentPickRejected(validation);
      }
      final combinedCount = current.length + attachments.length;
      final combinedBytes =
          current.fold<int>(
            0,
            (total, attachment) => total + attachment.byteCount,
          ) +
          attachments.fold<int>(
            0,
            (total, attachment) => total + attachment.byteCount,
          );
      if (combinedCount > PromptAttachment.maxAttachmentCount ||
          combinedBytes > PromptAttachment.maxTotalBytes) {
        _releaseAttachments(attachments);
        return const AttachmentPickRejected(
          'Keep up to 5 attachments totaling 25 MiB or less.',
        );
      }
      this.attachments.value = [...current, ...attachments];
    }
    return result;
  }

  String? _validateAttachmentSelection(List<PromptAttachment> selected) {
    if (selected.isEmpty) return null;
    final capabilities = _profile?.capabilities;
    if (capabilities?.supports(BackendFeature.imageAttachments) == true) {
      final constraints = capabilities?.attachmentConstraints;
      if (constraints == null) {
        return 'Image limits are unavailable. Reconnect before attaching images.';
      }
      return attachmentConstraintError(selected, constraints);
    }
    return null;
  }

  void removeAttachment(PromptAttachment attachment) {
    final current = attachments.value;
    if (!current.contains(attachment)) {
      return;
    }
    attachment.release();
    attachments.value = current
        .where((candidate) => !identical(candidate, attachment))
        .toList(growable: false);
  }

  /// Discards every memory-only attachment. Called after a cancelled or
  /// rejected attached submission, on lifecycle inactivity, and on teardown.
  void releaseAttachments() {
    _releaseAttachments(attachments.value);
    attachments.value = const <PromptAttachment>[];
  }

  /// Durably enqueues a slash command. Commands share the prompt queue so a
  /// busy session never loses or implicitly aborts active work.
  Future<bool> enqueueCommand(
    String commandName,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    if (executionOptionsLoad.value != ExecutionOptionsLoadState.ready) {
      return false;
    }
    final profile = _profile;
    final session = _session;
    final queueRepository = _queueRepository;
    if (profile == null || session == null || queueRepository == null) {
      return false;
    }
    final result = await queueRepository.enqueueCommand(
      profile: profile,
      session: session,
      commandName: commandName,
      arguments: arguments,
      executionOptions: executionOptions,
    );
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    return true;
  }

  /// Removes a queued prompt. Rejected by the repository while the prompt
  /// is currently `sending`.
  Future<void> removeFromQueue(String promptId) async {
    final queueRepository = _queueRepository;
    if (queueRepository == null) {
      return;
    }
    final result = await queueRepository.remove(promptId);
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Explicitly aborts the active generation, then dispatches [promptId]
  /// ahead of the queue head once the session settles idle. The caller is
  /// responsible for confirming this action with the user before calling
  /// it, since it cancels in-progress work.
  Future<void> sendNow(String promptId) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return;
    }
    final result = await queueCoordinator.sendNow(promptId);
    if (result case Err<void, QueueSendNowFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Responds to the open session's pending tool-call permission with
  /// [response]. See [QueueSendCoordinator.respondToPermission].
  Future<bool> respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return false;
    }
    final result = await queueCoordinator.respondToPermission(
      permissionId,
      response,
    );
    if (result case Err<void, QueueApprovalFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    return true;
  }

  /// Answers the open session's pending question request with [answers].
  /// See [QueueSendCoordinator.replyToQuestion].
  Future<bool> replyToQuestion(
    String requestId,
    List<List<String>> answers,
  ) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return false;
    }
    final result = await queueCoordinator.replyToQuestion(requestId, answers);
    if (result case Err<void, QueueApprovalFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    return true;
  }

  /// Rejects the open session's pending question request outright. See
  /// [QueueSendCoordinator.rejectQuestion].
  Future<bool> rejectQuestion(String requestId) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return false;
    }
    final result = await queueCoordinator.rejectQuestion(requestId);
    if (result case Err<void, QueueApprovalFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    return true;
  }

  /// Deactivates queue coordination and stops watching the queue for the
  /// currently open session, if any. Safe to call repeatedly, including
  /// before the queue has ever been opened. Called when the conversation
  /// screen leaves the active session, and internally by [open] before
  /// switching to a different one.
  Future<void> leave() async {
    _optionsLoadRevision++;
    _requestedSession = null;
    _requestedProfile = null;
    await _leaveCurrentSession();
  }

  /// Leaves only when [session] still owns this view model. A route being
  /// disposed after the next conversation has started must not tear down the
  /// next route's queue and SSE activation.
  Future<void> leaveSession(OpenCodeSession session) async {
    if (_requestedSession != session) {
      return;
    }
    await leave();
  }

  Future<void> _leaveCurrentSession() async {
    sessionMetadata.value = null;
    renamingSession.value = false;
    _liveRenderTimer?.cancel();
    _liveRenderTimer = null;
    _pendingLiveRender = null;
    releaseAttachments();
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    _detachLiveConversationState();
    _detachRemoteConnectionState();
    await _queueCoordinator?.deactivate();
    connectionState.value = const SseSuspended();
    executionState.value = const SessionExecutionUnknown();
    pendingApproval.value = null;
    artifacts.value = const SessionArtifactsLoading();
    _profile = null;
    _session = null;
    _detachHistoryListener();
    _artifactGeneration++;
  }

  Future<void> dispose() async {
    _optionsLoadRevision++;
    if (_disposed) {
      return;
    }
    _disposed = true;
    sessionMetadata.value = null;
    renamingSession.value = false;
    _requestedSession = null;
    _requestedProfile = null;
    _liveRenderTimer?.cancel();
    _liveRenderTimer = null;
    _pendingLiveRender = null;
    releaseAttachments();
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    _detachLiveConversationState();
    _detachRemoteConnectionState();
    _detachHistoryListener();
    _artifactGeneration++;
    _sessionInputMemories.clear();
    await _queueCoordinator?.deactivate();
    messages.dispose();
    artifacts.dispose();
    queue.dispose();
    attachments.dispose();
    connectionState.dispose();
    executionState.dispose();
    pendingApproval.dispose();
    refreshing.dispose();
    history.dispose();
    executionOptionsLoad.dispose();
    sessionMetadata.dispose();
    renamingSession.dispose();
    unawaited(_queueErrors.close());
    unawaited(_transcriptErrors.close());
  }

  void _detachLiveConversationState() {
    final liveConversationState = _liveConversationState;
    final listener = _liveConversationStateListener;
    if (liveConversationState != null && listener != null) {
      liveConversationState.removeListener(listener);
    }
    _liveConversationState = null;
    _liveConversationStateListener = null;
  }

  void _detachRemoteConnectionState() {
    final remoteConnectionState = _remoteConnectionState;
    final listener = _remoteConnectionStateListener;
    if (remoteConnectionState != null && listener != null) {
      remoteConnectionState.removeListener(listener);
    }
    _remoteConnectionState = null;
    _remoteConnectionStateListener = null;
    _lastSessionExecutionState = null;
  }

  void _attachHistoryListener() {
    _detachHistoryListener();
    void listener() {
      if (!_disposed) _mirrorHistory(_chatRepository.historyUpdates.value);
    }

    _historyListener = listener;
    _chatRepository.historyUpdates.addListener(listener);
    _mirrorHistory(_chatRepository.historyUpdates.value);
  }

  void _detachHistoryListener() {
    final listener = _historyListener;
    if (listener != null) {
      _chatRepository.historyUpdates.removeListener(listener);
      _historyListener = null;
    }
  }

  void _mirrorHistory(ChatHistoryState state, {ChatFailure? failure}) {
    history.value = ConversationHistoryUiState(
      hasMore: state.hasMore,
      loadingOlder: state.loadingOlder,
      limitedByServer: state.limitedByServer,
      failure: failure ?? state.failure,
    );
  }
}

class _SessionInputMemory {
  PromptExecutionOptions? executionOptions;
  String draft = '';
}

void _releaseAttachments(Iterable<PromptAttachment> attachments) {
  for (final attachment in attachments) {
    attachment.release();
  }
}
