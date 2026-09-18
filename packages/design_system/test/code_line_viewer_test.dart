import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'wrapped source retains its final character at 320px and 200 percent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = '${List.filled(16, 'source content').join(' ')} END';
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: CodeLineViewer(lines: [source, 'next'])),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('$source\n'),
          matching: find.byType(RichText),
        ),
      );
      final ending = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: source.length - 3,
          extentOffset: source.length,
        ),
      );
      expect(ending, isNotEmpty);
      expect(paragraph.size.height, greaterThan(39));
      for (final box in ending) {
        expect(box.bottom, lessThanOrEqualTo(paragraph.size.height));
        expect(box.right, lessThanOrEqualTo(paragraph.size.width));
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('source separators do not add visual blank rows scale=$scale', (
      tester,
    ) async {
      final theme = promptTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: CodeLineViewer(
                lines: const ['alpha', 'beta', 'gamma'],
                header: Text(
                  'reference',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final expected = tester.getSize(find.text('reference')).height + 4;
      for (var index = 1; index <= 3; index++) {
        expect(
          tester.getSize(find.byKey(ValueKey('code-line-$index'))).height,
          closeTo(expected, 0.01),
        );
      }
      final semantics = tester.ensureSemantics();
      try {
        final second = tester.getSemantics(
          find.byKey(const ValueKey('code-line-2')),
        );
        expect(second.toStringDeep(), contains('beta'));
        expect(second.toStringDeep(), contains('Line 2'));
      } finally {
        semantics.dispose();
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('one selection copies multiple lines without gutter or header', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeLineViewer(
            lines: ['alpha', 'beta'],
            header: Text('File header'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha\n'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    final selection = tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion;
    selection.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    Actions.invoke(
      tester.element(find.text('alpha\n')),
      CopySelectionTextIntent.copy,
    );
    await tester.pump();
    expect(copied, 'alpha\nbeta');
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'numbered code stays literal and lazy at 200 percent dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final lines = List.generate(
          1000,
          (index) => index == 0
              ? '<script>https://example.invalid/a</script>'
              : 'source line $index',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? promptDarkTheme() : promptTheme(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: CodeLineViewer(
                  lines: lines,
                  header: const Text('Read-only file'),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Read-only file'), findsOneWidget);
        expect(find.text('${lines.first}\n'), findsOneWidget);
        expect(find.byKey(const ValueKey('code-line-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('code-line-1000')), findsNothing);
        expect(find.byType(Text).evaluate().length, lessThan(100));
        final row = tester.widget<Semantics>(
          find.byKey(const ValueKey('code-line-1')),
        );
        expect(row.properties.label, 'Line 1');
        expect(find.byType(TextField), findsNothing);
        await tester.scrollUntilVisible(
          find.text('source line 20\n').hitTestable(),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.byKey(const ValueKey('code-line-21')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
