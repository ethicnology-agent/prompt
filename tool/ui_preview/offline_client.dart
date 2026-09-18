import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Synthetic OpenCode protocol fixture. No socket, DNS, subprocess, credential,
/// provider SDK, or real filesystem is used. Unknown routes fail closed.
class OfflinePreviewClient extends http.BaseClient {
  static const origin = 'http://10.23.42.1:4096';
  static const directory = '/fixture/prompt';
  static const sessionId = 'fixture-session';
  static const sessionTitle = 'Build a private coding companion';
  static const filePath = '/fixture/prompt/lib/example.dart';
  static const fileContent =
      '// Synthetic content, not a server file.\nfinal accent = "teal";\n';
  static const filePatch =
      '@@ -1 +1 @@\n-final accent = "blue";\n+final accent = "teal";\n';
  static const reply =
      'Fixture reply: your request stayed on this device. '
      'No CLI or remote model was executed.';

  final _events = StreamController<List<int>>.broadcast();
  final _timers = <Timer>[];
  final _messages = <Map<String, Object?>>[];
  var _busy = false;
  var _closed = false;
  var acceptedPrompts = 0;
  var promptAttempts = 0;
  var aborts = 0;
  var permissionReplies = 0;
  var fileReads = 0;
  String? lastPermissionResponse;
  Map<String, Object?>? _pendingPermission;
  Map<String, Object?>? _permissionAssistant;
  final _epoch = DateTime(2026, 9, 17, 12).millisecondsSinceEpoch;

  OfflinePreviewClient() {
    _messages.add(
      _message(
        'fixture-user',
        'user',
        'Give Prompt a calm, mobile-first interface while keeping my server private.',
      ),
    );
    final assistant = _message(
      'fixture-assistant',
      'assistant',
      '## A familiar interface, your infrastructure\n\n'
          'The session list, compact composer, and tool cards keep the conversation '
          'front and center.\n\n'
          '- Private server connection\n- Explicit approvals\n- Prompts queue without interruption\n\n'
          'This is a synthetic UI fixture, not an agent execution. '
          'Send `permission` to preview an approval. You have 1.6 seconds '
          'to queue a follow-up before the approval replaces the composer.',
    );
    (assistant['parts']! as List<Object?>).add({
      'id': 'fixture-tool',
      'type': 'tool',
      'tool': 'bash',
      'state': {
        'status': 'completed',
        'input': {'command': 'flutter test'},
        'output':
            'SYNTHETIC OUTPUT\n12 example checks passed.\nNo command was run.',
        'title': 'Example test report',
      },
    });
    _messages.add(assistant);
    final fileMessage = _message(
      'fixture-file-message',
      'assistant',
      'Open the example file to inspect its read-only content.',
    );
    (fileMessage['parts']! as List<Object?>).add({
      'id': 'fixture-file-tool',
      'type': 'tool',
      'tool': 'edit',
      'state': {
        'status': 'completed',
        'input': {
          'filePath': filePath,
          'oldString': 'blue',
          'newString': 'teal',
        },
        'output': 'SYNTHETIC: no real file was changed.',
      },
    });
    _messages.add(fileMessage);
  }

  Map<String, Object?> _message(String id, String role, String text) => {
    'info': {
      'id': id,
      'sessionID': sessionId,
      'role': role,
      'time': {'created': _epoch},
    },
    'parts': <Object?>[
      {
        'id': '$id-text',
        'messageID': id,
        'sessionID': sessionId,
        'type': 'text',
        'text': text,
      },
    ],
  };

  Map<String, Object?> get _session => {
    'id': sessionId,
    'projectID': 'fixture-project',
    'directory': directory,
    'title': sessionTitle,
    'time': {'created': _epoch, 'updated': _epoch},
    'summary': {'files': 3, 'additions': 84, 'deletions': 12},
  };

