import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/connection/connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('me.ethicnology.prompt/attachments');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('Android selection is not delivered before foreground resume', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => [
        {
          'name': 'fixture.png',
          'bytes': Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        },
      ],
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    AttachmentPickResult? delivered;
    final pending = createAttachmentPicker().pick().then(
      (value) => delivered = value,
    );
    await tester.pump();
    expect(delivered, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(delivered, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await pending;
    expect(delivered, isA<AttachmentsPicked>());
    (delivered as AttachmentsPicked).attachments.single.release();
    debugDefaultTargetPlatformOverride = null;
  });

  List<Uint8List> mockReplyBuffers(
    List<Object> reply, {
    bool readOnly = false,
  }) {
    const codec = StandardMethodCodec();
    final encoded = codec.encodeSuccessEnvelope(reply);
    final envelope = readOnly ? encoded.asUnmodifiableView() : encoded;
    // The codec returns views of the actual reply envelope, not copies of the
    // fixture arrays. Keep those views to observe the bridge's cleanup.
    final decoded = codec.decodeEnvelope(envelope) as List;
    final buffers = [
      for (final item in decoded)
        if (item is Map && item['bytes'] is Uint8List)
          item['bytes'] as Uint8List,
    ];
    expect(buffers, isNotEmpty);
    for (final buffer in buffers) {
      expect(buffer.any((value) => value != 0), isTrue);
    }
    messenger.setMockMessageHandler(channel.name, (_) async => envelope);
    return buffers;
  }

  for (final accepted in [true, false]) {
    test(
      'Android read-only engine buffers do not override result: $accepted',
      () async {
        final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
        mockReplyBuffers([
          {'name': 'fixture.png', 'bytes': bytes},
        ], readOnly: true);
        final result =
            await (createAttachmentPicker() as ConstrainedAttachmentPicker)
                .pickWithConstraints(
                  AttachmentConstraints(
                    mimeTypes: accepted ? ['image/png'] : ['image/jpeg'],
                    maxCount: 1,
                    maxBytesPerAttachment: 1024,
                    maxTotalBytes: 1024,
                  ),
                );
        if (accepted) {
          expect(result, isA<AttachmentsPicked>());
          final attachment = (result as AttachmentsPicked).attachments.single;
          expect(attachment.bytes, bytes);
          attachment.release();
        } else {
          expect(result, isA<AttachmentPickRejected>());
        }
      },
    );
  }

  for (final timeout in [false, true]) {
    testWidgets(
      'Android foreground wait cancels and wipes buffers: timeout=$timeout',
      (tester) async {
        final buffers = mockReplyBuffers([
          {
            'name': 'fixture.png',
            'bytes': Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          },
        ]);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        final pending = createAttachmentPicker().pick();
        await tester.pump();
        if (timeout) {
          await tester.pump(const Duration(seconds: 31));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.detached,
          );
          await tester.pump();
        }
        expect(await pending, isA<AttachmentPickCancelled>());
        for (final buffer in buffers) {
          expect(buffer, everyElement(0));
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  test(
    'Android success wipes channel buffers but retains owned bytes',
    () async {
      final original = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final buffers = mockReplyBuffers([
        {'name': 'fixture.png', 'bytes': original},
      ]);
      final picker = createAttachmentPicker() as ConstrainedAttachmentPicker;
      final result = await picker.pickWithConstraints(
        AttachmentConstraints(
          mimeTypes: ['image/png'],
          maxCount: 3,
          maxBytesPerAttachment: 1024,
          maxTotalBytes: 1024,
        ),
      );
      expect(result, isA<AttachmentsPicked>());
      final attachment = (result as AttachmentsPicked).attachments.single;
      addTearDown(attachment.release);
      expect(attachment.bytes, orderedEquals(original));
      for (final buffer in buffers) {
        expect(buffer, everyElement(0));
      }
      expect(attachment.bytes, orderedEquals(original));
    },
  );

  for (final failure in [
    'malformed first item',
    'malformed later item',
    'too many items',
    'oversized item',
    'aggregate overflow',
    'invalid image signature',
  ]) {
    test('Android wipes all channel buffers after $failure', () async {
      Map<String, Object> file(String name, [int length = 8]) => {
        'name': name,
        'bytes': Uint8List.fromList(List.filled(length, 7)),
      };
      final reply = switch (failure) {
        'malformed first item' => <Object>[
          {
            'name': 42,
            'bytes': Uint8List.fromList([1, 2, 3]),
          },
          file('unvisited.png'),
        ],
        'malformed later item' => <Object>[
          file('visited.png'),
          {
            'name': 42,
            'bytes': Uint8List.fromList([1, 2, 3]),
          },
          file('unvisited.png'),
        ],
        'too many items' => <Object>[
          for (var i = 0; i < 4; i++) file('fixture-$i.png'),
        ],
        'oversized item' => <Object>[
          file('oversized.png', 1025),
          file('unvisited.png'),
        ],
        'aggregate overflow' => <Object>[
          file('one.png', 700),
          file('two.png', 700),
          file('unvisited.png'),
        ],
        _ => <Object>[file('invalid.png')],
      };
      final buffers = mockReplyBuffers(reply);
      final picker = createAttachmentPicker() as ConstrainedAttachmentPicker;
      final result = await picker.pickWithConstraints(
        AttachmentConstraints(
          mimeTypes: ['image/png'],
          maxCount: 3,
          maxBytesPerAttachment: 1024,
          maxTotalBytes: 1024,
        ),
      );
      expect(result, isA<AttachmentPickRejected>());
      for (final buffer in buffers) {
        expect(buffer, everyElement(0));
      }
    });
  }

  test(
    'Android selection uses bounded memory channel instead of file cache',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pick');
        expect(call.arguments, {
          'imagesOnly': true,
          'maxCount': 2,
          'maxBytesPerFile': 1024,
          'maxTotalBytes': 2048,
        });
        return [
          {
            'name': 'fixture.png',
            'bytes': Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          },
        ];
      });
      final picker = createAttachmentPicker() as ConstrainedAttachmentPicker;
      final result = await picker.pickWithConstraints(
        AttachmentConstraints(
          mimeTypes: ['image/png'],
          maxCount: 2,
          maxBytesPerAttachment: 1024,
          maxTotalBytes: 2048,
        ),
      );
      expect(result, isA<AttachmentsPicked>());
      final file = (result as AttachmentsPicked).attachments.single;
      expect(file.mediaType, 'image/png');
      file.release();
    },
  );

  test('Android cancellation does not invoke a fallback picker', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await createAttachmentPicker().pick(),
      isA<AttachmentPickCancelled>(),
    );
  });

  for (final failure in [
    PlatformException(code: 'read_failed', message: '/private/sensitive-path'),
    MissingPluginException(),
  ]) {
    test(
      'Android failure stays generic without unsafe fallback: ${failure.runtimeType}',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async => throw failure);
        final result = await createAttachmentPicker().pick();
        expect(result, isA<AttachmentPickRejected>());
        expect(
          (result as AttachmentPickRejected).message,
          isNot(contains('sensitive')),
        );
      },
    );
  }

  test('Android aggregate limit is checked independently', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => [
        {'name': 'one.png', 'bytes': Uint8List(700)},
        {'name': 'two.png', 'bytes': Uint8List(700)},
      ],
    );
    final result =
        await (createAttachmentPicker() as ConstrainedAttachmentPicker)
            .pickWithConstraints(
              AttachmentConstraints(
                mimeTypes: ['image/png'],
                maxCount: 2,
                maxBytesPerAttachment: 1024,
                maxTotalBytes: 1024,
              ),
            );
    expect(result, isA<AttachmentPickRejected>());
  });

  test(
    'Android malformed and oversized channel replies are rejected',
    () async {
      for (final reply in [
        <Object>[],
        List.generate(2, (_) => {'name': 'fixture.png', 'bytes': Uint8List(1)}),
        [
          {'name': 'bad.png', 'bytes': 'not bytes'},
        ],
        [
          {'name': 'large.png', 'bytes': Uint8List(1025)},
        ],
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => reply);
        final result =
            await (createAttachmentPicker() as ConstrainedAttachmentPicker)
                .pickWithConstraints(
                  AttachmentConstraints(
                    mimeTypes: ['image/png'],
                    maxCount: 1,
                    maxBytesPerAttachment: 1024,
                    maxTotalBytes: 1024,
                  ),
                );
        expect(result, isA<AttachmentPickRejected>());
      }
    },
  );
}
