import 'dart:async';

import 'package:catalog/main.dart';
import 'package:catalog/specimens.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation title specimen toggles controlled details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: SpecimenPage(
          specimen: specimens.singleWhere(
            (item) => item.name == 'Navigation title',
          ),
        ),
      ),
    );
    const details = 'Synthetic session details are open';
    expect(find.text(details), findsNothing);
    await tester.tap(find.byType(NavigationTitleButton));
    await tester.pump();
    expect(find.text(details), findsOneWidget);
    await tester.tap(find.byType(NavigationTitleButton));
    await tester.pump();
    expect(find.text(details), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact choice interaction dark=$dark text=$scale', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          tester.view.physicalSize = const Size(320, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? promptDarkTheme() : promptTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SpecimenPage(
                specimen: specimens.singleWhere(
                  (item) => item.name == 'Compact choice button',
                ),
              ),
            ),
          );
          final choice = find.byType(CompactChoiceButton);
          final bounds = tester.getSize(choice);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          final label = tester.widget<Text>(
            find.descendant(of: choice, matching: find.byType(Text)),
          );
          expect(label.maxLines, 1);
          expect(label.overflow, TextOverflow.ellipsis);
          expect(
            find.bySemanticsLabel(
              'Model: Default synthetic model with a very long name',
            ),
            findsOneWidget,
          );
          await tester.tap(choice);
          await tester.pump();
          expect(
            find.bySemanticsLabel(
              'Model: Focused synthetic model with a very long name',
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<CompactChoiceButton>(choice).label,
            startsWith('Focused'),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 740), const Size(800, 360)]) {
      for (final specimen in specimens) {
        testWidgets('${specimen.name} dark=$dark size=$size large text', (
          tester,
        ) async {
          final opened = Completer<void>();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              navigatorObservers: [_ViewerObserver(opened)],
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
          if (specimen.name == 'Image viewer') {
            await tester.runAsync(() async {
              await tester.tap(find.text('Inspect synthetic image'));
              // PNG encoding is real asynchronous engine work; navigation
              // observers also need frames while that work completes.
              for (var frame = 0; frame < 200 && !opened.isCompleted; frame++) {
                await tester.pump();
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
            });
            expect(opened.isCompleted, isTrue);
            await tester.pumpAndSettle();
            final viewer = tester.widget<AttachmentImageViewer>(
              find.byType(AttachmentImageViewer),
            );
            await tester.runAsync(() async {
              final controller = viewer.controller;
              if (controller.state != AttachmentThumbnailState.loading) return;
              final ready = Completer<void>();
              void changed() {
                if (!ready.isCompleted) ready.complete();
              }

              controller.addListener(changed);
              await ready.future;
              controller.removeListener(changed);
            });
            await tester.pumpAndSettle();
            expect(viewer.controller.state, AttachmentThumbnailState.ready);
            expect(viewer.controller.debugImage!.width, 1024);
            await tester.tap(find.byTooltip('Zoom in'));
            await tester.pump();
            final transform = tester
                .widget<InteractiveViewer>(find.byType(InteractiveViewer))
                .transformationController!;
            expect(transform.value.getMaxScaleOnAxis(), 2);
            await tester.tap(find.byTooltip('Reset zoom'));
            expect(transform.value.getMaxScaleOnAxis(), 1);
            await tester.tap(find.byTooltip('Close image'));
            await tester.runAsync(() async {
              await Future<void>.delayed(Duration.zero);
            });
            await tester.pumpAndSettle();
            expect(find.byType(AttachmentImageViewer), findsNothing);
            expect(viewer.controller.debugImage, isNull);
          }
          if (specimen.name == 'Inline selection panel') {
            await tester.ensureVisible(find.text('Focused model'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Focused model'));
            await tester.pump();
            expect(
              tester
                  .widget<InlineSelectionPanel<String>>(
                    find.byType(InlineSelectionPanel<String>),
                  )
                  .selected,
              'focused',
            );
            expect(find.byType(BottomSheet), findsNothing);
            await tester.ensureVisible(find.byTooltip('Close Model choices'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Close Model choices'));
            await tester.pump();
            expect(find.text('Open inline choices'), findsOneWidget);
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

class _ViewerObserver extends NavigatorObserver {
  _ViewerObserver(this.opened);
  final Completer<void> opened;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && !opened.isCompleted) opened.complete();
  }
}
