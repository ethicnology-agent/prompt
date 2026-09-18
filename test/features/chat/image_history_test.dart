import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/data/remote/inline_image_parser.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/data/chat_data_mapper.dart';
import 'package:prompt/features/chat/data/conversation_sync.dart';
import 'package:prompt/features/chat/data/opencode_chat_api.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/presentation/widgets/transcript.dart';
import 'package:prompt/features/connection/connection.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==';

Map<String, dynamic> _part(Object? url, {String mime = 'image/png'}) => {
  'id': 'file-part',
  'messageID': 'message',
  'sessionID': 'session',
  'type': 'file',
  'filename': 'Écran privé.png',
  'mime': mime,
  'url': url,
};

ChatMessage _rest(Map<String, dynamic> part) => mapChatMessage(
  OpenCodeMessageRecord.fromJson({
    'info': {
      'id': 'message',
      'role': 'user',
      'time': {'created': 1},
    },
    'parts': [part],
  }),
);

ChatMessage _live(Map<String, dynamic> part) {
  final event =
      mapConversationEvent(
            OpenCodeEventEnvelope(
              directory: null,
              payload: {
                'type': 'message.part.updated',
                'properties': {'part': part},
              },
            ),
            sessionId: 'session',
          )
          as MessagePartUpdatedEvent;
  return mergeConversationMessages([], {
    'message': ConversationMessage(
      id: 'message',
      sessionId: 'session',
      role: ConversationRole.user,
      parts: [event.part],
    ),
  }).single;
}

void main() {
  test(
    'REST and SSE retain the same image-only message and stable file identity',
    () {
      final part = _part('data:image/png;base64,$_png');
      final rest = _rest(part);
      final live = _live(part);
      for (final message in [rest, live]) {
        expect(message.id, 'message');
        expect(message.text, isEmpty);
        final image = message.details.single as ChatFileDetail;
        expect(image.id, 'file-part');
        expect(image.name, 'Écran privé.png');
        expect(image.mediaType, 'image/png');
        expect(image.bytes, base64Decode(_png));
      }
      final repeated = _live(part).details.single;
      expect(repeated.id, rest.details.single.id);
    },
  );

  for (final url in <Object?>[
    'https://example.invalid/private.png',
    'file:///private/image.png',
    '/private/image.png',
    'data:image/png;base64,!!!!',
    'data:image/jpeg;base64,$_png',
    'data:image/png;base64,SGVsbG8=',
    'data:image/png;base64,$_png\n',
    null,
    12,
  ]) {
    test(
      'untrusted image source ${url.runtimeType} is not retained or resolved: ${url.toString().length}',
      () {
        for (final message in [_rest(_part(url)), _live(_part(url))]) {
          final file = message.details.single as ChatFileDetail;
          expect(file.bytes, isNull);
          expect(file.name, 'Écran privé.png');
        }
      },
    );
  }

  test('unsupported PDF and MIME mismatches cannot become image previews', () {
    expect(
      parseInlineImage('data:application/pdf;base64,$_png', 'application/pdf'),
      isNull,
    );
    expect(
      parseInlineImage('data:image/jpeg;base64,$_png', 'image/jpeg'),
      isNull,
    );
  });

  test(
    'native image constraints validate signatures, per-file, count and aggregate bounds',
    () {
      final constraints = AttachmentConstraints(
        mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
        maxCount: 5,
        maxBytesPerAttachment: 5 * 1024 * 1024,
        maxTotalBytes: 10 * 1024 * 1024,
      );
      PromptAttachment png([int? size]) {
        final source = base64Decode(_png);
        final bytes = Uint8List(size ?? source.length)
          ..setRange(0, source.length, source);
        return PromptAttachment(name: 'image.png', bytes: bytes);
      }

      expect(attachmentConstraintError([png()], constraints), isNull);
      expect(
        attachmentConstraintError([
          PromptAttachment(name: 'fake.png', bytes: Uint8List.fromList([65])),
        ], constraints),
        contains('images only'),
      );
      expect(
        attachmentConstraintError([
          PromptAttachment(
            name: 'file.pdf',
            bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
          ),
        ], constraints),
        contains('images only'),
      );
      expect(
        attachmentConstraintError([png(5 * 1024 * 1024 + 1)], constraints),
        contains('5 MiB'),
      );
      expect(
        attachmentConstraintError(List.generate(6, (_) => png()), constraints),
        contains('5 images'),
      );
      expect(
        attachmentConstraintError([
          png(4 * 1024 * 1024),
          png(4 * 1024 * 1024),
          png(4 * 1024 * 1024),
        ], constraints),
        contains('10 MiB'),
      );
      expect(
        BackendCapabilities.directOpenCode.supports(BackendFeature.attachments),
        isTrue,
      );
      expect(
        BackendCapabilities.directOpenCode.supports(
          BackendFeature.imageAttachments,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'history images are read-only, lifecycle-cleared, and never use network image providers',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: Scaffold(
            body: Transcript(
              messages: [_rest(_part('data:image/png;base64,$_png'))],
              onRefresh: () async {},
              controller: controller,
              onRevert: (_) {},
              onLoadOlder: () {},
              hasMore: false,
              loadingOlder: false,
              limitedByServer: false,
            ),
          ),
        ),
      );
      final thumbnail = tester.widget<AttachmentThumbnail>(
        find.byType(AttachmentThumbnail),
      );
      expect(thumbnail.onRemove, isNull);
      expect(find.byTooltip('Remove Écran privé.png'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Écran privé.png'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(thumbnail.controller.debugImage, isNull);
      expect(thumbnail.controller.state, AttachmentThumbnailState.cleared);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final restored = tester.widget<AttachmentThumbnail>(
        find.byType(AttachmentThumbnail),
      );
      expect(identical(restored.controller, thumbnail.controller), isFalse);
      expect(
        restored.controller.state,
        isNot(AttachmentThumbnailState.cleared),
      );
      expect(restored.onOpen, isNotNull);
      restored.onOpen!();
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentImageViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close image'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'remote history source displays a local unavailable placeholder only',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Transcript(
              messages: [_rest(_part('https://example.invalid/private.png'))],
              onRefresh: () async {},
              controller: controller,
              onRevert: (_) {},
              onLoadOlder: () {},
              hasMore: false,
              loadingOlder: false,
              limitedByServer: false,
            ),
          ),
        ),
      );
      expect(find.text('Preview unavailable'), findsOneWidget);
      expect(find.byType(AttachmentThumbnail), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('https://'), findsNothing);
    },
  );
}
