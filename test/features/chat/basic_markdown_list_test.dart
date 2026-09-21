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

  testWidgets('a list ends where the prose resumes', (tester) async {
    await tester.pumpWidget(host('- one\n\nAfterwards'));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('Afterwards'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
  });
}
