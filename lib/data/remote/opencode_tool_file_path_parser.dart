/// Extracts a navigation candidate only from recognized structured file tools.
/// This does not authorize access, resolve a path, or perform any I/O.
String? parseOpenCodeToolFilePath(String tool, Object? input) {
  if (!const {
        'read',
        'edit',
        'write',
        'multiedit',
      }.contains(tool.toLowerCase()) ||
      input is! Map<String, dynamic>) {
    return null;
  }
  for (final key in const ['filePath', 'file_path', 'path']) {
    if (!input.containsKey(key)) continue;
    final value = input[key];
    // Do not fall back to another alias when the authoritative field is invalid.
    if (value is! String || value.trim().isEmpty) return null;
    if (_controlCharacters.hasMatch(value)) return null;
    final trimmed = value.trim();
    if (_urlScheme.hasMatch(trimmed) || trimmed.startsWith('//')) return null;
    // Spaces, Unicode, colons, and platform-specific separators are preserved.
    return value;
  }
  return null;
}

final _controlCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f]');
final _urlScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://');