  void _emit(String type, Map<String, Object?> properties) {
    if (_closed) return;
    _events.add(
      utf8.encode(
        'data: ${jsonEncode({
          'directory': directory,
          'payload': {'type': type, 'properties': properties},
        })}\n\n',
      ),
    );
  }

  void _publish(Map<String, Object?> message) {
    _emit('message.updated', {'info': message['info']});
    for (final part in message['parts']! as List<Object?>) {
      _emit('message.part.updated', {'part': part});
    }
  }

  void _status(bool busy) {
    _busy = busy;
    _emit('session.status', {
      'sessionID': sessionId,
      'status': {'type': busy ? 'busy' : 'idle'},
    });
  }

  Stream<List<int>> _eventStream() async* {
    // Each connection gets a real initial SSE frame, including reconnects.
    yield utf8.encode(
      'data: {"payload":{"type":"server.connected",'
      '"properties":{}}}\n\n',
    );
    yield* _events.stream;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw StateError('Offline fixture was disposed.');
    // Consume even rejected requests locally; never forward them anywhere.
    final bytes = await request.finalize().toBytes();
    if (request.url.origin != origin) {
      return _json(403, {'error': 'Offline only'});
    }
    final path = request.url.path;
    if (request.method == 'GET') {
      if (path == '/file/content') {
        fileReads++;
        final scope = request.url.queryParameters['directory'];
        if (scope != directory &&
            scope != '$directory/lib' &&
            scope != '$directory/assets') {
          return _json(403, {'error': 'Fixture directory only'});
        }
        final requested = request.url.queryParameters['path'];
        final resolved = requested != null && requested.startsWith('/')
            ? requested
            : '$scope/$requested';
        return switch (resolved) {
          filePath => _json(200, {'type': 'text', 'content': fileContent}),
          '$directory/assets/fixture.bin' => _json(200, {'type': 'binary'}),
          _ => _json(404, {'error': 'Fixture file unavailable'}),
        };
      }
      if (path == '/file' ||
          path == '/file/status' ||
          path == '/vcs' ||
          path.startsWith('/find')) {
        final scope = request.url.queryParameters['directory'];
        if (scope != directory &&
            scope != '$directory/lib' &&
            scope != '$directory/assets') {
          return _json(403, {'error': 'Fixture directory only'});
        }
        if (path == '/vcs') return _json(200, {'branch': 'fixture'});
        if (path == '/file/status') {
          return _json(200, [
            {
              'path': 'lib/example.dart',
              'status': 'modified',
              'added': 1,
              'removed': 1,
            },
            {
              'path': 'removed.txt',
              'status': 'deleted',
              'added': 0,
              'removed': 1,
            },
          ]);
        }
        if (path == '/file') {
          final requested = request.url.queryParameters['path'];
          final names = switch (requested) {
            directory => ['lib', 'assets'],
            '$directory/lib' => ['example.dart'],
            '$directory/assets' => ['fixture.bin'],
            _ => <String>[],
          };
          return _json(200, [
            for (final name in names)
              {
                'name': name,
                'absolute': '$requested/$name',
                'type': requested == directory ? 'directory' : 'file',
                'ignored': false,
              },
          ]);
        }
        final query =
            request.url.queryParameters['query'] ??
            request.url.queryParameters['pattern'] ??
            '';
        if (scope == '$directory/assets' ||
            query.isEmpty ||
            !'example.dart accent teal'.contains(query.toLowerCase())) {
          return _json(200, []);
        }
        final relative = scope == directory
            ? 'lib/example.dart'
            : 'example.dart';
        return switch (path) {
          '/find/file' => _json(200, [relative]),
          '/find' => _json(200, [
            {
              'path': {'text': relative},
              'lines': {'text': 'final accent = "teal";'},
              'line_number': 2,
              'absolute_offset': 40,
              'submatches': <Object?>[],
            },
          ]),
          '/find/symbol' => _json(200, [
            {
              'name': 'accent',
              'kind': 13,
              'location': {
                'uri': 'file://$filePath',
                'range': {
                  'start': {'line': 1, 'character': 6},
                  'end': {'line': 1, 'character': 12},
                },
              },
            },
          ]),
          _ => _json(404, {'error': 'Fixture route unavailable'}),
        };
      }
      if (path == '/global/event') {
        return http.StreamedResponse(
          _eventStream(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return switch (path) {
        '/global/health' => _json(200, {'healthy': true, 'version': 'fixture'}),
        '/project' => _json(200, [
          {'id': 'fixture-project', 'worktree': directory},
        ]),
        '/session' => _json(200, [_session]),
        '/session/$sessionId' => _json(200, _session),
        '/session/status' => _json(200, {
          sessionId: {'type': _busy ? 'busy' : 'idle'},
        }),
        '/session/$sessionId/message' => _json(200, _messages),
        '/session/$sessionId/todo' => _json(200, [
          {
            'content': 'Keep transport private',
            'status': 'completed',
            'priority': 'high',
          },
          {
            'content': 'Review mobile layout',
            'status': 'pending',
            'priority': 'medium',
          },
        ]),
        '/session/$sessionId/diff' => _json(200, [
          {
            'file': 'lib/example.dart',
            'patch': filePatch,
            'additions': 1,
            'deletions': 1,
          },
          {
            'file': 'assets/fixture.bin',
            'patch': '',
            'additions': 0,
            'deletions': 0,
          },
          {'file': 'missing.txt', 'patch': '', 'additions': 0, 'deletions': 1},
        ]),
        '/permission' => _json(200, [?_pendingPermission]),
        '/question' || '/command' => _json(200, []),
        '/provider' => _json(200, {
          'all': [
            {
              'id': 'fixture',
              'models': {
                'offline': {'name': 'Offline fixture (no model)'},
              },
            },
          ],
          'connected': ['fixture'],
        }),
        '/agent' => _json(200, [
          {
            'name': 'fixture',
            'mode': 'primary',
            'description': 'Synthetic UI only',
            'builtIn': true,
          },
        ]),
        _ => _json(404, {'error': 'Not implemented by offline fixture'}),
      };
    }
    if (request.method == 'POST' &&
        path == '/session/$sessionId/prompt_async') {
      promptAttempts++;
      if (_busy) return _json(409, {'error': 'Fixture already busy'});
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final text = (payload['parts'] as List)
          .whereType<Map<String, dynamic>>()
          .where((part) => part['type'] == 'text')
          .map((part) => part['text'] as String)
          .join();
      acceptedPrompts++;
      final user = _message('fixture-user-$acceptedPrompts', 'user', text);
      _messages.add(user);
      _publish(user);
      _status(true);
      final assistant = _message(
        'fixture-reply-$acceptedPrompts',
        'assistant',
        '',
      );
      _messages.add(assistant);
      _publish(assistant);
      if (text.trim().toLowerCase() == 'permission') {
        _permissionAssistant = assistant;
        _timers.add(
          Timer(const Duration(milliseconds: 1600), () {
            _pendingPermission = {
              'id': 'fixture-permission-$acceptedPrompts',
              'sessionID': sessionId,
              'type': 'bash',
              'title':
                  'SYNTHETIC: permit example test output? No command runs.',
            };
            _emit('permission.updated', _pendingPermission!);
          }),
        );
      } else {
        _streamReply(assistant, reply);
      }
      return _json(204, null);
    }
    if (request.method == 'POST' &&
        _pendingPermission != null &&
        path ==
            '/session/$sessionId/permissions/${_pendingPermission!['id']}') {
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final response = payload['response'];
      if (!const ['once', 'always', 'reject'].contains(response)) {
        return _json(400, {'error': 'Invalid permission response'});
      }
      permissionReplies++;
      lastPermissionResponse = response as String;
      _pendingPermission = null;
      final assistant = _permissionAssistant!;
      _permissionAssistant = null;
      // Return acceptance first; an authoritative terminal event follows the
      // synthetic response. A reply alone must never release queued work.
      _streamReply(
        assistant,
        response == 'reject'
            ? 'Fixture permission denied. No command was run.'
            : 'Fixture permission accepted. Only example text was generated; '
                  'no command was run.',
      );
      return _json(200, true);
    }
    if (request.method == 'POST' && path == '/session/$sessionId/abort') {
      aborts++;
      for (final timer in _timers) {
        timer.cancel();
      }
      _timers.clear();
      _pendingPermission = null;
      _permissionAssistant = null;
      _status(false);
      return _json(200, true);
    }
    return _json(404, {'error': 'Not implemented by offline fixture'});
  }

  void _streamReply(Map<String, Object?> assistant, String text) {
    for (var step = 1; step <= 4; step++) {
      final currentStep = step;
      _timers.add(
        Timer(Duration(milliseconds: 800 * step), () {
          final part =
              (assistant['parts']! as List<Object?>).first!
                  as Map<String, Object?>;
          part['text'] = text.substring(0, text.length * currentStep ~/ 4);
          _publish(assistant);
          if (currentStep == 4) _status(false);
        }),
      );
    }
  }

  http.StreamedResponse _json(int status, Object? value) =>
      http.StreamedResponse(
        Stream.value(status == 204 ? <int>[] : utf8.encode(jsonEncode(value))),
        status,
        headers: {'content-type': 'application/json'},
      );

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _messages.clear();
    _pendingPermission = null;
    _permissionAssistant = null;
    unawaited(_events.close());
    super.close();
  }
}
