import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final expanded in [false, true]) {
    for (final canSubmit in [false, true]) {
      testWidgets(
        'draft uses send arrow and caller enabled state expanded=$expanded canSubmit=$canSubmit',
        (tester) async {
          final controller = TextEditingController();
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          var submissions = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DraftComposerPanel(
                  controller: controller,
                  focusNode: focus,
                  expanded: expanded,
                  onSubmit: canSubmit ? () => submissions++ : null,
                ),
              ),
            ),
          );
          final submit = find.widgetWithIcon(
            AppIconButton,
            Icons.arrow_upward_rounded,
          );
          expect(submit, findsOneWidget);
          expect(find.byIcon(Icons.add_rounded), findsNothing);
          expect(find.byTooltip('New session from draft'), findsOneWidget);
          expect(
            tester.widget<AppIconButton>(submit).onPressed != null,
            canSubmit,
          );
          // Empty drafts can intentionally open preparation; the caller decides.
          expect(controller.text, isEmpty);
          await tester.tap(submit);
          expect(submissions, canSubmit ? 1 : 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'configuration rows keep regular height and complete accessible values scale=$scale',
      (tester) async {
        const longValue =
            '/workspace/a-very-long-directory-name/another-folder/project';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      CreationConfigurationRow(
                        icon: Icons.computer,
                        label: 'Machine',
                        value: 'mini',
                        onTap: () {},
                      ),
                      CreationConfigurationRow(
                        icon: Icons.folder,
                        label: 'Directory',
                        value: longValue,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.widgetWithText(ListTile, longValue)).height,
          tester.getSize(find.widgetWithText(ListTile, 'mini')).height,
        );
        expect(
          tester.getSize(find.widgetWithText(ListTile, longValue)).height,
          greaterThanOrEqualTo(48),
        );
        final text = tester.widget<Text>(find.text(longValue));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        final semantics = tester.ensureSemantics();
        try {
          final node = tester.getSemantics(
            find.byType(CreationConfigurationRow).last,
          );
          expect(node.toStringDeep(), contains(longValue));
          expect(node.toStringDeep(), contains('Directory'));
        } finally {
          semantics.dispose();
        }
        expect(find.byTooltip(longValue), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final dark in [false, true]) {
    for (final height in [140.0, 500.0]) {
      testWidgets(
        'expanded composer scrolls without clipping actions height=$height dark=$dark',
        (tester) async {
          final controller = TextEditingController();
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          var submits = 0;
          var choices = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? promptDarkTheme() : promptTheme(),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 320,
                      height: height,
                      child: DraftComposerPanel(
                        controller: controller,
                        focusNode: focus,
                        expanded: true,
                        configuration: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CreationConfigurationRow(
                              icon: Icons.computer,
                              label: 'Machine',
                              value:
                                  'A complete long machine name without truncation',
                              onTap: () => choices++,
                            ),
                            const CreationConfigurationRow(
                              icon: Icons.folder,
                              label: 'Directory',
                              value: '/long/workspace/directory',
                            ),
                            const CreationConfigurationRow(
                              icon: Icons.account_tree,
                              label: 'Worktree',
                              value: 'Unavailable',
                            ),
                          ],
                        ),
                        onSubmit: () => submits++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final surface = tester.widget<Material>(
            find.byKey(const ValueKey('draft-configuration-surface')),
          );
          expect(
            surface.color,
            (dark ? promptDarkTheme() : promptTheme()).colorScheme.surface,
          );
          expect(surface.color!.a, 1);
          expect(
            find.byTooltip('New session from draft').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('New session from draft'));
          expect(submits, 1);
          final scrollable = find
              .descendant(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find
                .text('A complete long machine name without truncation')
                .hitTestable(),
            100,
            scrollable: scrollable,
          );
          final visibleRow = tester
              .getRect(
                find.widgetWithText(
                  ListTile,
                  'A complete long machine name without truncation',
                ),
              )
              .intersect(tester.getRect(find.byType(SingleChildScrollView)));
          expect(visibleRow.height, greaterThan(0));
          await tester.tapAt(visibleRow.center);
          expect(choices, 1);
          final unavailable = tester.widget<ListTile>(
            find.widgetWithText(ListTile, 'Unavailable'),
          );
          expect(unavailable.onTap, isNull);
          expect(unavailable.enabled, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
