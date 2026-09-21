import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/presentation/basic_markdown_text.dart';

Widget host(String markdown) => MaterialApp(
  home: Scaffold(body: BasicMarkdownText(text: markdown)),
);

void main() {
  testWidgets('a dash list becomes bullets, not literal dashes', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('- Private server connection\n- Explicit approvals'),
    );
    expect(find.text('- Private server connection'), findsNothing);
    expect(find.text('Private server connection'), findsOneWidget);
    expect(find.text('Explicit approvals'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('nesting walks the reference glyphs and indents by 16', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('- top\n  - second\n    - third\n      - deep'),
    );
    expect(find.text('•'), findsOneWidget);
    expect(find.text('◦'), findsOneWidget);
    // The third glyph is the last one; deeper levels keep it.
    expect(find.text('▪'), findsNWidgets(2));
    final top = tester.getTopLeft(find.text('top')).dx;
    final second = tester.getTopLeft(find.text('second')).dx;
    expect(second - top, 16);
  });

  testWidgets('an ordered list keeps its own numbers', (tester) async {
    await tester.pumpWidget(host('1. first\n2. second\n7. seventh'));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('7.'), findsOneWidget);
    expect(find.text('•'), findsNothing);
  });

  testWidgets('a dash inside prose is left alone', (tester) async {
    await tester.pumpWidget(host('a - b'));
    expect(find.text('a - b'), findsOneWidget);
    expect(find.text('•'), findsNothing);
  });

  codeBlockTests();

  testWidgets('a list ends where the prose resumes', (tester) async {
    await tester.pumpWidget(host('- one\n\nAfterwards'));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('Afterwards'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
  });
}

void codeBlockTests() {
  testWidgets('a fenced block prints its language and keeps code on one line', (
    tester,
  ) async {
    await tester.pumpWidget(host('```python\ndef greet(name):\n    pass\n```'));
    expect(find.text('python'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    final label = tester.widget<Text>(find.text('python'));
    expect(label.style!.fontSize, 12);
  });

  testWidgets('a fence without a language prints no label', (tester) async {
    await tester.pumpWidget(host('```\nplain\n```'));
    expect(find.text('plain'), findsOneWidget);
    // Nothing above the code but the code itself.
    expect(find.byType(Text), findsNWidgets(0));
  });

  testWidgets('only the first word of the info string is the language', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('```dart title=example.dart\nvar a = 1;\n```'),
    );
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('dart title=example.dart'), findsNothing);
  });
}
