import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [240.0, 320.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('actions stay reachable at width=$width scale=$scale', (
        tester,
      ) async {
        var sends = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: promptTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: ComposerActionBar(
                      leading: [
                        AppIconButton(
                          icon: Icons.add,
                          tooltip: 'Attach',
                          onPressed: () {},
                        ),
                        AppIconButton(
                          icon: Icons.mic,
                          tooltip: 'Voice',
                          onPressed: () {},
                        ),
                      ],
                      controls: AppButton(
                        label: 'Available agent and model',
                        variant: AppButtonVariant.tertiary,
                        onPressed: () {},
                      ),
                      trailing: AppIconButton(
                        icon: Icons.arrow_upward,
                        tooltip: 'Send',
                        onPressed: () => sends++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final attach = tester.getRect(find.byTooltip('Attach'));
        final send = tester.getRect(find.byTooltip('Send'));
        expect(attach.left, 0);
        expect(send.right, width);
        expect(attach.right, lessThan(send.left));
        expect(send.size, const Size(48, 48));
        await tester.tap(find.byTooltip('Send'));
        expect(sends, 1);
      });
    }
  }

  testWidgets('send stays at trailing edge with no supported extras', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ComposerActionBar(
              trailing: AppIconButton(
                icon: Icons.arrow_upward,
                tooltip: 'Send',
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getRect(find.byTooltip('Send')).right, 320);
    expect(find.byType(AppIconButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
