import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('segments stay reachable and report one selected value', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: StatefulBuilder(
              builder: (context, setState) => AppSegmentedControl<int>(
                segments: const [
                  AppSegment(value: 0, label: 'Overview'),
                  AppSegment(value: 1, label: 'Findings'),
                  AppSegment(value: 2, label: 'Disagreements'),
                ],
                selected: selected,
                onSelected: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.getSize(find.byType(SegmentedButton<int>)).height, 48);
    await tester.ensureVisible(find.text('Disagreements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disagreements'));
    await tester.pump();
    expect(selected, 2);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .selected,
      {2},
    );
  });

  testWidgets('disabled control remains non-interactive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: const Scaffold(
          body: AppSegmentedControl<int>(
            segments: [
              AppSegment(value: 0, label: 'Overview'),
              AppSegment(value: 1, label: 'Findings'),
            ],
            selected: 0,
            onSelected: null,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .onSelectionChanged,
      isNull,
    );
  });
}
