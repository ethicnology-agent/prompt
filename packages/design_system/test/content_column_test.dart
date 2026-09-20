import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets('content fills height and caps width at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const content = ValueKey('content');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContentColumn(
              child: ColoredBox(
                key: content,
                color: Colors.teal,
                child: Column(children: [Expanded(child: SizedBox())]),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(content));
      expect(rect.width, width < 800 ? width : 800);
      expect(rect.height, 900);
      expect(rect.center.dx, width / 2);
      expect(tester.takeException(), isNull);
    });
  }
}
