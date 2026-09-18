import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<SessionsFailure?> Function(String) save,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) =>
                    SessionRenameDialog(initialTitle: 'Original', onSave: save),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('rename validates title and cancel never writes', (tester) async {
    final calls = <String>[];
    await open(tester, (title) async {
      calls.add(title);
      return null;
    });
    for (final title in ['   ', 'x' * 257]) {
      await tester.enterText(find.byType(TextField), title);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a title between 1 and 256 characters.'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionRenameDialog), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('late rename completion closes only its own dialog', (
    tester,
  ) async {
    final pending = Completer<SessionsFailure?>();
    await open(tester, (_) => pending.future);
    await tester.enterText(find.byType(TextField), 'New title');
    await tester.tap(find.text('Rename'));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Unrelated route')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Unrelated route'), findsOneWidget);
    expect(find.byType(SessionRenameDialog, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename keeps failed draft for retry and serializes submission', (
    tester,
  ) async {
    final calls = <String>[];
    var pending = Completer<SessionsFailure?>();
    await open(tester, (title) {
      calls.add(title);
      return pending.future;
    });
    await tester.enterText(find.byType(TextField), '  New title  ');
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, ['New title']);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(SessionRenameDialog), findsOneWidget);
    pending.complete(SessionsFailure.unavailable);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '  New title  ',
    );
    expect(find.text(SessionsFailure.unavailable.message), findsOneWidget);
    pending = Completer<SessionsFailure?>();
    await tester.tap(find.text('Rename'));
    await tester.pump();
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(calls, ['New title', 'New title']);
    expect(find.byType(SessionRenameDialog), findsNothing);
  });
}
