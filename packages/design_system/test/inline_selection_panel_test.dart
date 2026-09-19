import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('action rows use their icon instead of a selection radio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineSelectionPanel<String>(
            title: 'Worktree',
            selected: 'main',
            onSelected: (_) {},
            onClose: () {},
            options: const [
              InlineSelectionOption(value: 'main', label: 'main'),
              InlineSelectionOption(
                value: 'create',
                label: 'Create new worktree',
                icon: Icons.add_rounded,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('native arrows and Enter choose, Escape closes', (tester) async {
    int? chosen;
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineSelectionPanel<int>(
            title: 'Effort',
            options: const [
              InlineSelectionOption(value: 1, label: 'Low'),
              InlineSelectionOption(value: 2, label: 'High'),
            ],
            selected: null,
            onSelected: (value) => chosen = value,
            onClose: () => closes++,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chosen, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chosen, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closes, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('short parent bounds scaled long labels dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? promptDarkTheme() : promptTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 280,
                height: 160,
                child: InlineSelectionPanel<int>(
                  title: 'Model',
                  options: List.generate(
                    20,
                    (index) => InlineSelectionOption(
                      value: index,
                      label:
                          'Very long model name that wraps onto several lines $index',
                      description: 'Legible extended model description',
                      groupLabel: 'Provider',
                    ),
                  ),
                  selected: null,
                  onSelected: (_) {},
                  onClose: () {},
                  listHeight: 300,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ListView)).height,
        lessThanOrEqualTo(104),
      );
      expect(
        tester.getSize(find.byTooltip('Close Model choices')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(ListTile).first).height,
        greaterThanOrEqualTo(48),
      );
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(
        scrollbar.controller,
        same(tester.widget<ListView>(find.byType(ListView)).controller),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollbar.controller!.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('short chooser shrinks inside its maximum with rounded surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: InlineSelectionPanel<int>(
              title: 'Effort',
              options: const [
                InlineSelectionOption(value: 1, label: 'Low'),
                InlineSelectionOption(value: 2, label: 'High'),
              ],
              selected: null,
              onSelected: (_) {},
              onClose: () {},
              listHeight: 300,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ListView)).height, lessThan(160));
    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(InlineSelectionPanel<int>),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      (surface.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(24),
    );
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
  });
  for (final radio in [false, true]) {
    testWidgets('selection indicator follows caller context radio=$radio', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineSelectionPanel<int>(
              title: 'Choice',
              radioIndicator: radio,
              options: const [
                InlineSelectionOption(value: 1, label: 'One'),
                InlineSelectionOption(value: 2, label: 'Two'),
              ],
              selected: 1,
              onSelected: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check), radio ? findsNothing : findsOneWidget);
      expect(
        find.byIcon(Icons.radio_button_checked),
        radio ? findsOneWidget : findsNothing,
      );
      expect(
        find.byIcon(Icons.radio_button_unchecked),
        radio ? findsOneWidget : findsNothing,
      );
      final selectedTile = tester.widget<ListTile>(find.byType(ListTile).first);
      expect(selectedTile.selectedTileColor, isNull);
    });
  }
  testWidgets(
    'immediate choices preserve duplicate-label identities and close does not select',
    (tester) async {
      ({String provider, String model})? chosen;
      var closes = 0;
      const first = (provider: 'one', model: 'model');
      const second = (provider: 'two', model: 'model');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineSelectionPanel(
              title: 'Model',
              options: const [
                InlineSelectionOption(
                  value: first,
                  label: 'Same model',
                  groupLabel: 'one',
                ),
                InlineSelectionOption(
                  value: second,
                  label: 'Same model',
                  groupLabel: 'two',
                  description: 'Exact description',
                ),
              ],
              selected: first,
              onSelected: (value) => chosen = value,
              onClose: () => closes++,
            ),
          ),
        ),
      );
      expect(find.text('Apply'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Default'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((tile) => tile.selected),
        [true, false],
      );
      await tester.tap(find.text('Same model').last);
      expect(chosen, second);
      await tester.tap(find.byTooltip('Close Model choices'));
      expect(closes, 1);
      expect(chosen, second);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'bounded lazy choices remain accessible at 320px font200 dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        int? chosen;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? promptDarkTheme() : promptTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: InlineSelectionPanel<int>(
                  title: 'Models',
                  listHeight: 180,
                  options: List.generate(
                    10000,
                    (index) => InlineSelectionOption(
                      value: index,
                      label: 'Long model label $index',
                      description: 'Description $index',
                    ),
                  ),
                  selected: 0,
                  onSelected: (value) => chosen = value,
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ListTile).evaluate().length, lessThan(20));
        expect(find.text('Long model label 9999'), findsNothing);
        expect(tester.getSize(find.byType(ListView)).height, 180);
        final semantics = tester.ensureSemantics();
        try {
          expect(
            tester.getSemantics(find.byType(ListTile).first).toStringDeep(),
            contains('Long model label 0'),
          );
        } finally {
          semantics.dispose();
        }
        await tester.tap(find.text('Long model label 0'));
        expect(chosen, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('disabled choices and empty state do not invent selections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineSelectionPanel<String>(
            title: 'Engine',
            options: const [
              InlineSelectionOption(value: 'id', label: 'Engine'),
            ],
            selected: 'id',
            onSelected: null,
            onClose: () {},
            listHeight: 100,
          ),
        ),
      ),
    );
    expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineSelectionPanel<String>(
            title: 'Engine',
            options: const [],
            selected: null,
            onSelected: null,
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('No available choices'), findsOneWidget);
  });
}
