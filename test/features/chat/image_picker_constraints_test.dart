import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';

class _Picker extends FilePicker {
  FilePickerResult? result;
  FileType? selectedType;
  List<String>? extensions;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(allowMultiple, isTrue);
    expect(withData, isTrue);
    selectedType = type;
    extensions = allowedExtensions;
    return result;
  }
}

void main() {
  final limits = AttachmentConstraints(
    mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
    maxCount: 5,
    maxBytesPerAttachment: 5 * 1024 * 1024,
    maxTotalBytes: 10 * 1024 * 1024,
  );

  test(
    'native picker filters images and safely rejects immutable platform data',
    () async {
      final fake = _Picker();
      FilePicker.platform = fake;
      final bytes = Uint8List.fromList([
        37,
        80,
        68,
        70,
        45,
      ]).asUnmodifiableView();
      fake.result = FilePickerResult([
        PlatformFile(name: 'disguised.png', size: bytes.length, bytes: bytes),
      ]);
      final result = await FilePickerAttachmentPicker().pickWithConstraints(
        limits,
      );
      expect(result, isA<AttachmentPickRejected>());
      expect(fake.selectedType, FileType.custom);
      expect(fake.extensions, ['png', 'jpg', 'jpeg', 'gif', 'webp']);
      expect(bytes, [37, 80, 68, 70, 45]);
    },
  );

  test(
    'direct picker retains generic file support and original limits',
    () async {
      final fake = _Picker();
      FilePicker.platform = fake;
      final bytes = Uint8List(6 * 1024 * 1024)
        ..setRange(0, 5, [37, 80, 68, 70, 45]);
      fake.result = FilePickerResult([
        PlatformFile(name: 'document.pdf', size: bytes.length, bytes: bytes),
      ]);
      final result = await FilePickerAttachmentPicker().pick();
      expect(result, isA<AttachmentsPicked>());
      expect(fake.selectedType, FileType.any);
      expect(fake.extensions, isNull);
      final attachment = (result as AttachmentsPicked).attachments.single;
      expect(attachment.mediaType, 'application/pdf');
      attachment.release();
    },
  );

  for (final invalid in [false, true]) {
    test(
      'health maps bounded native image constraints; invalid=$invalid fails closed',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'protocolVersion': 1,
              'engines': {
                'claude': {
                  'available': true,
                  'features': [
                    'sessions',
                    'text',
                    'abort',
                    'attachments',
                    'imageAttachments',
                  ],
                  'attachmentConstraints': {
                    'mimeTypes': [
                      'image/png',
                      'image/jpeg',
                      'image/gif',
                      'image/webp',
                    ],
                    'maxCount': invalid ? 999999 : 5,
                    'maxBytesPerAttachment': 5 * 1024 * 1024,
                    'maxTotalBytes': 10 * 1024 * 1024,
                  },
                },
              },
            }),
            200,
          ),
        );
        addTearDown(client.close);
        final capabilities =
            await OpenCodeHealthService(
              OpenCodeTransport(client),
            ).checkCapabilities(
              ServerProfile(
                origin: Uri.parse('http://10.80.0.1:4096'),
                username: 'prompt',
                backend: AgentBackend.gatewayClaude,
              ),
              'fixture',
            );
        expect(capabilities!.supports(BackendFeature.imageAttachments), isTrue);
        if (invalid) {
          expect(capabilities.attachmentConstraints, isNull);
        } else {
          expect(capabilities.attachmentConstraints!.maxCount, 5);
          expect(
            capabilities.attachmentConstraints!.maxBytesPerAttachment,
            5 * 1024 * 1024,
          );
          expect(
            capabilities.attachmentConstraints!.maxTotalBytes,
            10 * 1024 * 1024,
          );
          expect(
            capabilities.attachmentConstraints!.mimeTypes,
            limits.mimeTypes,
          );
        }
      },
    );
  }
}
