import 'dart:ui' show Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? promptDarkTheme() : promptTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final variant in AppIconButtonVariant.values) {
    testWidgets('$variant preserves selected semantics and active loading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        await tester.pumpWidget(
          host(
            AppIconButton(
              icon: Icons.filter_list,
              selectedIcon: Icons.check,
              tooltip: 'Filters',
              variant: variant,
              isSelected: true,
              onPressed: () => presses++,
            ),
          ),
        );
        expect(find.byIcon(Icons.check), findsOneWidget);
        final button = tester.widget<IconButton>(find.byType(IconButton));
        expect(button.isSelected, isTrue);
        expect(
          tester
              .getSemantics(find.byType(IconButton))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        await tester.pumpWidget(
          host(
            AppIconButton(
              icon: Icons.filter_list,
              selectedIcon: Icons.check,
              tooltip: 'Filters',
              variant: variant,
              isSelected: true,
              loading: true,
              onPressed: () => presses++,
            ),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.check), findsNothing);
        expect(find.bySemanticsLabel('Filters'), findsOneWidget);
        await tester.tap(find.byType(AppIconButton));
        expect(presses, 1);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('loading is visual and does not disable button callback', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      host(
        AppButton(
          label: 'Reconnect',
          loading: true,
          onPressed: () => presses++,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Reconnect'));
    expect(presses, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('semantic tones resolve theme colors in dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Revert',
                onPressed: () {},
                variant: AppButtonVariant.tertiary,
                tone: AppButtonTone.userMessage,
                leftAligned: true,
              ),
              AppIconButton(
                icon: Icons.stop,
                tooltip: 'Stop',
                onPressed: () {},
                tone: AppIconButtonTone.recording,
                variant: AppIconButtonVariant.tonal,
              ),
            ],
          ),
          dark: dark,
        ),
      );
      final theme = Theme.of(tester.element(find.byType(AppButton)));
      final tokens = theme.extension<PromptTokens>()!;
      final textButton = tester.widget<TextButton>(find.byType(TextButton));
      expect(
        textButton.style!.foregroundColor!.resolve({}),
        tokens.userMessageForeground,
      );
      expect(textButton.style!.alignment, Alignment.centerLeft);
      final icon = tester.widget<IconButton>(find.byType(IconButton));
      expect(
        icon.style!.backgroundColor!.resolve({}),
        tokens.userMessageForeground,
      );
      expect(
        icon.style!.foregroundColor!.resolve({}),
        tokens.userMessageBackground,
      );
    });
  }

  for (final variant in AppTextFieldVariant.values) {
    testWidgets('$variant field keeps shared editing behavior', (tester) async {
      String? changed;
      await tester.pumpWidget(
        host(
          AppTextField(
            label: 'Input',
            variant: variant,
            dense: true,
            onChanged: (value) => changed = value,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Example');
      expect(changed, 'Example');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.isDense, isTrue);
      if (variant == AppTextFieldVariant.borderless) {
        expect(field.decoration!.filled, isFalse);
        expect(field.decoration!.border, InputBorder.none);
      }
      if (variant == AppTextFieldVariant.code) {
        expect(field.style!.fontFamily, promptMonoFamily);
      }
    });
  }

  testWidgets('dialog preserves route result and action behavior', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => AppButton(
            label: 'Open',
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (context) => AppDialog(
                  title: const Text('Confirm'),
                  content: const Text('Continue this action?'),
                  scrollable: true,
                  actions: [
                    AppButton(
                      label: 'Continue',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(AppDialog), findsNothing);
  });
}
