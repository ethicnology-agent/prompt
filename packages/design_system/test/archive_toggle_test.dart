import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  theme: promptTheme(),
  home: Scaffold(body: SizedBox(width: 360, child: child)),
);

void main() {
  testWidgets('wording follows whether the archive is collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ArchiveToggle(hidden: true, onPressed: () {})),
    );
    expect(find.text('Show archived'), findsOneWidget);

    await tester.pumpWidget(
      host(ArchiveToggle(hidden: false, onPressed: () {})),
    );
    expect(find.text('Hide archived'), findsOneWidget);
  });

  testWidgets('the label sits centred between two rules', (tester) async {
    await tester.pumpWidget(
      host(ArchiveToggle(hidden: true, onPressed: () {})),
    );
    expect(find.byType(Divider), findsNWidgets(2));
    final label = tester.getRect(find.text('Show archived'));
    expect(label.center.dx, closeTo(180, 0.5));
    // 24 inset, 20 above and 12 below the label's line box.
    final row = tester.getRect(find.byType(ArchiveToggle));
    expect(tester.getRect(find.byType(Row)).left - row.left, 24);
  });

  testWidgets('it reports itself as one button to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      await tester.pumpWidget(
        host(ArchiveToggle(hidden: true, onPressed: () => taps++)),
      );
      final node = tester.getSemantics(find.byType(ArchiveToggle));
      expect(node.label, 'Show archived');
      await tester.tap(find.byType(ArchiveToggle));
      expect(taps, 1);
    } finally {
      semantics.dispose();
    }
  });
}
