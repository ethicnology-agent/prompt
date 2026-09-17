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
    super.key,
  });

  final PendingApproval approval;
  final bool allowAlways;
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
  final Map<int, Set<String>> _selectedOptions = <int, Set<String>>{};
  final Map<int, TextEditingController> _customControllers =
      <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _initQuestionControllers();
  }

  @override
  void dispose() {
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
            maxHeight: MediaQuery.sizeOf(context).height * 0.46,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: switch (approval) {
              PendingPermissionApproval() => _buildPermission(
                context,
                approval,
              ),
              PendingQuestionApproval() => _buildQuestions(context, approval),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPermission(
    BuildContext context,
    PendingPermissionApproval approval,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Approval needed: ${approval.toolType}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(approval.title),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _submitting
                  ? null
                  : () => _respondToPermission(
                      approval.permissionId,
                      PermissionResponse.once,
                    ),
              child: const Text('Allow once'),
            ),
            if (widget.allowAlways)
              OutlinedButton(
                onPressed: _submitting
                    ? null
                    : () => _respondToPermission(
                        approval.permissionId,
                        PermissionResponse.always,
                      ),
                child: const Text('Always allow'),
              ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => _respondToPermission(
                      approval.permissionId,
                      PermissionResponse.reject,
                    ),
              child: const Text('Deny'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    setState(() => _submitting = true);
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
            FilledButton(
              onPressed: canSubmit ? () => _submitAnswers(approval) : null,
              child: const Text('Submit answers'),
            ),
            TextButton(
              onPressed: _submitting ? null : () => _reject(approval.requestId),
              child: const Text('Reject'),
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
    setState(() => _submitting = true);
    final succeeded = await widget.onRejectQuestion(requestId);
    if (mounted && !succeeded) {
      setState(() => _submitting = false);
    }
  }
}

/// One question within an [ApprovalDock] showing [PendingQuestionApproval.
/// questions]. Options render as accessible, keyboard/touch-operable
/// [FilterChip]s; a free-text answer is offered alongside them whenever
/// [QuestionPrompt.allowsCustomAnswer] is true.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.prompt,
    required this.selected,
    required this.customController,
    required this.onToggleOption,
  });

  final QuestionPrompt prompt;
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in prompt.options)
                  Semantics(
                    label: '${option.label}: ${option.description}',
                    selected: selected.contains(option.label),
                    button: true,
                    child: FilterChip(
                      label: Text(option.label),
                      selected: selected.contains(option.label),
                      onSelected: (_) => onToggleOption(option.label),
                    ),
                  ),
              ],
            ),
          ],
          if (prompt.allowsCustomAnswer) ...[
            const SizedBox(height: 8),
            Semantics(
              label: 'Custom answer for ${prompt.header}',
              child: TextField(
                controller: customController,
                decoration: const InputDecoration(
                  hintText: 'Or type your own answer',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
