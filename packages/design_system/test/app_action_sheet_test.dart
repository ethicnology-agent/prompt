import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports enabled actions and keeps disabled actions inert', (
    tester,
  ) async {
    String? selected;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: AppActionSheet<String>(
            title: 'Session actions',
            options: const [
              AppActionSheetOption(
                value: 'rename',
                label: 'Rename',
                icon: Icons.edit_outlined,
              ),
              AppActionSheetOption(
                value: 'fork',
                label: 'Forking session…',
                icon: Icons.fork_right_rounded,
                enabled: false,
              ),
              AppActionSheetOption(
                value: 'delete',
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                dividerBefore: true,
              ),
            ],
            onSelected: (value) => selected = value,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Forking session…'));
    expect(selected, isNull);
    await tester.tap(find.text('Delete'));
    expect(selected, 'delete');
    await tester.tap(find.byTooltip('Close Session actions'));
    expect(closed, isTrue);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('remains bounded and scrollable on a compact scaled surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: promptDarkTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 240,
                child: AppActionSheet<int>(
                  title: 'Actions',
                  options: [
                    for (var index = 0; index < 8; index++)
                      AppActionSheetOption(
                        value: index,
                        label: 'Action $index with a readable label',
                        icon: Icons.bolt_outlined,
                      ),
                  ],
                  onSelected: (_) {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Action 7 with a readable label'),
      80,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.text('Action 7 with a readable label').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
