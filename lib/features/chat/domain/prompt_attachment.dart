import 'dart:typed_data';

/// A file selected by the user for a prompt.
///
/// The bytes are intentionally memory-only. Call [release] as soon as the
/// selection is removed or its owning conversation leaves the foreground.
/// A private mutable copy is owned here; platform/caller buffers may be
/// immutable and remain the caller's responsibility.
class PromptAttachment {
  factory PromptAttachment({
    required String name,
    required Uint8List bytes,
    String? mediaType,
  }) => PromptAttachment._(
    name: name,
    bytes: Uint8List.fromList(bytes),
    mediaType: mediaType ?? _detectMediaType(name, bytes),
  );

  PromptAttachment._({
    required this.name,
    required Uint8List this._bytes,
    required this.mediaType,
  });

  static const int maxBytesPerAttachment = 10 * 1024 * 1024;
  static const int maxAttachmentCount = 5;
  static const int maxTotalBytes = 25 * 1024 * 1024;

  final String name;
  final String mediaType;
  Uint8List? _bytes;

  int get byteCount => _bytes?.lengthInBytes ?? 0;
  bool get isReleased => _bytes == null;

  /// Only available while this attachment is owned by the active composer.
  Uint8List get bytes {
    final value = _bytes;
    if (value == null) {
      throw StateError('Attachment bytes were released.');
    }
    return value;
  }

  /// Overwrites the mutable buffer before dropping this object's reference.
  void release() {
    final value = _bytes;
    if (value == null) {
      return;
    }
    value.fillRange(0, value.length, 0);
    _bytes = null;
  }

  @override
  String toString() => 'PromptAttachment(bytes: $byteCount)';
}

String _detectMediaType(String name, Uint8List bytes) {
  if (_startsWith(bytes, const [
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ])) {
    return 'image/png';
  }
  if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) {
    return 'image/jpeg';
  }
  if (_startsWith(bytes, const [0x47, 0x49, 0x46, 0x38])) {
    return 'image/gif';
  }
  if (bytes.lengthInBytes >= 12 &&
      _matchesAt(bytes, 0, const [0x52, 0x49, 0x46, 0x46]) &&
      _matchesAt(bytes, 8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  if (_startsWith(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2d])) {
    return 'application/pdf';
  }

  final extension = name.toLowerCase().split('.').last;
  return switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}

bool _startsWith(Uint8List bytes, List<int> signature) =>
    _matchesAt(bytes, 0, signature);

bool _matchesAt(Uint8List bytes, int offset, List<int> signature) {
  if (bytes.lengthInBytes < offset + signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[offset + index] != signature[index]) return false;
  }
  return true;
}

sealed class AttachmentPickResult {
  const AttachmentPickResult();
}

class AttachmentsPicked extends AttachmentPickResult {
  const AttachmentsPicked(this.attachments);

  final List<PromptAttachment> attachments;
}

class AttachmentPickCancelled extends AttachmentPickResult {
  const AttachmentPickCancelled();
}

class AttachmentPickRejected extends AttachmentPickResult {
  const AttachmentPickRejected(this.message);

  final String message;
}
