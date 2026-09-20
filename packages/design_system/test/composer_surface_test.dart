import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses the shared elevated composer treatment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: const Scaffold(
          body: ComposerSurface(
            contentPadding: EdgeInsets.all(12),
            child: SizedBox(key: ValueKey('content'), width: 40, height: 20),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ComposerSurface),
        matching: find.byType(Material),
      ),
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(material.elevation, 4);
    // The reference's shell radius, shared by the home draft and the chat
    // composer so neither shifts under the thumb.
    expect(
      shape.borderRadius,
      BorderRadius.circular(MobileComposerMetrics.shellRadius),
    );
    expect(shape.side.color, promptTheme().colorScheme.outlineVariant);
    expect(tester.getSize(find.byType(ComposerSurface)), const Size(64, 44));
  });
}
