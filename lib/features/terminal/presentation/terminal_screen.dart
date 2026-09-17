import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';

import '../../connection/connection.dart';
import '../domain/remote_terminal.dart';
import 'terminal_view_model.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    required this.profile,
    required this.viewModel,
    super.key,
  });
  final ServerProfile profile;
  final TerminalViewModel viewModel;
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  final _directory = TextEditingController();
  final _input = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _directory.dispose();
    _input.dispose();
    unawaited(widget.viewModel.deactivate());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.viewModel.deactivate());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Remote terminal'),
      actions: [
        AppIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh terminals',
          onPressed: _load,
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'Experimental: commands run on the selected server directory. Output stays only in memory and is limited to 100 KiB.',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _directory,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            label: 'Server directory',
            hint: '/path/on/server',
            prefixIcon: Icons.folder_outlined,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<TerminalUiState>(
              valueListenable: widget.viewModel,
              builder: (context, state, _) => switch (state) {
                TerminalIdle() => const Center(
                  child: Text('Choose a server directory to list terminals.'),
                ),
                TerminalLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                TerminalUnavailable(:final failure) => _Unavailable(
                  failure: failure,
                  onRetry: _load,
                ),
                TerminalReady() => _Ready(
                  state: state,
                  onCreate: () => widget.viewModel.create(widget.profile),
                  onConnect: (id) =>
                      widget.viewModel.connect(widget.profile, id),
                  onClose: (id) => widget.viewModel.close(widget.profile, id),
                  input: _input,
                  onSend: _send,
                ),
              },
            ),
          ),
        ],
      ),
    ),
  );
  void _load() {
    final directory = _directory.text.trim();
    if (directory.isNotEmpty) widget.viewModel.load(widget.profile, directory);
  }

  void _send() {
    widget.viewModel.send('${_input.text}\n');
    _input.clear();
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.failure, required this.onRetry});
  final RemoteTerminalFailure failure;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.terminal_outlined, size: 48),
        const SizedBox(height: 12),
        const Text('Remote terminal unavailable'),
        const SizedBox(height: 8),
        Text(failure.message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        AppButton(
          label: 'Try again',
          variant: AppButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    ),
  );
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.state,
    required this.onCreate,
    required this.onConnect,
    required this.onClose,
    required this.input,
    required this.onSend,
  });
  final TerminalReady state;
  final VoidCallback onCreate;
  final ValueChanged<String> onConnect;
  final ValueChanged<String> onClose;
  final TextEditingController input;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text('Terminals', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          AppButton(
            label: 'New terminal',
            icon: Icons.add,
            onPressed: onCreate,
          ),
        ],
      ),
      if (state.failure != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            state.failure!.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        height: 132,
        child: state.terminals.isEmpty
            ? const Center(child: Text('No terminals in this directory.'))
            : ListView.builder(
                itemCount: state.terminals.length,
                itemBuilder: (context, index) {
                  final terminal = state.terminals[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      terminal.title.isEmpty
                          ? terminal.command
                          : terminal.title,
                    ),
                    subtitle: Text(
                      terminal.isRunning
                          ? 'Running in ${terminal.cwd}'
                          : 'Exited',
                    ),
                    trailing: AppIconButton(
                      icon: Icons.close,
                      tooltip: 'Close terminal',
                      onPressed: () => onClose(terminal.id),
                    ),
                    selected: state.activeId == terminal.id,
                    onTap: terminal.isRunning
                        ? () => onConnect(terminal.id)
                        : null,
                  );
                },
              ),
      ),
      const Divider(),
      Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              // Keep one selectable semantic text surface. The view model's
              // bounded buffer addresses streaming pressure; lazy output
              // would risk changing selection and accessibility semantics.
              state.connecting
                  ? 'Connecting...'
                  : state.output.isEmpty
                  ? 'Select a running terminal to connect.'
                  : state.output,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      AppTextField(
        controller: input,
        enabled: state.activeId != null && !state.connecting,
        onSubmitted: (_) => onSend(),
        label: 'Terminal input',
        suffix: AppIconButton(
          icon: Icons.send,
          tooltip: 'Send terminal input',
          onPressed: state.activeId == null || state.connecting ? null : onSend,
        ),
      ),
    ],
  );
}
