import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  InlineSelectionOption(
    value: 'a',
    label: 'First',
    description: 'First description',
  ),
  InlineSelectionOption(
    value: 'b',
    label: 'Second',
    description: 'Second description',
  ),
];

class _Configuration {
  const _Configuration({
    this.options = _options,
    this.enabled = true,
    this.scope = 'one',
    this.visible = true,
    this.selected = 'a',
  });
  final List<InlineSelectionOption<String>> options;
  final bool enabled;
  final String scope;
  final bool visible;
  final String selected;
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    ValueNotifier<_Configuration> state,
    ValueChanged<String> onSelected, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<_Configuration>(
            valueListenable: state,
            builder: (_, configuration, _) => configuration.visible
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: ChoiceField<String>(
                      label: 'Model',
                      selected: configuration.selected,
                      options: configuration.options,
                      scopeKey: configuration.scope,
                      onSelected: configuration.enabled ? onSelected : null,
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      ),
    );
  }

  testWidgets('field selection is controlled and close/back cancel', (
    tester,
  ) async {
    final state = ValueNotifier(const _Configuration());
    addTearDown(state.dispose);
    final selected = <String>[];
    await mount(tester, state, selected.add);
    expect(find.text('Model: First'), findsOneWidget);
    await tester.tap(find.text('Model: First'));
    await tester.pumpAndSettle();
    expect(find.text('First description'), findsOneWidget);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => tile.selected),
      [true, false],
    );
    await tester.tap(find.byTooltip('Close Model choices'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    await tester.tap(find.text('Model: First'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    await tester.tap(find.text('Model: First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(selected, ['b']);
    expect(find.text('Model: First'), findsOneWidget);
    state.value = const _Configuration(selected: 'b');
    await tester.pump();
    expect(find.text('Model: Second'), findsOneWidget);
  });

  testWidgets('pending selection validates fresh options and enabled state', (
    tester,
  ) async {
    final state = ValueNotifier(const _Configuration());
    addTearDown(state.dispose);
    final selected = <String>[];
    await mount(tester, state, selected.add);
    await tester.tap(find.text('Model: First'));
    await tester.pumpAndSettle();
    final stale = tester
        .widget<InlineSelectionPanel<String>>(
          find.byType(InlineSelectionPanel<String>),
        )
        .onSelected!;
    state.value = const _Configuration(
      options: [InlineSelectionOption(value: 'a', label: 'Updated')],
    );
    await tester.pumpAndSettle();
    stale('b');
    expect(selected, isEmpty);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
    state.value = const _Configuration(enabled: false);
    await tester.pumpAndSettle();
    stale('a');
    expect(selected, isEmpty);
    expect(
      tester
          .widget<InlineSelectionPanel<String>>(
            find.byType(InlineSelectionPanel<String>),
          )
          .onSelected,
      isNull,
    );
    await tester.tap(find.byTooltip('Close Model choices'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  for (final dispose in [false, true]) {
    testWidgets('owner change removes only its dialog dispose=$dispose', (
      tester,
    ) async {
      final state = ValueNotifier(const _Configuration());
      addTearDown(state.dispose);
      final selected = <String>[];
      await mount(tester, state, selected.add);
      await tester.tap(find.text('Model: First'));
      await tester.pumpAndSettle();
      final panel = find.byType(InlineSelectionPanel<String>);
      final route = ModalRoute.of(tester.element(panel))!;
      final stale = tester
          .widget<InlineSelectionPanel<String>>(panel)
          .onSelected!;
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        ),
      );
      await tester.pumpAndSettle();
      state.value = _Configuration(scope: 'two', visible: !dispose);
      await tester.pumpAndSettle();
      stale('b');
      expect(selected, isEmpty);
      expect(route.navigator, isNull);
      expect(find.text('Other route'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(InlineSelectionPanel<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large text field and popup remain bounded and accessible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = ValueNotifier(const _Configuration());
    addTearDown(state.dispose);
    await mount(tester, state, (_) {}, scale: 2);
    final semantics = tester.ensureSemantics();
    expect(tester.getSize(find.byType(ChoiceField<String>)).width, 288);
    expect(find.bySemanticsLabel('Model: First'), findsOneWidget);
    await tester.tap(find.text('Model: First'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(InlineSelectionPanel<String>));
    expect(rect.width, lessThanOrEqualTo(288));
    expect(rect.height, lessThanOrEqualTo(368));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
