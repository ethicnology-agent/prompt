import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../domain/prompt_attachment.dart';
import '../../connection/connection.dart';
import '../../../data/remote/inline_image_parser.dart';

abstract interface class ConstrainedAttachmentPicker
    implements AttachmentPicker {
  Future<AttachmentPickResult> pickWithConstraints(
    AttachmentConstraints constraints,
  );
}

String? attachmentConstraintError(
  Iterable<PromptAttachment> attachments,
  AttachmentConstraints constraints,
) {
  if (attachments.length > constraints.maxCount) {
    return 'Select up to ${constraints.maxCount} images.';
  }
  var total = 0;
  for (final attachment in attachments) {
    if (attachment.isReleased ||
        !constraints.mimeTypes.contains(attachment.mediaType) ||
        !matchesImageSignature(attachment.bytes, attachment.mediaType)) {
      return 'This backend supports PNG, JPEG, GIF and WebP images only.';
    }
    if (attachment.byteCount > constraints.maxBytesPerAttachment) {
      return 'Each image must be ${constraints.maxBytesPerAttachment ~/ (1024 * 1024)} MiB or smaller.';
    }
    total += attachment.byteCount;
  }
  if (total > constraints.maxTotalBytes) {
    return 'Images together must be ${constraints.maxTotalBytes ~/ (1024 * 1024)} MiB or smaller.';
  }
  return null;
}

/// Platform file selection is isolated here so presentation never invokes a
/// platform plugin directly. The picker is called only from a user gesture.
abstract interface class AttachmentPicker {
  Future<AttachmentPickResult> pick();
}

AttachmentPicker createAttachmentPicker() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? _AndroidMemoryAttachmentPicker()
    : FilePickerAttachmentPicker();

class _AndroidMemoryAttachmentPicker implements ConstrainedAttachmentPicker {
  static const _channel = MethodChannel('me.ethicnology.prompt/attachments');

  @override
  Future<AttachmentPickResult> pick() => _pick();

  @override
  Future<AttachmentPickResult> pickWithConstraints(
    AttachmentConstraints constraints,
  ) => _pick(constraints);

  Future<AttachmentPickResult> _pick([
    AttachmentConstraints? constraints,
  ]) async {
    const rejected = AttachmentPickRejected(
      'The selected files could not be read safely.',
    );
    final attachments = <PromptAttachment>[];
    final maxCount = math.min(
      constraints?.maxCount ?? PromptAttachment.maxAttachmentCount,
      PromptAttachment.maxAttachmentCount,
    );
    final maxBytes = math.min(
      constraints?.maxBytesPerAttachment ??
          PromptAttachment.maxBytesPerAttachment,
      PromptAttachment.maxBytesPerAttachment,
    );
    final maxTotal = math.min(
      constraints?.maxTotalBytes ?? PromptAttachment.maxTotalBytes,
      PromptAttachment.maxTotalBytes,
    );
    if (maxCount < 1 || maxBytes < 1 || maxTotal < 1) return rejected;
    Object? result;
    try {
      result = await _channel.invokeMethod<Object?>('pick', {
        'imagesOnly': constraints != null,
        'maxCount': maxCount,
        'maxBytesPerFile': maxBytes,
        'maxTotalBytes': maxTotal,
      });
      if (result == null) return const AttachmentPickCancelled();
      if (result is! List || result.isEmpty || result.length > maxCount) {
        return rejected;
      }
      // Android may deliver the activity result before Flutter resumes. Do not
      // hand it to a composer that is still releasing inactive selections.
      if (!await _waitForForeground()) return const AttachmentPickCancelled();
      var total = 0;
      for (final item in result) {
        if (item is! Map ||
            item['name'] is! String ||
            item['bytes'] is! Uint8List) {
          _releaseAttachments(attachments);
          return rejected;
        }
        final bytes = item['bytes'] as Uint8List;
        total += bytes.length;
        if (bytes.length > maxBytes || total > maxTotal) {
          _releaseAttachments(attachments);
          return rejected;
        }
        attachments.add(
          PromptAttachment(name: item['name'] as String, bytes: bytes),
        );
      }
      if (constraints != null) {
        final error = attachmentConstraintError(attachments, constraints);
        if (error != null) {
          _releaseAttachments(attachments);
          return AttachmentPickRejected(error);
        }
      }
      return AttachmentsPicked(List.unmodifiable(attachments));
    } on PlatformException {
      _releaseAttachments(attachments);
      return rejected;
    } on MissingPluginException {
      _releaseAttachments(attachments);
      return rejected;
    } finally {
      // Wipe writable decoded buffers, including unvisited rejected items.
      // Engine-owned read-only views cannot be erased here; release their
      // references while attachments retain independently erasable copies.
      if (result is List) {
        for (final item in result) {
          if (item is Map && item['bytes'] is Uint8List) {
            final bytes = item['bytes'] as Uint8List;
            try {
              bytes.fillRange(0, bytes.length, 0);
            } on UnsupportedError {
              // Flutter may deliver an unmodifiable platform-message view.
            }
          }
        }
      }
    }
  }

