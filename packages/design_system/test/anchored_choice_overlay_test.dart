import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _anchorKey = ValueKey('anchor');
const _popupKey = ValueKey('popup');

void main() {
  Future<void> mount(
    WidgetTester tester,
    ValueNotifier<bool> open, {
    int count = 2,
    VoidCallback? onDismiss,
    VoidCallback? onBackground,
    FocusNode? focusNode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: onBackground,
                    child: const Text('Background action'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<bool>(
                  valueListenable: open,
                  builder: (context, visible, child) => AnchoredChoiceOverlay(
                    open: visible,
                    onDismiss: () {
                      onDismiss?.call();
                      open.value = false;
                    },
                    popupBuilder: (context, maxHeight) => Material(
                      key: _popupKey,
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: count,
                        itemExtent: 40,
                        itemBuilder: (context, index) => Text('Choice $index'),
                      ),
                    ),
                    child: SizedBox(
                      key: _anchorKey,
                      height: 120,
                      child: Column(
                        children: [
                          TextField(focusNode: focusNode),
                          TextButton(
                            onPressed: () => open.value = !open.value,
                            child: const Text('Choices'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  for (final count in [2, 1000]) {
    testWidgets('popup count=$count preserves anchor and stays bounded', (
      tester,
    ) async {
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      await mount(tester, open, count: count);
      final before = tester.getRect(find.byKey(_anchorKey));
      open.value = true;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_anchorKey)), before);
      final popup = tester.getRect(find.byKey(_popupKey));
      expect(popup.width, before.width);
      expect(popup.bottom, before.top - 8);
      expect(popup.height, count == 2 ? 80 : 400);
      expect(popup.left, greaterThanOrEqualTo(16));
      expect(popup.top, greaterThanOrEqualTo(16));
      expect(find.text('Choice 999'), findsNothing);
      await tester.tap(find.text('Choices'));
      await tester.pumpAndSettle();
      expect(open.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keyboard and short viewport recompute popup geometry', (
    tester,
  ) async {
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await mount(tester, open, count: 1000);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final composer = tester.getRect(find.byKey(_anchorKey));
    final popup = tester.getRect(find.byKey(_popupKey));
    expect(popup.bottom, composer.top - 8);
    expect(popup.top, greaterThanOrEqualTo(16));
    expect(popup.bottom, lessThan(500));
    open.value = false;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_anchorKey)), composer);
    open.value = true;
    tester.view.physicalSize = const Size(400, 480);
    await tester.pumpAndSettle();
    final tinyPopup = tester.getRect(find.byKey(_popupKey));
    expect(tinyPopup.top, greaterThanOrEqualTo(16));
    expect(tinyPopup.bottom, lessThanOrEqualTo(180));
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(_popupKey)).bottom,
      tester.getRect(find.byKey(_anchorKey)).top - 8,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('caller can tighten the popup bounds around its anchor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AnchoredChoiceOverlay(
              open: true,
              onDismiss: () {},
              maxHeight: 280,
              horizontalInset: 24,
              popupBuilder: (_, maxHeight) =>
                  const Material(key: _popupKey, child: SizedBox(height: 1000)),
              child: const SizedBox(
                key: _anchorKey,
                width: double.infinity,
                height: 120,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final popup = tester.getRect(find.byKey(_popupKey));
    expect(popup.height, 280);
    expect(popup.left, 24);
    expect(popup.right, 376);
  });

  testWidgets('outside tap consumes background action and preserves focus', (
    tester,
  ) async {
    final open = ValueNotifier(false);
    final focus = FocusNode();
    addTearDown(open.dispose);
    addTearDown(focus.dispose);
    var actions = 0;
    var dismissals = 0;
    await mount(
      tester,
      open,
      focusNode: focus,
      onBackground: () => actions++,
      onDismiss: () => dismissals++,
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('Choices'));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('Background action'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(actions, 0);
    expect(dismissals, 1);
    expect(open.value, isFalse);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets(
    'Escape and back dismiss only popup and dispose removes handlers',
    (tester) async {
      final open = ValueNotifier(true);
      addTearDown(open.dispose);
      var dismissals = 0;
      await mount(tester, open, onDismiss: () => dismissals++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(open.value, isFalse);
      expect(find.byKey(_anchorKey), findsOneWidget);
      open.value = true;
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(open.value, isFalse);
      expect(find.byKey(_anchorKey), findsOneWidget);
      expect(dismissals, 2);
      open.value = true;
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dismissals, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
