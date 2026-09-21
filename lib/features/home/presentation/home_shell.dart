import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/local_notification_service.dart';
import '../../../core/ui/ui.dart';
import '../../chat/chat.dart';
import '../../capabilities/capabilities.dart';
import '../../connection/connection.dart';
import '../../diagnostics/diagnostics.dart';
import '../../sessions/sessions.dart';
import '../../settings/settings.dart';
import '../../workspace/workspace.dart';
import '../../terminal/terminal.dart';
import '../../voice/voice.dart';
import '../../review/review.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.profile,
    required this.sessionsViewModel,
    required this.conversationViewModel,
    required this.capabilitiesViewModel,
    required this.workspaceViewModel,
    required this.terminalViewModel,
    required this.diagnosticsViewModel,
    required this.voiceViewModel,
    required this.localNotificationService,
    required this.themeViewModel,
    required this.onReconnect,
    required this.onDisconnect,
    this.connectionViewModelFactory,
    this.onProfileConnected,
    this.reviewViewModelFactory,
    this.sessionCreationViewModel,
    this.onSessionLaunched,
    this.initialLaunch,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel sessionsViewModel;
  final ConversationViewModel conversationViewModel;
  final CapabilitiesViewModel capabilitiesViewModel;
  final WorkspaceViewModel workspaceViewModel;
  final TerminalViewModel terminalViewModel;
  final DiagnosticsViewModel diagnosticsViewModel;
  final VoiceViewModel voiceViewModel;
  final LocalNotificationService localNotificationService;
  final ThemeViewModel themeViewModel;
  final Future<bool> Function() onReconnect;
  final VoidCallback onDisconnect;
  final ConnectionViewModel Function()? connectionViewModelFactory;
  final ValueChanged<ServerProfile>? onProfileConnected;
  final ReviewViewModel Function()? reviewViewModelFactory;
  final SessionCreationViewModel? sessionCreationViewModel;
  final ValueChanged<SessionLaunch>? onSessionLaunched;
  final SessionLaunch? initialLaunch;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _selection = ValueNotifier<ScopedSession?>(null);
  final _paneNavigator = GlobalKey<NavigatorState>();
  final _creationDraft = TextEditingController();
  final _creationFocus = FocusNode();
  Route<void>? _creationRoute;
  ScopedSession? get _selectedSession => _selection.value;
  set _selectedSession(ScopedSession? entry) => _selection.value = entry;
  double? _catalogWidth;
  bool _keepPaneEmpty = false;

  @override
  void initState() {
    super.initState();
    _selectedSession =
        (widget.initialLaunch == null
            ? null
            : ScopedSession(
                widget.initialLaunch!.profile,
                widget.initialLaunch!.session,
              )) ??
        _resolvedSelection(widget.sessionsViewModel.value, _selectedSession);
    widget.sessionsViewModel.addListener(_reconcileSelectedSession);
    if (widget.initialLaunch case final launch?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (MediaQuery.sizeOf(context).width < PromptBreakpoints.desktop) {
          _openConversation(
            context,
            ScopedSession(launch.profile, launch.session),
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionsViewModel != widget.sessionsViewModel) {
      oldWidget.sessionsViewModel.removeListener(_reconcileSelectedSession);
      widget.sessionsViewModel.addListener(_reconcileSelectedSession);
      _reconcileSelectedSession();
    }
  }

  @override
  void dispose() {
    widget.sessionsViewModel.removeListener(_reconcileSelectedSession);
    _selection.dispose();
    _creationDraft.dispose();
    _creationFocus.dispose();
    super.dispose();
  }

  void _reconcileSelectedSession() {
    if (!mounted) {
      return;
    }
    final state = widget.sessionsViewModel.value;
    if (state is! SessionsReady) {
      return;
    }
    final next = _resolvedSelection(state, _selectedSession);
    if (!identical(next, _selectedSession)) {
      setState(() => _selectedSession = next);
    }
  }

  ScopedSession? _resolvedSelection(
    SessionsUiState state,
    ScopedSession? selected,
  ) {
    if (state is! SessionsReady) {
      return selected;
    }
    if (selected == null && _keepPaneEmpty) return null;
    final entries = state.entriesFor(widget.profile);
    if (entries.isEmpty) {
      return null;
    }
    if (selected != null) {
      for (final session in entries) {
        if (_hasSameIdentity(session, selected)) {
          return session;
        }
      }
    }
    return entries.first;
  }

  bool _hasSameIdentity(ScopedSession left, ScopedSession right) {
    return left.identity == right.identity &&
        left.session.directory == right.session.directory;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= PromptBreakpoints.desktop;
        return _HomePaneLayout(
          desktop: desktop,
          child: Material(
            child: Row(
              // Paint the catalog after the pane's modal semantics boundary,
              // while keeping its visual position at the leading edge.
              textDirection: Directionality.of(context) == TextDirection.ltr
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              children: [
                if (desktop) ...[
                  SizedBox(
                    width: _catalogWidthFor(constraints.maxWidth),
                    child: _catalog(context, true),
                  ),
                  _DesktopResizeHandle(
                    key: const ValueKey('home-session-catalog-divider'),
                    label: 'Resize session catalog',
                    onDelta: (delta) => setState(() {
                      _catalogWidth = _clampCatalogWidth(
                        _catalogWidthFor(constraints.maxWidth) + delta,
                        constraints.maxWidth,
                      );
                    }),
                  ),
                ],
                Expanded(
                  child: NavigatorPopHandler<Object?>(
                    // `maybePop`, not `pop`: a screen inside the pane may want
                    // the back gesture for itself — a composer with an open
                    // choice panel closes the panel rather than leaving the
                    // conversation. Popping unconditionally walked straight
                    // past its `PopScope`.
                    onPopWithResult: (result) =>
                        _paneNavigator.currentState!.maybePop(result),
                    child: Navigator(
                      key: _paneNavigator,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (paneContext) =>
                            ValueListenableBuilder<ScopedSession?>(
                              valueListenable: _selection,
                              builder: (_, entry, _) =>
                                  _HomePaneLayout.of(paneContext).desktop
                                  ? _conversationPane(entry)
                                  : _catalog(paneContext, false),
                            ),
                      ),
                    ),
                  ),
                ),
              ].reversed.toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _catalog(BuildContext context, bool desktop) => SessionsScreen(
    embedded: desktop,
    profile: widget.profile,
    viewModel: widget.sessionsViewModel,
    capabilitiesViewModel: widget.capabilitiesViewModel,
    sessionCreationViewModel: _creationRoute == null
        ? widget.sessionCreationViewModel
        : null,
    onSessionLaunched: widget.onSessionLaunched,
    onOpenCreation:
        desktop &&
            widget.sessionCreationViewModel != null &&
            widget.onSessionLaunched != null
        ? _openCreation
        : null,
    onDisconnect: widget.onDisconnect,
    onOpenSession: (session) {
      if (desktop) {
        _selectDesktopSession(ScopedSession(widget.profile, session));
      } else {
        _openConversation(context, ScopedSession(widget.profile, session));
      }
    },
    onOpenScopedSession: (entry) {
      if (desktop) {
        _selectDesktopSession(entry);
      } else {
        _openConversation(context, entry);
      }
    },
    onSessionCreated: (session, draft, options) {
      widget.conversationViewModel.rememberExecutionOptions(
        widget.profile,
        session,
        options,
      );
      widget.conversationViewModel.rememberDraft(
        widget.profile,
        session,
        draft,
      );
      if (desktop) {
        _selectDesktopSession(ScopedSession(widget.profile, session));
      } else {
        _openConversation(context, ScopedSession(widget.profile, session));
      }
    },
    onOpenWorkspace: (projects) => _openWorkspace(context, projects),
    onOpenTerminal: () => _openTerminal(context),
    onOpenDiagnostics: () => _openDiagnostics(context),
    onOpenSettings: () => _openSettings(context),
    onOpenVoiceSettings: () => _openVoiceSettings(context),
  );

  Widget _conversationPane(ScopedSession? selected) => switch (selected) {
    final entry? => ConversationScreen(
      key: ValueKey(('conversation', entry.identity, entry.session.directory)),
      profile: entry.profile,
      session: entry.session,
      viewModel: widget.conversationViewModel,
      capabilitiesViewModel: widget.capabilitiesViewModel,
      voiceViewModel: widget.voiceViewModel,
      onOpenFork: (forked) =>
          _selectDesktopSession(ScopedSession(entry.profile, forked)),
      onOpenFile: (path) => _openSessionFile(context, entry, path),
      reviewViewModelFactory: widget.reviewViewModelFactory,
      onSessionDeleted: () => unawaited(_sessionDeleted(entry)),
    ),
    _ => const _EmptyMasterDetail(),
  };

  void _selectDesktopSession(ScopedSession entry) {
    _selectedSession = entry;
    _paneNavigator.currentState!.popUntil((route) => route.isFirst);
  }

  void _openCreation() {
    final navigator = _paneNavigator.currentState!;
    if (_creationRoute case final route?) {
      navigator.popUntil((candidate) => candidate == route);
      _creationFocus.requestFocus();
      return;
    }
    final state = widget.sessionsViewModel.value;
    final projects = state is SessionsReady
        ? state.projects
        : const <OpenCodeProject>[];
    final directory =
        projects
            .where((project) => project.id != 'global')
            .firstOrNull
            ?.directory ??
        '';
    final route = MaterialPageRoute<void>(
      builder: (_) => SessionCreationScreen(
        profile: widget.profile,
        viewModel: widget.sessionCreationViewModel!,
        controller: _creationDraft,
        focusNode: _creationFocus,
        initialDirectory: directory,
        onLaunch: widget.onSessionLaunched!,
      ),
    );
    _creationRoute = route;
    unawaited(navigator.push(route));
    unawaited(
      route.completed.whenComplete(() {
        if (_creationRoute == route && mounted) {
          setState(() => _creationRoute = null);
        }
      }),
    );
  }

  Future<void> _reconcileAfterReload() async {
    await Future.wait([
      widget.sessionsViewModel.load(widget.profile),
      widget.capabilitiesViewModel.load(widget.profile),
    ]);
  }

  double _catalogWidthFor(double totalWidth) {
    final maximum = (totalWidth - 640).clamp(240.0, double.infinity);
    final width = _catalogWidth ?? (totalWidth * .3).clamp(280.0, 336.0);
    return width.clamp(240.0, maximum);
  }

  double _clampCatalogWidth(double width, double totalWidth) {
    final maximum = (totalWidth - 640).clamp(240.0, double.infinity);
    return width.clamp(240.0, maximum);
  }

  void _openDiagnostics(BuildContext context) {
    _paneNavigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsScreen(
          profile: widget.profile,
          viewModel: widget.diagnosticsViewModel,
          localNotificationService: widget.localNotificationService,
          themeViewModel: widget.themeViewModel,
          onReconnect: widget.onReconnect,
          onDisconnect: widget.onDisconnect,
          onReloadReconciled: _reconcileAfterReload,
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    final sessionState = widget.sessionsViewModel.value;
    _paneNavigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (settingsContext) => SettingsScreen(
          serverLabel:
              '${widget.profile.backend.label}\n${widget.profile.displayOrigin}',
          themeViewModel: widget.themeViewModel,
          onOpenWorkspace:
              widget.profile.capabilities.supports(BackendFeature.workspace) &&
                  sessionState is SessionsReady
              ? () => _openWorkspace(settingsContext, sessionState.projects)
              : null,
          onOpenTerminal:
              widget.profile.capabilities.supports(BackendFeature.terminal)
              ? () => _openTerminal(settingsContext)
              : null,
          onOpenServer:
              widget.profile.capabilities.supports(BackendFeature.configuration)
              ? () => _openDiagnostics(settingsContext)
              : null,
          onScanPairing:
              widget.connectionViewModelFactory != null &&
                  widget.onProfileConnected != null
              ? () => _openPairing(settingsContext)
              : null,
          onOpenVoice: () => _openVoiceSettings(settingsContext),
          onOpenNotifications: () => Navigator.of(settingsContext).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationSettingsScreen(
                service: widget.localNotificationService,
              ),
            ),
          ),
          onDisconnect: () {
            Navigator.of(settingsContext).pop();
            widget.onDisconnect();
          },
        ),
      ),
    );
  }

  Future<void> _openPairing(BuildContext context) async {
    final viewModel = widget.connectionViewModelFactory?.call();
    if (viewModel == null) return;
    try {
      final profile = await _paneNavigator.currentState!.push<ServerProfile>(
        MaterialPageRoute<ServerProfile>(
          builder: (pairingContext) => ConnectionScreen(
            viewModel: viewModel,
            profileLoader: () async => null,
            restoreAutomatically: false,
            onConnected: (profile) => Navigator.of(pairingContext).pop(profile),
          ),
        ),
      );
      if (profile != null) {
        if (context.mounted) Navigator.of(context).pop();
        widget.onProfileConnected?.call(profile);
      }
    } finally {
      viewModel.dispose();
    }
  }

  void _openVoiceSettings(BuildContext context) {
    _paneNavigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceSettingsScreen(viewModel: widget.voiceViewModel),
      ),
    );
  }

  void _openTerminal(BuildContext context) {
    _paneNavigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          profile: widget.profile,
          viewModel: widget.terminalViewModel,
        ),
      ),
    );
  }

  void _openWorkspace(BuildContext context, List<OpenCodeProject> projects) {
    _paneNavigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          profile: widget.profile,
          projects: projects,
          viewModel: widget.workspaceViewModel,
        ),
      ),
    );
  }

  void _openSessionFile(
    BuildContext context,
    ScopedSession entry,
    String path,
  ) {
    if (!entry.profile.capabilities.supports(BackendFeature.workspace)) return;
    _paneNavigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceFileScreen(
          profile: entry.profile,
          directory: entry.session.directory,
          path: path,
          viewModel: widget.workspaceViewModel.createFileViewModel(),
        ),
      ),
    );
  }

  Future<void> _openConversation(
    BuildContext context,
    ScopedSession entry,
  ) async {
    final deleted = await _paneNavigator.currentState!.push<bool>(
      _conversationRoute(context, entry),
    );
    if (mounted && deleted != true) {
      await widget.sessionsViewModel.load(widget.profile);
    }
  }

  Future<void> _sessionDeleted(ScopedSession entry) async {
    if (!mounted) return;
    if (_selectedSession case final selected?) {
      if (_hasSameIdentity(selected, entry)) {
        setState(() {
          _selectedSession = null;
          _keepPaneEmpty = true;
        });
      }
    }
    await widget.sessionsViewModel.load(widget.profile);
  }

  MaterialPageRoute<bool> _conversationRoute(
    BuildContext context,
    ScopedSession entry,
  ) {
    late final MaterialPageRoute<bool> route;
    route = MaterialPageRoute<bool>(
      builder: (_) => ConversationScreen(
        profile: entry.profile,
        session: entry.session,
        viewModel: widget.conversationViewModel,
        capabilitiesViewModel: widget.capabilitiesViewModel,
        voiceViewModel: widget.voiceViewModel,
        onOpenFork: (forked) =>
            _replaceConversation(context, ScopedSession(entry.profile, forked)),
        onOpenFile: (path) => _openSessionFile(context, entry, path),
        reviewViewModelFactory: widget.reviewViewModelFactory,
        onSessionDeleted: () {
          final navigator = route.navigator;
          if (navigator != null) navigator.removeRoute(route, true);
          unawaited(_sessionDeleted(entry));
        },
      ),
    );
    return route;
  }

  void _replaceConversation(BuildContext context, ScopedSession entry) {
    _paneNavigator.currentState!.pushReplacement<bool, bool>(
      _conversationRoute(context, entry),
    );
  }
}

