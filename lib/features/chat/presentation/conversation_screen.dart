import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/async/result.dart';
import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../../capabilities/capabilities.dart';
import '../../queue/queue.dart';
import '../../sessions/sessions.dart';
import '../../voice/voice.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/pending_approval.dart';
import '../domain/prompt_attachment.dart';
import '../domain/session_artifacts.dart';
import '../domain/session_execution_state.dart';
import 'conversation_view_model.dart';
import 'session_details_screen.dart';
import 'session_file_diff_screen.dart';
import 'widgets/approval_dock.dart';
import 'widgets/composer.dart';
import 'widgets/connection_status_banner.dart';
import 'widgets/queue_panel.dart';
import 'widgets/session_artifacts_panel.dart';
import 'widgets/transcript.dart';
import '../../review/review.dart';

/// The user-facing text for [state], or `null` when nothing needs
/// announcing (a healthy connection, or the app simply being inactive,
/// which the conversation screen is not visible to observe anyway).
String? _connectionBanner(SseConnectionState state) {
  return switch (state) {
    SseConnected() || SseSuspended() => null,
    SseConnecting() => 'Connecting…',
    SseReconciling() => 'Reconnected — syncing before sending resumes…',
    SseReconnecting(:final attempt) =>
      'Connection lost. Reconnecting (attempt $attempt)…',
    SseDisconnected() =>
      'Connection lost and reconnect attempts stopped. Reopen this '
          'conversation to try again.',
  };
}

/// A stable identity for [approval], used as `ApprovalDock`'s key so a
/// brand-new approval (a different permission, or a different question
/// request) always rebuilds the dock's internal selection/text state from
/// scratch, instead of carrying over stale selections from the previous
/// approval.
String _approvalKey(PendingApproval approval) {
  return switch (approval) {
    PendingPermissionApproval(:final permissionId) =>
      'permission:$permissionId',
    PendingQuestionApproval(:final requestId) => 'question:$requestId',
  };
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    required this.profile,
    required this.session,
    required this.viewModel,
    this.capabilitiesViewModel,
    this.voiceViewModel,
    this.onOpenFork,
    this.onOpenFile,
    this.onSessionDeleted,
    this.reviewViewModelFactory,
    super.key,
  });

  final ServerProfile profile;
  final OpenCodeSession session;
  final ConversationViewModel viewModel;
  final CapabilitiesViewModel? capabilitiesViewModel;
  final VoiceViewModel? voiceViewModel;
  final ValueChanged<OpenCodeSession>? onOpenFork;
  final ValueChanged<String>? onOpenFile;
  final VoidCallback? onSessionDeleted;
  final ReviewViewModel Function()? reviewViewModelFactory;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

