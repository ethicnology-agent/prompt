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
    this.reviewViewModelFactory,
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
  final ReviewViewModel Function()? reviewViewModelFactory;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  OpenCodeSession? _selectedSession;
  double? _catalogWidth;

  @override
  void initState() {
    super.initState();
    _selectedSession = _resolvedSelection(
      widget.sessionsViewModel.value,
      _selectedSession,
    );
    widget.sessionsViewModel.addListener(_reconcileSelectedSession);
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

  OpenCodeSession? _resolvedSelection(
    SessionsUiState state,
    OpenCodeSession? selected,
  ) {
    if (state is! SessionsReady) {
      return selected;
    }
    if (state.sessions.isEmpty) {
      return null;
    }
    if (selected != null) {
      for (final session in state.sessions) {
        if (_hasSameIdentity(session, selected)) {
          return session;
        }
      }
    }
    return state.sessions.first;
  }

  bool _hasSameIdentity(OpenCodeSession left, OpenCodeSession right) {
    return left.id == right.id && left.directory == right.directory;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= PromptBreakpoints.desktop;
        final sessions = SessionsScreen(
          embedded: desktop,
          profile: widget.profile,
          viewModel: widget.sessionsViewModel,
          onDisconnect: widget.onDisconnect,
          onOpenSession: (session) {
            if (desktop) {
              setState(() => _selectedSession = session);
            } else {
              _openConversation(context, session);
            }
          },
          onOpenSessionWithDraft: (session, draft) {
            widget.conversationViewModel.rememberDraft(
              widget.profile,
              session,
              draft,
            );
            if (desktop) {
              setState(() => _selectedSession = session);
            } else {
              _openConversation(context, session);
            }
          },
          onOpenWorkspace: (projects) => _openWorkspace(context, projects),
          onOpenTerminal: () => _openTerminal(context),
          onOpenDiagnostics: () => _openDiagnostics(context),
          onOpenSettings: () => _openSettings(context),
          onOpenVoiceSettings: () => _openVoiceSettings(context),
        );
        if (!desktop) return sessions;
        final catalogWidth = _catalogWidthFor(constraints.maxWidth);
        final resizeHandle = _DesktopResizeHandle(
          key: const ValueKey('home-session-catalog-divider'),
          label: 'Resize session catalog',
          onDelta: (delta) => setState(() {
            _catalogWidth = _clampCatalogWidth(
              _catalogWidthFor(constraints.maxWidth) + delta,
              constraints.maxWidth,
            );
          }),
        );
        return Row(
          children: [
            SizedBox(width: catalogWidth, child: sessions),
            resizeHandle,
            Expanded(
              child: switch (_selectedSession) {
                final session? => ConversationScreen(
                  key: ValueKey('conversation:${session.id}'),
                  profile: widget.profile,
                  session: session,
                  viewModel: widget.conversationViewModel,
                  capabilitiesViewModel: widget.capabilitiesViewModel,
                  voiceViewModel: widget.voiceViewModel,
                  onOpenFork: (forked) =>
                      setState(() => _selectedSession = forked),
                  reviewViewModelFactory: widget.reviewViewModelFactory,
                ),
                _ => const _EmptyMasterDetail(),
              },
            ),
          ],
        );
      },
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
    final width = _catalogWidth ?? (totalWidth * .2).clamp(280.0, 400.0);
    return width.clamp(240.0, maximum);
  }

  double _clampCatalogWidth(double width, double totalWidth) {
    final maximum = (totalWidth - 640).clamp(240.0, double.infinity);
    return width.clamp(240.0, maximum);
  }

  void _openDiagnostics(BuildContext context) {
    Navigator.of(context).push(
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
    Navigator.of(context).push(
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

  void _openVoiceSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceSettingsScreen(viewModel: widget.voiceViewModel),
      ),
    );
  }

  void _openTerminal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          profile: widget.profile,
          viewModel: widget.terminalViewModel,
        ),
      ),
    );
  }

  void _openWorkspace(BuildContext context, List<OpenCodeProject> projects) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          profile: widget.profile,
          projects: projects,
          viewModel: widget.workspaceViewModel,
        ),
      ),
    );
  }

  Future<void> _openConversation(
    BuildContext context,
    OpenCodeSession session,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          profile: widget.profile,
          session: session,
          viewModel: widget.conversationViewModel,
          capabilitiesViewModel: widget.capabilitiesViewModel,
          voiceViewModel: widget.voiceViewModel,
          onOpenFork: (forked) => _replaceConversation(context, forked),
          reviewViewModelFactory: widget.reviewViewModelFactory,
        ),
      ),
    );
    await widget.sessionsViewModel.load(widget.profile);
  }

  void _replaceConversation(BuildContext context, OpenCodeSession session) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          profile: widget.profile,
          session: session,
          viewModel: widget.conversationViewModel,
          capabilitiesViewModel: widget.capabilitiesViewModel,
          voiceViewModel: widget.voiceViewModel,
          onOpenFork: (forked) => _replaceConversation(context, forked),
          reviewViewModelFactory: widget.reviewViewModelFactory,
        ),
      ),
    );
  }
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
