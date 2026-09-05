import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.reviewViewModelFactory,
    super.key,
  });

  final ServerProfile profile;
  final OpenCodeSession session;
  final ConversationViewModel viewModel;
  final CapabilitiesViewModel? capabilitiesViewModel;
  final VoiceViewModel? voiceViewModel;
  final ValueChanged<OpenCodeSession>? onOpenFork;
  final ReviewViewModel Function()? reviewViewModelFactory;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _transcriptController = ScrollController();
  StreamSubscription<String>? _queueErrorSubscription;
  StreamSubscription<String>? _transcriptErrorSubscription;
  bool _showJumpToLatest = false;
  bool? _artifactsPanelOverride;
  double? _artifactsWidth;
  late final ValueNotifier<PromptExecutionOptions> _executionOptions;
  OpenCodeSlashCommand? _selectedCommand;
  String? _voiceDraftPrefix;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _executionOptions = ValueNotifier(
      widget.viewModel.executionOptionsFor(widget.profile, widget.session),
    );
    final draft = widget.viewModel.draftFor(widget.profile, widget.session);
    _composerController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _composerController.addListener(_rememberComposerDraft);
    _transcriptController.addListener(_updateJumpToLatestVisibility);
    widget.viewModel.open(widget.profile, widget.session);
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
    WidgetsBinding.instance.removeObserver(this);
    _queueErrorSubscription?.cancel();
    _transcriptErrorSubscription?.cancel();
    widget.voiceViewModel?.state.removeListener(_applyVoiceState);
    unawaited(widget.voiceViewModel?.cancel());
    _composerController.removeListener(_rememberComposerDraft);
    _composerController.dispose();
    _executionOptions.dispose();
    _transcriptController
      ..removeListener(_updateJumpToLatestVisibility)
      ..dispose();
    widget.viewModel.leaveSession(widget.session);
    super.dispose();
  }

  void _rememberComposerDraft() {
    widget.viewModel.rememberDraft(
      widget.profile,
      widget.session,
      _composerController.text,
    );
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
    final text = _composerController.text.trim();
    final command = _selectedCommand;
    final hasAttachments = widget.viewModel.attachments.value.isNotEmpty;
    if (text.isEmpty && command == null && !hasAttachments) {
      return;
    }
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
    if (queued) {
      _composerController.clear();
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
    return PromptExecutionOptions(
      modelProviderId:
          command.model?.providerId ?? _executionOptions.value.modelProviderId,
      modelId: command.model?.modelId ?? _executionOptions.value.modelId,
      agentName: command.agentName ?? _executionOptions.value.agentName,
    );
  }

  Future<void> _selectCommand(List<OpenCodeSlashCommand> commands) async {
    final selectedName = await _showAdaptiveChoice<String>(
      title: 'Slash command',
      builder: (context, controller) => ListView(
        controller: controller,
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Message'),
            subtitle: const Text('Send a regular queued prompt'),
            onTap: () => Navigator.of(context).pop(const _Selection('')),
          ),
          for (final command in commands)
            ListTile(
              title: Text('/${command.name}'),
              subtitle: Text(command.description ?? 'Run slash command'),
              selected: command.name == _selectedCommand?.name,
              onTap: () => Navigator.of(context).pop(_Selection(command.name)),
            ),
        ],
      ),
    );
    if (!mounted || selectedName == null) {
      return;
    }
    setState(
      () => _selectedCommand = selectedName.value!.isEmpty
          ? null
          : commands.firstWhere(
              (command) => command.name == selectedName.value,
            ),
    );
  }

  Future<void> _selectExecutionOptions(
    OpenCodeCapabilities capabilities,
  ) async {
    final selected = await _showAdaptiveChoice<PromptExecutionOptions>(
      title: 'Prompt execution',
      builder: (context, controller) {
        var model = _selectedModel(capabilities.models);
        var agent = _selectedAgent(capabilities.agents);
        return StatefulBuilder(
          builder: (context, setDialogState) => ListView(
            controller: controller,
            shrinkWrap: true,
            children: [
              _ExecutionChoice(
                label: 'Model',
                value: model?.name ?? 'Default',
                onTap: () async {
                  final choice = await _chooseModel(capabilities.models, model);
                  if (choice != null) {
                    setDialogState(() => model = choice.value);
                  }
                },
              ),
              _ExecutionChoice(
                label: 'Agent',
                value: agent?.name ?? 'Default',
                onTap: () async {
                  final choice = await _chooseAgent(capabilities.agents, agent);
                  if (choice != null) {
                    setDialogState(() => agent = choice.value);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _Selection(
                        PromptExecutionOptions(
                          modelProviderId: model?.providerId,
                          modelId: model?.id,
                          agentName: agent?.name,
                        ),
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
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
        return AlertDialog(
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
  ) => _showAdaptiveChoice<OpenCodeModel>(
    title: 'Model',
    builder: (context, controller) => ListView(
      controller: controller,
      children: [
        ListTile(
          title: const Text('Default'),
          selected: selected == null,
          onTap: () => Navigator.of(context).pop(const _Selection(null)),
        ),
        for (final candidate in models.where(
          (model) => model.isProviderConnected,
        ))
          ListTile(
            title: Text(candidate.name),
            selected: candidate == selected,
            onTap: () => Navigator.of(context).pop(_Selection(candidate)),
          ),
      ],
    ),
  );

  Future<_Selection<OpenCodeAgent>?> _chooseAgent(
    List<OpenCodeAgent> agents,
    OpenCodeAgent? selected,
  ) => _showAdaptiveChoice<OpenCodeAgent>(
    title: 'Agent',
    builder: (context, controller) => ListView(
      controller: controller,
      children: [
        ListTile(
          title: const Text('Default'),
          selected: selected == null,
          onTap: () => Navigator.of(context).pop(const _Selection(null)),
        ),
        for (final candidate in agents)
          ListTile(
            title: Text(candidate.name),
            selected: candidate == selected,
            onTap: () => Navigator.of(context).pop(_Selection(candidate)),
          ),
      ],
    ),
  );

  OpenCodeModel? _selectedModel(List<OpenCodeModel> models) {
    for (final model in models) {
      if (model.providerId == _executionOptions.value.modelProviderId &&
          model.id == _executionOptions.value.modelId) {
        return model;
      }
    }
    return null;
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
        return AlertDialog(
          title: const Text('Abort current generation and send now?'),
          content: const Text(
            'This cancels whatever the session is currently generating, '
            'then sends this queued prompt immediately, ahead of the rest '
            'of the queue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Abort & send now'),
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
      builder: (context) => AlertDialog(
        title: const Text('Revert this message?'),
        content: const Text(
          'OpenCode will revert the session to this message. Later messages '
          'and session changes may be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revert message'),
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
                    TextButton(
                      onPressed: () =>
                          widget.viewModel.loadOlderFromUserAction(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              Expanded(
                child: Transcript(
                  messages: messages,
                  onRefresh: widget.viewModel.refreshFromUserAction,
                  onRevert: _confirmRevert,
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
          Positioned(right: 16, bottom: 16, child: _composerActionColumn()),
      ],
    );
  }

  Widget _composerActionColumn() {
    final capabilitiesViewModel = widget.capabilitiesViewModel;
    Widget buildActions(List<OpenCodeSlashCommand> commands) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.voiceViewModel case final voiceViewModel?)
          ValueListenableBuilder<VoiceUiState>(
            valueListenable: voiceViewModel.state,
            builder: (context, state, _) => ValueListenableBuilder<bool>(
              valueListenable: voiceViewModel.hasSelectedModel,
              builder: (context, hasModel, _) {
                if (!hasModel || state is! VoiceIdle) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FloatingActionButton.small(
                    heroTag: 'start-voice-mode',
                    onPressed: _enterVoiceMode,
                    tooltip: 'Start voice mode',
                    child: const Icon(Icons.mic_rounded),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: commands.isEmpty ? 0 : 8),
          child: FloatingActionButton.small(
            heroTag: 'add-attachment',
            onPressed: _pickAttachments,
            tooltip: 'Add attachment',
            child: const Icon(Icons.attach_file_rounded),
          ),
        ),
        if (commands.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FloatingActionButton.small(
              heroTag: 'choose-slash-command',
              onPressed: () => _selectCommand(commands),
              tooltip: 'Choose slash command',
              child: const Icon(Icons.code_rounded),
            ),
          ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _composerController,
          builder: (context, value, _) =>
              ValueListenableBuilder<List<PromptAttachment>>(
                valueListenable: widget.viewModel.attachments,
                builder: (context, selected, _) {
                  final enabled =
                      value.text.trim().isNotEmpty ||
                      _selectedCommand != null ||
                      selected.isNotEmpty;
                  return FloatingActionButton.small(
                    heroTag: 'queue-prompt',
                    onPressed: enabled
                        ? () => unawaited(_submitComposer())
                        : null,
                    tooltip: _selectedCommand == null
                        ? 'Queue this prompt'
                        : 'Queue command',
                    child: const Icon(Icons.send),
                  );
                },
              ),
        ),
      ],
    );
    if (capabilitiesViewModel == null) {
      return buildActions(const []);
    }
    return ValueListenableBuilder<CapabilitiesUiState>(
      valueListenable: capabilitiesViewModel,
      builder: (context, state, _) => buildActions(
        state is CapabilitiesReady ? state.capabilities.commands : const [],
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
            builder: (context, state, _) => ListView(
              controller: scrollController,
              children: [
                _executionPanel(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 560,
                  child: SessionArtifactsPanel(
                    state: state,
                    onRefresh: widget.viewModel.reloadArtifacts,
                    lazy: true,
                  ),
                ),
              ],
            ),
          ),
    ),
  );

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
    // The pending approval is not here: it takes the composer's place, see
    // _composerPanel. Stacking it above the input read as two bars bolted
    // together, and put the one thing that must be acted on furthest from the
    // thumb.
    return ValueListenableBuilder<List<QueuedPrompt>>(
      valueListenable: widget.viewModel.queue,
      builder: (context, prompts, _) {
        final activePrompts = prompts
            .where((prompt) => prompt.state != QueuedPromptState.acknowledged)
            .toList(growable: false);
        if (activePrompts.isEmpty) return const SizedBox.shrink();
        final panel = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: activityMaxHeight),
          child: SingleChildScrollView(
            key: const ValueKey('conversation-activity-scroll'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
            ),
          ),
        );
        return flexible ? Flexible(fit: FlexFit.loose, child: panel) : panel;
      },
    );
  }

  Widget _composerPanel({bool constrainWidth = false}) => SafeArea(
    key: const ValueKey('conversation-composer-panel'),
    top: false,
    child: Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        key: const ValueKey('conversation-composer-content'),
        constraints: BoxConstraints(
          maxWidth: constrainWidth ? 960 : double.infinity,
        ),
        // While something is waiting on the user, it stands where the input
        // stands. Generation is blocked until it is answered, so offering a
        // text field beside it invited typing into a session that cannot
        // listen, and left the required action stacked above as a second bar.
        child: ValueListenableBuilder<PendingApproval?>(
          valueListenable: widget.viewModel.pendingApproval,
          builder: (context, approval, _) => approval == null
              ? Composer(
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
                  onVoiceStop: widget.voiceViewModel?.stopModeFromUserAction,
                )
              : ApprovalDock(
                  key: ValueKey(_approvalKey(approval)),
                  approval: approval,
                  onRespondToPermission: widget.viewModel.respondToPermission,
                  onReplyToQuestion: widget.viewModel.replyToQuestion,
                  onRejectQuestion: widget.viewModel.rejectQuestion,
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
                FilledButton.icon(
                  onPressed: widget.viewModel.reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
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
        final isDesktop = constraints.maxWidth >= PromptBreakpoints.desktop;
        final showArtifactsPanel = _artifactsPanelOverride ?? isDesktop;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            titleSpacing: 4,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.session.title.isEmpty
                      ? 'Untitled session'
                      : widget.session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  directoryName(widget.session.directory),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.reviewViewModelFactory != null &&
                  widget.capabilitiesViewModel != null)
                IconButton(
                  onPressed: _openReview,
                  tooltip: 'Review diff',
                  icon: const Icon(Icons.rate_review_outlined),
                ),
              if (isDesktop)
                IconButton(
                  onPressed: widget.viewModel.refreshFromUserAction,
                  tooltip: 'Refresh transcript',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ValueListenableBuilder<SessionExecutionState>(
                valueListenable: widget.viewModel.executionState,
                builder: (context, state, _) =>
                    Center(child: _ExecutionIndicator(state: state)),
              ),
              IconButton(
                onPressed: () => _toggleArtifactsPanel(
                  isDesktop: isDesktop,
                  showing: showArtifactsPanel,
                ),
                icon: const Icon(Icons.assignment_outlined),
                tooltip: isDesktop
                    ? showArtifactsPanel
                          ? 'Hide session details'
                          : 'Show session details'
                    : 'Session artifacts',
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
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
                        state is SseReconnecting || state is SseReconciling,
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
                                        maxHeight: constraints.maxHeight,
                                      ),
                                      _composerPanel(constrainWidth: true),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  key: const ValueKey(
                                    'desktop-composer-action-rail',
                                  ),
                                  width: 64,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: _composerActionColumn(),
                                    ),
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
                                    _artifactsWidthFor(constraints.maxWidth) -
                                    delta;
                              }),
                            ),
                            SizedBox(
                              width: _artifactsWidthFor(constraints.maxWidth),
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
                    : _transcriptPanel(),
              ),
              if (!isDesktop)
                _activityPanel(
                  maxHeight: constraints.maxHeight,
                  flexible: true,
                ),
              if (!isDesktop) _composerPanel(),
            ],
          ),
        );
      },
    );
  }
}

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
                  TextButton(
                    onPressed: onRetry == null
                        ? null
                        : () => unawaited(onRetry!()),
                    child: const Text('Retry'),
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
