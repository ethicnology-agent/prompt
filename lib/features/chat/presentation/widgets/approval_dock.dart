import 'dart:async';

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
    super.key,
  });

  final PendingApproval approval;
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

  /// The navigator holding the open sheet, and the request it is asking about.
  ///
  /// The sheet owns its own answers, so it can safely outlive this state for
  /// the frame it takes to pop. Keeping only a navigator here means nothing
  /// the sheet renders can reach into state that has been torn down.
  NavigatorState? _sheetNavigator;
  String? _sheetRequestId;

  @override
  void didUpdateWidget(covariant ApprovalDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compare the request, never the object: live conversation state is
    // rebuilt on every SSE event, so the same pending question arrives as a
    // fresh instance constantly.
    if (oldWidget.approval.id != widget.approval.id) _closeSheet();
  }

  @override
  void dispose() {
    // The screen keys this dock by request, so a new request destroys this
    // state outright and didUpdateWidget never runs. Without this, an open
    // sheet would be left asking about a request nobody waits on.
    _closeSheet();
    super.dispose();
  }

  /// Closes the sheet, after the current frame.
  ///
  /// Both callers run during a build or a teardown, and a route cannot be
  /// popped then.
  void _closeSheet() {
    final navigator = _sheetNavigator;
    final requestId = _sheetRequestId;
    _sheetNavigator = null;
    _sheetRequestId = null;
    if (navigator == null || requestId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && navigator.canPop()) navigator.pop();
    });
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
              // A questionnaire can carry several questions, chips and a free
              // text field. Inside this dock, capped at part of the screen and
              // squeezed further by the keyboard, that reads badly on a phone,
              // so there it moves to a sheet that owns the height it needs.
              PendingQuestionApproval() =>
                promptSizeClassForWidth(
                      MediaQuery.sizeOf(context).width,
                    ).isPhone
                    ? _buildQuestionsSummary(context, approval)
                    : _QuestionnaireForm(
                        questions: approval.questions,
                        submitting: _submitting,
                        onSubmit: (answers) =>
                            unawaited(_submitAnswers(approval, answers)),
                        onReject: () => unawaited(_reject(approval.requestId)),
                      ),
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

  /// A phone-sized stand-in that opens the questionnaire.
  Widget _buildQuestionsSummary(
    BuildContext context,
    PendingQuestionApproval approval,
  ) {
    final theme = Theme.of(context);
    final count = approval.questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count == 1
              ? 'The agent is asking a question'
              : 'The agent is asking $count questions',
          style: theme.textTheme.titleSmall,
        ),
        // Nothing else here on purpose. This says something is waiting and
        // opens it; the questions, their descriptions and the way to refuse
        // them all live one tap away, where they can be read in full. A
        // preview would be the one thing deliberately cut short, and a Reject
        // button here would invite refusing a request nobody has read.
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('approval-open-questions'),
            onPressed: _submitting
                ? null
                : () => _openQuestionSheet(context, approval),
            child: Text(count == 1 ? 'Answer' : 'Answer questions'),
          ),
        ),
      ],
    );
  }

  Future<void> _openQuestionSheet(
    BuildContext context,
    PendingQuestionApproval approval,
  ) async {
    _sheetNavigator = Navigator.of(context);
    _sheetRequestId = approval.id;
    final answers = await showModalBottomSheet<List<List<String>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        // Lift the form above the keyboard rather than letting it cover the
        // field being typed into.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _QuestionnaireForm(
            questions: approval.questions,
            onSubmit: (answers) => Navigator.of(sheetContext).pop(answers),
            onReject: () {
              Navigator.of(sheetContext).pop();
              unawaited(_reject(approval.requestId));
            },
          ),
        ),
      ),
    );
    _sheetNavigator = null;
    _sheetRequestId = null;
    if (answers != null) await _submitAnswers(approval, answers);
  }

  Future<void> _submitAnswers(
    PendingQuestionApproval approval,
    List<List<String>> answers,
  ) async {
    if (mounted) setState(() => _submitting = true);
    final succeeded = await widget.onReplyToQuestion(
      approval.requestId,
      answers,
    );
    if (mounted && !succeeded) setState(() => _submitting = false);
  }

  Future<void> _reject(String requestId) async {
    if (mounted) setState(() => _submitting = true);
    final succeeded = await widget.onRejectQuestion(requestId);
    if (mounted && !succeeded) setState(() => _submitting = false);
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
            // Full-width rows rather than chips: an option comes from an agent
            // and can be a sentence, which a chip clips on a phone. This also
            // finally shows each option's description, which until now only
            // existed for screen readers.
            for (final option in prompt.options)
              _OptionRow(
                option: option,
                multiple: prompt.multiple,
                selected: selected.contains(option.label),
                onToggle: () => onToggleOption(option.label),
              ),
          ],
          if (prompt.allowsCustomAnswer) ...[
            const SizedBox(height: 8),
            Semantics(
              label: 'Custom answer for ${prompt.header}',
              child: TextField(
                controller: customController,
                // A free answer can be a sentence; a single line would hide
                // its beginning as soon as it grew.
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
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

/// One selectable answer, shown in full.
///
/// The label and the description both wrap: nothing about an option is worth
/// hiding behind an ellipsis when the answer decides what the agent does next.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.multiple,
    required this.selected,
    required this.onToggle,
  });

  final QuestionOption option;
  final bool multiple;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: option.description.isEmpty
          ? option.label
          : '${option.label}: ${option.description}',
      selected: selected,
      inMutuallyExclusiveGroup: !multiple,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                multiple
                    ? (selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded)
                    : (selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded),
                size: 22,
                color: selected ? theme.colorScheme.primary : theme.hintColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(option.label, style: theme.textTheme.bodyMedium),
                    if (option.description.isNotEmpty)
                      Text(
                        option.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The questionnaire itself, owning the answers being composed.
///
/// It holds its own selections and text controllers so it can be rendered
/// either inside the dock or inside a modal sheet on its own route. Nothing
/// here reaches back into the dock's state, which is what lets the sheet
/// outlive it safely for the frame it takes to close.
class _QuestionnaireForm extends StatefulWidget {
  const _QuestionnaireForm({
    required this.questions,
    required this.onSubmit,
    required this.onReject,
    this.submitting = false,
  });

  final List<QuestionPrompt> questions;
  final ValueChanged<List<List<String>>> onSubmit;
  final VoidCallback onReject;
  final bool submitting;

  @override
  State<_QuestionnaireForm> createState() => _QuestionnaireFormState();
}

class _QuestionnaireFormState extends State<_QuestionnaireForm> {
  late final List<Set<String>> _selected;
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _selected = [for (final _ in widget.questions) <String>{}];
    _controllers = [for (final _ in widget.questions) TextEditingController()];
    for (final controller in _controllers) {
      // Whether Submit is enabled depends on the free-text answers too, so a
      // keystroke has to rebuild this form and not just its own field.
      controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_onChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _everyQuestionAnswered {
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selected[i].isEmpty && _controllers[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _toggle(int index, String label, bool multiple) {
    setState(() {
      final current = _selected[index];
      if (multiple) {
        if (!current.add(label)) current.remove(label);
      } else {
        current
          ..clear()
          ..add(label);
      }
    });
  }

  void _submit() {
    widget.onSubmit([
      for (var i = 0; i < widget.questions.length; i++)
        <String>[
          ..._selected[i],
          if (_controllers[i].text.trim().isNotEmpty)
            _controllers[i].text.trim(),
        ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit = !widget.submitting && _everyQuestionAnswered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.questions.length == 1
              ? 'The agent is asking a question'
              : 'The agent is asking ${widget.questions.length} questions',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < widget.questions.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == widget.questions.length - 1 ? 12 : 16,
            ),
            child: _QuestionCard(
              prompt: widget.questions[i],
              selected: _selected[i],
              customController: _controllers[i],
              onToggleOption: (label) =>
                  _toggle(i, label, widget.questions[i].multiple),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: const Text('Submit answers'),
            ),
            TextButton(
              onPressed: widget.submitting ? null : widget.onReject,
              child: const Text('Reject'),
            ),
          ],
        ),
      ],
    );
  }
}
