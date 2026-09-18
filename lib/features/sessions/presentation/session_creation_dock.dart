import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../capabilities/capabilities.dart';
import '../../chat/chat.dart';
import '../../connection/connection.dart';
import '../../queue/queue.dart';
import '../domain/session_launch.dart';
import '../domain/session_worktree.dart';
import 'new_session_dock.dart';
import 'session_creation_view_model.dart';
import 'worktree_picker.dart';

enum _InlineChoice { engine, model, effort }

typedef _ModelIdentity = ({String providerId, String modelId});

/// Inline preparation of a real, backend-scoped session. Focus only loads
/// choices; only the explicit send action creates a session.
class SessionCreationDock extends StatefulWidget {
  const SessionCreationDock({
    required this.profile,
    required this.viewModel,
    required this.controller,
    required this.focusNode,
    required this.onLaunch,
    required this.onExpandedChanged,
    this.initialDirectory = '',
    super.key,
  });

  final ServerProfile profile;
  final SessionCreationViewModel viewModel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<SessionLaunch> onLaunch;
  final ValueChanged<bool> onExpandedChanged;
  final String initialDirectory;

  @override
  State<SessionCreationDock> createState() => _SessionCreationDockState();
}

class _SessionCreationDockState extends State<SessionCreationDock>
    with WidgetsBindingObserver {
  bool _expanded = false;
  bool _initialized = false;
  bool _launching = false;
  bool _showDirectory = false;
  bool _customDirectory = false;
  _InlineChoice? _choice;
  String? _choiceProfileId;
  AgentBackend? _choiceBackend;
  _ModelIdentity? _effortModel;
  final _directoryController = TextEditingController();
  final _directoryFocus = FocusNode();
  final _directoryForm = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        !widget.viewModel.isPickingAttachments) {
      widget.viewModel.releaseAttachments();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.viewModel.releaseAttachments();
    _directoryController.dispose();
    _directoryFocus.dispose();
    super.dispose();
  }

  void _expand(bool expanded) {
    if (!mounted || _launching) return;
    if (!expanded && _choice != null) {
      _closeChoice();
      return;
    }
    if (!expanded && _showDirectory) {
      _closeDirectory();
      return;
    }
    if (!expanded) widget.viewModel.cancelPreparation();
    setState(() => _expanded = expanded);
    widget.onExpandedChanged(expanded);
    if (expanded && !_initialized) {
      _initialized = true;
      unawaited(
        widget.viewModel.initialize(
          widget.profile,
          directory: widget.initialDirectory,
          draft: widget.controller.text,
        ),
      );
    }
  }

  Future<void> _send() async {
    if (!_expanded) {
      _expand(true);
      widget.focusNode.requestFocus();
      return;
    }
    if (_launching ||
        (widget.controller.text.trim().isEmpty &&
            widget.viewModel.attachments.value.isEmpty)) {
      return;
    }
    widget.viewModel.updateDraft(widget.controller.text);
    _launching = true;
    final launch = await widget.viewModel.create(submitDraft: true);
    if (!mounted) return;
    _launching = false;
    if (launch == null) return;
    widget.focusNode.unfocus();
    widget.controller.clear();
    _initialized = false;
    _expand(false);
    widget.onLaunch(launch);
  }

  Future<void> _attach() async {
    final result = await widget.viewModel.pickAttachments();
    if (!mounted) return;
    if (result case AttachmentPickRejected(:final message)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<T?> _choose<T>(
    String title,
    List<SelectionOption<T>> options,
    T? selected,
  ) async {
    widget.focusNode.unfocus();
    return showModalBottomSheet<T>(
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
            includeDefault: false,
            options: options,
            selected: selected,
            onApply: (value) => Navigator.of(context).pop(value),
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  void _directory(SessionCreationState state) {
    _directoryController.text = state.directory;
    setState(() {
      _showDirectory = true;
      _customDirectory = false;
      _choice = null;
    });
  }

  void _closeDirectory() {
    setState(() {
      _showDirectory = false;
      _customDirectory = false;
    });
    widget.focusNode.requestFocus();
  }

  Widget _directoryPanel(SessionCreationState state) {
    final enabled =
        state.phase == SessionCreationPhase.ready &&
        state.worktreePhase != WorktreePhase.creating;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIconButton(
              icon: Icons.close,
              tooltip: 'Close project choices',
              onPressed: _closeDirectory,
            ),
            Expanded(
              child: Text(
                'Project',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (!_customDirectory) ...[
          if (state.projects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No server projects reported.'),
            )
          else
            SizedBox(
              height:
                  (state.projects.length *
                          56.0 *
                          MediaQuery.textScalerOf(context).scale(1))
                      .clamp(56.0, 180.0),
              child: ListView.builder(
                key: const ValueKey('creation-project-choices'),
                primary: false,
                itemCount: state.projects.length,
                itemBuilder: (context, index) {
                  final project = state.projects[index];
                  return CreationConfigurationRow(
                    icon: project.directory == state.directory
                        ? Icons.check
                        : Icons.folder_outlined,
                    label: 'Server project',
                    value: project.directory,
                    onTap: !enabled
                        ? null
                        : () {
                            widget.viewModel.updateDirectory(project.directory);
                            _closeDirectory();
                          },
                  );
                },
              ),
            ),
          AppButton(
            label: 'Enter custom path',
            variant: AppButtonVariant.tertiary,
            leftAligned: true,
            onPressed: !enabled
                ? null
                : () {
                    setState(() => _customDirectory = true);
                    _directoryFocus.requestFocus();
                  },
          ),
        ] else
          Padding(
            padding: const EdgeInsets.all(12),
            child: Form(
              key: _directoryForm,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextFormField(
                    controller: _directoryController,
                    focusNode: _directoryFocus,
                    enabled: enabled,
                    label: 'Absolute server path',
                    validator: (value) {
                      final path = value?.trim() ?? '';
                      return (path.startsWith('/') ||
                                  RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) &&
                              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)
                          ? null
                          : 'Enter an absolute path on the connected machine.';
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Folder on the connected machine, not on this phone.',
                  ),
                  AppButton(
                    label: 'Use folder',
                    onPressed: !enabled
                        ? null
                        : () {
                            if (!(_directoryForm.currentState?.validate() ??
                                false)) {
                              return;
                            }
                            widget.viewModel.updateDirectory(
                              _directoryController.text.trim(),
                            );
                            _closeDirectory();
                          },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _openChoice(_InlineChoice choice, SessionCreationState state) {
    setState(() {
      _choice = choice;
      _choiceProfileId = state.profile?.id;
      _choiceBackend = state.backend;
      _showDirectory = false;
      _customDirectory = false;
    });
    widget.focusNode.requestFocus();
  }

  void _closeChoice() {
    setState(() => _choice = null);
    widget.focusNode.requestFocus();
  }

  bool _choiceIsCurrent(SessionCreationState state) =>
      !state.queuePending &&
      state.phase != SessionCreationPhase.creating &&
      state.phase != SessionCreationPhase.loading &&
      state.worktreePhase != WorktreePhase.creating &&
      state.profile?.id == _choiceProfileId &&
      state.backend == _choiceBackend;

  void _engine(SessionCreationState state) =>
      _openChoice(_InlineChoice.engine, state);

  List<OpenCodeModel> _models(SessionCreationState state) =>
      state.capabilities?.models
          .where(
            (model) =>
                model.isProviderConnected &&
                !(model.id == 'default' &&
                    model.providerId == state.backend?.engine &&
                    (state.backend == AgentBackend.gatewayCodex ||
                        state.backend == AgentBackend.gatewayClaude)),
          )
          .toList() ??
      [];

  Widget _choicePanel(SessionCreationState state, double listHeight) {
    final openedProfile = _choiceProfileId;
    final openedBackend = _choiceBackend;
    final openedChoice = _choice;
    final effortIdentity = _effortModel;
    bool canApply(SessionCreationState current) =>
        _choice == openedChoice &&
        current.profile?.id == openedProfile &&
        current.backend == openedBackend &&
        _choiceIsCurrent(current);
    final enabled = _choiceIsCurrent(state);
    if (_choice == _InlineChoice.engine) {
      return InlineSelectionPanel<AgentBackend>(
        listHeight:
            (state.backends.length *
                    (56 * MediaQuery.textScalerOf(context).scale(14) / 14))
                .clamp(48.0, listHeight),
        title: 'Coding engine',
        options: [
          for (final backend in state.backends)
            InlineSelectionOption(value: backend, label: _engineName(backend)),
        ],
        selected: state.backend,
        onClose: _closeChoice,
        onSelected: !enabled
            ? null
            : (backend) {
                final current = widget.viewModel.value;
                if (!canApply(current) || !current.backends.contains(backend)) {
                  return;
                }
                _closeChoice();
                unawaited(widget.viewModel.selectBackend(backend));
              },
      );
    }
    final models = _models(state);
    if (_choice == _InlineChoice.model) {
      final selected = models
          .where(
            (model) =>
                model.providerId == state.options.modelProviderId &&
                model.id == state.options.modelId,
          )
          .firstOrNull;
      return InlineSelectionPanel<_ModelIdentity?>(
        listHeight: listHeight,
        title: 'Model',
        options: [
          const InlineSelectionOption(
            value: null,
            label: 'CLI / server default',
          ),
          for (final model in models)
            InlineSelectionOption(
              value: (providerId: model.providerId, modelId: model.id),
              label: model.name,
              description: model.id,
              groupLabel: model.providerId,
            ),
        ],
        selected: selected == null
            ? null
            : (providerId: selected.providerId, modelId: selected.id),
        onClose: _closeChoice,
        onSelected: !enabled
            ? null
            : (identity) {
                final current = widget.viewModel.value;
                if (!canApply(current) ||
                    (identity != null &&
                        !_models(current).any(
                          (model) =>
                              model.providerId == identity.providerId &&
                              model.id == identity.modelId,
                        ))) {
                  return;
                }
                widget.viewModel.updateOptions(
                  PromptExecutionOptions(
                    modelProviderId: identity?.providerId,
                    modelId: identity?.modelId,
                    agentName: current.options.agentName,
                    reasoningEffort:
                        identity?.providerId ==
                                current.options.modelProviderId &&
                            identity?.modelId == current.options.modelId
                        ? current.options.reasoningEffort
                        : null,
                  ),
                );
                _closeChoice();
              },
      );
    }
    final model = models
        .where(
          (model) =>
              model.providerId == _effortModel?.providerId &&
              model.id == _effortModel?.modelId,
        )
        .firstOrNull;
    final choices = model?.executionOptions?.reasoningEfforts ?? [];
    final sameModel =
        state.options.modelProviderId == _effortModel?.providerId &&
        state.options.modelId == _effortModel?.modelId;
    return InlineSelectionPanel<String?>(
      listHeight: listHeight,
      title: 'Reasoning effort',
      options: [
        const InlineSelectionOption(value: null, label: 'Engine default'),
        for (final choice in choices)
          InlineSelectionOption(
            value: choice.id,
            label: choice.label,
            description: choice.description,
          ),
      ],
      selected: state.options.reasoningEffort,
      onClose: _closeChoice,
      onSelected: !enabled || !sameModel || choices.isEmpty
          ? null
          : (effort) {
              final current = widget.viewModel.value;
              final currentModel = _models(current)
                  .where(
                    (model) =>
                        model.providerId == _effortModel?.providerId &&
                        model.id == _effortModel?.modelId,
                  )
                  .firstOrNull;
              if (!canApply(current) ||
                  _effortModel != effortIdentity ||
                  current.options.modelProviderId != _effortModel?.providerId ||
                  current.options.modelId != _effortModel?.modelId ||
                  currentModel == null ||
                  (effort != null &&
                      !(currentModel.executionOptions?.reasoningEfforts.any(
                            (choice) => choice.id == effort,
                          ) ??
                          false))) {
                return;
              }
              widget.viewModel.updateOptions(
                PromptExecutionOptions(
                  modelProviderId: current.options.modelProviderId,
                  modelId: current.options.modelId,
                  agentName: current.options.agentName,
                  reasoningEffort: effort,
                ),
              );
              _closeChoice();
            },
    );
  }

  Future<void> _worktree() async {
    widget.focusNode.unfocus();
    unawaited(widget.viewModel.refreshWorktrees());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => WorktreePicker(viewModel: widget.viewModel),
    );
  }

  void _model(SessionCreationState state) =>
      _openChoice(_InlineChoice.model, state);

  void _effort(SessionCreationState state, OpenCodeModel model) {
    final choices = model.executionOptions?.reasoningEfforts;
    if (choices == null || choices.isEmpty) return;
    _effortModel = (providerId: model.providerId, modelId: model.id);
    _openChoice(_InlineChoice.effort, state);
  }

  Widget _configuration(SessionCreationState state) {
    final busy =
        state.queuePending ||
        state.phase == SessionCreationPhase.creating ||
        state.worktreePhase == WorktreePhase.creating;
    final worktree = state.worktrees
        .where((tree) => tree.directory == state.directory)
        .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CreationConfigurationRow(
          icon: Icons.desktop_windows_outlined,
          label: 'Machine',
          value: widget.profile.displayOrigin,
          onTap: busy
              ? null
              : () => _choose<ServerProfile>('Machine', [
                  SelectionOption(
                    value: widget.profile,
                    label: widget.profile.displayOrigin,
                    description: 'Connected private server',
                  ),
                ], widget.profile),
        ),
        CreationConfigurationRow(
          icon: Icons.folder_outlined,
          label: 'Folder',
          value: state.directory.isEmpty ? 'Choose a folder' : state.directory,
          onTap: busy ? null : () => _directory(state),
        ),
        CreationConfigurationRow(
          icon: Icons.account_tree_outlined,
          label: 'Worktree',
          value: worktree?.branch ?? 'Select worktree',
          onTap: busy || state.profile == null ? null : _worktree,
        ),
        CreationConfigurationRow(
          icon: Icons.memory_outlined,
          label: 'Coding engine',
          value: _engineName(state.backend ?? widget.profile.backend),
          onTap: busy || state.backends.isEmpty ? null : () => _engine(state),
        ),
        if (state.phase == SessionCreationPhase.loading)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading machine and engine choices',
          ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(state.failure!.message),
          ),
        if (state.phase == SessionCreationPhase.failed &&
            state.failure != SessionCreationFailure.creationUncertain)
          AppButton(
            label: 'Retry connection',
            onPressed: () {
              final backend = state.backend;
              if (state.backends.contains(backend)) {
                unawaited(widget.viewModel.selectBackend(backend!));
              } else {
                unawaited(
                  widget.viewModel.initialize(
                    widget.profile,
                    directory: state.directory,
                    draft: widget.controller.text,
                    options: state.options,
                  ),
                );
              }
            },
          ),
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<SessionCreationState>(
    valueListenable: widget.viewModel,
    builder: (context, state, _) {
      final selectedModel = state.capabilities?.models
          .where(
            (model) =>
                model.providerId == state.options.modelProviderId &&
                model.id == state.options.modelId,
          )
          .firstOrNull;
      final effortChoices = selectedModel?.executionOptions?.reasoningEfforts;
      final selectedEffort = effortChoices
          ?.where((choice) => choice.id == state.options.reasoningEffort)
          .firstOrNull;
      final controlsEnabled =
          state.phase == SessionCreationPhase.ready &&
          !state.queuePending &&
          state.worktreePhase != WorktreePhase.creating;
      // Budget each optional control as its own wrapped row. This is an
      // upper allowance, not a device-width assumption: the outer scroller
      // remains available when large text or a tiny window cannot fit both.
      final choiceChromeHeight =
          (184 +
                  (selectedModel != null &&
                          effortChoices?.isNotEmpty == true &&
                          MediaQuery.textScalerOf(context).scale(14) > 18
                      ? 64
                      : 0)) *
              MediaQuery.textScalerOf(context).scale(14) /
              14 +
          (widget.viewModel.attachments.value.isNotEmpty ? 80 : 0);
      return LayoutBuilder(
        builder: (context, constraints) => NewSessionDock(
          draftController: widget.controller,
          focusNode: widget.focusNode,
          expanded: _expanded,
          enabled: state.phase != SessionCreationPhase.creating,
          readOnly: state.queuePending,
          attachments: AttachmentStrip(
            attachments: widget.viewModel.attachments,
            onRemove: state.queuePending
                ? null
                : widget.viewModel.removeAttachment,
          ),
          onAttach:
              controlsEnabled &&
                  state.profile?.capabilities.supports(
                        BackendFeature.attachments,
                      ) ==
                      true
              ? _attach
              : null,
          onExpandedChanged: _expand,
          onChanged: widget.viewModel.updateDraft,
          onCreate:
              !_showDirectory &&
                  _choice == null &&
                  (!_expanded ||
                      (state.canCreate &&
                          (widget.controller.text.trim().isNotEmpty ||
                              widget.viewModel.attachments.value.isNotEmpty)))
              ? _send
              : null,
          onTerminal: null,
          configuration: _choice != null
              ? _choicePanel(
                  state,
                  constraints.hasBoundedHeight
                      // Leave room for the picker header, configuration gap,
                      // draft field and action row above the keyboard. Tiny
                      // viewports retain the surrounding scroll fallback.
                      ? (constraints.maxHeight - choiceChromeHeight).clamp(
                          48.0,
                          240.0,
                        )
                      : 240.0,
                )
              : _showDirectory
              ? _directoryPanel(state)
              : _configuration(state),
          hint: _expanded
              ? 'Ask ${_engineName(state.backend ?? widget.profile.backend)}'
              : 'What would you like to do?',
          actions: LayoutBuilder(
            builder: (context, constraints) {
              final choices = <Widget>[
                if (state.queuePending) ...[
                  AppButton(
                    label: 'Retry saving prompt',
                    onPressed: state.canCreate ? _send : null,
                  ),
                  AppButton(
                    label: 'Cancel preparation',
                    onPressed: state.phase == SessionCreationPhase.creating
                        ? null
                        : () {
                            widget.viewModel.cancelPreparation();
                          },
                  ),
                ],
                CompactChoiceButton(
                  label: selectedModel?.name ?? 'Model default',
                  semanticLabel:
                      'Model: ${selectedModel?.name ?? 'CLI / server default'}',
                  onPressed: controlsEnabled && state.capabilities != null
                      ? () => _model(state)
                      : null,
                ),
                if (selectedModel != null &&
                    effortChoices != null &&
                    effortChoices.isNotEmpty)
                  Tooltip(
                    message: 'Reasoning effort',
                    child: CompactChoiceButton(
                      key: const ValueKey('creation-reasoning-effort'),
                      label:
                          selectedEffort?.label ??
                          (state.options.reasoningEffort == null
                              ? 'Default'
                              : 'Unavailable effort'),
                      semanticLabel:
                          'Reasoning effort: ${selectedEffort?.label ?? (state.options.reasoningEffort == null ? 'Engine default' : 'Unavailable effort')}',
                      onPressed: controlsEnabled
                          ? () => _effort(state, selectedModel)
                          : null,
                    ),
                  ),
              ];
              if (!state.queuePending &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18 &&
                  constraints.maxWidth >= choices.length * 48) {
                return Row(
                  children: [
                    for (final choice in choices) Expanded(child: choice),
                  ],
                );
              }
              return Wrap(spacing: 4, children: choices);
            },
          ),
        ),
      );
    },
  );
}

String _engineName(AgentBackend backend) => switch (backend) {
  AgentBackend.gatewayClaude => 'Claude Code',
  AgentBackend.gatewayCodex => 'Codex',
  AgentBackend.gatewayOpenCode || AgentBackend.directOpenCode => 'OpenCode',
};
