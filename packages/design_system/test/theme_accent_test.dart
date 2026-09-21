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

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? promptDarkTheme() : promptTheme();
    final expected = ColorScheme.fromSeed(
      seedColor: const Color(0xff56d6b2),
      brightness: dark ? Brightness.dark : Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    test('historical teal accent preserves neutral surfaces in dark=$dark', () {
      final scheme = theme.colorScheme;
      expect(scheme.primary, expected.primary);
      expect(scheme.onPrimary, expected.onPrimary);
      expect(scheme.primaryContainer, expected.primaryContainer);
      expect(scheme.onPrimaryContainer, expected.onPrimaryContainer);
      expect(scheme.secondaryContainer, expected.secondaryContainer);
      expect(scheme.onSecondaryContainer, expected.onSecondaryContainer);
      expect(
        contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.primaryContainer, scheme.onPrimaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(scheme.surface, dark ? Colors.black : Colors.white);
      expect(
        scheme.surfaceContainerLow,
        dark ? const Color(0xff111111) : Colors.white,
      );
      final tokens = theme.extension<PromptTokens>()!;
      expect(tokens.panel, dark ? const Color(0xff161618) : Colors.white);
      expect(
        tokens.userMessageBackground,
        dark ? const Color(0xff242426) : const Color(0xfff0eee6),
      );
      expect(
        theme.inputDecorationTheme.focusedBorder!.borderSide.color,
        scheme.primary,
      );
      expect(
        theme.floatingActionButtonTheme.backgroundColor,
        scheme.primaryContainer,
      );
      expect(theme.chipTheme.selectedColor, scheme.primaryContainer);
    });

    testWidgets('shared controls take the reference treatment in dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                AppButton(label: 'Primary', onPressed: () {}),
                AppButton(
                  label: 'Secondary',
                  variant: AppButtonVariant.secondary,
                  onPressed: () {},
                ),
                AppButton(
                  label: 'Tertiary',
                  variant: AppButtonVariant.tertiary,
                  onPressed: () {},
                ),
                AppIconButton(
                  icon: Icons.add,
                  tooltip: 'Filled',
                  variant: AppIconButtonVariant.filled,
                  onPressed: () {},
                ),
                AppIconButton(
                  icon: Icons.filter_list,
                  tooltip: 'Tonal',
                  variant: AppIconButtonVariant.tonal,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      final tokens = theme.extension<PromptTokens>()!;
      final primaryMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FilledButton),
              matching: find.byType(Material),
            )
            .first,
      );
      // The primary call to action is the reference's black pill, not the
      // brand accent. The accent survives where it still carries meaning:
      // a focused field, a selected chip, the floating action.
      expect(primaryMaterial.color, tokens.buttonPrimaryBackground);
      expect(primaryMaterial.shape, isA<StadiumBorder>());
      expect(
        tester
            .widget<RichText>(
              find
                  .descendant(
                    of: find.byType(OutlinedButton),
                    matching: find.byType(RichText),
                  )
                  .first,
            )
            .text
            .style!
            .color,
        theme.colorScheme.onSurface,
      );
      expect(
        tester
            .widget<RichText>(
              find
                  .descendant(
                    of: find.byType(TextButton),
                    matching: find.byType(RichText),
                  )
                  .first,
            )
            .text
            .style!
            .color,
        expected.primary,
      );
      final icons = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(AppIconButton),
              matching: find.byType(Material),
            ),
          )
          .toList();
      // The filled round action is a neutral composer control, not an accent
      // surface: Happy fills it with `surfaceHighest` and a secondary glyph.
      // Only the tonal variant still carries the accent.
      expect(
        icons.map((material) => material.color),
        containsAll([tokens.surfaceHighest, expected.secondaryContainer]),
      );
      expect(
        icons.map((material) => material.color),
        isNot(contains(expected.primary)),
      );
    });
  }
}
