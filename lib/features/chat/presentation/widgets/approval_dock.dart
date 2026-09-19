import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../domain/pending_approval.dart';
import '../../domain/permission_response.dart';

/// A non-dismissible dock shown above the composer whenever
/// [ConversationViewModel.pendingApproval] is not `null`: a pending
/// tool-call permission, or a pending question request. There is
/// deliberately no close/dismiss affordance — the human must allow,
/// always-allow, deny, or answer/reject before this goes away, and it
/// disappears on its own the moment that submission succeeds (see
/// [ConversationViewModel.respondToPermission]/[replyToQuestion]/
/// [rejectQuestion]).
///
/// [approval] and every [QuestionPrompt] it may carry can describe a
/// sensitive command, path, or question; this widget renders that detail
/// only to the person being asked to decide it and never logs or persists
/// it (see `pending_approval.dart`).
class ApprovalDock extends StatefulWidget {
  const ApprovalDock({
    required this.approval,
    required this.onRespondToPermission,
    required this.onReplyToQuestion,
    required this.onRejectQuestion,
    this.allowAlways = true,
    this.directory,
    this.maxHeight,
    super.key,
  });

  final PendingApproval approval;
  final bool allowAlways;
  final String? directory;
  final double? maxHeight;
  final Future<bool> Function(String permissionId, PermissionResponse response)
  onRespondToPermission;
  final Future<bool> Function(String requestId, List<List<String>> answers)
  onReplyToQuestion;
  final Future<bool> Function(String requestId) onRejectQuestion;

  @override
  State<ApprovalDock> createState() => ApprovalDockState();
}

class ApprovalDockState extends State<ApprovalDock> {
  bool _submitting = false;
  final _decisionScroll = ScrollController();
  final _detailsScroll = ScrollController();
  final Map<int, Set<String>> _selectedOptions = <int, Set<String>>{};
  final Map<int, TextEditingController> _customControllers =
      <int, TextEditingController>{};

