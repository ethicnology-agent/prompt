import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/workspace/workspace.dart';

WorkspaceSymbolSearchResult symbol(String path) => WorkspaceSymbolSearchResult(
  path: path,
  name: 'symbol',
  kind: 12,
  line: 1,
  character: 0,
);

void main() {
  test('search positions normalize only reported valid source lines', () {
    expect(const WorkspaceFileSearchResult(path: 'file').targetLine, isNull);
    for (final line in [-1, 0, 1, 700]) {
      expect(
        WorkspaceTextSearchResult(
          path: 'file',
          line: '',
          lineNumber: line,
          absoluteOffset: 0,
          matches: const [],
        ).targetLine,
        line > 0 ? line : null,
      );
      expect(
        WorkspaceSymbolSearchResult(
          path: 'file',
          name: 'symbol',
          kind: 1,
          line: line,
          character: 0,
        ).targetLine,
        line >= 0 ? line + 1 : null,
      );
    }
  });
  for (final path in [
    'main.dart',
    'lib/main.dart',
    './lib/main.dart',
    '/workspace/main.dart',
    'fichiers/été/文件.dart',
    'folder with spaces/my file.dart',
    'literal%20name.dart',
    'name#version.dart',
    r'C:\Users\fixture\main.dart',
    'C:/Users/fixture/main.dart',
  ]) {
    test('plain path stays exact: $path', () {
      expect(WorkspaceFileSearchResult(path: path).filePath, path);
      expect(symbol(path).filePath, path);
      expect(
        WorkspaceTextSearchResult(
          path: path,
          line: 'match',
          lineNumber: 1,
          absoluteOffset: 0,
          matches: const [],
        ).filePath,
        path,
      );
    });
  }

  for (final entry in <String, String>{
    'file:///workspace/main.dart': '/workspace/main.dart',
    'file:/workspace/main.dart': '/workspace/main.dart',
    'file://localhost/workspace/main.dart': '/workspace/main.dart',
    'FILE:///workspace/main.dart': '/workspace/main.dart',
    'file:///workspace/my%20file.dart': '/workspace/my file.dart',
    'file:///workspace/%C3%A9t%C3%A9/%E6%96%87%E4%BB%B6.dart':
        '/workspace/été/文件.dart',
    'file:///workspace/name%23version.dart': '/workspace/name#version.dart',
    'file:///C:/Workspace/My%20File.dart': r'C:\Workspace\My File.dart',
    'file://localhost/C:/Workspace/main.dart': r'C:\Workspace\main.dart',
  }.entries) {
    test('symbol local file URI is decoded: ${entry.key}', () {
      expect(symbol(entry.key).filePath, entry.value);
      expect(WorkspaceFileSearchResult(path: entry.key).filePath, isNull);
    });
  }

  for (final path in [
    '',
    '   ',
    'https://example.invalid/file',
    'https:example.invalid/file',
    'data:text/plain,hello',
    'javascript:alert(1)',
    '//remote/share/file',
    r'\\remote\share\file',
    'file:relative.dart',
    'file:../relative.dart',
    'file://remote/workspace/file',
    'file://user@localhost/workspace/file',
    'file://localhost:123/workspace/file',
    'file:///workspace/file?query=value',
    'file:///workspace/file#fragment',
    'file:///workspace/%0afile',
    'file:///workspace/%00file',
    'file:///workspace/%09file',
    'file:///workspace/%7ffile',
    'file:////remote/share/file',
    'file:///%2Fremote/share/file',
    'raw\nfile',
    'raw\rfile',
    'raw\tfile',
    'raw\u0000file',
    'raw\u007ffile',
  ]) {
    test(
      'unsafe navigation target is rejected: ${Uri.encodeComponent(path)}',
      () {
        expect(symbol(path).filePath, isNull);
        expect(WorkspaceFileSearchResult(path: path).filePath, isNull);
      },
    );
  }
}
