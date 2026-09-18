import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';

void main() {
  test(
    'immutable platform bytes become an owned mutable buffer that can be cleared',
    () {
      final platform = Uint8List.fromList([4, 5, 6]).asUnmodifiableView();
      final attachment = PromptAttachment(name: 'private.txt', bytes: platform);
      final owned = attachment.bytes;
      expect(identical(owned, platform), isFalse);
      attachment.release();
      expect(owned, everyElement(0));
      expect(platform, [4, 5, 6]);
      expect(attachment.isReleased, isTrue);
    },
  );
  test('detects a PNG screenshot as image media', () {
    final attachment = PromptAttachment(
      name: 'Screenshot',
      bytes: Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
    );

    expect(attachment.mediaType, 'image/png');
  });

  test('uses the filename for common image formats', () {
    final attachment = PromptAttachment(
      name: 'photo.JPEG',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(attachment.mediaType, 'image/jpeg');
  });

  test('release overwrites and drops memory-only attachment bytes', () {
    final bytes = Uint8List.fromList([4, 5, 6]);
    final attachment = PromptAttachment(name: 'private.txt', bytes: bytes);
    final owned = attachment.bytes;

    attachment.release();

    expect(attachment.isReleased, isTrue);
    expect(owned, everyElement(0));
    expect(() => attachment.bytes, throwsStateError);
  });
}
