import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/ui.dart';
import '../domain/connection_result.dart';
import '../domain/connection_origin_policy.dart';
import '../domain/server_profile.dart';
import '../domain/agent_backend.dart';
import 'connection_view_model.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    required this.viewModel,
    required this.profileLoader,
    required this.onConnected,
    this.restoreAutomatically = true,
    super.key,
  });

  final ConnectionViewModel viewModel;
  final Future<ServerProfile?> Function() profileLoader;
  final ValueChanged<ServerProfile> onConnected;
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
  ServerProfile? _prefilledProfile;
  ConnectionReady? _notifiedReady;
  AgentBackend _backend = AgentBackend.directOpenCode;

  @override
  void initState() {
    super.initState();
    _restoreLastProfile();
  }

  Future<void> _restoreLastProfile() async {
    final generation = widget.viewModel.operationGeneration;
    final profile = await widget.profileLoader();
    if (!mounted ||
        profile == null ||
        _editedAddress ||
        generation != widget.viewModel.operationGeneration) {
      return;
    }
    _originController.text = profile.origin.toString();
    _usernameController.text = profile.username ?? '';
    _prefilledProfile = profile;
    setState(() => _backend = profile.backend);
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
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

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
    if (password == null && _prefilledProfile?.id == profile.id) {
      await widget.viewModel.restore(profile);
    } else {
      await widget.viewModel.connect(profile, password);
    }
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
      return 'HTTP is only permitted for a private WireGuard or Tailscale address.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
                        widget.onConnected(profile);
                      });
                    }

                    final checking = state is ConnectionChecking;
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
                              'Connect Prompt',
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your agents. Your machine. Connect through WireGuard or Tailscale, without a public relay.',
                              style: theme.textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            DropdownButtonFormField<AgentBackend>(
                              key: ValueKey(_backend),
                              isExpanded: true,
                              itemHeight: null,
                              initialValue: _backend,
                              decoration: const InputDecoration(
                                labelText: 'Agent connection',
                              ),
                              items: AgentBackend.values
                                  .map(
                                    (backend) => DropdownMenuItem(
                                      value: backend,
                                      child: Text(
                                        backend.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: checking
                                  ? null
                                  : (backend) {
                                      if (backend == null) return;
                                      setState(() {
                                        _backend = backend;
                                        _editedAddress = true;
                                        if (backend.isGateway &&
                                            _usernameController.text.isEmpty) {
                                          _usernameController.text = 'prompt';
                                        }
                                      });
                                    },
                            ),
                            const SizedBox(height: 16),
                            AppTextFormField(
                              label: 'Private server address',
                              hint: 'http://10.0.0.1:4096',
                              controller: _originController,
                              enabled: !checking,
                              autofocus: true,
                              autocorrect: false,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.url],
                              onChanged: (_) => _editedAddress = true,
                              validator: _validateOrigin,
                            ),
                            const SizedBox(height: 16),
                            AppTextFormField(
                              label: 'Username (optional)',
                              controller: _usernameController,
                              enabled: !checking,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
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
                              onSubmitted: (_) => _connect(),
                            ),
                            if (_prefilledProfile != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Leave the password blank to use the saved credential.',
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              'HTTP is permitted only on a private WireGuard or Tailscale address. Credentials stay on this device.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            if (failure != null) ...[
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  failure.message,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            AppButton(
                              label: 'Test private connection',
                              busy: checking,
                              onPressed: checking ? null : _connect,
                            ),
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
