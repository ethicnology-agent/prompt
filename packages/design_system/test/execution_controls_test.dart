import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selection summary does not become the composer label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(size: Size(1440, 900)),
              child: Column(
                children: [
                  const AppTextField(hint: 'Message'),
                  ExecutionControls(
                    summary: 'Ask · Balanced · High',
                    onOpen: () {},
                    compact: const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(TextField)).label,
        isNot(contains('Balanced')),
      );
      expect(
        find.bySemanticsLabel('Current execution settings'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
  for (final width in [800.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('execution controls adapt at $width scale=$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: SizedBox(
                  width: 680,
                  child: ExecutionControls(
                    summary:
                        'Ask · A very long model name that must remain accessible · High',
                    onOpen: () => opened++,
                    compact: const Text('Detailed choices'),
                  ),
                ),
              ),
            ),
          ),
        );
        final unified = width >= 1200 && scale == 1;
        expect(
          find.text('Detailed choices'),
          unified ? findsNothing : findsOneWidget,
        );
        if (unified) {
          await tester.tap(find.byTooltip('Execution settings'));
          expect(opened, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('unavailable entry retains compact recovery actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionControls(
            summary: 'Unavailable',
            onOpen: null,
            compact: Text('Retry preparation'),
          ),
        ),
      ),
    );
    expect(find.text('Retry preparation'), findsOneWidget);
    expect(find.byTooltip('Execution settings'), findsNothing);
  });
}
