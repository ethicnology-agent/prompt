import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('menu uses shared rows and returns only enabled actions', (
    tester,
  ) async {
    String? selected;
    var workspaceEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: AppMenuButton<String>(
            tooltip: 'More actions',
            optionsBuilder: (_) => [
              const AppMenuOption(
                value: 'filter',
                label: 'Filter sessions',
                selected: true,
              ),
              AppMenuOption(
                value: 'workspace',
                label: 'Browse workspace',
                icon: Icons.folder_open_outlined,
                enabled: workspaceEnabled,
              ),
              const AppMenuOption(
                value: 'disconnect',
                label: 'Disconnect',
                icon: Icons.power_settings_new_rounded,
                dividerBefore: true,
              ),
            ],
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    for (final item in tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    )) {
      expect(item.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.text('Browse workspace'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(selected, 'disconnect');

    workspaceEnabled = true;
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse workspace'));
    await tester.pumpAndSettle();
    expect(selected, 'workspace');
  });

  testWidgets('menu stays bounded with large text on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AppMenuButton<String>(
                tooltip: 'More actions',
                optionsBuilder: (_) => const [
                  AppMenuOption(
                    value: 'long',
                    label: 'A long action that remains readable and reachable',
                    icon: Icons.folder_open_outlined,
                  ),
                ],
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    final menu = tester.getRect(find.byType(PopupMenuItem<String>));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(320));
    expect(menu.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
