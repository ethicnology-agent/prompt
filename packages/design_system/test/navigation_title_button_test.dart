import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextSpan _spanWithText(InlineSpan span, String text) {
  if (span case final TextSpan value) {
    if (value.text == text) return value;
    for (final child in value.children ?? const <InlineSpan>[]) {
      try {
        return _spanWithText(child, text);
      } on StateError {
        // Continue through sibling spans.
      }
    }
  }
  throw StateError('Text span not found.');
}

void main() {
  const title = 'A long session title that must remain fully accessible';
  const description = 'Open session details: $title';
  const directory = '/workspace/a-long-synthetic-directory';
  for (final height in [56.0, 68.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('title fits height=$height scale=$scale dark=$dark', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? promptDarkTheme() : promptTheme(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: SizedBox(
                      width: 96,
                      height: height,
                      child: NavigationTitleButton(
                        label: title,
                        semanticLabel: description,
                        subtitle: directory,
                        onPressed: () => taps++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final button = find.byType(TextButton);
          final bounds = tester.getRect(button);
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, lessThanOrEqualTo(height));
          final text = tester.widget<Text>(find.text(title));
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          final theme = Theme.of(tester.element(button));
          expect(text.style!.color, theme.colorScheme.onSurface);
          expect(find.byTooltip('$title\n$directory'), findsOneWidget);
          final node = tester.getSemantics(find.bySemanticsLabel(description));
          expect(
            node,
            matchesSemantics(
              label: description,
              value: directory,
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasFocusAction: true,
              hasTapAction: true,
            ),
          );
          if (height == 56 && scale == 2) {
            expect(find.text(directory), findsNothing);
          } else if (scale == 1) {
            expect(find.text(directory), findsOneWidget);
          }
          await tester.tap(button);
          expect(taps, 1);
          semantics.dispose();
        });
      }
    }
  }

  testWidgets('title supports keyboard focus and activation without subtitle', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          appBar: AppBar(
            title: NavigationTitleButton(
              label: title,
              semanticLabel: description,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final buttonContext = tester.element(find.text(title));
    expect(Focus.of(buttonContext).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    expect(find.byTooltip(title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('segmented subtitle keeps colors and one semantic value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          appBar: AppBar(
            title: NavigationTitleButton(
              label: 'Session',
              semanticLabel: 'Open session details: Session',
              subtitleSegments: const [
                NavigationTitleSegment('main'),
                NavigationTitleSegment(
                  '+4',
                  tone: NavigationTitleSegmentTone.positive,
                ),
                NavigationTitleSegment(
                  '-2',
                  tone: NavigationTitleSegmentTone.negative,
                ),
              ],
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Session\nmain +4 -2'), findsOneWidget);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Open session details: Session'),
      ),
      matchesSemantics(
        label: 'Open session details: Session',
        value: 'main +4 -2',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
    final richText = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(RichText),
          ),
        )
        .firstWhere((widget) => widget.text.toPlainText() == 'main +4 -2');
    expect(richText.text.toPlainText(), 'main +4 -2');
    expect(
      _spanWithText(richText.text, '+4').style!.color,
      promptTheme().colorScheme.primary,
    );
    expect(
      _spanWithText(richText.text, '-2').style!.color,
      promptTheme().colorScheme.error,
    );
    semantics.dispose();
  });
}