/// Carries the outer shell's width decision through its nested routes.
class _HomePaneLayout extends InheritedWidget {
  const _HomePaneLayout({required this.desktop, required super.child});

  final bool desktop;

  static _HomePaneLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HomePaneLayout>()!;

  @override
  bool updateShouldNotify(_HomePaneLayout oldWidget) =>
      desktop != oldWidget.desktop;
}

class _EmptyMasterDetail extends StatelessWidget {
  const _EmptyMasterDetail();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, size: 40),
        SizedBox(height: 12),
        Text('Start a conversation'),
        SizedBox(height: 4),
        Text('Create a session from the catalog to get started.'),
      ],
    ),
  );
}

/// Width of the pane splitter's interactive area.
///
/// The separator itself stays a hairline; this box is what the pointer has to
/// hit. It is sized from WCAG 2.5.8 (Target Size, Minimum, Level AA), which
/// asks for 24x24, rather than from Material's 48x48 tap target: the splitter
/// lives inside the desktop layout, so every extra logical pixel here is taken
/// from the transcript beside it. Widening it further would have to overlay a
/// neighbouring pane, and an opaque overlay swallows taps meant for the
/// session catalog.
const double _desktopResizeHandleWidth = 24;

class _DesktopResizeHandle extends StatefulWidget {
  const _DesktopResizeHandle({
    required this.label,
    required this.onDelta,
    super.key,
  });

