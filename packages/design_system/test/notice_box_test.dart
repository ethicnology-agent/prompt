import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? promptDarkTheme() : promptTheme(),
  home: Scaffold(body: SizedBox(width: 360, child: child)),
);

void main() {
  for (final dark in [false, true]) {
    for (final tone in NoticeTone.values) {
      testWidgets('${tone.name} notice is bordered and legible dark=$dark', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            NoticeBox(message: 'Something to know', tone: tone),
            dark: dark,
          ),
        );
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byType(NoticeBox),
            matching: find.byType(Container),
          ),
        );
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.border, isNotNull);
        expect(decoration.borderRadius, BorderRadius.circular(8));
        final text = tester.widget<Text>(find.text('Something to know'));
        // The reference writes the message in the border's colour; whatever the
        // surface underneath, it has to stay readable.
        expect(
          contrast(
            Color.alphaBlend(
              decoration.color!,
              dark ? Colors.black : Colors.white,
            ),
            text.style!.color!,
          ),
          greaterThanOrEqualTo(2.5),
          reason: '${tone.name} on ${dark ? 'dark' : 'light'} is too faint',
        );
      });
    }
  }

  testWidgets('an error notice announces itself', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        host(const NoticeBox(message: 'It failed', tone: NoticeTone.error)),
      );
      final node = tester.getSemantics(find.byType(NoticeBox));
      expect(node.flagsCollection.isLiveRegion, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an empty state names the situation and the way out', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        EmptyState(
          icon: Icons.terminal_outlined,
          title: 'No directory chosen',
          message: 'Choose one to list its terminals.',
          action: AppButton(label: 'Choose', onPressed: () {}),
        ),
      ),
    );
    expect(find.text('No directory chosen'), findsOneWidget);
    expect(find.text('Choose one to list its terminals.'), findsOneWidget);
    expect(find.byType(AppButton), findsOneWidget);
    expect(tester.getSize(find.byIcon(Icons.terminal_outlined)).width, 56);
  });
}
