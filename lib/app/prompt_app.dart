import 'dart:async';

import 'package:flutter/material.dart';

import '../features/connection/connection.dart';
import '../features/connection/presentation/connection_screen.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/settings/settings.dart';
import 'app_dependencies.dart';
import 'prompt_theme.dart';
import 'third_party_licenses.dart';

class PromptApp extends StatefulWidget {
  const PromptApp({
    this.dependencies,
    this.lastProfileLoader,
    this.themePreferenceStore,
    super.key,
  });

  final AppDependencies? dependencies;
  final Future<ServerProfile?> Function()? lastProfileLoader;
  final ThemePreferenceStore? themePreferenceStore;

  @override
  State<PromptApp> createState() => _PromptAppState();
}

class _PromptAppState extends State<PromptApp> {
  late final AppDependencies _dependencies;
  ServerProfile? _connectedProfile;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    registerThirdPartyLicenses();
    _dependencies =
        widget.dependencies ??
        AppDependencies.create(
          themePreferenceStore: widget.themePreferenceStore,
        );
    _appLifecycleListener = AppLifecycleListener(
      onStateChange: _handleAppLifecycleStateChange,
    );
    unawaited(_dependencies.themeViewModel.load());
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    unawaited(_dependencies.dispose());
    super.dispose();
  }

  void _handleAppLifecycleStateChange(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _dependencies.conversationViewModel.releaseAttachments();
      unawaited(_dependencies.voiceViewModel.notifyAppInactive());
    }
    final coordinator = _dependencies.queueCoordinator;
    if (coordinator == null) return;
    if (state == AppLifecycleState.resumed) {
      coordinator.notifyAppForeground();
    } else {
      coordinator.notifyAppInactive();
    }
  }

  void _openConnectedServer(ServerProfile profile) {
    setState(() => _connectedProfile = profile);
  }

  void _disconnect() {
    _dependencies.connectionViewModel.reset();
    setState(() => _connectedProfile = null);
  }

  Future<bool> _reconnect() async {
    final profile = _connectedProfile;
    if (profile == null) return false;
    await _dependencies.connectionViewModel.restore(profile);
    return _dependencies.connectionViewModel.value is ConnectionReady;
  }

  Future<ServerProfile?> _loadLastProfile() async {
    return (await _dependencies.ensureStorage()).serverProfiles.loadLast();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _dependencies.themeViewModel,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Prompt',
        debugShowCheckedModeBanner: false,
        theme: promptTheme(),
        darkTheme: promptDarkTheme(),
        themeMode: themeMode,
        home: _connectedProfile == null
            ? ConnectionScreen(
                viewModel: _dependencies.connectionViewModel,
                profileLoader: widget.lastProfileLoader ?? _loadLastProfile,
                onConnected: _openConnectedServer,
              )
            : HomeShell(
                profile: _connectedProfile!,
                sessionsViewModel: _dependencies.sessionsViewModel,
                conversationViewModel: _dependencies.conversationViewModel,
                capabilitiesViewModel: _dependencies.capabilitiesViewModel,
                workspaceViewModel: _dependencies.workspaceViewModel,
                terminalViewModel: _dependencies.terminalViewModel,
                diagnosticsViewModel: _dependencies.diagnosticsViewModel,
                voiceViewModel: _dependencies.voiceViewModel,
                localNotificationService:
                    _dependencies.localNotificationService,
                themeViewModel: _dependencies.themeViewModel,
                onReconnect: _reconnect,
                onDisconnect: _disconnect,
                reviewViewModelFactory: _dependencies.createReviewViewModel,
              ),
      ),
    );
  }
}
