import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/ui.dart';
import '../data/pairing_code_scanner.dart';
import '../domain/connection_result.dart';
import '../domain/connection_origin_policy.dart';
import '../domain/pairing_configuration.dart';
import '../domain/server_profile.dart';
import '../domain/agent_backend.dart';
import 'connection_view_model.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    required this.viewModel,
    required this.profileLoader,
    required this.onConnected,
    this.pairingCodeScanner,
    this.scanAutomatically = false,
    this.restoreAutomatically = true,
    super.key,
  });

  final ConnectionViewModel viewModel;
  final Future<ServerProfile?> Function() profileLoader;
  final ValueChanged<ServerProfile> onConnected;
  final PairingCodeScanner? pairingCodeScanner;
  final bool scanAutomatically;
  final bool restoreAutomatically;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _originController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _editedAddress = false;
  bool _profileLoadFailed = false;
  bool _scanningPairingCode = false;
  bool _manualExpanded = true;
  bool _credentialsExpanded = false;
  bool _showNetworkHelp = false;
  String? _pairingMessage;
  String? _pairingTicket;
  ServerProfile? _prefilledProfile;
  ConnectionReady? _notifiedReady;
  AgentBackend _backend = AgentBackend.directOpenCode;

  PairingCodeScanner get _pairingCodeScanner =>
      widget.pairingCodeScanner ?? createPairingCodeScanner();

  @override
  void initState() {
    super.initState();
    _restoreLastProfile();
    if (widget.scanAutomatically && _pairingCodeScanner.isAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanPairingCode();
      });
    }
  }

  Future<void> _restoreLastProfile() async {
    final generation = widget.viewModel.operationGeneration;
    ServerProfile? profile;
    try {
      profile = await widget.profileLoader();
    } on Exception {
      if (mounted &&
          !_editedAddress &&
          generation == widget.viewModel.operationGeneration) {
        setState(() => _profileLoadFailed = true);
      }
      return;
    }
    if (!mounted ||
        profile == null ||
        _editedAddress ||
        generation != widget.viewModel.operationGeneration) {
      return;
    }
    _originController.text = profile.origin.toString();
    _usernameController.text = profile.username ?? '';
    _prefilledProfile = profile;
    _credentialsExpanded = profile.username?.isNotEmpty ?? false;
    final backend = profile.backend;
    setState(() => _backend = backend);
    if (widget.restoreAutomatically) await widget.viewModel.restore(profile);
  }

  @override
  void dispose() {
    _originController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_scanningPairingCode || widget.viewModel.value is ConnectionChecking) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final originError = _validateOrigin(_originController.text);
    if (originError != null) {
      setState(() => _pairingMessage = originError);
      return;
    }

    if (_profileLoadFailed) setState(() => _profileLoadFailed = false);

    final profile = ServerProfile(
      origin: Uri.parse(_originController.text.trim()),
      backend: _backend,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
    );
    final password = _passwordController.text.isEmpty
        ? null
        : _passwordController.text;
    final ticket = _pairingTicket;
    if (ticket != null) {
      await widget.viewModel.pair(profile, ticket);
      if (widget.viewModel.value is ConnectionReady) _pairingTicket = null;
    } else if (password == null && _prefilledProfile?.id == profile.id) {
      await widget.viewModel.restore(profile);
    } else {
      await widget.viewModel.connect(profile, password, detectBackend: true);
    }
  }

  Future<void> _scanPairingCode() async {
    if (_scanningPairingCode || widget.viewModel.value is ConnectionChecking) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _scanningPairingCode = true;
      _editedAddress = true;
      _pairingMessage = null;
    });
    final result = await _pairingCodeScanner.scan();
    if (!mounted) return;

    switch (result) {
      case PairingScanCompleted(:final value):
        switch (PairingConfiguration.parse(value)) {
          case PairingCodeAccepted(:final configuration):
            _originController.text = configuration.profile.displayOrigin;
            _usernameController.text = configuration.profile.username ?? '';
            _passwordController.clear();
            _pairingTicket = configuration.ticket;
            _prefilledProfile = null;
            setState(() {
              _backend = configuration.profile.backend;
              _manualExpanded = _credentialsExpanded;
              _editedAddress = true;
              _profileLoadFailed = false;
              _pairingMessage =
                  'Pairing code loaded. Review the private server, then connect.';
            });
          case PairingCodeRejected():
            setState(() {
              _pairingMessage =
                  'This pairing code is invalid or does not use a private server.';
            });
        }
      case PairingScanCancelled():
        break;
      case PairingScanUnavailable():
        setState(() {
          _pairingMessage =
              'QR scanning is unavailable. Enter the private server manually.';
        });
      case PairingScanPermissionDenied():
        setState(() {
          _pairingMessage =
              'Camera access was not granted. Allow it in system settings or enter the private server manually.';
        });
    }
    if (mounted) setState(() => _scanningPairingCode = false);
  }

  void _markManualEdit() {
    _editedAddress = true;
    _pairingTicket = null;
  }

  void _toggleCredentials() {
    widget.viewModel.reset();
    setState(() {
      _credentialsExpanded = !_credentialsExpanded;
      if (!_credentialsExpanded) {
        _usernameController.clear();
        _passwordController.clear();
        _prefilledProfile = null;
        _pairingMessage = null;
        _markManualEdit();
      }
    });
  }

  String? _validateOrigin(String? input) {
    final origin = Uri.tryParse(input?.trim() ?? '');
    if (origin == null || origin.host.isEmpty) {
      return 'Use a complete private server address.';
    }
    if (origin.scheme == 'http' && kIsWeb) {
      return 'Web browsers require HTTPS, even through WireGuard or Tailscale.';
    }
    if (!ConnectionOriginPolicy.supports(origin)) {
      return 'Use a private IP address, not a public address or hostname.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              leading: AppIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: ValueListenableBuilder<ConnectionUiState>(
                  valueListenable: widget.viewModel,
                  builder: (context, state, _) {
                    if (state case ConnectionReady(:final profile)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted ||
                            !identical(widget.viewModel.value, state) ||
                            identical(_notifiedReady, state)) {
                          return;
                        }
                        _notifiedReady = state;
                        TextInput.finishAutofillContext(shouldSave: true);
                        _passwordController.clear();
                        widget.onConnected(profile);
                      });
                    }

                    final checking = state is ConnectionChecking;
                    final canScan = _pairingCodeScanner.isAvailable;
                    final showDetails =
                        !canScan ||
                        _manualExpanded ||
                        _prefilledProfile != null;
                    final failure = state is ConnectionError
                        ? state.failure
                        : null;

                    return AutofillGroup(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 48,
                              color: theme.colorScheme.primary,
                              semanticLabel: 'Private connection',
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Connect a machine',
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enter the address of your private server to connect.',
                              style: theme.textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            const SizedBox(height: 8),
                            Text(
                              'This device must be able to reach your server through your local network or private VPN.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            if (_pairingMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _pairingMessage!,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            AppButton(
                              label: _showNetworkHelp
                                  ? 'Hide connection help'
                                  : 'How do I connect?',
                              variant: AppButtonVariant.tertiary,
                              onPressed: () => setState(
                                () => _showNetworkHelp = !_showNetworkHelp,
                              ),
                            ),
                            if (_showNetworkHelp)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  '1. Connect this device to your private network, such as Tailscale (including Headscale) or WireGuard.\n\n'
                                  '2. Enter your machine’s private server address, then connect. No extra login is needed when your server authorizes your network identity.\n\n'
                                  '3. Choose an available engine when starting a session.\n\n'
                                  'Other servers may require credentials or a pairing QR. Prompt does not set up your VPN or expose your server to the internet.',
                                ),
                              ),
                            if (_pairingTicket != null && !showDetails) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Machine found',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(_originController.text),
                              const SizedBox(height: 8),
                              const Text(
                                'Check that this is your computer before connecting.',
                              ),
                            ],
                            if (!showDetails)
                              AppButton(
                                label: _pairingTicket == null
                                    ? 'Enter details manually'
                                    : 'Edit connection details',
                                variant: AppButtonVariant.tertiary,
                                onPressed: checking || _scanningPairingCode
                                    ? null
                                    : () => setState(
                                        () => _manualExpanded = true,
                                      ),
                              ),
                            if (showDetails) ...[
                              const SizedBox(height: 24),
                              AppTextFormField(
                                label: 'Private server address',
                                hint: kIsWeb
                                    ? 'https://10.0.0.1:4096'
                                    : 'http://10.0.0.1:4096',
                                controller: _originController,
                                enabled: !checking,
                                autofocus: false,
                                autocorrect: false,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.url],
                                onChanged: (_) => _markManualEdit(),
                                validator: _validateOrigin,
                              ),
                              const SizedBox(height: 16),
                              AppButton(
                                label: _credentialsExpanded
                                    ? 'Use network identity'
                                    : 'Server requires credentials?',
                                variant: AppButtonVariant.tertiary,
                                onPressed: checking || _scanningPairingCode
                                    ? null
                                    : _toggleCredentials,
                              ),
                              if (_credentialsExpanded) ...[
                                const SizedBox(height: 16),
                                AppTextFormField(
                                  label: 'Username (optional)',
                                  controller: _usernameController,
                                  enabled: !checking,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.username],
                                  onChanged: (_) => _markManualEdit(),
                                ),
                                const SizedBox(height: 16),
                                AppTextFormField(
                                  label: 'Password (optional)',
                                  controller: _passwordController,
                                  enabled: !checking,
                                  obscureText: true,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  autofillHints: const [AutofillHints.password],
                                  onChanged: (_) => _markManualEdit(),
                                  onSubmitted: (_) => _connect(),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Use the credentials supplied by your Prompt server, not your Claude, Codex or OpenCode account. A pairing QR fills these in for you.',
                                ),
                                if (_prefilledProfile != null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Leave the password blank to use the saved credential.',
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                kIsWeb
                                    ? 'HTTPS with a browser-trusted certificate is required. Your server must allow this web app’s origin. Credentials belong to this browser profile.'
                                    : 'HTTP is permitted only for a private IP address. Credentials stay on this device.',
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Connect once. Choose Claude, Codex or OpenCode when starting a session, according to what your server provides.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (failure != null) ...[
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  failure == ConnectionFailure.unauthorized &&
                                          !_credentialsExpanded
                                      ? 'This server did not authorize the connection. Check your private-network access, or use server credentials if required.'
                                      : failure.message,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                            if (_profileLoadFailed)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: const Text(
                                    'Could not load the saved connection. Enter your server details to continue.',
                                  ),
                                ),
                              ),
                            if (showDetails ||
                                _pairingTicket != null ||
                                checking) ...[
                              const SizedBox(height: 24),
                              AppButton(
                                label: 'Connect',
                                busy: checking,
                                onPressed: checking || _scanningPairingCode
                                    ? null
                                    : _connect,
                              ),
                            ],
                            if (canScan) ...[
                              const SizedBox(height: 12),
                              AppButton(
                                label: 'Scan pairing QR',
                                icon: Icons.qr_code_scanner,
                                variant: AppButtonVariant.tertiary,
                                busy: _scanningPairingCode,
                                onPressed: checking || _scanningPairingCode
                                    ? null
                                    : _scanPairingCode,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