enum _ComposerChoice { permission, model, agent, effort, command }

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _composerController = TextEditingController();
  bool _submittingComposer = false;
  final _transcriptController = ScrollController();
  StreamSubscription<String>? _queueErrorSubscription;
  StreamSubscription<String>? _transcriptErrorSubscription;
  bool _showJumpToLatest = false;
  final _forkInProgress = ValueNotifier<bool>(false);
  bool? _artifactsPanelOverride;
  double? _artifactsWidth;
  late final ValueNotifier<PromptExecutionOptions> _executionOptions;
  OpenCodeSlashCommand? _selectedCommand;
  String? _voiceDraftPrefix;
  late OpenCodeSession _openedSession;
  late ServerProfile _openedProfile;
  bool _deleteDialogOpen = false;
  _ComposerChoice? _composerChoice;
  int _composerChoiceRevision = 0;

  void _toggleComposerChoice(_ComposerChoice choice) => setState(() {
    _composerChoiceRevision++;
    _composerChoice = _composerChoice == choice ? null : choice;
  });

  void _closeComposerChoice() {
    if (_composerChoice != null) {
      setState(() {
        _composerChoiceRevision++;
        _composerChoice = null;
      });
    }
  }

  OpenCodeCapabilities? get _currentCapabilities =>
      switch (widget.capabilitiesViewModel?.value) {
        CapabilitiesReady(:final capabilities) => capabilities,
        _ => null,
      };

  bool _selectableModel(OpenCodeModel model) =>
      model.isProviderConnected &&
      !((widget.profile.backend == AgentBackend.gatewayClaude ||
              widget.profile.backend == AgentBackend.gatewayCodex) &&
          model.providerId == widget.profile.backend.engine &&
          model.id == 'default');

  void _commitComposerOptions(PromptExecutionOptions options) {
    _executionOptions.value = options;
    widget.viewModel.rememberExecutionOptions(
      widget.profile,
      widget.session,
      options,
    );
    _closeComposerChoice();
  }

  Future<void> _openSession() {
    // Catalog refreshes replace metadata objects without replacing this State.
    // Teardown must target the exact request this route actually opened.
    _openedSession = widget.session;
    _openedProfile = widget.profile;
    return widget.viewModel.open(widget.profile, _openedSession);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _executionOptions = ValueNotifier(
      widget.viewModel.executionOptionsFor(widget.profile, widget.session),
    );
    widget.viewModel.executionOptionsLoad.addListener(_applyRestoredOptions);
    final draft = widget.viewModel.draftFor(widget.profile, widget.session);
    _composerController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _composerController.addListener(_rememberComposerDraft);
    _transcriptController.addListener(_updateJumpToLatestVisibility);
    unawaited(_openSession());
    widget.capabilitiesViewModel?.load(widget.profile);
    widget.voiceViewModel?.state.addListener(_applyVoiceState);
    _transcriptErrorSubscription = widget.viewModel.transcriptErrors.listen((
      message,
    ) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
    _queueErrorSubscription = widget.viewModel.queueErrors.listen((message) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _forkInProgress.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _queueErrorSubscription?.cancel();
    _transcriptErrorSubscription?.cancel();
    widget.voiceViewModel?.state.removeListener(_applyVoiceState);
    unawaited(widget.voiceViewModel?.cancel());
    _composerController.removeListener(_rememberComposerDraft);
    _composerController.dispose();
    _executionOptions.dispose();
    widget.viewModel.executionOptionsLoad.removeListener(_applyRestoredOptions);
    _transcriptController
      ..removeListener(_updateJumpToLatestVisibility)
      ..dispose();
    widget.viewModel.leaveSession(_openedSession);
    super.dispose();
  }

  void _rememberComposerDraft() {
    widget.viewModel.rememberDraft(
      widget.profile,
      widget.session,
      _composerController.text,
    );
  }

  bool get _composerOptionsReady =>
      widget.viewModel.executionOptionsLoad.value ==
      ExecutionOptionsLoadState.ready;

  void _applyRestoredOptions() {
    if (!mounted) return;
    if (_composerOptionsReady) {
      _executionOptions.value = widget.viewModel.executionOptionsFor(
        widget.profile,
        widget.session,
      );
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    } else if (state == AppLifecycleState.resumed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _submitComposer() async {
    if (_submittingComposer || !_composerOptionsReady) return;
    final submittedText = _composerController.text;
    final text = submittedText.trim();
    final command = _selectedCommand;
    final hasAttachments = widget.viewModel.attachments.value.isNotEmpty;
    if (command != null && hasAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Slash commands cannot include attachments. Remove the attachments or choose Message.',
          ),
        ),
      );
      return;
    }
    if (text.isEmpty && command == null && !hasAttachments) {
      return;
    }
    setState(() => _submittingComposer = true);
    try {
      final queued = command == null
          ? await widget.viewModel.enqueuePrompt(
              text,
              executionOptions: _executionOptions.value,
            )
          : await widget.viewModel.enqueueCommand(
              command.name,
              text,
              executionOptions: _commandExecutionOptions(command),
            );
      if (queued && mounted && _composerController.text == submittedText) {
        _composerController.clear();
      }
    } finally {
      if (mounted) setState(() => _submittingComposer = false);
    }
  }

  Future<void> _pickAttachments() async {
    final result = await widget.viewModel.pickAttachments();
    if (!mounted || result is! AttachmentPickRejected) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _enterVoiceMode() async {
    final voiceViewModel = widget.voiceViewModel;
    if (voiceViewModel == null) return;
    _voiceDraftPrefix = _composerController.text;
    await voiceViewModel.enterModeFromUserAction();
  }

  Future<void> _startVoiceCapture() async {
    final voiceViewModel = widget.voiceViewModel;
    if (voiceViewModel == null) return;
    await voiceViewModel.startSegmentFromUserAction();
    if (voiceViewModel.state.value is VoiceRecording) {
      await HapticFeedback.mediumImpact();
    }
  }

  void _applyVoiceState() {
    final voiceViewModel = widget.voiceViewModel;
    if (!mounted || voiceViewModel == null) return;
    final state = voiceViewModel.state.value;
    final transcript = switch (state) {
      VoiceRecording(:final partialTranscript) => partialTranscript,
      VoiceTranscribing(:final partialTranscript) => partialTranscript,
      VoiceReady(:final transcript) => transcript,
      _ => null,
    };
    if (transcript != null) {
      final prefix = _voiceDraftPrefix ?? _composerController.text;
      final separator = prefix.trim().isEmpty || transcript.isEmpty ? '' : '\n';
      final text = '$prefix$separator$transcript';
      _composerController
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
    }
    if (state is VoiceIdle || state is VoiceUnavailable) {
      _voiceDraftPrefix = null;
    }
  }

  PromptExecutionOptions _commandExecutionOptions(
    OpenCodeSlashCommand command,
  ) {
    // Native reasoning effort is not an OpenCode command variant.
    return PromptExecutionOptions(
      modelProviderId:
          command.model?.providerId ?? _executionOptions.value.modelProviderId,
      modelId: command.model?.modelId ?? _executionOptions.value.modelId,
      agentName: command.agentName ?? _executionOptions.value.agentName,
      permissionModeId: _executionOptions.value.permissionModeId,
    );
  }

  void _selectCommand() => _toggleComposerChoice(_ComposerChoice.command);

  Future<void> _selectExecutionOptions(
    OpenCodeCapabilities capabilities,
  ) async {
    final owner = (widget.profile.id, widget.session.id);
    final selected = await _showAdaptiveChoice<PromptExecutionOptions>(
      title: 'Prompt execution',
      builder: (context, controller) {
        var model = _selectedModel(capabilities.models);
        var agent = _selectedAgent(capabilities.agents);
        var effort = _executionOptions.value.reasoningEffort;
        var permissionModeId = _executionOptions.value.permissionModeId;
        return StatefulBuilder(
          builder: (context, setDialogState) => ListView(
            controller: controller,
            shrinkWrap: true,
            children: [
              if (capabilities.permissionModes.isNotEmpty)
                _ExecutionChoice(
                  label: 'Permissions',
                  value: _permissionLabel(capabilities, permissionModeId),
                  onTap: () async {
                    final selected = capabilities.permissionModes
                        .where((mode) => mode.id == permissionModeId)
                        .firstOrNull;
                    final choice = await _showSelectionPicker(
                      title: 'Permissions',
                      selected: selected,
                      options: [
                        for (final mode in capabilities.permissionModes)
                          SelectionOption(
                            value: mode,
                            label: mode.label,
                            description: mode.description,
                          ),
                      ],
                    );
                    if (choice != null && context.mounted) {
                      setDialogState(() => permissionModeId = choice.value?.id);
                    }
                  },
                ),
              _ExecutionChoice(
                label: 'Model',
                value: model?.name ?? 'Default',
                onTap: () async {
                  final choice = await _chooseModel(capabilities.models, model);
                  if (choice != null && context.mounted) {
                    setDialogState(() {
                      if (model?.providerId != choice.value?.providerId ||
                          model?.id != choice.value?.id) {
                        effort = null;
                      }
                      model = choice.value;
                    });
                  }
                },
              ),
              _ExecutionChoice(
                label: 'Agent',
                value: agent?.name ?? 'Default',
                onTap: () async {
                  final choice = await _chooseAgent(capabilities.agents, agent);
                  if (choice != null && context.mounted) {
                    setDialogState(() => agent = choice.value);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.tertiary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    label: 'Apply',
                    onPressed: () => Navigator.of(context).pop(
                      _Selection(
                        PromptExecutionOptions(
                          modelProviderId: model?.providerId,
                          modelId: model?.id,
                          agentName: agent?.name,
                          reasoningEffort: effort,
                          permissionModeId: permissionModeId,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (selected != null &&
        mounted &&
        owner == (widget.profile.id, widget.session.id)) {
      _executionOptions.value = selected.value!;
      widget.viewModel.rememberExecutionOptions(
        widget.profile,
        widget.session,
        selected.value!,
      );
    }
  }

  Future<_Selection<T>?> _showAdaptiveChoice<T>({
    required String title,
    required Widget Function(BuildContext, ScrollController) builder,
  }) {
    final isCompact =
        MediaQuery.sizeOf(context).width < PromptBreakpoints.tablet;
    if (isCompact) {
      return showModalBottomSheet<_Selection<T>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.35,
            maxChildSize: 0.95,
            builder: (context, controller) => Material(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  Expanded(child: builder(context, controller)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return showDialog<_Selection<T>>(
      context: context,
      builder: (dialogContext) {
        final usableHeight =
            MediaQuery.sizeOf(dialogContext).height -
            MediaQuery.viewInsetsOf(dialogContext).bottom;
        final contentMaxHeight = (usableHeight - 180).clamp(120.0, 560.0);
        return AppDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: contentMaxHeight),
              child: builder(dialogContext, ScrollController()),
            ),
          ),
        );
      },
    );
  }

  Future<_Selection<OpenCodeModel>?> _chooseModel(
    List<OpenCodeModel> models,
    OpenCodeModel? selected,
  ) => _showSelectionPicker<OpenCodeModel>(
    title: 'Model',
    selected: selected,
    options: [
      for (final candidate in models.where(
        (model) =>
            model.isProviderConnected &&
            !((widget.profile.backend == AgentBackend.gatewayClaude ||
                    widget.profile.backend == AgentBackend.gatewayCodex) &&
                model.providerId == widget.profile.backend.engine &&
                model.id == 'default'),
      ))
        SelectionOption(
          value: candidate,
          label: candidate.name,
          description: '${candidate.providerId} / ${candidate.id}',
        ),
    ],
  );

  Future<_Selection<OpenCodeAgent>?> _chooseAgent(
    List<OpenCodeAgent> agents,
    OpenCodeAgent? selected,
  ) => _showSelectionPicker<OpenCodeAgent>(
    title: 'Agent',
    selected: selected,
    options: [
      for (final candidate in agents)
        SelectionOption(value: candidate, label: candidate.name),
    ],
  );

  Future<_Selection<T>?> _showSelectionPicker<T>({
    required String title,
    required T? selected,
    required List<SelectionOption<T>> options,
  }) {
    return showDialog<_Selection<T>>(
      context: context,
      useSafeArea: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: 560,
            child: InlineSelectionPanel<T?>(
              title: title,
              radioIndicator: true,
              listHeight: (constraints.maxHeight - 56).clamp(0.0, 344.0),
              selected: selected,
              options: [
                InlineSelectionOption<T?>(value: null, label: 'Default'),
                for (final option in options)
                  InlineSelectionOption<T?>(
                    value: option.value,
                    label: option.label,
                    description: option.description,
                  ),
              ],
              onSelected: (value) =>
                  Navigator.of(context).pop(_Selection<T>(value)),
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }

  void _selectComposerModel(OpenCodeCapabilities capabilities) =>
      _toggleComposerChoice(_ComposerChoice.model);

  void _applyComposerModel((String, String)? choice) {
    final capabilities = _currentCapabilities;
    if (capabilities == null ||
        (choice != null &&
            !capabilities.models.any(
              (model) =>
                  _selectableModel(model) &&
                  (model.providerId, model.id) == choice,
            ))) {
      return;
    }
    final current = _executionOptions.value;
    final options = PromptExecutionOptions(
      modelProviderId: choice?.$1,
      modelId: choice?.$2,
      agentName: current.agentName,
      permissionModeId: current.permissionModeId,
      reasoningEffort:
          choice?.$1 == current.modelProviderId && choice?.$2 == current.modelId
          ? current.reasoningEffort
          : null,
    );
    _commitComposerOptions(options);
  }

  void _selectComposerAgent(OpenCodeCapabilities capabilities) =>
      _toggleComposerChoice(_ComposerChoice.agent);

  String _permissionLabel(
    OpenCodeCapabilities capabilities,
    String? permissionModeId,
  ) {
    final effective = permissionModeId ?? capabilities.defaultPermissionModeId;
    return capabilities.permissionModes
            .where((mode) => mode.id == effective)
            .firstOrNull
            ?.label ??
        (permissionModeId == null ? 'Default' : 'Unavailable');
  }

  void _selectComposerPermission() =>
      _toggleComposerChoice(_ComposerChoice.permission);

  void _applyComposerPermission(String? choice) {
    final capabilities = _currentCapabilities;
    if (capabilities == null ||
        (choice != null &&
            !capabilities.permissionModes.any((mode) => mode.id == choice))) {
      return;
    }
    final current = _executionOptions.value;
    _commitComposerOptions(
      PromptExecutionOptions(
        modelProviderId: current.modelProviderId,
        modelId: current.modelId,
        agentName: current.agentName,
        reasoningEffort: current.reasoningEffort,
        permissionModeId: choice,
      ),
    );
  }

  void _applyComposerAgent(String? choice) {
    final capabilities = _currentCapabilities;
    if (capabilities == null ||
        (choice != null &&
            !capabilities.agents.any((agent) => agent.name == choice))) {
      return;
    }
    final current = _executionOptions.value;
    final options = PromptExecutionOptions(
      modelProviderId: current.modelProviderId,
      modelId: current.modelId,
      agentName: choice,
      reasoningEffort: current.reasoningEffort,
      permissionModeId: current.permissionModeId,
    );
    _commitComposerOptions(options);
  }

  OpenCodeModel? _selectedModel(List<OpenCodeModel> models) {
    for (final model in models) {
      if (model.providerId == _executionOptions.value.modelProviderId &&
          model.id == _executionOptions.value.modelId) {
        return model;
      }
    }
    return null;
  }

  Widget _effortControl(
    OpenCodeCapabilities capabilities,
    PromptExecutionOptions options,
  ) {
    final model = _selectedModel(capabilities.models);
    final choices = model?.executionOptions?.reasoningEfforts;
    if (!widget.profile.backend.isGateway ||
        widget.profile.backend.engine == 'opencode' ||
        model == null ||
        !model.isProviderConnected ||
        model.id == 'default' ||
        model.providerId != widget.profile.backend.engine ||
        choices == null ||
        choices.isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = choices
        .where((choice) => choice.id == options.reasoningEffort)
        .firstOrNull;
    final label =
        selected?.label ??
        (options.reasoningEffort == null
            ? 'Effort default'
            : 'Unavailable effort');
    return CompactChoiceButton(
      key: const ValueKey('composer-effort-picker'),
      label: label,
      semanticLabel: 'Reasoning effort: $label',
      onPressed: () => _selectComposerEffort(model),
    );
  }

  void _selectComposerEffort(OpenCodeModel model) =>
      _toggleComposerChoice(_ComposerChoice.effort);

  void _applyComposerEffort(OpenCodeModel model, String? effort) {
    final current = _executionOptions.value;
    if (current.modelProviderId != model.providerId ||
        current.modelId != model.id) {
      return;
    }
    final fresh = _currentCapabilities?.models
        .where(
          (candidate) =>
              candidate.providerId == model.providerId &&
              candidate.id == model.id &&
              _selectableModel(candidate),
        )
        .firstOrNull;
    final choices = fresh?.executionOptions?.reasoningEfforts;
    if (choices == null ||
        choices.isEmpty ||
        (effort != null && !choices.any((choice) => choice.id == effort))) {
      return;
    }
    final options = PromptExecutionOptions(
      modelProviderId: current.modelProviderId,
      modelId: current.modelId,
      agentName: current.agentName,
      reasoningEffort: effort,
      permissionModeId: current.permissionModeId,
    );
    _commitComposerOptions(options);
  }

  OpenCodeAgent? _selectedAgent(List<OpenCodeAgent> agents) {
    for (final agent in agents) {
      if (agent.name == _executionOptions.value.agentName) {
        return agent;
      }
    }
    return null;
  }

  Future<void> _confirmSendNow(QueuedPrompt prompt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AppDialog(
          title: const Text('Abort current generation and send now?'),
          content: const Text(
            'This cancels whatever the session is currently generating, '
            'then sends this queued prompt immediately, ahead of the rest '
            'of the queue.',
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton(
              label: 'Abort & send now',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await widget.viewModel.sendNow(prompt.id);
    }
  }

  Future<void> _confirmRevert(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Revert this message?'),
        content: const Text(
          'OpenCode will revert the session to this message. Later messages '
          'and session changes may be removed.',
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: 'Revert message',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final failure = await widget.viewModel.revert(message.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure?.message ?? 'Message reverted')),
    );
  }

  void _updateJumpToLatestVisibility() {
    if (!_transcriptController.hasClients) {
      return;
    }
    // The transcript is reversed, so offset 0 is the newest message and no
    // scrolling is needed to stay anchored to it.
    final shouldShow = _transcriptController.position.pixels > 48;
    if (shouldShow != _showJumpToLatest && mounted) {
      setState(() => _showJumpToLatest = shouldShow);
    }
  }

  void _jumpToLatest() {
    if (_transcriptController.hasClients) {
      _transcriptController.jumpTo(0);
    }
  }

  void _openReview() {
    final factory = widget.reviewViewModelFactory;
    final capabilities = widget.capabilitiesViewModel;
    if (factory == null || capabilities == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          target: ReviewTarget(
            profile: widget.profile,
            session: widget.session,
          ),
          viewModel: factory(),
          capabilitiesViewModel: capabilities,
        ),
      ),
    );
  }

  Widget _buildTranscript(
    List<ChatMessage> messages, {
    bool showComposerActions = true,
    bool desktop = false,
  }) {
    return Stack(
      children: [
        ValueListenableBuilder<ConversationHistoryUiState>(
          valueListenable: widget.viewModel.history,
          builder: (context, history, _) => Column(
            children: [
              if (history.failure case final failure?)
                MaterialBanner(
                  content: Text(
                    'Earlier messages unavailable: ${failure.message}',
                  ),
                  actions: [
                    AppButton(
                      label: 'Retry',
                      variant: AppButtonVariant.tertiary,
                      onPressed: () =>
                          widget.viewModel.loadOlderFromUserAction(),
                    ),
                  ],
                ),
              Expanded(
                child: Transcript(
                  messages: messages,
                  onRefresh: widget.viewModel.refreshFromUserAction,
                  onRevert: _confirmRevert,
                  onOpenFile:
                      widget.profile.capabilities.supports(
                        BackendFeature.workspace,
                      )
                      ? widget.onOpenFile
                      : null,
                  canRevert: widget.profile.capabilities.supports(
                    BackendFeature.sessionRevert,
                  ),
                  onLoadOlder: () => widget.viewModel.loadOlderFromUserAction(),
                  hasMore: history.hasMore,
                  loadingOlder: history.loadingOlder,
                  limitedByServer: history.limitedByServer,
                  controller: _transcriptController,
                  desktop: desktop,
                ),
              ),
            ],
          ),
        ),
        // Reconciliation floats over the transcript so the previous messages
        // stay readable and the list is never rebuilt from an empty state.
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.viewModel.refreshing,
            builder: (context, refreshing, _) {
              if (!refreshing) {
                return const SizedBox.shrink();
              }
              return Center(
                child: Semantics(
                  liveRegion: true,
                  label: 'Syncing this conversation',
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Syncing…',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_showJumpToLatest)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(child: _jumpButton()),
          ),
        if (showComposerActions)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _composerActionColumn(),
          ),
      ],
    );
  }

  Widget _composerActionColumn() {
    final capabilitiesViewModel = widget.capabilitiesViewModel;
    bool hasAgentChoices(List<OpenCodeAgent> agents) =>
        agents.isNotEmpty &&
        !((widget.profile.backend == AgentBackend.gatewayClaude ||
                widget.profile.backend == AgentBackend.gatewayCodex) &&
            agents.length == 1 &&
            agents.single.name == widget.profile.backend.engine);
    Widget buildActions(
      List<OpenCodeSlashCommand> commands, {
      OpenCodeCapabilities? capabilities,
    }) => ComposerActionBar(
      key: const ValueKey('composer-action-toolbar'),
      controls:
          capabilities == null ||
              (!capabilities.models.any((model) => model.isProviderConnected) &&
                  !hasAgentChoices(capabilities.agents) &&
                  capabilities.permissionModes.isEmpty)
          ? null
          : ValueListenableBuilder<PromptExecutionOptions>(
              valueListenable: _executionOptions,
              builder: (context, options, _) => Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (capabilities.permissionModes.isNotEmpty)
                    CompactChoiceButton(
                      key: const ValueKey('composer-permission-picker'),
                      label: _permissionLabel(
                        capabilities,
                        options.permissionModeId,
                      ),
                      semanticLabel:
                          'Permissions: ${_permissionLabel(capabilities, options.permissionModeId)}',
                      onPressed: _selectComposerPermission,
                    ),
                  if (hasAgentChoices(capabilities.agents))
                    CompactChoiceButton(
                      key: const ValueKey('composer-agent-picker'),
                      label:
                          _selectedAgent(capabilities.agents)?.name ??
                          options.agentName ??
                          'Agent default',
                      semanticLabel:
                          'Agent: ${_selectedAgent(capabilities.agents)?.name ?? options.agentName ?? 'Agent default'}',
                      onPressed: () => _selectComposerAgent(capabilities),
                    ),
                  if (capabilities.models.any(
                    (model) => model.isProviderConnected,
                  ))
                    CompactChoiceButton(
                      key: const ValueKey('composer-model-picker'),
                      label:
                          _selectedModel(capabilities.models)?.name ??
                          options.modelId ??
                          'Model default',
                      semanticLabel:
                          'Model: ${_selectedModel(capabilities.models)?.name ?? options.modelId ?? 'CLI / server default'}',
                      onPressed: () => _selectComposerModel(capabilities),
                    ),
                  _effortControl(capabilities, options),
                ],
              ),
            ),
      leading: [
        if (widget.profile.capabilities.supports(BackendFeature.attachments))
          AppIconButton(
            onPressed: _composerOptionsReady ? _pickAttachments : null,
            tooltip: 'Add attachment',
            icon: Icons.add_rounded,
          ),
        if (widget.voiceViewModel case final voiceViewModel?)
          ValueListenableBuilder<VoiceUiState>(
            valueListenable: voiceViewModel.state,
            builder: (context, state, _) => ValueListenableBuilder<bool>(
              valueListenable: voiceViewModel.hasSelectedModel,
              builder: (context, hasModel, _) {
                if (!hasModel || state is! VoiceIdle) {
                  return const SizedBox.shrink();
                }
                return AppIconButton(
                  onPressed: _enterVoiceMode,
                  tooltip: 'Start voice mode',
                  icon: Icons.mic_rounded,
                );
              },
            ),
          ),
        if (commands.isNotEmpty &&
            widget.profile.capabilities.supports(BackendFeature.commands))
          AppIconButton(
            onPressed: _selectCommand,
            tooltip: 'Choose slash command',
            icon: Icons.code_rounded,
          ),
      ],
      trailing: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _composerController,
        builder: (context, value, _) =>
            ValueListenableBuilder<List<PromptAttachment>>(
              valueListenable: widget.viewModel.attachments,
              builder: (context, selected, _) {
                final enabled =
                    value.text.trim().isNotEmpty ||
                    _selectedCommand != null ||
                    selected.isNotEmpty;
                return AppIconButton(
                  variant: AppIconButtonVariant.filled,
                  onPressed:
                      enabled && !_submittingComposer && _composerOptionsReady
                      ? () => unawaited(_submitComposer())
                      : null,
                  tooltip: _selectedCommand == null
                      ? 'Queue this prompt'
                      : 'Queue command',
                  icon: Icons.arrow_upward_rounded,
                );
              },
            ),
      ),
    );
    if (capabilitiesViewModel == null) {
      return buildActions(const []);
    }
    return ValueListenableBuilder<CapabilitiesUiState>(
      valueListenable: capabilitiesViewModel,
      builder: (context, state, _) => buildActions(
        state is CapabilitiesReady ? state.capabilities.commands : const [],
        capabilities: state is CapabilitiesReady ? state.capabilities : null,
      ),
    );
  }

  Widget _jumpButton() => FloatingActionButton.small(
    heroTag: 'scroll-to-latest',
    onPressed: _jumpToLatest,
    tooltip: 'Scroll to latest message',
    child: const Icon(Icons.south),
  );

  Widget _artifactsPanel({bool lazy = false}) {
    final artifacts = ValueListenableBuilder<SessionArtifactsState>(
      valueListenable: widget.viewModel.artifacts,
      builder: (context, state, _) => SessionArtifactsPanel(
        state: state,
        onOpenDiff: (diff) => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SessionFileDiffScreen(
              diff: diff,
              onOpenFile:
                  widget.onOpenFile == null ||
                      !widget.profile.capabilities.supports(
                        BackendFeature.workspace,
                      )
                  ? null
                  : () => widget.onOpenFile!(diff.file),
            ),
          ),
        ),
        onRefresh: widget.viewModel.reloadArtifacts,
        lazy: false,
      ),
    );
    if (!lazy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_executionPanel(), const SizedBox(height: 8), artifacts],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _executionPanel()),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverToBoxAdapter(child: artifacts),
      ],
    );
  }

  Widget _executionPanel() {
    final capabilitiesViewModel = widget.capabilitiesViewModel;
    if (capabilitiesViewModel == null) {
      return const _ExecutionPanel(
        modelName: 'Unavailable',
        agentName: 'Unavailable',
      );
    }
    return ValueListenableBuilder<PromptExecutionOptions>(
      valueListenable: _executionOptions,
      builder: (context, options, _) =>
          ValueListenableBuilder<CapabilitiesUiState>(
            valueListenable: capabilitiesViewModel,
            builder: (context, state, _) {
              final capabilities = state is CapabilitiesReady
                  ? state.capabilities
                  : null;
              final selectedModel = capabilities == null
                  ? null
                  : _selectedModel(capabilities.models);
              final selectedAgent = capabilities == null
                  ? null
                  : _selectedAgent(capabilities.agents);
              final configuredModel = options.modelId;
              final modelName =
                  selectedModel?.name ??
                  (configuredModel == null
                      ? 'OpenCode default'
                      : '${options.modelProviderId}/$configuredModel');
              final agentName =
                  selectedAgent?.name ??
                  options.agentName ??
                  'OpenCode default';
              return _ExecutionPanel(
                modelName: modelName,
                agentName: agentName,
                loading:
                    state is CapabilitiesIdle || state is CapabilitiesLoading,
                failure: state is CapabilitiesError
                    ? state.failure.message
                    : null,
                onSelect: capabilities == null
                    ? null
                    : () => _selectExecutionOptions(capabilities),
                onRetry: state is CapabilitiesError
                    ? capabilitiesViewModel.retry
                    : null,
              );
            },
          ),
    );
  }

  Future<void> _showArtifacts() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          ValueListenableBuilder<SessionArtifactsState>(
            valueListenable: widget.viewModel.artifacts,
            builder: (context, state, _) => SessionArtifactsPanel(
              scrollController: scrollController,
              header: _executionPanel(),
              onOpenDiff: (diff) => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SessionFileDiffScreen(
                    diff: diff,
                    onOpenFile:
                        widget.onOpenFile == null ||
                            !widget.profile.capabilities.supports(
                              BackendFeature.workspace,
                            )
                        ? null
                        : () => widget.onOpenFile!(diff.file),
                  ),
                ),
              ),
              state: state,
              onRefresh: widget.viewModel.reloadArtifacts,
              lazy: true,
            ),
          ),
    ),
  );

  OpenCodeSession _displaySession(OpenCodeSession? metadata) =>
      metadata != null &&
          metadata.id == widget.session.id &&
          metadata.directory == widget.session.directory
      ? metadata
      : widget.session;

  Future<void> _renameSession(
    BuildContext detailsContext,
    OpenCodeSession session,
  ) async {
    final originalSession = _openedSession;
    final profile = widget.profile;
    await showDialog<String>(
      context: detailsContext,
      builder: (_) => SessionRenameDialog(
        initialTitle: session.title,
        onSave: (title) async {
          if (!mounted) return SessionsFailure.unexpectedResponse;
          final result = await widget.viewModel.renameSession(
            title,
            expectedSession: originalSession,
            expectedProfile: profile,
          );
          return switch (result) {
            Ok<void, SessionsFailure>() => null,
            Err<void, SessionsFailure>(:final failure) => failure,
            null => SessionsFailure.unexpectedResponse,
          };
        },
      ),
    );
  }

  Future<void> _deleteSession(
    BuildContext detailsContext,
    OpenCodeSession displayedSession,
  ) async {
    final onDeleted = widget.onSessionDeleted;
    if (_deleteDialogOpen ||
        onDeleted == null ||
        !widget.profile.capabilities.supports(BackendFeature.sessionDelete)) {
      return;
    }
    _deleteDialogOpen = true;
    final session = _openedSession;
    final profile = _openedProfile;
    final viewModel = widget.viewModel;
    final navigator = Navigator.of(detailsContext);
    final detailsRoute = ModalRoute.of(detailsContext);
    try {
      final deleted = await showDialog<bool>(
        context: detailsContext,
        barrierDismissible: false,
        builder: (_) => SessionDeleteDialog(
          title: displayedSession.title,
          backendLabel: profile.backend.label,
          onDelete: () async {
            if (!mounted) return SessionsFailure.unexpectedResponse;
            final result = await viewModel.deleteSession(
              expectedSession: session,
              expectedProfile: profile,
            );
            return switch (result) {
              Ok<void, SessionsFailure>() => null,
              Err<void, SessionsFailure>(:final failure) => failure,
              null => SessionsFailure.unexpectedResponse,
            };
          },
        ),
      );
      if (deleted != true) return;
      // Remove the exact details route even if another route was opened while
      // the request ran. The owner removes only this conversation's route/pane.
      if (navigator.mounted && detailsRoute?.navigator == navigator) {
        navigator.removeRoute(detailsRoute!);
      }
      onDeleted();
    } finally {
      _deleteDialogOpen = false;
    }
  }

  void _openSessionDetails() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<OpenCodeSession?>(
          valueListenable: widget.viewModel.sessionMetadata,
          builder: (_, metadata, _) => ValueListenableBuilder<bool>(
            valueListenable: _forkInProgress,
            builder: (detailsContext, forkInProgress, _) =>
                ValueListenableBuilder<SessionExecutionState>(
                  valueListenable: widget.viewModel.executionState,
                  builder: (context, state, _) => SessionDetailsScreen(
                    session: _displaySession(metadata),
                    onDelete:
                        widget.onSessionDeleted != null &&
                            widget.profile.capabilities.supports(
                              BackendFeature.sessionDelete,
                            )
                        ? () => unawaited(
                            _deleteSession(
                              detailsContext,
                              _displaySession(metadata),
                            ),
                          )
                        : null,
                    onRename:
                        widget.profile.capabilities.supports(
                          BackendFeature.sessionRename,
                        )
                        ? () => _renameSession(
                            detailsContext,
                            _displaySession(metadata),
                          )
                        : null,
                    backendLabel: widget.profile.backend.label,
                    serverOriginLabel: widget.profile.displayOrigin,
                    executionLabel: _executionLabel(state),
                    forkInProgress: forkInProgress,
                    onFork:
                        widget.onOpenFork != null &&
                            widget.profile.capabilities.supports(
                              BackendFeature.sessionFork,
                            )
                        ? () => unawaited(_forkSession(detailsContext))
                        : null,
                    onRefresh: () {
                      Navigator.of(detailsContext).pop();
                      unawaited(widget.viewModel.refreshFromUserAction());
                    },
                    onReview:
                        widget.profile.capabilities.supports(
                              BackendFeature.review,
                            ) &&
                            widget.reviewViewModelFactory != null &&
                            widget.capabilitiesViewModel != null
                        ? () {
                            Navigator.of(detailsContext).pop();
                            _openReview();
                          }
                        : null,
                    onOpenArtifacts:
                        widget.profile.capabilities.supports(
                          BackendFeature.sessionArtifacts,
                        )
                        ? () {
                            Navigator.of(detailsContext).pop();
                            unawaited(_showArtifacts());
                          }
                        : null,
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Future<void> _forkSession(BuildContext detailsContext) async {
    if (_forkInProgress.value ||
        widget.onOpenFork == null ||
        !widget.profile.capabilities.supports(BackendFeature.sessionFork)) {
      return;
    }
    final navigator = Navigator.of(detailsContext);
    final detailsRoute = ModalRoute.of(detailsContext);
    _forkInProgress.value = true;
    try {
      final result = await widget.viewModel.fork();
      if (!mounted || !detailsContext.mounted) return;
      switch (result) {
        case Ok(:final value):
          if (navigator.mounted && detailsRoute?.navigator == navigator) {
            navigator.removeRoute(detailsRoute!);
          }
          widget.onOpenFork!(value);
        case Err(:final failure):
          ScaffoldMessenger.of(
            detailsContext,
          ).showSnackBar(SnackBar(content: Text(failure.message)));
        case null:
          ScaffoldMessenger.of(detailsContext).showSnackBar(
            SnackBar(content: Text(SessionsFailure.unexpectedResponse.message)),
          );
      }
    } finally {
      if (mounted) _forkInProgress.value = false;
    }
  }

  void _toggleArtifactsPanel({required bool isDesktop, required bool showing}) {
    if (!isDesktop) {
      unawaited(_showArtifacts());
      return;
    }
    setState(() => _artifactsPanelOverride = !showing);
  }

  double _artifactsWidthFor(double availableWidth) {
    final maximum = (availableWidth - 560).clamp(280.0, 720.0);
    final preferred = _artifactsWidth ?? availableWidth * .32;
    return preferred.clamp(280.0, maximum);
  }

  Widget _activityPanel({double? maxHeight, bool flexible = false}) {
    final activityMaxHeight =
        (maxHeight ?? MediaQuery.sizeOf(context).height) < 500 ? 160.0 : 320.0;
    return ValueListenableBuilder<PendingApproval?>(
      valueListenable: widget.viewModel.pendingApproval,
      builder: (context, approval, _) =>
          ValueListenableBuilder<List<QueuedPrompt>>(
            valueListenable: widget.viewModel.queue,
            builder: (context, prompts, _) {
              final activePrompts = prompts
                  .where(
                    (prompt) => prompt.state != QueuedPromptState.acknowledged,
                  )
                  .toList(growable: false);
              if (approval == null && activePrompts.isEmpty) {
                return const SizedBox.shrink();
              }
              final panel = ConstrainedBox(
                constraints: BoxConstraints(maxHeight: activityMaxHeight),
                child: LayoutBuilder(
                  builder: (context, panelConstraints) => SingleChildScrollView(
                    key: const ValueKey('conversation-activity-scroll'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (approval != null) ...[
                          const Divider(height: 1),
                          ApprovalDock(
                            key: ValueKey(_approvalKey(approval)),
                            approval: approval,
                            directory: widget.session.directory,
                            maxHeight: (panelConstraints.maxHeight - 1).clamp(
                              // The outer activity viewport scrolls when the
                              // window is shorter than a readable decision row.
                              // Never compress Deny itself below its text height.
                              (MediaQuery.textScalerOf(context).scale(32) + 48)
                                  .clamp(0.0, activityMaxHeight),
                              activityMaxHeight,
                            ),
                            allowAlways: widget.profile.capabilities.supports(
                              BackendFeature.permissionAlways,
                            ),
                            onRespondToPermission:
                                widget.viewModel.respondToPermission,
                            onReplyToQuestion: widget.viewModel.replyToQuestion,
                            onRejectQuestion: widget.viewModel.rejectQuestion,
                          ),
                        ],
                        if (activePrompts.isNotEmpty) ...[
                          const Divider(height: 1),
                          QueuePanel(
                            prompts: activePrompts,
                            onRemove: (prompt) =>
                                widget.viewModel.removeFromQueue(prompt.id),
                            onSendNow: _confirmSendNow,
                            onMergeIntoPrevious: (prompt) =>
                                widget.viewModel.mergeIntoPrevious(prompt.id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
              return Flexible(
                flex: flexible ? 1 : 0,
                fit: FlexFit.loose,
                child: panel,
              );
            },
          ),
    );
  }

  Widget _inlineComposerChoices(double availableHeight) {
    final viewModel = widget.capabilitiesViewModel;
    if (_composerChoice == null || viewModel == null) {
      return const SizedBox.shrink();
    }
    final owner = (widget.profile.id, widget.session.id);
    final kind = _composerChoice;
    final revision = _composerChoiceRevision;
    bool current() =>
        mounted &&
        revision == _composerChoiceRevision &&
        _composerChoice == kind &&
        owner == (widget.profile.id, widget.session.id);
    final height = (availableHeight - 56).clamp(0.0, 344.0);
    return ValueListenableBuilder<CapabilitiesUiState>(
      valueListenable: viewModel,
      builder: (context, state, _) {
        final capabilities = state is CapabilitiesReady
            ? state.capabilities
            : null;
        final options = _executionOptions.value;
        final key = const ValueKey('composer-inline-selection');
        switch (kind) {
          case _ComposerChoice.command:
            return InlineSelectionPanel<String?>(
              key: key,
              title: 'Slash command',
              radioIndicator: true,
              listHeight: height,
              selected: _selectedCommand?.name,
              options: [
                const InlineSelectionOption(
                  value: null,
                  label: 'Message',
                  description: 'Send a regular queued prompt',
                ),
                for (final command
                    in capabilities?.commands ?? <OpenCodeSlashCommand>[])
                  InlineSelectionOption(
                    value: command.name,
                    label: '/${command.name}',
                    description: command.description ?? 'Run slash command',
                  ),
              ],
              onSelected: capabilities == null
                  ? null
                  : (name) {
                      if (!current()) return;
                      final fresh = _currentCapabilities;
                      if (fresh == null) return;
                      final command = fresh.commands
                          .where((command) => command.name == name)
                          .firstOrNull;
                      if (name != null && command == null) return;
                      setState(() => _selectedCommand = command);
                      _closeComposerChoice();
                    },
              onClose: _closeComposerChoice,
            );
          case _ComposerChoice.permission:
            final defaultLabel = capabilities == null
                ? 'Default'
                : _permissionLabel(capabilities, null);
            return InlineSelectionPanel<String?>(
              key: key,
              title: 'Permissions',
              radioIndicator: true,
              listHeight: height,
              selected: options.permissionModeId,
              options: [
                InlineSelectionOption(
                  value: null,
                  label: 'Default ($defaultLabel)',
                ),
                for (final mode
                    in capabilities?.permissionModes ??
                        <PermissionModeChoice>[])
                  InlineSelectionOption(
                    value: mode.id,
                    label: mode.label,
                    description: mode.description,
                  ),
              ],
              onSelected:
                  capabilities == null || capabilities.permissionModes.isEmpty
                  ? null
                  : (choice) {
                      if (current()) _applyComposerPermission(choice);
                    },
              onClose: _closeComposerChoice,
            );
          case _ComposerChoice.model:
            return InlineSelectionPanel<(String, String)?>(
              key: key,
              title: 'Model',
              radioIndicator: true,
              listHeight: height,
              selected: options.modelId == null
                  ? null
                  : (options.modelProviderId ?? '', options.modelId!),
              options: [
                const InlineSelectionOption(value: null, label: 'Default'),
                for (final model in capabilities?.models ?? <OpenCodeModel>[])
                  if (_selectableModel(model))
                    InlineSelectionOption(
                      value: (model.providerId, model.id),
                      label: model.name,
                      groupLabel: model.providerId,
                    ),
              ],
              onSelected: capabilities == null
                  ? null
                  : (choice) {
                      if (current()) _applyComposerModel(choice);
                    },
              onClose: _closeComposerChoice,
            );
          case _ComposerChoice.agent:
            return InlineSelectionPanel<String?>(
              key: key,
              title: 'Agent',
              radioIndicator: true,
              listHeight: height,
              selected: options.agentName,
              options: [
                const InlineSelectionOption(value: null, label: 'Default'),
                for (final agent in capabilities?.agents ?? <OpenCodeAgent>[])
                  InlineSelectionOption(value: agent.name, label: agent.name),
              ],
              onSelected: capabilities == null
                  ? null
                  : (choice) {
                      if (current()) _applyComposerAgent(choice);
                    },
              onClose: _closeComposerChoice,
            );
          case _ComposerChoice.effort:
            final model = _selectedModel(capabilities?.models ?? []);
            final choices = model?.executionOptions?.reasoningEfforts ?? [];
            return InlineSelectionPanel<String?>(
              key: key,
              title: 'Reasoning effort',
              radioIndicator: true,
              listHeight: height,
              selected: options.reasoningEffort,
              options: [
                const InlineSelectionOption(
                  value: null,
                  label: 'Engine default',
                ),
                for (final choice in choices)
                  InlineSelectionOption(
                    value: choice.id,
                    label: choice.label,
                    description: choice.description,
                  ),
              ],
              onSelected: model == null || choices.isEmpty
                  ? null
                  : (choice) {
                      if (current()) _applyComposerEffort(model, choice);
                    },
              onClose: _closeComposerChoice,
            );
          case null:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _composerPanel({
    bool constrainWidth = false,
    double availableHeight = 800,
  }) => TextFieldTapRegion(
    child: SafeArea(
      key: const ValueKey('conversation-composer-panel'),
      top: false,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          key: const ValueKey('conversation-composer-content'),
          constraints: BoxConstraints(
            maxWidth: constrainWidth ? 960 : double.infinity,
          ),
          child: AnchoredChoiceOverlay(
            open: _composerChoice != null,
            onDismiss: _closeComposerChoice,
            popupBuilder: (_, height) => _inlineComposerChoices(height),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<SseConnectionState>(
                  valueListenable: widget.viewModel.connectionState,
                  builder: (context, state, _) {
                    if (state is! SseConnected) {
                      return const SizedBox.shrink();
                    }
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(22, 0, 22, 1),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AppStatusIndicator(
                          key: ValueKey('conversation-online-status'),
                          label: 'Online',
                          semanticLabel: 'Connection status: Online',
                          liveRegion: true,
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_composerOptionsReady)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child:
                              widget.viewModel.executionOptionsLoad.value ==
                                  ExecutionOptionsLoadState.failed
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Could not restore saved model options. Sending is paused.',
                                    ),
                                    AppButton(
                                      label: 'Retry saved options',
                                      onPressed: () =>
                                          unawaited(_openSession()),
                                    ),
                                  ],
                                )
                              : const Text('Restoring saved model options…'),
                        ),
                      Composer(
                        controller: _composerController,
                        command: _selectedCommand,
                        attachments: widget.viewModel.attachments,
                        onRemoveAttachment: widget.viewModel.removeAttachment,
                        onSubmit: _submitComposer,
                        voiceState: widget.voiceViewModel?.state,
                        onVoiceHoldStart: widget.voiceViewModel == null
                            ? null
                            : _startVoiceCapture,
                        onVoiceHoldEnd:
                            widget.voiceViewModel?.finishSegmentFromUserAction,
                        onVoiceStop:
                            widget.voiceViewModel?.stopModeFromUserAction,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                        child: _composerActionColumn(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _transcriptPanel({
    bool showComposerActions = true,
    bool desktop = false,
  }) => ValueListenableBuilder<ConversationUiState>(
    valueListenable: widget.viewModel.messages,
    builder: (context, state, _) {
      return switch (state) {
        ConversationLoading() => Center(
          child: Semantics(
            label: 'Loading conversation',
            child: const CircularProgressIndicator(),
          ),
        ),
        ConversationError(:final failure) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(failure.message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Try again',
                  icon: Icons.refresh,
                  onPressed: widget.viewModel.reload,
                ),
              ],
            ),
          ),
        ),
        ConversationReady(:final messages) => _buildTranscript(
          messages,
          showComposerActions: showComposerActions,
          desktop: desktop,
        ),
      };
    },
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < PromptBreakpoints.tablet;
        final isDesktop = constraints.maxWidth >= PromptBreakpoints.desktop;
        final showArtifactsPanel =
            widget.profile.capabilities.supports(
              BackendFeature.sessionArtifacts,
            ) &&
            (_artifactsPanelOverride ?? isDesktop);
        return PopScope(
          canPop: _composerChoice == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _closeComposerChoice();
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: isPhone ? 56 : 68,
              titleSpacing: isPhone ? 8 : 4,
              title: ValueListenableBuilder<OpenCodeSession?>(
                valueListenable: widget.viewModel.sessionMetadata,
                builder: (context, metadata, _) {
                  final session = _displaySession(metadata);
                  final title = session.title.isEmpty
                      ? 'Untitled session'
                      : session.title;
                  final additions = session.additions;
                  final deletions = session.deletions;
                  final branch = session.branch?.replaceFirst(
                    'refs/heads/',
                    '',
                  );
                  final control = NavigationTitleButton(
                    label: title,
                    semanticLabel: 'Open session details: $title',
                    subtitleSegments: [
                      NavigationTitleSegment(
                        branch == null || branch.isEmpty
                            ? directoryName(session.directory)
                            : branch,
                      ),
                      if (additions != null &&
                          deletions != null &&
                          (additions > 0 || deletions > 0)) ...[
                        NavigationTitleSegment(
                          '+$additions',
                          tone: NavigationTitleSegmentTone.positive,
                        ),
                        NavigationTitleSegment(
                          '-$deletions',
                          tone: NavigationTitleSegmentTone.negative,
                        ),
                      ],
                    ],
                    onPressed: _openSessionDetails,
                  );
                  return SizedBox(
                    height: isPhone ? 56 : 68,
                    child: isPhone
                        ? control
                        : Row(
                            children: [
                              IdentityAvatar(identifier: session.id, size: 34),
                              const SizedBox(width: 10),
                              Expanded(child: control),
                            ],
                          ),
                  );
                },
              ),
              actions: [
                if (isPhone)
                  IdentityAvatarButton(
                    identifier: widget.session.id,
                    tooltip: 'Session details and actions',
                    onPressed: _openSessionDetails,
                  )
                else ...[
                  if (widget.profile.capabilities.supports(
                        BackendFeature.review,
                      ) &&
                      widget.reviewViewModelFactory != null &&
                      widget.capabilitiesViewModel != null)
                    AppIconButton(
                      icon: Icons.rate_review_outlined,
                      tooltip: 'Review diff',
                      onPressed: _openReview,
                    ),
                  if (isDesktop)
                    AppIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh transcript',
                      onPressed: widget.viewModel.refreshFromUserAction,
                    ),
                  ValueListenableBuilder<SessionExecutionState>(
                    valueListenable: widget.viewModel.executionState,
                    builder: (context, state, _) =>
                        Center(child: _ExecutionIndicator(state: state)),
                  ),
                  if (widget.profile.capabilities.supports(
                    BackendFeature.sessionArtifacts,
                  ))
                    AppIconButton(
                      icon: Icons.assignment_outlined,
                      tooltip: isDesktop
                          ? showArtifactsPanel
                                ? 'Hide session details'
                                : 'Show session details'
                          : 'Session artifacts',
                      onPressed: () => _toggleArtifactsPanel(
                        isDesktop: isDesktop,
                        showing: showArtifactsPanel,
                      ),
                    ),
                ],
                const SizedBox(width: 8),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, bodyConstraints) {
                final compactHeight =
                    bodyConstraints.maxHeight <
                    240 * MediaQuery.textScalerOf(context).scale(14) / 14;
                Widget footer(Widget child) => Flexible(
                  flex: compactHeight ? 3 : 0,
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    key: const ValueKey('conversation-composer-viewport'),
                    child: child,
                  ),
                );
                return Column(
                  children: [
                    ValueListenableBuilder<SseConnectionState>(
                      valueListenable: widget.viewModel.connectionState,
                      builder: (context, state, _) {
                        final banner = _connectionBanner(state);
                        if (banner == null) {
                          return const SizedBox.shrink();
                        }
                        return ConnectionStatusBanner(
                          banner,
                          reconnecting:
                              state is SseReconnecting ||
                              state is SseReconciling,
                          onRetry: state is SseDisconnected
                              ? widget.viewModel.retryConnection
                              : null,
                        );
                      },
                    ),
                    Expanded(
                      child: isDesktop
                          ? Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: _transcriptPanel(
                                                showComposerActions: false,
                                                desktop: true,
                                              ),
                                            ),
                                            _activityPanel(
                                              maxHeight:
                                                  bodyConstraints.maxHeight,
                                            ),
                                            footer(
                                              _composerPanel(
                                                availableHeight:
                                                    bodyConstraints.maxHeight,
                                                constrainWidth: true,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (showArtifactsPanel) ...[
                                  _DesktopResizeHandle(
                                    key: const ValueKey(
                                      'desktop-session-details-divider',
                                    ),
                                    label: 'Resize session details',
                                    onDelta: (delta) => setState(() {
                                      _artifactsWidth =
                                          _artifactsWidthFor(
                                            constraints.maxWidth,
                                          ) -
                                          delta;
                                    }),
                                  ),
                                  SizedBox(
                                    width: _artifactsWidthFor(
                                      constraints.maxWidth,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        24,
                                      ),
                                      child: _artifactsPanel(lazy: true),
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : _transcriptPanel(showComposerActions: false),
                    ),
                    if (!isDesktop)
                      _activityPanel(
                        maxHeight: bodyConstraints.maxHeight,
                        flexible: compactHeight,
                      ),
                    if (!isDesktop)
                      footer(
                        _composerPanel(
                          availableHeight: bodyConstraints.maxHeight,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

String _executionLabel(SessionExecutionState state) => switch (state) {
  SessionBusy() => 'Working',
  SessionIdle() => 'Idle',
  SessionRetrying() => 'Retrying',
  SessionExecutionUnknown() => 'Syncing activity',
};

class _ExecutionIndicator extends StatefulWidget {
  const _ExecutionIndicator({required this.state});

  final SessionExecutionState state;

  @override
  State<_ExecutionIndicator> createState() => _ExecutionIndicatorState();
}

class _ExecutionIndicatorState extends State<_ExecutionIndicator> {
  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (widget.state) {
      SessionBusy() => ('Working', Icons.sync_rounded),
      SessionIdle() => ('Idle', Icons.check_circle_outline_rounded),
      SessionRetrying() => ('Retrying', Icons.replay_rounded),
      SessionExecutionUnknown() => ('Syncing activity', Icons.sync_problem),
    };
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Semantics(
          liveRegion: true,
          label: 'Execution status: $label',
          child: SpinningIcon(
            key: const ValueKey('conversation-execution-spin'),
            icon: icon,
            size: 22,
            spinning:
                widget.state is SessionBusy || widget.state is SessionRetrying,
          ),
        ),
      ),
    );
  }
}

class _Selection<T> {
  const _Selection(this.value);

  final T? value;
}

class _ExecutionChoice extends StatelessWidget {
  const _ExecutionChoice({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ExecutionPanel extends StatelessWidget {
  const _ExecutionPanel({
    required this.modelName,
    required this.agentName,
    this.loading = false,
    this.failure,
    this.onSelect,
    this.onRetry,
  });

  final String modelName;
  final String agentName;
  final bool loading;
  final String? failure;
  final VoidCallback? onSelect;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return PromptPanel(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Execution',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_rounded),
            title: const Text('Model'),
            subtitle: Text(modelName),
            trailing: loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : onSelect == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
            onTap: onSelect,
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Agent'),
            subtitle: Text(agentName),
            trailing: onSelect == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
            onTap: onSelect,
          ),
          if (failure case final failure?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text(failure)),
                  AppButton(
                    label: 'Retry',
                    variant: AppButtonVariant.tertiary,
                    onPressed: onRetry == null
                        ? null
                        : () => unawaited(onRetry!()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopResizeHandle extends StatelessWidget {
  const _DesktopResizeHandle({
    required this.label,
    required this.onDelta,
    super.key,
  });

  final String label;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: Semantics(
        label: label,
        onIncrease: () => onDelta(24),
        onDecrease: () => onDelta(-24),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
          child: const SizedBox(
            width: 9,
            child: Center(child: VerticalDivider(width: 1)),
          ),
        ),
      ),
    );
  }
}
