import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/async/result.dart';
import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import '../domain/session_activity.dart';
import 'sessions_view_model.dart';
import 'new_session_dock.dart';

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
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final ValueChanged<OpenCodeSession> onOpenSession;
  final ValueChanged<List<OpenCodeProject>> onOpenWorkspace;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenVoiceSettings;
  final VoidCallback onDisconnect;
  final bool embedded;
  final VoidCallback? onOpenSettings;
  final void Function(OpenCodeSession session, String draft)?
  onOpenSessionWithDraft;

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
  late final AppLifecycleListener _lifecycleListener;
  Timer? _focusCooldown;
  bool _showFilters = false;

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
    final body = _buildBody();
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
        child: Column(
          children: [
            if (!compactKeyboard || prioritizeSearch) Expanded(child: body),
            if (!compactKeyboard || !prioritizeSearch)
              if (compactKeyboard)
                Expanded(child: SingleChildScrollView(child: _buildDraftDock()))
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
      builder: (context, state, _) => NewSessionDock(
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
      ),
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
          widget.onOpenWorkspace(projects);
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

  PopupMenuButton<_CatalogAction> _buildCatalogMenu({bool brand = false}) {
    return PopupMenuButton<_CatalogAction>(
      tooltip: 'More actions',
      icon: brand
          ? Semantics(
              label: 'Prompt',
              child: const Icon(Icons.code_rounded, size: 22),
            )
          : null,
      onSelected: _onCatalogAction,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: _CatalogAction.filters,
          checked: _showFilters,
          child: const Text('Filter sessions'),
        ),
        if (widget.onOpenSettings != null)
          const PopupMenuItem(
            value: _CatalogAction.settings,
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'),
            ),
          ),
        if (widget.profile.capabilities.supports(BackendFeature.workspace))
          PopupMenuItem(
            value: _CatalogAction.workspace,
            enabled: widget.viewModel.value is SessionsReady,
            child: const ListTile(
              leading: Icon(Icons.folder_open_outlined),
              title: Text('Browse workspace'),
            ),
          ),
        if (widget.profile.capabilities.supports(BackendFeature.terminal))
          const PopupMenuItem(
            value: _CatalogAction.terminal,
            child: ListTile(
              leading: Icon(Icons.terminal_outlined),
              title: Text('Remote terminal'),
            ),
          ),
        if (widget.profile.capabilities.supports(BackendFeature.configuration))
          const PopupMenuItem(
            value: _CatalogAction.diagnostics,
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Server settings'),
            ),
          ),
        const PopupMenuItem(
          value: _CatalogAction.voiceSettings,
          child: ListTile(
            leading: Icon(Icons.mic_none_outlined),
            title: Text('Voice settings'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _CatalogAction.disconnect,
          child: ListTile(
            leading: Icon(Icons.power_settings_new_rounded),
            title: Text('Disconnect'),
          ),
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
          SessionsReady(
            :final sessions,
            :final projects,
            :final activities,
            :final unavailableDirectories,
          ) =>
            _buildReady(sessions, projects, activities, unavailableDirectories),
        };
      },
    );
  }

  Widget _buildReady(
    List<OpenCodeSession> sessions,
    List<OpenCodeProject> projects,
    Map<String, SessionActivity> activities,
    Set<String> unavailableDirectories,
  ) {
    final projectIdsWithSessions = sessions
        .map((session) => session.projectId)
        .toSet();
    final filterProjects = projects
        .where((project) => projectIdsWithSessions.contains(project.id))
        .toList(growable: false);
    final selectedProjectId =
        projectIdsWithSessions.contains(_selectedProjectId)
        ? _selectedProjectId
        : null;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = sessions
        .where((session) {
          if (selectedProjectId != null &&
              session.projectId != selectedProjectId) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return session.title.toLowerCase().contains(query) ||
              session.directory.toLowerCase().contains(query) ||
              session.id.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final primary = filtered
        .where((session) => session.parentId?.isNotEmpty != true)
        .toList(growable: false);
    final visibleSessions = query.isEmpty ? primary : filtered;
    final childrenByParent = <String, int>{};
    for (final session in sessions) {
      final parentId = session.parentId;
      if (parentId != null && parentId.isNotEmpty) {
        childrenByParent.update(
          parentId,
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
          if (widget.embedded || _showFilters)
            SliverToBoxAdapter(
              child: _CatalogControls(
                searchController: _searchController,
                searchFocus: _searchFocus,
                projects: filterProjects,
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
                  final session = visibleSessions[index];
                  return _SessionCard(
                    session: session,
                    activity:
                        activities[session.id] ??
                        (unavailableDirectories.contains(session.directory)
                            ? SessionActivity.unavailable
                            : SessionActivity.unknown),
                    childCount: childrenByParent[session.id] ?? 0,
                    onTap: () => widget.onOpenSession(session),
                    onCopyId: () => _copySessionId(session),
                    onRename: () => _renameSession(session),
                    onDelete: () => _deleteSession(session),
                    canRename: widget.profile.capabilities.supports(
                      BackendFeature.sessionRename,
                    ),
                    canDelete: widget.profile.capabilities.supports(
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
      ),
    );
    if (!mounted || session == null) {
      return;
    }
    final draft = _newDraftController.text;
    if (draft.isNotEmpty && widget.onOpenSessionWithDraft != null) {
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

  Future<void> _renameSession(OpenCodeSession session) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameSessionDialog(initialTitle: session.title),
    );
    if (!mounted || title == null || title.isEmpty || title == session.title) {
      return;
    }
    final failure = await widget.viewModel.rename(
      widget.profile,
      session,
      title,
    );
    if (mounted && failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _deleteSession(OpenCodeSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Delete session?'),
        content: Text(
          'Delete "${session.title}" from OpenCode? This cannot be undone.',
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: 'Delete',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final failure = await widget.viewModel.delete(widget.profile, session);
    if (mounted && failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _RenameSessionDialog extends StatefulWidget {
  const _RenameSessionDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: const Text('Rename session'),
      content: AppTextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        label: 'Title',
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Rename',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet({
    required this.profile,
    required this.viewModel,
    required this.projects,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final List<OpenCodeProject> projects;

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

  @override
  void initState() {
    super.initState();
    final initial = widget.projects
        .firstWhere(
          (project) => project.id != 'global',
          orElse: () => widget.projects.isEmpty
              ? const OpenCodeProject(id: '', directory: '')
              : widget.projects.first,
        )
        .directory;
    _directoryController = TextEditingController(text: initial)
      ..addListener(_directoryChanged);
    _titleController = TextEditingController();
    _suggestions = widget.projects
        .map((project) => project.directory)
        .where((directory) => directory.isNotEmpty)
        .toSet()
        .toList();
  }

  @override
  void dispose() {
    _suggestionRevision++;
    _debounce?.cancel();
    _directoryController
      ..removeListener(_directoryChanged)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _directoryChanged() {
    final revision = ++_suggestionRevision;
    _debounce?.cancel();
    final input = _directoryController.text.trim();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _suggestionFailure = null;
      _suggestions = _knownSuggestions(input);
    });
    if (input.isEmpty || !_isAbsoluteServerPath(input)) {
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
    if (_submitting || !_isAbsoluteServerPath(directory)) return;
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
    final valid = _isAbsoluteServerPath(directory);
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
                  errorText: directory.isNotEmpty && !valid
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
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final List<OpenCodeProject> projects;
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
                  ChoiceChip(
                    label: const Text('All'),
                    selected: selectedProjectId == null,
                    onSelected: (_) => onSelectProject(null),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  for (final project in projects) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(_projectLabel(project)),
                      selected: selectedProjectId == project.id,
                      onSelected: (_) => onSelectProject(project.id),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
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
    required this.onRename,
    required this.onDelete,
    required this.canRename,
    required this.canDelete,
  });

  final OpenCodeSession session;
  final int childCount;
  final SessionActivity activity;
  final VoidCallback onTap;
  final VoidCallback onCopyId;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool canRename;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final (status, icon) = switch (activity) {
      SessionActivity.working => ('Working', Icons.sync_rounded),
      SessionActivity.idle => ('Idle', Icons.check_circle_outline_rounded),
      SessionActivity.retrying => ('Retrying', Icons.replay_rounded),
      SessionActivity.unknown => ('Activity unknown', Icons.help_outline),
      SessionActivity.unavailable => ('Status unavailable', Icons.sync_problem),
    };
    final project = _directoryName(session.directory);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('Copy session ID'),
              onTap: () => Navigator.pop(context, _SessionAction.copyId),
            ),
            if (canRename)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(context, _SessionAction.rename),
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
    );
    switch (action) {
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

enum _SessionAction { copyId, rename, delete }

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
