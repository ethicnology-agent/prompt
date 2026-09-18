class WorkspaceEntry {
  const WorkspaceEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.isIgnored,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isIgnored;
}

class WorkspaceFileContent {
  const WorkspaceFileContent.text(this.value) : isText = true;

  const WorkspaceFileContent.binary() : isText = false, value = null;

  final bool isText;
  final String? value;
}

enum WorkspaceFileStatus { added, deleted, modified }

class WorkspaceStatusEntry {
  const WorkspaceStatusEntry({
    required this.path,
    required this.status,
    required this.added,
    required this.removed,
  });

  final String path;
  final WorkspaceFileStatus status;
  final int added;
  final int removed;
}

class WorkspaceVcsSummary {
  const WorkspaceVcsSummary(this.branch);

  final String branch;
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.entries,
    required this.status,
    required this.vcs,
  });

  final List<WorkspaceEntry> entries;
  final List<WorkspaceStatusEntry> status;
  final WorkspaceVcsSummary vcs;
}

enum WorkspaceSearchKind { text, file, symbol }

sealed class WorkspaceSearchResult {
  const WorkspaceSearchResult(this.path);

  final String path;

  /// Server-local file data, never an external URL or a client filesystem read.
  String? get filePath {
    if (path.trim().isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
      return null;
    }
    if (RegExp(r'^[\\/]{2}').hasMatch(path)) return null;
    // A drive prefix is filesystem data, not a URI scheme.
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) return path;
    final scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').firstMatch(path);
    if (scheme == null) return path;
    if (this is WorkspaceSymbolSearchResult &&
        scheme.group(0)!.toLowerCase() == 'file:') {
      // Uri normalizes file:relative into an absolute-looking path. Require
      // the absolute syntax before parsing instead of inventing a root.
      if (!path.substring(scheme.end).startsWith('/')) return null;
      final uri = Uri.tryParse(path);
      if (uri == null ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !uri.path.startsWith('/') ||
          (uri.host.isNotEmpty && uri.host != 'localhost')) {
        return null;
      }
      try {
        final local = uri
            .replace(host: '')
            .toFilePath(windows: RegExp(r'^/[A-Za-z]:/').hasMatch(uri.path));
        return local.isEmpty ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(local) ||
                RegExp(r'^[\\/]{2}').hasMatch(local)
            ? null
            : local;
      } on UnsupportedError {
        return null;
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }
}

class WorkspaceTextSearchResult extends WorkspaceSearchResult {
  const WorkspaceTextSearchResult({
    required String path,
    required this.line,
    required this.lineNumber,
    required this.absoluteOffset,
    required this.matches,
  }) : super(path);

  final String line;
  final int lineNumber;
  final int absoluteOffset;
  final List<WorkspaceTextSubmatch> matches;
}

class WorkspaceTextSubmatch {
  const WorkspaceTextSubmatch({required this.start, required this.end});

  final int start;
  final int end;
}

class WorkspaceFileSearchResult extends WorkspaceSearchResult {
  const WorkspaceFileSearchResult({required String path}) : super(path);
}

class WorkspaceSymbolSearchResult extends WorkspaceSearchResult {
  const WorkspaceSymbolSearchResult({
    required String path,
    required this.name,
    required this.kind,
    required this.line,
    required this.character,
  }) : super(path);

  final String name;
  final int kind;
  final int line;
  final int character;
}
