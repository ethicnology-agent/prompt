import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

import '../../../queue/queue.dart';

/// Lists the prompts and commands waiting to be dispatched for the session.
class QueuePanel extends StatelessWidget {
  const QueuePanel({
    required this.prompts,
    required this.onRemove,
    required this.onSendNow,
    required this.onMergeIntoPrevious,
    super.key,
  });

  final List<QueuedPrompt> prompts;
  final ValueChanged<QueuedPrompt> onRemove;
  final ValueChanged<QueuedPrompt> onSendNow;
  final ValueChanged<QueuedPrompt> onMergeIntoPrevious;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Queue: ${prompts.length} '
                  '${prompts.length == 1 ? 'prompt' : 'prompts'}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: prompts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final prompt = prompts[index];
                  return _QueueRow(
                    prompt: prompt,
                    position: index + 1,
                    previous: index == 0 ? null : prompts[index - 1],
                    onRemove: () => onRemove(prompt),
                    onSendNow: () => onSendNow(prompt),
                    onMergeIntoPrevious: () => onMergeIntoPrevious(prompt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.prompt,
    required this.position,
    required this.previous,
    required this.onRemove,
    required this.onSendNow,
    required this.onMergeIntoPrevious,
  });

  final QueuedPrompt prompt;
  final int position;

  /// The prompt this row would be merged into, or `null` for the queue head.
  final QueuedPrompt? previous;
  final VoidCallback onRemove;
  final VoidCallback onSendNow;
  final VoidCallback onMergeIntoPrevious;

  @override
  Widget build(BuildContext context) {
    final canSendNow = prompt.state == QueuedPromptState.queued;
    final canRemove = prompt.state != QueuedPromptState.sending;
    // Merging keeps one deferred turn instead of several: the row's text is
    // appended to the prompt above it, which stays the one that dispatches.
    final mergeablePair =
        previous != null && _mergeable(prompt) && _mergeable(previous!);
    final attachmentBlocksMerge =
        mergeablePair && prompt.attachments.isNotEmpty;
    final canMerge = mergeablePair && !attachmentBlocksMerge;
    final statusLabel = _statusLabel(prompt);

    return Semantics(
      label: 'Queued prompt $position, $statusLabel',
      child: ListTile(
        dense: true,
        leading: Text('$position'),
        title: Text(
          prompt.operationType == QueuedOperationType.command
              ? '/${prompt.commandName}${prompt.promptText.isEmpty ? '' : ' ${prompt.promptText}'}'
              : prompt.promptText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          attachmentBlocksMerge
              ? '$statusLabel\nAttachments cannot be merged. Keep this prompt separate.'
              : statusLabel,
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (canSendNow)
              AppIconButton(
                icon: Icons.bolt,
                tooltip: 'Send now (aborts current generation)',
                onPressed: onSendNow,
              ),
            if (canMerge)
              AppIconButton(
                icon: Icons.arrow_upward_rounded,
                tooltip: 'Merge into the prompt above',
                onPressed: onMergeIntoPrevious,
              ),
            AppIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove from queue',
              onPressed: canRemove ? onRemove : null,
            ),
          ],
        ),
      ),
    );
  }

  bool _mergeable(QueuedPrompt prompt) {
    return prompt.operationType == QueuedOperationType.prompt &&
        prompt.pauseReason != QueuePauseReason.submissionUnknown &&
        prompt.pauseReason != QueuePauseReason.sessionDeleted &&
        (prompt.state == QueuedPromptState.queued ||
            prompt.state == QueuedPromptState.paused ||
            prompt.state == QueuedPromptState.failed);
  }

  String _statusLabel(QueuedPrompt prompt) {
    return switch (prompt.state) {
      QueuedPromptState.queued => 'Queued',
      QueuedPromptState.sending => 'Sending…',
      QueuedPromptState.acknowledged => 'Sent',
      QueuedPromptState.failed => 'Failed to send',
      QueuedPromptState.paused => switch (prompt.pauseReason) {
        QueuePauseReason.submissionUnknown =>
          'Paused: delivery unconfirmed. Check the conversation before '
              'removing this local queue item. Removal does not cancel server work.',
        QueuePauseReason.permissionPending => 'Paused: awaiting permission',
        QueuePauseReason.questionPending => 'Paused: awaiting a question',
        QueuePauseReason.sessionGenerating => 'Paused: session busy',
        QueuePauseReason.networkUnavailable => 'Paused: network unavailable',
        QueuePauseReason.sessionDeleted =>
          'Stopped: session deletion requested. Remove this queued item to discard it.',
        QueuePauseReason.serverRejected => 'Paused: server rejected it',
        null => 'Paused',
      },
    };
  }
}
