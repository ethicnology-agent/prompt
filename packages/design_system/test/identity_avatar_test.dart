import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('avatarHashCode matches the reference implementation', () {
    // Produced by running Happy's own `hashCode` from
    // `sources/components/AvatarBrutalist.tsx` under Node. A Dart port that
    // truncates in the wrong place passes none of these.
    const reference = <String, (int, int)>{
      'session-1': (607795898, 3),
      'local-session': (1599515188, 1),
      'fixture-session': (932362542, 3),
      'cmuacr2c2m6e5h0g': (1644047222, 1),
      'Build a private coding companion': (1580408516, 3),
      'a': (97, 0),
      '': (0, 3),
      'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz': (291400512, 3),
    };

    for (final entry in reference.entries) {
      test('"${entry.key}"', () {
        expect(avatarHashCode(entry.key), entry.value.$1);
        expect(
          avatarHashCode('${entry.key}color') % avatarColorPairs.length,
          entry.value.$2,
        );
      });
    }
  });

  testWidgets('the disc takes the pair colour and the mark is inset to 80%', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: IdentityAvatar(identifier: 'session-1', size: 60),
          ),
        ),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(IdentityAvatar),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = box.decoration as BoxDecoration;
    // 'session-1color' lands on pair 3: pink on teal green.
    expect(decoration.color, avatarColorPairs[3].background);
    expect(decoration.shape, BoxShape.circle);
    expect(tester.getSize(find.byType(CustomPaint).last), const Size(48, 48));
  });

  testWidgets('a monochrome avatar drops to the quiet pair', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: IdentityAvatar(
              identifier: 'session-1',
              size: 60,
              monochrome: true,
            ),
          ),
        ),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(IdentityAvatar),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, avatarMonochromeBackground);
  });
}
