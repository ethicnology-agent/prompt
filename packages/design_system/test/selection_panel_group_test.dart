import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('open group hides background actions from assistive traversal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AppButton(label: 'Background action', onPressed: () {}),
                SelectionPanelGroup(
                  maxHeight: 320,
                  onClose: () {},
                  primaryBuilder: (h) => InlineSelectionPanel<String>(
                    title: 'Model',
                    embedded: true,
                    listHeight: h - 40,
                    selected: null,
                    options: const [
                      InlineSelectionOption(value: 'one', label: 'Model one'),
                    ],
                    onSelected: (_) {},
                    onClose: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final tree = tester.getSemantics(find.byType(Scaffold)).toStringDeep();
      expect(tree, isNot(contains('Background action')));
      expect(tree, contains('Close execution settings'));
    } finally {
      semantics.dispose();
    }
  });
  for (final scale in [1.0, 2.0]) {
    for (final height in [320.0, 520.0]) {
      testWidgets('grouped sections fit and remain selectable $scale $height', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(800, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var selected = -1;
        var closed = 0;
        Widget section(String title, double h) => InlineSelectionPanel<int>(
          title: title,
          embedded: true,
          listHeight: (h - 40).clamp(0, 500),
          selected: selected,
          options: List.generate(
            40,
            (i) => InlineSelectionOption(
              value: i,
              label: '$title $i',
              description: 'Description of this option',
            ),
          ),
          onSelected: (value) => selected = value,
          onClose: () => closed++,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SelectionPanelGroup(
                    maxHeight: height,
                    onClose: () => closed++,
                    topBuilder: (h) => section('Permissions', h),
                    primaryBuilder: (h) => section('Model', h),
                    secondaryBuilder: (h) => section('Effort', h),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(SelectionPanelGroup)).height,
          lessThanOrEqualTo(height),
        );
        expect(
          tester.getRect(find.text('Model 0')).left,
          lessThan(tester.getRect(find.text('Effort 0')).left),
        );
        expect(find.byType(AppIconButton), findsOneWidget);
        await tester.tap(find.text('Model 0'));
        expect(selected, 0);
        expect(closed, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final visited = <FocusNode>{};
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final focusedContext = FocusManager.instance.primaryFocus!.context;
          visited.add(FocusManager.instance.primaryFocus!);
          expect(
            find.ancestor(
              of: find.byElementPredicate(
                (element) => element == focusedContext,
              ),
              matching: find.byType(SelectionPanelGroup),
            ),
            findsOneWidget,
          );
        }
        expect(visited.length, greaterThan(2));
        await tester.tap(find.byTooltip('Close execution settings'));
        expect(closed, 1);
      });
    }
  }
}
