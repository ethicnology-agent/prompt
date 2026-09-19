import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/async/result.dart';
import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../../capabilities/capabilities.dart';
import '../../queue/queue.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import '../domain/session_activity.dart';
import 'sessions_view_model.dart';
import 'session_rename_dialog.dart';
import 'session_delete_dialog.dart';
import 'new_session_dock.dart';
import 'session_creation_dock.dart';
import 'session_creation_view_model.dart';
import '../domain/session_launch.dart';
import '../domain/scoped_session.dart';

enum _CatalogAction {
  filters,
  settings,
  workspace,
  terminal,
  diagnostics,
  voiceSettings,
  disconnect,
}

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    required this.profile,
    required this.viewModel,
    required this.onOpenSession,
    required this.onOpenWorkspace,
    required this.onOpenTerminal,
    required this.onOpenDiagnostics,
    required this.onOpenVoiceSettings,
    required this.onDisconnect,
    this.embedded = false,
    this.onOpenSettings,
    this.onOpenSessionWithDraft,
    this.capabilitiesViewModel,
    this.onSessionCreated,
    this.sessionCreationViewModel,
    this.onSessionLaunched,
    this.onOpenScopedSession,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final ValueChanged<OpenCodeSession> onOpenSession;
  final ValueChanged<ScopedSession>? onOpenScopedSession;
  final ValueChanged<List<OpenCodeProject>> onOpenWorkspace;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenVoiceSettings;
  final VoidCallback onDisconnect;
  final bool embedded;
  final VoidCallback? onOpenSettings;
  final void Function(OpenCodeSession session, String draft)?
  onOpenSessionWithDraft;
  final CapabilitiesViewModel? capabilitiesViewModel;
  final SessionCreationViewModel? sessionCreationViewModel;
  final ValueChanged<SessionLaunch>? onSessionLaunched;
  final void Function(
    OpenCodeSession session,
    String draft,
    PromptExecutionOptions options,
  )?
  onSessionCreated;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

/// Shortest delay between two focus-triggered reloads of the catalog.
///
/// Regaining focus is a good moment to refresh, but it fires again on every
/// alt-tab. This keeps a burst of window switches from turning into a burst of
/// requests, which the product's data and battery budget does not allow.
const _focusRefreshCooldown = Duration(seconds: 15);

class _SessionsScreenState extends State<SessionsScreen> {
  final _searchController = TextEditingController();
  final _newDraftController = TextEditingController();
  final _searchFocus = FocusNode();
  final _draftFocus = FocusNode();
  final _draftDockKey = GlobalKey();
  String? _selectedProjectId;
  String? _creationDirectory;
  String _creationTitle = '';
  PromptExecutionOptions _creationOptions = const PromptExecutionOptions();
  late final AppLifecycleListener _lifecycleListener;
  Timer? _focusCooldown;
  bool _showFilters = false;
  bool _creationExpanded = false;
  (String, String)? _forkingSession;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(_onSearchChanged);
    _draftFocus.addListener(_onSearchChanged);
    _lifecycleListener = AppLifecycleListener(onResume: _refreshOnResume);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchFocus
      ..removeListener(_onSearchChanged)
      ..dispose();
    _draftFocus
      ..removeListener(_onSearchChanged)
      ..dispose();
    _newDraftController.dispose();
    _focusCooldown?.cancel();
    _lifecycleListener.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() {
    _focusCooldown?.cancel();
    _focusCooldown = Timer(_focusRefreshCooldown, () {});
    return widget.viewModel.load(widget.profile);
  }

  /// Reloads the catalog when the window or app regains focus.
  ///
  /// The catalog has no live subscription: sessions created or renamed
  /// elsewhere would otherwise stay stale until a manual refresh. Polling on a
  /// timer would keep fetching while nobody is looking, so the refresh is tied
  /// to the moment the user comes back instead.
  void _refreshOnResume() {
    if (_focusCooldown?.isActive ?? false) return;
    unawaited(_load());
  }

