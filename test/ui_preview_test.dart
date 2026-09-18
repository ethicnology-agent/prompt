import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/chat.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/workspace/workspace.dart';
import 'package:prompt/features/chat/presentation/session_file_diff_screen.dart';

import '../tool/ui_preview.dart';
import '../tool/ui_preview/offline_client.dart';

void main() {
  testWidgets(
    'workspace fixture searches and opens relative results in their scope',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = OfflinePreviewClient();
      final preview = OfflinePreview(client: client);
      await tester.pumpWidget(preview);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse workspace'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('prompt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search workspace',
      );
      await tester.enterText(search, 'example');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(client.fileReads, 0);
      await tester.tap(find.text('example.dart'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceFileScreen), findsOneWidget);
      expect(find.text('final accent = "teal";\n'), findsOneWidget);
      expect(client.fileReads, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'example');
      await tester.tap(find.byTooltip('Clear workspace search'));
      await tester.pumpAndSettle();
      expect(find.text('example.dart'), findsOneWidget);
      await tester.tap(find.byTooltip('Parent directory'));
      await tester.pumpAndSettle();
      expect(find.text('lib'), findsOneWidget);
      expect(client.acceptedPrompts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'file navigation preserves the conversation and distinguishes snapshot from current content',
    (tester) async {
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
      await tester.enterText(composer, 'Keep this unsent draft');
      await tester.pump();
      expect(client.fileReads, 0);
      final transcript = tester.widget<CustomScrollView>(
        find.byKey(const ValueKey('conversation-transcript-scroll')),
      );
      final offset = transcript.controller!.offset;
      await tester.tap(find.text(OfflinePreviewClient.filePath));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceFileScreen), findsOneWidget);
      expect(find.text('Current server file · read-only'), findsOneWidget);
      expect(find.text('final accent = "teal";\n'), findsOneWidget);
      expect(client.fileReads, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep this unsent draft',
      );
      expect(transcript.controller!.offset, offset);
      expect(client.acceptedPrompts, 0);
      await tester.tap(find.byTooltip('Session details and actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Session artifacts'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('lib/example.dart').hitTestable(),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('lib/example.dart'));
      await tester.pump();
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(SessionFileDiffScreen), findsOneWidget);
      expect(find.text('Session snapshot · +1 −1'), findsOneWidget);
      expect(client.fileReads, 1);
      await tester.tap(find.text('Current file'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceFileScreen), findsOneWidget);
      expect(client.fileReads, 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SessionFileDiffScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Session artifacts'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Session artifacts'), findsNothing);
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep this unsent draft',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
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