  bool _canAlways(PendingPermissionApproval approval) =>
      widget.allowAlways &&
      approval.hasKnownAlwaysScope &&
      widget.directory != null &&
      widget.directory!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initQuestionControllers();
  }

  @override
  void dispose() {
    _decisionScroll.dispose();
    _detailsScroll.dispose();
    for (final controller in _customControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initQuestionControllers() {
    final approval = widget.approval;
    if (approval is! PendingQuestionApproval) {
      return;
    }
    for (var i = 0; i < approval.questions.length; i++) {
      _selectedOptions[i] = <String>{};
      final controller = TextEditingController();
      // Submit's enabled state depends on whether any question still has
      // no answer; a custom-answer keystroke must rebuild this dock, not
      // just the `TextField` itself.
      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      _customControllers[i] = controller;
    }
  }

  @override
  Widget build(BuildContext context) {
    final approval = widget.approval;
    final theme = Theme.of(context);
    final tokens = theme.extension<PromptTokens>();
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Action required before generation can continue',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border(
            left: BorderSide(
              color: tokens?.warning ?? theme.colorScheme.tertiary,
              width: 4,
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                widget.maxHeight ?? MediaQuery.sizeOf(context).height * 0.46,
          ),
          child: switch (approval) {
            PendingPermissionApproval() => _buildPermission(context, approval),
            PendingQuestionApproval() => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildQuestions(context, approval),
            ),
          },
        ),
      ),
    );
  }

  Widget _buildPermission(
    BuildContext context,
    PendingPermissionApproval approval,
  ) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight <
            MediaQuery.textScalerOf(context).scale(120) + 48;
        Widget decision(
          String label,
          PermissionResponse response,
          AppButtonVariant variant,
        ) => AppButton(
          label: label,
          variant: variant,
          autofocus: response == PermissionResponse.reject,
          onPressed: _submitting
              ? null
              : () => _respondToPermission(approval.permissionId, response),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Permission request details',
                hint: 'Scroll vertically to read the complete request',
                child: Scrollbar(
                  controller: _detailsScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _detailsScroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Approval needed: ${approval.toolType}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(approval.title),
                        if (approval.patterns.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text('Requested patterns'),
                          SelectableText(approval.patterns.join('\n')),
                        ],
                        if (approval.workingDirectory case final directory?)
                          SelectableText('Working directory: $directory'),
                        if (approval.reason case final reason?)
                          SelectableText('Reason: $reason'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: compact
                  ? Semantics(
                      hint: 'Scroll horizontally for more permission options',
                      child: Scrollbar(
                        controller: _decisionScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          key: const ValueKey('approval-decisions-scroll'),
                          controller: _decisionScroll,
                          padding: const EdgeInsets.only(bottom: 8),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              decision(
                                'Deny',
                                PermissionResponse.reject,
                                AppButtonVariant.tertiary,
                              ),
                              decision(
                                'Allow once',
                                PermissionResponse.once,
                                AppButtonVariant.primary,
                              ),
                              if (_canAlways(approval))
                                decision(
                                  'Always allow',
                                  PermissionResponse.always,
                                  AppButtonVariant.secondary,
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                label: 'Allow once',
                                onPressed: _submitting
                                    ? null
                                    : () => _respondToPermission(
                                        approval.permissionId,
                                        PermissionResponse.once,
                                      ),
                              ),
                            ),
                            Expanded(
                              child: AppButton(
                                label: 'Deny',
                                autofocus: true,
                                variant: AppButtonVariant.tertiary,
                                onPressed: _submitting
                                    ? null
                                    : () => _respondToPermission(
                                        approval.permissionId,
                                        PermissionResponse.reject,
                                      ),
                              ),
                            ),
                          ],
                        ),
                        if (_canAlways(approval))
                          AppButton(
                            label: 'Always allow',
                            variant: AppButtonVariant.secondary,
                            onPressed: _submitting
                                ? null
                                : () => _respondToPermission(
                                    approval.permissionId,
                                    PermissionResponse.always,
                                  ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    final approval = widget.approval;
    if (_submitting ||
        approval is! PendingPermissionApproval ||
        approval.permissionId != permissionId) {
      return;
    }
    setState(() => _submitting = true);
    if (response == PermissionResponse.always) {
      if (!_canAlways(approval)) {
        setState(() => _submitting = false);
        return;
      }
      final directory = widget.directory;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: const Text('Allow matching requests across sessions?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This can allow future matching requests in other '
                  'sessions for this directory. It is not limited to this '
                  'session. The server controls how long these rules remain.',
                ),
                const SizedBox(height: 12),
                SelectableText('Directory: $directory'),
                SelectableText('Permission: ${approval.toolType}'),
                const Text('Reusable patterns'),
                SelectableText(approval.alwaysPatterns.join('\n')),
              ],
            ),
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              autofocus: true,
              variant: AppButtonVariant.tertiary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton(
              label: 'Confirm always allow',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true ||
          !identical(widget.approval, approval) ||
          widget.directory != directory ||
          !_canAlways(approval)) {
        setState(() => _submitting = false);
        return;
      }
    }
    final succeeded = await widget.onRespondToPermission(
      permissionId,
      response,
    );
    if (mounted && !succeeded) {
      setState(() => _submitting = false);
    }
  }

  Widget _buildQuestions(
    BuildContext context,
    PendingQuestionApproval approval,
  ) {
    final theme = Theme.of(context);
    final canSubmit = !_submitting && _everyQuestionAnswered(approval);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'The agent is asking a question',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < approval.questions.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == approval.questions.length - 1 ? 12 : 16,
            ),
            child: _QuestionCard(
              enabled: !_submitting,
              prompt: approval.questions[i],
              selected: _selectedOptions[i]!,
              customController: _customControllers[i]!,
              onToggleOption: (label) =>
                  _toggleOption(i, label, approval.questions[i].multiple),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              label: 'Submit answers',
              onPressed: canSubmit ? () => _submitAnswers(approval) : null,
            ),
            AppButton(
              label: 'Reject',
              variant: AppButtonVariant.tertiary,
              onPressed: _submitting ? null : () => _reject(approval.requestId),
            ),
          ],
        ),
      ],
    );
  }

  bool _everyQuestionAnswered(PendingQuestionApproval approval) {
    for (var i = 0; i < approval.questions.length; i++) {
      final hasSelection = (_selectedOptions[i] ?? const <String>{}).isNotEmpty;
      final hasCustom =
          (_customControllers[i]?.text.trim().isNotEmpty) ?? false;
      if (!hasSelection && !hasCustom) {
        return false;
      }
    }
    return true;
  }

  void _toggleOption(int index, String label, bool multiple) {
    if (!mounted || _submitting) return;
    setState(() {
      final current = _selectedOptions[index]!;
      if (multiple) {
        if (!current.add(label)) {
          current.remove(label);
        }
      } else {
        current
          ..clear()
          ..add(label);
      }
    });
  }

  Future<void> _submitAnswers(PendingQuestionApproval approval) async {
    if (!mounted ||
        _submitting ||
        !identical(widget.approval, approval) ||
        !_everyQuestionAnswered(approval)) {
      return;
    }
    final answers = <List<String>>[];
    for (var i = 0; i < approval.questions.length; i++) {
      final answer = <String>[...?_selectedOptions[i]];
      final custom = _customControllers[i]?.text.trim() ?? '';
      if (custom.isNotEmpty) {
        answer.add(custom);
      }
      answers.add(answer);
    }
    setState(() => _submitting = true);
    final succeeded = await widget.onReplyToQuestion(
      approval.requestId,
      answers,
    );
    if (mounted && !succeeded) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _reject(String requestId) async {
    if (!mounted ||
        _submitting ||
        widget.approval is! PendingQuestionApproval ||
        (widget.approval as PendingQuestionApproval).requestId != requestId) {
      return;
    }
    setState(() => _submitting = true);
    final succeeded = await widget.onRejectQuestion(requestId);
    if (mounted && !succeeded) {
      setState(() => _submitting = false);
    }
  }
}

/// One question within an [ApprovalDock] showing [PendingQuestionApproval.
/// questions]. Options render as accessible, keyboard/touch-operable
/// radio or checkbox rows; a free-text answer is offered alongside them whenever
/// [QuestionPrompt.allowsCustomAnswer] is true.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.enabled,
    required this.prompt,
    required this.selected,
    required this.customController,
    required this.onToggleOption,
  });

  final QuestionPrompt prompt;
  final bool enabled;
  final Set<String> selected;
  final TextEditingController customController;
  final ValueChanged<String> onToggleOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prompt.header, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(prompt.question),
          if (prompt.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in prompt.options)
                  ChoiceOptionTile(
                    label: option.label,
                    description: option.description,
                    selected: selected.contains(option.label),
                    multiple: prompt.multiple,
                    enabled: enabled,
                    onPressed: () => onToggleOption(option.label),
                  ),
              ],
            ),
          ],
          if (prompt.allowsCustomAnswer) ...[
            const SizedBox(height: 8),
            Semantics(
              label: 'Custom answer for ${prompt.header}',
              child: AppTextField(
                controller: customController,
                readOnly: !enabled,
                hint: 'Or type your own answer',
                dense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
