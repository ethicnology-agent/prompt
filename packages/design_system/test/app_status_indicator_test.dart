import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a text-backed semantic success status', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: const Scaffold(
            body: AppStatusIndicator(
              label: 'Online',
              semanticLabel: 'Connection status: Online',
              liveRegion: true,
            ),
          ),
        ),
      );

      expect(find.text('Online'), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(AppStatusIndicator))
          .getSemanticsData();
      expect(data.label, 'Connection status: Online');
      expect(data.flagsCollection.isLiveRegion, isTrue);

      final text = tester.widget<Text>(find.text('Online'));
      expect(
        text.style?.color,
        promptTheme().extension<PromptTokens>()!.success,
      );
    } finally {
      semantics.dispose();
    }
  });
}
