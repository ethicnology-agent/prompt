import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/chat.dart';
import 'package:prompt/features/queue/queue.dart';

import '../tool/ui_preview.dart';
import '../tool/ui_preview/offline_client.dart';

void main() {
  for (final decision in {'Deny': 'reject', 'Allow once': 'once'}.entries) {
    testWidgets('offline permission ${decision.key} gates queued work', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = OfflinePreviewClient();
      final preview = OfflinePreview(client: client);
      await tester.pumpWidget(preview);
      await tester.pumpAndSettle();
      await tester.tap(find.text(OfflinePreviewClient.sessionTitle).first);
      await _ready(tester, preview);
      final composer = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Message this session…',
      );
      await tester.enterText(composer, 'permission');
      await _frame(tester);
      await tester.tap(find.byTooltip('Queue this prompt'));
      await _frame(tester);
      await _frame(tester);
      expect(client.acceptedPrompts, 1);
      await tester.enterText(composer, 'Run after the approval is resolved');
      await _frame(tester);
      await tester.tap(find.byTooltip('Queue this prompt'));
      for (var frame = 0; frame < 60; frame++) {
        await _frame(tester);
      }
      expect(find.text(decision.key), findsOneWidget);
      expect(client.acceptedPrompts, 1);
      expect(client.permissionReplies, 0);
      expect(client.promptAttempts, 1);
      expect(client.aborts, 0);
      await tester.tap(find.text(decision.key));
      await _frame(tester);
      await _frame(tester);
      expect(client.permissionReplies, 1);
      expect(client.lastPermissionResponse, decision.value);
      // Permission response acceptance is not terminal execution state.
      expect(client.acceptedPrompts, 1);
      expect(client.promptAttempts, 1);
      for (var frame = 0; frame < 90; frame++) {
        await _frame(tester);
      }
      expect(client.acceptedPrompts, 2);
      expect(client.promptAttempts, 2);
      expect(client.aborts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('offline fixture opens real UI and queues without aborting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = OfflinePreviewClient();
    final preview = OfflinePreview(client: client);
    await tester.pumpWidget(preview);
    await tester.pumpAndSettle();
    expect(find.byType(Banner), findsOneWidget);
    await tester.tap(find.text(OfflinePreviewClient.sessionTitle).first);
    await _ready(tester, preview);
    final composer = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Message this session…',
    );
    expect(composer, findsOneWidget);
    await tester.enterText(composer, 'First synthetic request');
    await _frame(tester);
    await tester.tap(find.byTooltip('Queue this prompt'));
    await _frame(tester);
    await _frame(tester);
    expect(client.acceptedPrompts, 1);
    await tester.enterText(composer, 'Second synthetic request');
    await _frame(tester);
    await tester.tap(find.byTooltip('Queue this prompt'));
    await _frame(tester);
    expect(client.acceptedPrompts, 1);
    expect(client.aborts, 0);
    // Advance frame-by-frame so stream reconciliation and queue dispatch run.
    for (var frame = 0; frame < 90; frame++) {
      await _frame(tester);
    }
    expect(client.acceptedPrompts, 2);
    expect(client.aborts, 0);
    expect(find.textContaining('Fixture reply:'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _ready(WidgetTester tester, OfflinePreview preview) async {
  for (var frame = 0; frame < 20; frame++) {
    await _frame(tester);
  }
  final vm = preview.dependencies.conversationViewModel;
  expect(vm.messages.value, isA<ConversationReady>());
  expect(vm.connectionState.value, isA<SseConnected>());
}

Future<void> _frame(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  // Stream cancellation can complete in the root microtask zone. Flush it
  // without a real delay; all fixture generation timers stay on fake time.
  await tester.runAsync(() async {});
  await tester.pump();
}