  final String label;
  final ValueChanged<double> onDelta;

  @override
  State<_DesktopResizeHandle> createState() => _DesktopResizeHandleState();
}

class _ResizeLeftIntent extends Intent {
  const _ResizeLeftIntent();
}

class _ResizeRightIntent extends Intent {
  const _ResizeRightIntent();
}

class _DesktopResizeHandleState extends State<_DesktopResizeHandle> {
  late final FocusNode _focusNode = FocusNode(debugLabel: widget.label);
  bool _showFocusHighlight = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: Semantics(
        label: widget.label,
        onIncrease: () => widget.onDelta(24),
        onDecrease: () => widget.onDelta(-24),
        child: FocusableActionDetector(
          focusNode: _focusNode,
          onShowFocusHighlight: (show) =>
              setState(() => _showFocusHighlight = show),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): _ResizeLeftIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                _ResizeRightIntent(),
          },
          actions: {
            _ResizeLeftIntent: CallbackAction<_ResizeLeftIntent>(
              onInvoke: (_) {
                widget.onDelta(-24);
                return null;
              },
            ),
            _ResizeRightIntent: CallbackAction<_ResizeRightIntent>(
              onInvoke: (_) {
                widget.onDelta(24);
                return null;
              },
            ),
          },
          child: DecoratedBox(
            decoration: _showFocusHighlight
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  )
                : const BoxDecoration(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  widget.onDelta(details.delta.dx),
              child: const SizedBox(
                width: _desktopResizeHandleWidth,
                child: Center(child: VerticalDivider(width: 1)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