  void _onSearchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final body = IgnorePointer(
      ignoring: _creationExpanded,
      child: AnimatedOpacity(
        opacity: _creationExpanded ? .15 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: _buildBody(),
      ),
    );
    final media = MediaQuery.of(context);
    final compactKeyboard =
        media.viewInsets.bottom > 0 &&
        media.size.height - media.viewInsets.bottom - media.padding.top < 200;
    final prioritizeSearch = _showFilters && !_draftFocus.hasFocus;
    if (widget.embedded) {
      return Column(
        children: [
          _buildEmbeddedHeader(context),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: compactKeyboard
          ? null
          : AppBar(
              toolbarHeight: 60,
              centerTitle: true,
              leading: _buildCatalogMenu(brand: true),
              title: const Text('Sessions'),
              actions: [
                if (widget.onOpenSettings != null)
                  AppIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onPressed: widget.onOpenSettings,
                  ),
                const SizedBox(width: 4),
              ],
            ),
      // Keep the draft inside the body that Scaffold resizes for the keyboard.
      // A bottomNavigationBar stays behind the IME instead of moving above it.
      body: SafeArea(
        top: compactKeyboard,
        bottom: false,
        child: _creationExpanded && widget.sessionCreationViewModel != null
            ? LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(child: body),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight,
                        ),
                        child: _buildDraftDock(),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (!compactKeyboard || prioritizeSearch)
                    Expanded(child: body),
                  if (!compactKeyboard || !prioritizeSearch)
                    if (compactKeyboard)
                      Expanded(
                        child: SingleChildScrollView(child: _buildDraftDock()),
                      )
                    else
                      _buildDraftDock(),
                ],
              ),
      ),
    );
  }

  Widget _buildDraftDock() => SafeArea(
    key: _draftDockKey,
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: ValueListenableBuilder<SessionsUiState>(
      valueListenable: widget.viewModel,
      builder: (context, state, _) {
        final creation = widget.sessionCreationViewModel;
        if (creation != null && widget.onSessionLaunched != null) {
          final groups = state is SessionsReady ? state.catalogGroups : null;
          // Catalog IDs are scoped for filtering; creation must use the
          // active engine's original project IDs and roots, not another
          // engine's synthetic global project.
          final projects = groups != null
              ? groups
                        .where((group) => group.profile.id == widget.profile.id)
                        .firstOrNull
                        ?.projects ??
                    const <OpenCodeProject>[]
              : state is SessionsReady
              ? state.projects
              : const <OpenCodeProject>[];
          final initial =
              projects
                  .where(
                    (project) =>
                        (groups == null
                            ? project.id
                            : scopedProjectKey(widget.profile, project.id)) ==
                        _selectedProjectId,
                  )
                  .firstOrNull ??
              projects.where((project) => project.id != 'global').firstOrNull ??
              projects.firstOrNull;
          return SessionCreationDock(
            key: ValueKey('creation:${widget.profile.id}'),
            profile: widget.profile,
            viewModel: creation,
            controller: _newDraftController,
            focusNode: _draftFocus,
            initialDirectory: initial?.directory ?? '',
            onLaunch: widget.onSessionLaunched!,
            onExpandedChanged: (expanded) {
              if (mounted && _creationExpanded != expanded) {
                setState(() => _creationExpanded = expanded);
              }
            },
          );
        }
        return NewSessionDock(
          focusNode: _draftFocus,
          draftController: widget.onOpenSessionWithDraft == null
              ? null
              : _newDraftController,
          onCreate: state is SessionsReady || state is SessionsEmpty
              ? () => _createSession(
                  state is SessionsReady ? state.projects : const [],
                )
              : null,
          onTerminal:
              widget.profile.capabilities.supports(BackendFeature.terminal)
              ? widget.onOpenTerminal
              : null,
        );
      },
    ),
  );

  Widget _buildEmbeddedHeader(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            const _OnlineDot(),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                widget.profile.displayOrigin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                semanticsLabel:
                    'Connected server ${widget.profile.displayOrigin}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            _buildCatalogMenu(),
          ],
        ),
      ),
    );
  }

  void _onCatalogAction(_CatalogAction action) {
    switch (action) {
      case _CatalogAction.filters:
        setState(() => _showFilters = !_showFilters);
      case _CatalogAction.settings:
        widget.onOpenSettings?.call();
      case _CatalogAction.workspace:
        final state = widget.viewModel.value;
        if (state case SessionsReady(:final projects)) {
          widget.onOpenWorkspace(
            state.catalogGroups == null
                ? projects
                : [
                    for (final group in state.catalogGroups!)
                      if (group.profile.id == widget.profile.id)
                        ...group.projects,
                  ],
          );
        }
      case _CatalogAction.terminal:
        widget.onOpenTerminal();
      case _CatalogAction.diagnostics:
        widget.onOpenDiagnostics();
      case _CatalogAction.voiceSettings:
        widget.onOpenVoiceSettings();
      case _CatalogAction.disconnect:
        widget.onDisconnect();
    }
  }

  AppMenuButton<_CatalogAction> _buildCatalogMenu({bool brand = false}) {
    return AppMenuButton<_CatalogAction>(
      tooltip: 'More actions',
      icon: brand ? const Icon(Icons.code_rounded, size: 22) : null,
      onSelected: _onCatalogAction,
      optionsBuilder: (_) => [
        AppMenuOption(
          value: _CatalogAction.filters,
          label: 'Filter sessions',
          selected: _showFilters,
        ),
        if (widget.onOpenSettings != null)
          const AppMenuOption(
            value: _CatalogAction.settings,
            label: 'Settings',
            icon: Icons.settings_outlined,
          ),
        if (widget.profile.capabilities.supports(BackendFeature.workspace))
          AppMenuOption(
            value: _CatalogAction.workspace,
            label: 'Browse workspace',
            icon: Icons.folder_open_outlined,
            enabled: widget.viewModel.value is SessionsReady,
          ),
        if (widget.profile.capabilities.supports(BackendFeature.terminal))
          const AppMenuOption(
            value: _CatalogAction.terminal,
            label: 'Remote terminal',
            icon: Icons.terminal_outlined,
          ),
        if (widget.profile.capabilities.supports(BackendFeature.configuration))
          const AppMenuOption(
            value: _CatalogAction.diagnostics,
            label: 'Server settings',
            icon: Icons.settings_outlined,
          ),
        const AppMenuOption(
          value: _CatalogAction.voiceSettings,
          label: 'Voice settings',
          icon: Icons.mic_none_outlined,
        ),
        const AppMenuOption(
          value: _CatalogAction.disconnect,
          label: 'Disconnect',
          icon: Icons.power_settings_new_rounded,
          dividerBefore: true,
        ),
      ],
    );
  }

  Widget _buildBody() {
    return ValueListenableBuilder<SessionsUiState>(
      valueListenable: widget.viewModel,
      builder: (context, state, _) {
        return switch (state) {
          SessionsIdle() || SessionsLoading() => const _LoadingCatalog(),
          SessionsEmpty() => _EmptyCatalog(
            onCreate: () => _createSession(const []),
          ),
          SessionsError(:final failure) => _SessionsError(
            failure: failure,
            onRetry: _load,
          ),
          SessionsReady() => _buildReady(state),
        };
      },
    );
  }

  Widget _buildReady(SessionsReady state) {
    final entries = state.entriesFor(widget.profile);
    final projects = state.projects;
    final scoped = state.catalogGroups != null;
    String projectKey(ScopedSession entry) =>
        scoped ? entry.projectKey : entry.session.projectId;
    final projectIdsWithSessions = entries.map(projectKey).toSet();
    final filterProjects = projects
        .where((project) => projectIdsWithSessions.contains(project.id))
        .toList(growable: false);
    final selectedProjectId =
        projectIdsWithSessions.contains(_selectedProjectId)
        ? _selectedProjectId
        : null;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = entries
        .where((entry) {
          final session = entry.session;
          if (selectedProjectId != null &&
              projectKey(entry) != selectedProjectId) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return session.title.toLowerCase().contains(query) ||
              session.directory.toLowerCase().contains(query) ||
              session.id.toLowerCase().contains(query) ||
              (scoped &&
                  entry.profile.backend.label.toLowerCase().contains(query));
        })
        .toList(growable: false);
    final primary = filtered
        .where((entry) => entry.session.parentId?.isNotEmpty != true)
        .toList(growable: false);
    final visibleSessions = query.isEmpty ? primary : filtered;
    final childrenByParent = <(String, String), int>{};
    for (final entry in entries) {
      final parentId = entry.session.parentId;
      if (parentId != null && parentId.isNotEmpty) {
        childrenByParent.update(
          (entry.profile.id, parentId),
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group
              in state.catalogGroups ?? const <SessionCatalogGroup>[])
            if (group.failure != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${group.profile.backend.label}: ${group.failure!.message} Previously loaded sessions may be out of date.',
                  ),
                ),
              ),
          if (widget.embedded || _showFilters)
            SliverToBoxAdapter(
              child: _CatalogControls(
                searchController: _searchController,
                searchFocus: _searchFocus,
                projects: filterProjects,
                projectLabels: {
                  for (final group
                      in state.catalogGroups ?? const <SessionCatalogGroup>[])
                    for (final project in group.projects)
                      scopedProjectKey(group.profile, project.id):
                          '${group.profile.backend.label} · ${project.name}',
                },
                selectedProjectId: selectedProjectId,
                onSelectProject: (id) =>
                    setState(() => _selectedProjectId = id),
                onCreate: () => _createSession(projects),
                onRefresh: _load,
              ),
            ),
          if (visibleSessions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _NoMatchingSessions(
                hasQuery: query.isNotEmpty || selectedProjectId != null,
                onClear: () {
                  _searchController.clear();
                  setState(() => _selectedProjectId = null);
                },
                onCreate: () => _createSession(projects),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              sliver: SliverList.separated(
                itemCount: visibleSessions.length,
                separatorBuilder: (_, _) => const Padding(
                  padding: EdgeInsets.only(left: 88),
                  child: Divider(height: 1, thickness: 0.5),
                ),
                itemBuilder: (context, index) {
                  final entry = visibleSessions[index];
                  final session = entry.session;
                  return _SessionCard(
                    key: ValueKey(entry.identity),
                    session: session,
                    engineLabel: scoped ? entry.profile.backend.label : null,
                    activity: entry.activity,
                    childCount: childrenByParent[entry.identity] ?? 0,
                    onTap: () {
                      if (widget.onOpenScopedSession case final open?) {
                        open(entry);
                      } else if (entry.profile.id == widget.profile.id) {
                        widget.onOpenSession(session);
                      }
                    },
                    onCopyId: () => _copySessionId(session),
                    onFork: () => unawaited(_forkSession(entry)),
                    onRename: () =>
                        _renameSession(session, profile: entry.profile),
                    onDelete: () =>
                        _deleteSession(session, profile: entry.profile),
                    canRename: entry.profile.capabilities.supports(
                      BackendFeature.sessionRename,
                    ),
                    canFork:
                        entry.profile.capabilities.supports(
                          BackendFeature.sessionFork,
                        ) &&
                        (entry.profile.id == widget.profile.id ||
                            widget.onOpenScopedSession != null),
                    forkInProgress: _forkingSession != null,
                    canDelete: entry.profile.capabilities.supports(
                      BackendFeature.sessionDelete,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createSession(List<OpenCodeProject> projects) async {
    if (widget.sessionCreationViewModel != null) {
      _draftFocus.requestFocus();
      return;
    }
    final state = widget.viewModel.value;
    final selectedId =
        state is SessionsReady &&
            state.sessions.any(
              (session) => session.projectId == _selectedProjectId,
            )
        ? _selectedProjectId
        : null;
    final initialProject =
        projects.where((project) => project.id == selectedId).firstOrNull ??
        projects.where((project) => project.id != 'global').firstOrNull ??
        projects.firstOrNull;
    final session = await showModalBottomSheet<OpenCodeSession>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      enableDrag: false,
      builder: (context) => _NewSessionSheet(
        profile: widget.profile,
        viewModel: widget.viewModel,
        projects: projects,
        initialDirectory: _creationDirectory ?? initialProject?.directory ?? '',
        initialTitle: _creationTitle,
        capabilitiesViewModel: widget.capabilitiesViewModel,
        initialOptions: _creationOptions,
        onOptionsChanged: (options) => _creationOptions = options,
        onDraftChanged: (directory, title) {
          _creationDirectory = directory;
          _creationTitle = title;
        },
      ),
    );
    if (!mounted || session == null) {
      return;
    }
    _creationDirectory = null;
    _creationTitle = '';
    final options = _creationOptions;
    _creationOptions = const PromptExecutionOptions();
    final draft = _newDraftController.text;
    if (widget.onSessionCreated != null) {
      widget.onSessionCreated!(session, draft, options);
      _newDraftController.clear();
    } else if (draft.isNotEmpty && widget.onOpenSessionWithDraft != null) {
      widget.onOpenSessionWithDraft!(session, draft);
      _newDraftController.clear();
    } else {
      widget.onOpenSession(session);
    }
  }

  void _copySessionId(OpenCodeSession session) {
    Clipboard.setData(ClipboardData(text: session.id));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session ID copied')));
  }

  Future<void> _forkSession(ScopedSession entry) async {
    if (_forkingSession != null) return;
    setState(() => _forkingSession = entry.identity);
    final result = await widget.viewModel.fork(entry.profile, entry.session);
    if (!mounted) return;
    setState(() => _forkingSession = null);
    switch (result) {
      case Ok<OpenCodeSession, SessionsFailure>(:final value):
        if (widget.onOpenScopedSession case final open?) {
          open(ScopedSession(entry.profile, value));
        } else {
          widget.onOpenSession(value);
        }
      case Err<OpenCodeSession, SessionsFailure>(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _renameSession(
    OpenCodeSession session, {
    ServerProfile? profile,
  }) async {
    final targetProfile = profile ?? widget.profile;
    final viewModel = widget.viewModel;
    await showDialog<String>(
      context: context,
      builder: (context) => SessionRenameDialog(
        initialTitle: session.title,
        onSave: (title) async {
          if (!mounted) return SessionsFailure.unexpectedResponse;
          return viewModel.rename(targetProfile, session, title);
        },
      ),
    );
  }

  Future<void> _deleteSession(
    OpenCodeSession session, {
    ServerProfile? profile,
  }) async {
    final targetProfile = profile ?? widget.profile;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SessionDeleteDialog(
        title: session.title,
        backendLabel: targetProfile.backend.label,
        onDelete: () async {
          if (!mounted) return SessionsFailure.unexpectedResponse;
          return widget.viewModel.delete(targetProfile, session);
        },
      ),
    );
  }
}

class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet({
    required this.profile,
    required this.viewModel,
    required this.projects,
    required this.initialDirectory,
    required this.initialTitle,
    required this.onDraftChanged,
    required this.initialOptions,
    required this.onOptionsChanged,
    this.capabilitiesViewModel,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final List<OpenCodeProject> projects;
  final String initialDirectory;
  final String initialTitle;
  final void Function(String directory, String title) onDraftChanged;
  final PromptExecutionOptions initialOptions;
  final ValueChanged<PromptExecutionOptions> onOptionsChanged;
  final CapabilitiesViewModel? capabilitiesViewModel;

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  late final TextEditingController _directoryController;
  late final TextEditingController _titleController;
  Timer? _debounce;
  List<String> _suggestions = const [];
  SessionsFailure? _suggestionFailure;
  bool _searching = false;
  bool _submitting = false;
  SessionsFailure? _creationFailure;
  int _suggestionRevision = 0;
  late PromptExecutionOptions _options;

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController(text: widget.initialDirectory)
      ..addListener(_directoryChanged);
    _titleController = TextEditingController(text: widget.initialTitle)
      ..addListener(_rememberDraft);
    _options = widget.initialOptions;
    widget.capabilitiesViewModel?.addListener(_capabilitiesChanged);
    _suggestions = widget.projects
        .map((project) => project.directory)
        .where((directory) => directory.isNotEmpty)
        .toSet()
        .toList();
  }

  @override
  void dispose() {
    _suggestionRevision++;
    widget.capabilitiesViewModel?.removeListener(_capabilitiesChanged);
    _debounce?.cancel();
    _directoryController
      ..removeListener(_directoryChanged)
      ..dispose();
    _titleController
      ..removeListener(_rememberDraft)
      ..dispose();
    super.dispose();
  }

  void _rememberDraft() =>
      widget.onDraftChanged(_directoryController.text, _titleController.text);

  void _capabilitiesChanged() {
    if (mounted) setState(() {});
  }

  OpenCodeCapabilities? get _capabilities {
    final state = widget.capabilitiesViewModel?.value;
    return state is CapabilitiesReady ? state.capabilities : null;
  }

  bool get _optionsValid {
    if (_options.isEmpty) return true;
    final capabilities = _capabilities;
    if (capabilities == null) return false;
    return (!_options.hasModel ||
            capabilities.models.any(
              (model) =>
                  model.isProviderConnected &&
                  model.providerId == _options.modelProviderId &&
                  model.id == _options.modelId,
            )) &&
        (_options.agentName == null ||
            capabilities.agents.any(
              (agent) => agent.name == _options.agentName,
            )) &&
        (_options.permissionModeId == null ||
            capabilities.permissionModes.any(
              (mode) => mode.id == _options.permissionModeId,
            ));
  }

  Future<void> _pick<T>({
    required String title,
    required T? selected,
    required List<SelectionOption<T>> choices,
    required void Function(T?) apply,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<(T?,)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      MediaQuery.paddingOf(context).top)
                  .clamp(0.0, 560.0),
          child: SelectionPicker<T>(
            title: title,
            options: choices,
            selected: selected,
            onApply: (value) => Navigator.of(context).pop((value,)),
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    if (result == null || !mounted || _submitting) return;
    setState(() => apply(result.$1));
    widget.onOptionsChanged(_options);
  }

  Widget _executionSettings() {
    final state = widget.capabilitiesViewModel?.value;
    final capabilities = _capabilities;
    final model = capabilities?.models
        .where(
          (model) =>
              model.providerId == _options.modelProviderId &&
              model.id == _options.modelId,
        )
        .firstOrNull;
    final agent = capabilities?.agents
        .where((agent) => agent.name == _options.agentName)
        .firstOrNull;
    final effectivePermissionId =
        _options.permissionModeId ?? capabilities?.defaultPermissionModeId;
    final permission = capabilities?.permissionModes
        .where((mode) => mode.id == effectivePermissionId)
        .firstOrNull;
    final permissionModes =
        capabilities?.permissionModes ?? const <PermissionModeChoice>[];
    final defaultLabel =
        widget.profile.backend == AgentBackend.gatewayClaude ||
            widget.profile.backend == AgentBackend.gatewayCodex
        ? 'CLI default'
        : 'Server default';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Permissions'),
          subtitle: Text(
            permission?.label ?? widget.profile.backend.defaultPermissionLabel,
          ),
          trailing: permissionModes.isEmpty
              ? null
              : const Icon(Icons.expand_more),
          onTap: _submitting || permissionModes.isEmpty
              ? null
              : () => _pick<PermissionModeChoice>(
                  title: 'Permissions',
                  selected: _options.permissionModeId == null
                      ? null
                      : permission,
                  choices: [
                    for (final item in permissionModes)
                      SelectionOption(
                        value: item,
                        label: item.label,
                        description: item.description,
                      ),
                  ],
                  apply: (value) => _options = PromptExecutionOptions(
                    modelProviderId: _options.modelProviderId,
                    modelId: _options.modelId,
                    agentName: _options.agentName,
                    reasoningEffort: _options.reasoningEffort,
                    permissionModeId: value?.id,
                  ),
                ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Model'),
          subtitle: Text(
            model?.name ??
                (_options.hasModel
                    ? 'Selected model unavailable'
                    : defaultLabel),
          ),
          trailing: const Icon(Icons.expand_more),
          onTap: _submitting || capabilities == null
              ? null
              : () => _pick<OpenCodeModel>(
                  title: 'Model',
                  selected: model,
                  choices: [
                    for (final item in capabilities.models.where(
                      (model) => model.isProviderConnected,
                    ))
                      SelectionOption(
                        value: item,
                        label: item.name,
                        description: '${item.providerId} / ${item.id}',
                      ),
                  ],
                  apply: (value) => _options = PromptExecutionOptions(
                    modelProviderId: value?.providerId,
                    modelId: value?.id,
                    agentName: _options.agentName,
                    permissionModeId: _options.permissionModeId,
                  ),
                ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Agent'),
          subtitle: Text(
            agent?.name ??
                (_options.agentName != null
                    ? 'Selected agent unavailable'
                    : defaultLabel),
          ),
          trailing: const Icon(Icons.expand_more),
          onTap: _submitting || capabilities == null
              ? null
              : () => _pick<OpenCodeAgent>(
                  title: 'Agent',
                  selected: agent,
                  choices: [
                    for (final item in capabilities.agents)
                      SelectionOption(value: item, label: item.name),
                  ],
                  apply: (value) => _options = PromptExecutionOptions(
                    modelProviderId: _options.modelProviderId,
                    modelId: _options.modelId,
                    agentName: value?.name,
                    permissionModeId: _options.permissionModeId,
                  ),
                ),
        ),
        if (state is CapabilitiesLoading || state is CapabilitiesIdle)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading execution choices',
          ),
        if (state is CapabilitiesError) ...[
          const Text(
            'Execution choices unavailable. You can use the server default.',
          ),
          AppButton(
            label: 'Retry execution choices',
            variant: AppButtonVariant.tertiary,
            onPressed: _submitting ? null : widget.capabilitiesViewModel!.retry,
          ),
        ],
        if (!_optionsValid)
          const Text(
            'Refresh execution choices or select an available model and agent before creating.',
          ),
      ],
    );
  }

  void _directoryChanged() {
    _rememberDraft();
    final revision = ++_suggestionRevision;
    _debounce?.cancel();
    final input = _directoryController.text.trim();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _suggestionFailure = null;
      _suggestions = _knownSuggestions(input);
    });
    if (input.isEmpty ||
        !_isAbsoluteServerPath(input) ||
        !widget.profile.capabilities.supports(BackendFeature.workspace)) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      setState(() {
        _searching = true;
        _suggestionFailure = null;
      });
      final result = await widget.viewModel.suggestDirectories(
        widget.profile,
        input,
      );
      if (!mounted || revision != _suggestionRevision || result == null) return;
      setState(() {
        _searching = false;
        switch (result) {
          case Ok<List<String>, SessionsFailure>(:final value):
            _suggestions = {..._knownSuggestions(input), ...value}.toList()
              ..sort();
          case Err<List<String>, SessionsFailure>(:final failure):
            _suggestionFailure = failure;
        }
      });
    });
  }

  List<String> _knownSuggestions(String input) {
    final normalized = input.toLowerCase();
    return widget.projects
        .map((project) => project.directory)
        .where(
          (directory) =>
              normalized.isEmpty ||
              directory.toLowerCase().startsWith(normalized),
        )
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _create() async {
    final directory = _directoryController.text.trim();
    if (_submitting || !_isAbsoluteServerPath(directory) || !_optionsValid) {
      return;
    }
    setState(() {
      _submitting = true;
      _creationFailure = null;
    });
    final result = await widget.viewModel.create(
      widget.profile,
      directory,
      title: _titleController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Ok<OpenCodeSession, SessionsFailure>(:final value):
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop(value);
      case Err<OpenCodeSession, SessionsFailure>(:final failure):
        setState(() => _creationFailure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final directory = _directoryController.text.trim();
    final valid = _isAbsoluteServerPath(directory) && _optionsValid;
    return PopScope(
      canPop: !_submitting,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'New session',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.profile.backend.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter an absolute path on the server. This does not select or copy files from the phone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _directoryController,
                  enabled: !_submitting,
                  autofocus: true,
                  label: 'Server project path',
                  hint: '/srv/projects/my-app',
                  suffix: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  errorText:
                      directory.isNotEmpty && !_isAbsoluteServerPath(directory)
                      ? 'Use an absolute Unix or Windows path.'
                      : null,
                ),
                if (_suggestionFailure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Directory suggestions unavailable; you can still enter the path manually.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length > 20
                          ? 20
                          : _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            suggestion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _submitting
                              ? null
                              : () {
                                  _directoryController.value = TextEditingValue(
                                    text: suggestion,
                                    selection: TextSelection.collapsed(
                                      offset: suggestion.length,
                                    ),
                                  );
                                },
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                AppTextField(
                  controller: _titleController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.done,
                  label: 'Title (optional)',
                  hint: 'What are we working on?',
                ),
                const SizedBox(height: 16),
                if (widget.capabilitiesViewModel != null) _executionSettings(),
                if (_creationFailure case final failure?) ...[
                  Semantics(liveRegion: true, child: Text(failure.message)),
                  const SizedBox(height: 12),
                ],
                AppButton(
                  label: 'Create and open',
                  icon: Icons.add_comment_outlined,
                  busy: _submitting,
                  onPressed: valid ? _create : null,
                ),
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.tertiary,
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _isAbsoluteServerPath(String value) =>
    RegExp(r'^/(?:[^/].*)?$').hasMatch(value) ||
    RegExp(r'^(?:\\\\|//)[^\\/]+[\\/][^\\/]+(?:[\\/].*)?$').hasMatch(value) ||
    RegExp(r'^[A-Za-z]:[\\/](?:.*)?$').hasMatch(value);

class _CatalogControls extends StatelessWidget {
  const _CatalogControls({
    required this.searchController,
    required this.searchFocus,
    required this.projects,
    required this.selectedProjectId,
    required this.onSelectProject,
    required this.onCreate,
    required this.onRefresh,
    this.projectLabels = const {},
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final List<OpenCodeProject> projects;
  final Map<String, String> projectLabels;
  final String? selectedProjectId;
  final ValueChanged<String?> onSelectProject;
  final VoidCallback? onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    textInputAction: TextInputAction.search,
                    hint: 'Search sessions, projects, IDs',
                    prefixIcon: Icons.search_rounded,
                    suffix: searchController.text.isEmpty
                        ? null
                        : AppIconButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Clear search',
                            onPressed: searchController.clear,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                AppIconButton(
                  variant: AppIconButtonVariant.filled,
                  onPressed: onCreate,
                  icon: Icons.add_rounded,
                  tooltip: 'New session',
                ),
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh sessions',
                  onPressed: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              // The horizontal viewport needs a bounded cross-axis extent.
              // Keep room for the padded tap target and for scaled labels.
              height: math
                  .max(
                    kMinInteractiveDimension,
                    MediaQuery.textScalerOf(
                      context,
                    ).scale(kMinInteractiveDimension),
                  )
                  .toDouble(),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  AppChoiceChip(
                    label: 'All',
                    selected: selectedProjectId == null,
                    onSelected: (_) => onSelectProject(null),
                  ),
                  for (final project in projects) ...[
                    const SizedBox(width: 8),
                    AppChoiceChip(
                      label:
                          projectLabels[project.id] ?? _projectLabel(project),
                      selected: selectedProjectId == project.id,
                      onSelected: (_) => onSelectProject(project.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.childCount,
    required this.activity,
    required this.onTap,
    required this.onCopyId,
    required this.onFork,
    required this.onRename,
    required this.onDelete,
    required this.canRename,
    required this.canFork,
    required this.canDelete,
    required this.forkInProgress,
    this.engineLabel,
    super.key,
  });

  final OpenCodeSession session;
  final int childCount;
  final SessionActivity activity;
  final VoidCallback onTap;
  final VoidCallback onCopyId;
  final VoidCallback onFork;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool canRename;
  final bool canFork;
  final bool canDelete;
  final bool forkInProgress;
  final String? engineLabel;

  @override
  Widget build(BuildContext context) {
    final (status, icon) = switch (activity) {
      SessionActivity.working => ('Working', Icons.sync_rounded),
      SessionActivity.idle => ('Idle', Icons.check_circle_outline_rounded),
      SessionActivity.retrying => ('Retrying', Icons.replay_rounded),
      SessionActivity.unknown => ('Activity unknown', Icons.help_outline),
      SessionActivity.unavailable => ('Status unavailable', Icons.sync_problem),
    };
    final project = [
      ?engineLabel,
      _directoryName(session.directory),
    ].join(' · ');
    return SessionListTile(
      identifier: session.id,
      title: session.title.isEmpty ? 'Untitled session' : session.title,
      project: childCount > 0 ? '$project · $childCount subagents' : project,
      status: status,
      statusIcon: icon,
      inProgress:
          activity == SessionActivity.working ||
          activity == SessionActivity.retrying,
      timestamp: _relativeTime(session.updatedAt),
      nested: session.parentId?.isNotEmpty == true,
      showDivider: false,
      onTap: onTap,
      onLongPress: () => _showActions(context),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_SessionAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canRename)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Rename'),
                  onTap: () => Navigator.pop(context, _SessionAction.rename),
                ),
              if (canFork)
                ListTile(
                  leading: const Icon(Icons.fork_right_rounded),
                  title: Text(
                    forkInProgress ? 'Forking session…' : 'Fork session',
                  ),
                  onTap: forkInProgress
                      ? null
                      : () => Navigator.pop(context, _SessionAction.fork),
                ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: const Text('Copy session ID'),
                onTap: () => Navigator.pop(context, _SessionAction.copyId),
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.pop(context, _SessionAction.delete),
                ),
            ],
          ),
        ),
      ),
    );
    switch (action) {
      case _SessionAction.fork:
        onFork();
      case _SessionAction.copyId:
        onCopyId();
      case _SessionAction.rename:
        onRename();
      case _SessionAction.delete:
        onDelete();
      case null:
        break;
    }
  }
}

enum _SessionAction { fork, copyId, rename, delete }

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Server connected',
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color:
              Theme.of(context).extension<PromptTokens>()?.success ??
              const Color(0xff13795b),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LoadingCatalog extends StatelessWidget {
  const _LoadingCatalog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Loading sessions',
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _NoMatchingSessions extends StatelessWidget {
  const _NoMatchingSessions({
    required this.hasQuery,
    required this.onClear,
    required this.onCreate,
  });

  final bool hasQuery;
  final VoidCallback onClear;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: hasQuery ? Icons.search_off_rounded : Icons.forum_outlined,
      title: hasQuery ? 'No matching sessions' : 'No sessions yet',
      body: hasQuery
          ? 'Try a different search or show every project.'
          : 'Create a session in one of the server projects.',
      action: hasQuery ? ('Clear filters', onClear) : ('New session', onCreate),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.folder_off_outlined,
      title: 'No OpenCode projects',
      body: 'Open a project on the server, then refresh this catalog.',
      action: ('New session', onCreate),
    );
  }
}

class _SessionsError extends StatelessWidget {
  const _SessionsError({required this.failure, required this.onRetry});

  final SessionsFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.sync_problem_rounded,
      title: 'Cannot load sessions',
      body: failure.message,
      action: ('Try again', onRetry),
      error: true,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final (String, VoidCallback?) action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 52,
                color: error
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (action.$2 != null) ...[
                const SizedBox(height: 20),
                AppButton(label: action.$1, onPressed: action.$2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _projectLabel(OpenCodeProject project) {
  return project.id == 'global' ? 'Global' : project.name;
}

String _directoryName(String directory) {
  final normalized = directory.replaceAll('\\', '/');
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? directory : segments.last;
}

String _relativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d';
  }
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
