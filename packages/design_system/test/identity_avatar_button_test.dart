import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('avatar action has a labeled target and disabled state', (
    tester,
  ) async {
    var presses = 0;
    Future<void> pump(VoidCallback? callback) => tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: IdentityAvatarButton(
            identifier: 'fixture',
            tooltip: 'Session details',
            onPressed: callback,
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await pump(() => presses++);
    final button = find.byType(IconButton);
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Session details'), findsOneWidget);
    await tester.tap(find.byTooltip('Session details'));
    expect(presses, 1);
    await pump(null);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    await tester.tap(find.byTooltip('Session details'));
    expect(presses, 1);
    handle.dispose();
  });
}