  Future<bool> _waitForForeground() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return true;
    if (state == AppLifecycleState.detached) return false;
    final result = Completer<bool>();
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        if (!result.isCompleted &&
            (state == AppLifecycleState.resumed ||
                state == AppLifecycleState.detached)) {
          result.complete(state == AppLifecycleState.resumed);
        }
      },
    );
    try {
      return await result.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
    } finally {
      listener.dispose();
    }
  }
}

class FilePickerAttachmentPicker implements ConstrainedAttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() => _pick();

  @override
  Future<AttachmentPickResult> pickWithConstraints(
    AttachmentConstraints constraints,
  ) => _pick(constraints);

  Future<AttachmentPickResult> _pick([
    AttachmentConstraints? constraints,
  ]) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: constraints == null ? FileType.any : FileType.custom,
      allowedExtensions: constraints == null
          ? null
          : [
              if (constraints.mimeTypes.contains('image/png')) 'png',
              if (constraints.mimeTypes.contains('image/jpeg')) ...[
                'jpg',
                'jpeg',
              ],
              if (constraints.mimeTypes.contains('image/gif')) 'gif',
              if (constraints.mimeTypes.contains('image/webp')) 'webp',
            ],
    );
    if (result == null) {
      return const AttachmentPickCancelled();
    }

    final files = result.files;
    if (files.length > PromptAttachment.maxAttachmentCount) {
      return const AttachmentPickRejected('Select up to 5 attachments.');
    }

    var totalBytes = 0;
    final attachments = <PromptAttachment>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _releaseAttachments(attachments);
        return const AttachmentPickRejected(
          'The selected file could not be read into memory.',
        );
      }
      if (bytes.lengthInBytes > PromptAttachment.maxBytesPerAttachment) {
        _releaseAttachments(attachments);
        return const AttachmentPickRejected(
          'Each attachment must be 10 MiB or smaller.',
        );
      }
      totalBytes += bytes.lengthInBytes;
      if (totalBytes > PromptAttachment.maxTotalBytes) {
        _releaseAttachments(attachments);
        return const AttachmentPickRejected(
          'Attachments together must be 25 MiB or smaller.',
        );
      }
      attachments.add(PromptAttachment(name: file.name, bytes: bytes));
    }
    if (constraints != null) {
      final error = attachmentConstraintError(attachments, constraints);
      if (error != null) {
        _releaseAttachments(attachments);
        return AttachmentPickRejected(error);
      }
    }
    return AttachmentsPicked(List.unmodifiable(attachments));
  }
}

void _releaseAttachments(Iterable<PromptAttachment> attachments) {
  for (final attachment in attachments) {
    attachment.release();
  }
}
