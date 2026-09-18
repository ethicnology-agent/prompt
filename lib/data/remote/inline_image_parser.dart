import 'dart:convert';
import 'dart:typed_data';

const inlineImageMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};
const maxInlineImageBytes = 10 * 1024 * 1024;

/// Decodes only bounded, canonical inline images. Never resolves a URL or path.
Uint8List? parseInlineImage(Object? url, String mime) {
  if (!inlineImageMimeTypes.contains(mime) || url is! String) return null;
  final prefix = 'data:$mime;base64,';
  if (!url.startsWith(prefix)) return null;
  final encoded = url.substring(prefix.length);
  if (encoded.isEmpty ||
      encoded.length > 4 * ((maxInlineImageBytes + 2) ~/ 3) ||
      encoded.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(encoded)) {
    return null;
  }
  try {
    final bytes = base64Decode(encoded);
    if (bytes.length > maxInlineImageBytes ||
        base64Encode(bytes) != encoded ||
        !matchesImageSignature(bytes, mime)) {
      bytes.fillRange(0, bytes.length, 0);
      return null;
    }
    return bytes;
  } on FormatException {
    return null;
  }
}

bool matchesImageSignature(Uint8List bytes, String mime) {
  bool starts(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  return switch (mime) {
    'image/png' => starts(const [137, 80, 78, 71, 13, 10, 26, 10]),
    'image/jpeg' => starts(const [255, 216, 255]),
    'image/gif' =>
      starts(ascii.encode('GIF87a')) || starts(ascii.encode('GIF89a')),
    'image/webp' =>
      starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8),
    _ => false,
  };
}

String safeAttachmentName(Object? name) =>
    name is String &&
        name.isNotEmpty &&
        name.length <= 255 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)
    ? name
    : 'Attachment';
