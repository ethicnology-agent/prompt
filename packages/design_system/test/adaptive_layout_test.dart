import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';

void main() {
  test('size classes use width thresholds', () {
    expect(promptSizeClassForWidth(599), PromptSizeClass.phone);
    expect(promptSizeClassForWidth(600), PromptSizeClass.tablet);
    expect(promptSizeClassForWidth(899), PromptSizeClass.tablet);
    expect(promptSizeClassForWidth(900), PromptSizeClass.desktop);
  });

  testWidgets('the same view responds to resizing', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(599, 600));
    await tester.pumpWidget(const _AdaptiveHarness());
    expect(find.text('phone'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(600, 600));
    await tester.pump();
    expect(find.text('tablet'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(900, 600));
    await tester.pump();
    expect(find.text('desktop'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(599, 600));
    await tester.pump();
    expect(find.text('phone'), findsOneWidget);
  });

  testWidgets('layout selection is independent of target platform', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    try {
      const cases = <(double, PromptSizeClass)>[
        (599, PromptSizeClass.phone),
        (600, PromptSizeClass.tablet),
        (899, PromptSizeClass.tablet),
        (900, PromptSizeClass.desktop),
      ];
      for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        for (final (width, expected) in cases) {
          await tester.binding.setSurfaceSize(Size(width, 600));
          await tester.pumpWidget(
            _AdaptiveHarness(key: ValueKey((platform, width))),
          );
          expect(find.text(expected.name), findsOneWidget);
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });
}

class _AdaptiveHarness extends StatelessWidget {
  const _AdaptiveHarness({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        child: Center(
          child: PromptAdaptiveBuilder(
            builder: (context, sizeClass) => Text(sizeClass.name),
          ),
        ),
      ),
    );
  }
}
