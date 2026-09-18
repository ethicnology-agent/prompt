import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
import 'package:prompt/features/chat/presentation/session_file_diff_screen.dart';

Future<void> finishParsing(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'diff snapshot exposes raw content without automatic file reads dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var reads = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? promptDarkTheme() : promptTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: SessionFileDiffScreen(
              diff: const SessionFileDiff(
                file: 'lib/a file with a long name.dart',
                patch: '@@ -1 +1 @@\n-before\n+after\n',
                additions: 1,
                deletions: 1,
              ),
              onOpenFile: () => reads++,
            ),
          ),
        );
        await finishParsing(tester);
        expect(reads, 0);
        expect(find.text('Session snapshot · +1 −1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Current file'));
        expect(reads, 1);
        await tester.tap(find.text('Raw patch'));
        await tester.pumpAndSettle();
        expect(find.byType(CodeLineViewer), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('+after\n').hitTestable(),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('-before\n'), findsOneWidget);
        expect(find.text('+after\n'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('missing patch does not imply an empty file', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SessionFileDiffScreen(
          diff: SessionFileDiff(
            file: 'binary.dat',
            patch: '',
            additions: 0,
            deletions: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The server reported no patch for this file.'),
      findsOneWidget,
    );
    expect(find.text('Current file'), findsNothing);
    expect(find.text('Raw patch'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
