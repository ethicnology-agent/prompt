import 'package:catalog/main.dart';
import 'package:catalog/specimens.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 740), const Size(800, 360)]) {
      for (final specimen in specimens) {
        testWidgets('${specimen.name} dark=$dark size=$size large text', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? promptDarkTheme() : promptTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: SpecimenPage(specimen: specimen),
            ),
          );
          await tester.pump();
          if (specimen.name == 'Dialog') {
            await tester.tap(find.text('Open dialog'));
            await tester.pumpAndSettle();
            expect(find.text('Confirm action'), findsOneWidget);
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            expect(find.text('Confirm action'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('catalog starts without application services', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ComponentCatalog());
    await tester.pumpAndSettle();
    expect(find.text('UI kit'), findsOneWidget);
    await tester.tap(find.text('Button - primary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(AppButton, 'Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
