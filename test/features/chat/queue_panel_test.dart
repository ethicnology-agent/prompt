import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/presentation/widgets/queue_panel.dart';
import 'package:prompt/features/queue/queue.dart';

void main() {
  for (final stoppedIndex in [0, 1]) {
    testWidgets(
      'session deletion item $stoppedIndex cannot merge and explains discard',
      (tester) async {
        final prompts = [_prompt('first'), _prompt('second')];
        prompts[stoppedIndex] = prompts[stoppedIndex].copyWith(
          state: QueuedPromptState.paused,
          pauseReason: QueuePauseReason.sessionDeleted,
        );
        await _pump(tester, prompts);
        expect(find.byTooltip('Merge into the prompt above'), findsNothing);
        expect(
          find.textContaining('session deletion requested'),
          findsOneWidget,
        );
        expect(find.textContaining('session deleted'), findsNothing);
        expect(find.byTooltip('Remove from queue'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final uncertainIndex in [0, 1]) {
    testWidgets(
      'uncertain item $uncertainIndex cannot be merged in either direction',
      (tester) async {
        final prompts = [_prompt('first'), _prompt('second')];
        prompts[uncertainIndex] = prompts[uncertainIndex].copyWith(
          state: QueuedPromptState.paused,
          pauseReason: QueuePauseReason.submissionUnknown,
        );
        await _pump(tester, prompts);
        expect(find.byTooltip('Merge into the prompt above'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'uncertain delivery explains local removal without promising resume',
    (tester) async {
      final prompt = _prompt(
        'unknown',
        state: QueuedPromptState.paused,
        reason: QueuePauseReason.submissionUnknown,
      );
      var removed = 0;
      var sent = 0;
      await _pump(
        tester,
        [prompt],
        onRemove: (_) => removed++,
        onSendNow: (_) => sent++,
      );

      expect(find.textContaining('resume or remove'), findsNothing);
      expect(
        find.textContaining('Removal does not cancel server work.'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Send now (aborts current generation)'),
        findsNothing,
      );
      expect(find.byTooltip('Merge into the prompt above'), findsNothing);
      expect(sent, 0);
      await tester.tap(find.byTooltip('Remove from queue'));
      expect(removed, 1);
      expect(sent, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a source attachment prevents merge with an actionable explanation',
    (tester) async {
      var merged = 0;
      await _pump(tester, [
        _prompt('first'),
        _prompt('second', attachment: true),
      ], onMerge: (_) => merged++);

      expect(find.byTooltip('Merge into the prompt above'), findsNothing);
      expect(
        find.textContaining(
          'Attachments cannot be merged. Keep this prompt separate.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove from queue'), findsNWidgets(2));
      expect(merged, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'text can still merge into a preceding prompt with an attachment',
    (tester) async {
      String? mergedId;
      await _pump(tester, [
        _prompt('first', attachment: true),
        _prompt('second'),
      ], onMerge: (prompt) => mergedId = prompt.id);
      await tester.tap(find.byTooltip('Merge into the prompt above'));
      expect(mergedId, 'second');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<QueuedPrompt> prompts, {
  ValueChanged<QueuedPrompt>? onRemove,
  ValueChanged<QueuedPrompt>? onSendNow,
  ValueChanged<QueuedPrompt>? onMerge,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: QueuePanel(
          prompts: prompts,
          onRemove: onRemove ?? (_) {},
          onSendNow: onSendNow ?? (_) {},
          onMergeIntoPrevious: onMerge ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

QueuedPrompt _prompt(
  String id, {
  QueuedPromptState state = QueuedPromptState.queued,
  QueuePauseReason? reason,
  bool attachment = false,
}) => QueuedPrompt(
  id: id,
  serverProfileId: 'profile',
  sessionId: 'session',
  directory: '/fixture',
  position: id == 'first' ? 0 : 1,
  promptText: 'Synthetic $id',
  state: state,
  pauseReason: reason,
  attachments: attachment
      ? [
          QueuedAttachment(
            name: 'fixture.txt',
            mediaType: 'text/plain',
            bytes: Uint8List.fromList([65]),
          ),
        ]
      : [],
  attemptCount: 0,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
