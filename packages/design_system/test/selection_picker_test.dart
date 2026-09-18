import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default option remains available and applies null explicitly', (
    tester,
  ) async {
    String? applied = 'unchanged';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionPicker<String>(
            title: 'Engine',
            options: const [
              SelectionOption(value: 'engine', label: 'Available engine'),
            ],
            selected: 'engine',
            onApply: (value) => applied = value,
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.text('Default'));
    expect(applied, 'unchanged');
    await tester.tap(find.text('Apply'));
    expect(applied, isNull);
  });

  testWidgets(
    'generic default can be hidden without changing explicit option identities',
    (tester) async {
      String? applied = 'unchanged';
      var cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionPicker<String>(
              title: 'Model',
              includeDefault: false,
              options: const [
                SelectionOption(value: '', label: 'CLI default'),
                SelectionOption(value: 'provider/model', label: 'Actual model'),
              ],
              selected: '',
              onApply: (value) => applied = value,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );
      expect(find.text('Default'), findsNothing);
      expect(find.text('CLI default'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      expect(applied, '');
      await tester.tap(find.text('Actual model'));
      expect(applied, '');
      await tester.tap(find.text('Cancel'));
      expect(cancels, 1);
      expect(applied, '');
      await tester.tap(find.text('Apply'));
      expect(applied, 'provider/model');
    },
  );

  testWidgets(
    'hidden default does not invent selection when initial value is null',
    (tester) async {
      String? applied = 'unchanged';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionPicker<String>(
              title: 'Engine',
              includeDefault: false,
              options: const [
                SelectionOption(value: 'engine', label: 'Available engine'),
              ],
              selected: null,
              onApply: (value) => applied = value,
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(find.text('Default'), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Available engine'))
            .selected,
        isFalse,
      );
      await tester.tap(find.text('Apply'));
      expect(applied, isNull);
    },
  );
}
