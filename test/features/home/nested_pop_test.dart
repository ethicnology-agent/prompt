import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape `HomeShell` uses: a nested navigator behind a
/// `NavigatorPopHandler`, with a route inside that wants to handle back itself.
Widget host({
  required GlobalKey<NavigatorState> navigator,
  required ValueNotifier<bool> guarded,
  required VoidCallback onGuardedPop,
}) => MaterialApp(
  home: Scaffold(
    body: NavigatorPopHandler<Object?>(
      onPopWithResult: (result) => navigator.currentState!.maybePop(result),
      child: Navigator(
        key: navigator,
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => const Text('root pane')),
      ),
    ),
  ),
);

void main() {
  testWidgets('back reaches a guard inside the nested navigator', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final guarded = ValueNotifier<bool>(true);
    addTearDown(guarded.dispose);
    var guardFired = 0;

    await tester.pumpWidget(
      host(
        navigator: navigator,
        guarded: guarded,
        onGuardedPop: () => guardFired++,
      ),
    );

    // A screen pushed into the pane that wants back for itself — the composer
    // with an open choice panel is exactly this.
    unawaitedPush(navigator, guarded, () => guardFired++);
    await tester.pumpAndSettle();
    expect(find.text('guarded screen'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      guardFired,
      1,
      reason: 'the screen should have been told to handle back',
    );
    expect(
      find.text('guarded screen'),
      findsOneWidget,
      reason: 'back should not have popped a screen that handles it itself',
    );

    // Once the screen stops guarding, back pops it as usual.
    guarded.value = false;
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('guarded screen'), findsNothing);
  });
}

void unawaitedPush(
  GlobalKey<NavigatorState> navigator,
  ValueNotifier<bool> guarded,
  VoidCallback onGuardedPop,
) {
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: guarded,
        builder: (context, isGuarded, _) => PopScope(
          canPop: !isGuarded,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onGuardedPop();
          },
          child: const Scaffold(body: Text('guarded screen')),
        ),
      ),
    ),
  );
}
