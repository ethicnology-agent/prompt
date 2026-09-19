import 'dart:async';

import 'package:flutter/material.dart';

import '../features/connection/connection.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/settings/settings.dart';
import '../features/sessions/sessions.dart';
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
  ServerProfile? _disconnectedProfile;
  bool _restoreAutomatically = true;
  Future<void>? _disconnectCleanup;
  SessionLaunch? _initialLaunch;
  bool _openingLaunch = false;
  int _launchRevision = 0;
  final Set<(String, String)> _openedLaunches = {};
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
    if (_connectedProfile == null || _openingLaunch) {
      coordinator.notifyAppInactive();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      coordinator.notifyAppForeground();
    } else {
      coordinator.notifyAppInactive();
    }
  }

  void _openConnectedServer(ServerProfile profile) async {
    final generation = _dependencies.connectionViewModel.operationGeneration;
    await _disconnectCleanup;
    if (!mounted ||
        generation != _dependencies.connectionViewModel.operationGeneration ||
        _dependencies.connectionViewModel.value is! ConnectionReady) {
      return;
    }
    _dependencies.queueCoordinator?.notifyAppForeground();
    setState(() => _connectedProfile = profile);
  }

  void _disconnect() {
    _launchRevision++;
    _openingLaunch = false;
    _initialLaunch = null;
    _disconnectedProfile = _connectedProfile;
    _restoreAutomatically = false;
    _dependencies.connectionViewModel.reset();
    // Suspend dispatch synchronously. A new connection waits for the old
    // conversation's asynchronous teardown before mounting another session.
    _dependencies.queueCoordinator?.notifyAppInactive();
    _disconnectCleanup = Future.wait([
      _dependencies.conversationViewModel.leave(),
      _dependencies.voiceViewModel.notifyAppInactive(),
    ]).then((_) {});
    setState(() => _connectedProfile = null);
  }

  void _openSessionLaunch(SessionLaunch launch) async {
    final identity = (launch.profile.id, launch.session.id);
    if (!_openedLaunches.add(identity)) return;
    final revision = ++_launchRevision;
    _dependencies.connectionViewModel.reset();
    _dependencies.queueCoordinator?.notifyAppInactive();
    setState(() => _openingLaunch = true);
    await _dependencies.conversationViewModel.leave();
    await _dependencies.voiceViewModel.notifyAppInactive();
    if (!mounted || revision != _launchRevision) return;
    _dependencies.conversationViewModel.rememberExecutionOptions(
      launch.profile,
      launch.session,
      launch.options,
    );
    _dependencies.conversationViewModel.rememberDraft(
      launch.profile,
      launch.session,
      launch.draft,
    );
    final accepted = await _dependencies.queueLaunchDraft(launch);
    if (accepted) {
      _dependencies.conversationViewModel.rememberDraft(
        launch.profile,
        launch.session,
        '',
      );
    }
    if (!mounted || revision != _launchRevision) return;
    await Future.wait([
      _dependencies.sessionsViewModel.load(launch.profile),
      _dependencies.capabilitiesViewModel.load(launch.profile),
    ]);
    if (!mounted || revision != _launchRevision) return;
    _dependencies.queueCoordinator?.notifyAppForeground();
    setState(() {
      _connectedProfile = launch.profile;
      _initialLaunch = launch;
      _openingLaunch = false;
    });
  }

  Future<bool> _reconnect() async {
    final profile = _connectedProfile;
    if (profile == null) return false;
    await _dependencies.connectionViewModel.restore(profile);
    return mounted &&
        identical(profile, _connectedProfile) &&
        _dependencies.connectionViewModel.value is ConnectionReady;
  }

  Future<void> _replaceConnectedProfile(ServerProfile profile) async {
    if (_connectedProfile?.id == profile.id) return;
    final revision = ++_launchRevision;
    _dependencies.queueCoordinator?.notifyAppInactive();
    setState(() => _openingLaunch = true);
    await Future.wait([
      _dependencies.conversationViewModel.leave(),
      _dependencies.voiceViewModel.notifyAppInactive(),
    ]);
    if (!mounted || revision != _launchRevision) return;
    _dependencies.queueCoordinator?.notifyAppForeground();
    setState(() {
      _connectedProfile = profile;
      _initialLaunch = null;
      _openingLaunch = false;
    });
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
        home: _openingLaunch
            ? const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Opening session',
                  ),
                ),
              )
            : _connectedProfile == null
            ? ConnectionScreen(
                viewModel: _dependencies.connectionViewModel,
                profileLoader: _disconnectedProfile != null
                    ? () async => _disconnectedProfile
                    : widget.lastProfileLoader ?? _loadLastProfile,
                restoreAutomatically: _restoreAutomatically,
                onConnected: _openConnectedServer,
              )
            : HomeShell(
                key: ValueKey((
                  _connectedProfile!.id,
                  _initialLaunch?.session.id,
                )),
                profile: _connectedProfile!,
                sessionCreationViewModel:
                    _dependencies.sessionCreationViewModel,
                onSessionLaunched: _openSessionLaunch,
                initialLaunch: _initialLaunch,
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
                connectionViewModelFactory:
                    _dependencies.createConnectionViewModel,
                onProfileConnected: (profile) =>
                    unawaited(_replaceConnectedProfile(profile)),
                reviewViewModelFactory: _dependencies.createReviewViewModel,
              ),
      ),
    );
  }
}
