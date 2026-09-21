import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('settings group at 320px dark=$dark scale=$scale', (
        tester,
      ) async {
        final theme = dark ? promptDarkTheme() : promptTheme();
        var opened = 0;
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                backgroundColor: SettingsGroup.pageColor(theme),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SettingsGroup(
                    title: 'CONNECTION',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Your server'),
                        subtitle: const Text('Private local infrastructure'),
                        onTap: () => opened++,
                      ),
                      const ExpansionTile(
                        leading: Icon(Icons.contrast_rounded),
                        title: Text('Appearance'),
                        children: [ListTile(title: Text('System'))],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final card = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SettingsGroup),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(card.color, theme.extension<PromptTokens>()!.panel);
        expect(card.color, isNot(SettingsGroup.pageColor(theme)));
        expect(card.clipBehavior, Clip.antiAlias);
        final background = card.color!.computeLuminance();
        final foreground = theme.colorScheme.onSurface.computeLuminance();
        final ratio = foreground > background
            ? (foreground + 0.05) / (background + 0.05)
            : (background + 0.05) / (foreground + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
        // The group sets only the neutral colour the trailing chevron takes;
        // a row's leading glyph is coloured by what the row does, as in the
        // reference, and says so at its own call site.
        for (final icon in [Icons.dns_outlined, Icons.contrast_rounded]) {
          expect(
            IconTheme.of(tester.element(find.byIcon(icon))).color,
            theme.colorScheme.onSurfaceVariant,
          );
        }
        final heading = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.text('CONNECTION'),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(heading.properties.header, isTrue);
        expect(find.byType(Divider), findsOneWidget);
        await tester.tap(find.text('Your server'));
        expect(opened, 1);
        await tester.ensureVisible(find.text('Appearance'));
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        expect(find.text('System'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
