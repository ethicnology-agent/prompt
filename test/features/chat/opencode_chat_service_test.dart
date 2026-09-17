import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session 1',
    projectId: 'project-1',
    directory: '/workspace/my project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  test(
    'captures the V1 pagination cursor and sends it unchanged next time',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '[{"info":{"id":"message-${requests.length}","role":"user",'
          '"time":{"created":1000}},"parts":[]}]',
          200,
          headers: requests.length == 1
              ? {'x-next-cursor': 'opaque cursor/?'}
              : const {},
        );
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final first = await service.listMessages(profile, 'secret', session);
      final second = await service.listMessages(
        profile,
        'secret',
        session,
        before: first.nextCursor,
      );

      expect(first.nextCursor, 'opaque cursor/?');
      expect(requests.first.url.queryParameters, {
        'directory': session.directory,
        'limit': '100',
      });
      expect(requests[1].url.queryParameters['before'], 'opaque cursor/?');
      expect(requests[1].url.queryParameters['limit'], '100');
      expect(second.nextCursor, isNull);
    },
  );

  test('uses a Link next cursor when the cursor header is absent', () async {
    final client = MockClient(
      (request) async => http.Response(
        '[]',
        200,
        headers: {
          'link':
              '<https://server.test/session/session%201/message?before=link-cursor>; rel="next"',
        },
      ),
    );
    final service = OpenCodeChatService(OpenCodeTransport(client));

    final page = await service.listMessages(profile, 'secret', session);

    expect(page.nextCursor, 'link-cursor');
  });

  group('sendPromptAsync', () {
    test('native gateway carries the durable operation identity', () async {
      http.Request? captured;
      final service = OpenCodeChatService(
        OpenCodeTransport(
          MockClient((request) async {
            captured = request;
            return http.Response('', 204);
          }),
        ),
      );
      for (final backend in [
        AgentBackend.gatewayClaude,
        AgentBackend.gatewayCodex,
      ]) {
        await service.sendPromptAsync(
          ServerProfile(
            origin: profile.origin,
            username: 'prompt',
            backend: backend,
          ),
          'secret',
          session,
          'Hello',
          operationId: 'durable-operation-1',
        );
        expect(jsonDecode(captured!.body)['messageID'], 'durable-operation-1');
        expect(
          captured!.url.path,
          startsWith('/prompt/${backend.engine}/session/'),
        );
      }
      await service.sendPromptAsync(
        profile,
        'secret',
        session,
        'Hello',
        operationId: 'durable-operation-1',
      );
      expect(
        jsonDecode(captured!.body).containsKey('messageID'),
        isFalse,
        reason: 'Direct OpenCode wire format stays unchanged.',
      );
    });
    test('sends a Basic-authorized request with an encoded path, '
        'directory query, and a text part body', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await service.sendPromptAsync(profile, 'secret', session, 'Hello');

      final request = captured!;
      expect(request.method, 'POST');
      expect(request.url.path, '/session/session%201/prompt_async');
      expect(request.url.queryParameters['directory'], session.directory);
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
      );
      expect(jsonDecode(request.body), {
        'parts': [
          {'type': 'text', 'text': 'Hello'},
        ],
      });
    });

    test('accepts every successful OpenCode response status', () async {
      final statuses = [200, 202, 204];
      for (final status in statuses) {
        final client = MockClient((_) async => http.Response('{}', status));
        final service = OpenCodeChatService(OpenCodeTransport(client));

        await expectLater(
          service.sendPromptAsync(profile, 'secret', session, 'Hello'),
          completes,
        );
      }
    });

    test(
      'includes selected model and agent with OpenCode API field names',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        });
        final service = OpenCodeChatService(OpenCodeTransport(client));

        await service.sendPromptAsync(
          profile,
          'secret',
          session,
          'Hello',
          executionOptions: const PromptExecutionOptions(
            modelProviderId: 'anthropic',
            modelId: 'claude-sonnet-4',
            agentName: 'build',
          ),
        );

        expect(jsonDecode(captured!.body), {
          'parts': [
            {'type': 'text', 'text': 'Hello'},
          ],
          'model': {'providerID': 'anthropic', 'modelID': 'claude-sonnet-4'},
          'agent': 'build',
        });
      },
    );

    test('sends attachments as OpenCode file parts with data URLs', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await service.sendPromptAsync(
        profile,
        'secret',
        session,
        'Read this',
        attachments: [
          QueuedAttachment(
            name: 'notes.txt',
            mediaType: 'text/plain',
            bytes: Uint8List.fromList([104, 105]),
          ),
        ],
      );

      expect(jsonDecode(captured!.body), {
        'parts': [
          {'type': 'text', 'text': 'Read this'},
          {
            'type': 'file',
            'mime': 'text/plain',
            'filename': 'notes.txt',
            'url': 'data:text/plain;base64,aGk=',
          },
        ],
      });
    });

    test('rejects a non-success status', () async {
      final client = MockClient((_) async => http.Response('', 400));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.sendPromptAsync(profile, 'secret', session, 'Hello'),
        throwsA(isA<OpenCodeHttpFailure>()),
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.sendPromptAsync(profile, 'secret', session, 'Hello'),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('session artifacts', () {
    test('gets todos and an optionally message-scoped diff', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/todo')) {
          return http.Response(
            '[{"id":"todo-1","content":"Review","status":"in_progress","priority":"high"}]',
            200,
          );
        }
        return http.Response(
          '[{"file":"lib/a.dart","before":"old","after":"new","additions":1,"deletions":1}]',
          200,
        );
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final todos = await service.listTodos(profile, 'secret', session);
      final diffs = await service.listDiffs(
        profile,
        'secret',
        session,
        messageId: 'message 1',
      );

      expect(todos.single.content, 'Review');
      expect(diffs.single.file, 'lib/a.dart');
      expect(requests[0].url.path, '/session/session%201/todo');
      expect(requests[1].url.path, '/session/session%201/diff');
      expect(requests[1].url.queryParameters['messageID'], 'message 1');
      expect(requests[0].url.queryParameters, isEmpty);
    });

    test('rejects malformed artifact responses', () async {
      final service = OpenCodeChatService(
        OpenCodeTransport(MockClient((_) async => http.Response('{}', 200))),
      );

      await expectLater(
        service.listTodos(profile, 'secret', session),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('abortSession', () {
    test(
      'posts to the abort endpoint with authorization and directory',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response('true', 200);
        });
        final service = OpenCodeChatService(OpenCodeTransport(client));

        final aborted = await service.abortSession(profile, 'secret', session);

        expect(aborted, isTrue);
        final request = captured!;
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session%201/abort');
        expect(request.url.queryParameters['directory'], session.directory);
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
        );
      },
    );

    test('returns false when the server reports nothing was aborted', () async {
      final client = MockClient((_) async => http.Response('false', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final aborted = await service.abortSession(profile, 'secret', session);

      expect(aborted, isFalse);
    });

    test('rejects a non-boolean response body', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.abortSession(profile, 'secret', session),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.abortSession(profile, 'secret', session),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('executeCommand', () {
    test('posts the official command body with execution defaults', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await service.executeCommand(
        profile,
        'secret',
        session,
        'review',
        'lib/',
        executionOptions: const PromptExecutionOptions(
          modelProviderId: 'anthropic',
          modelId: 'claude-sonnet-4',
          agentName: 'build',
        ),
      );

      final request = captured!;
      expect(request.method, 'POST');
      expect(request.url.path, '/session/session%201/command');
      expect(request.url.queryParameters['directory'], session.directory);
      expect(jsonDecode(request.body), {
        'command': 'review',
        'arguments': 'lib/',
        'agent': 'build',
        'model': {'providerID': 'anthropic', 'modelID': 'claude-sonnet-4'},
      });
    });

    test('rejects a non-success command response', () async {
      final service = OpenCodeChatService(
        OpenCodeTransport(MockClient((_) async => http.Response('', 409))),
      );

      await expectLater(
        service.executeCommand(profile, 'secret', session, 'review', ''),
        throwsA(isA<OpenCodeHttpFailure>()),
      );
    });
  });

  group('respondToPermission', () {
    test(
      'posts the chosen response with authorization and directory',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response('true', 200);
        });
        final service = OpenCodeChatService(OpenCodeTransport(client));

        final processed = await service.respondToPermission(
          profile,
          'secret',
          session,
          'perm 1',
          PermissionResponse.always,
        );

        expect(processed, isTrue);
        final request = captured!;
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session%201/permissions/perm%201');
        expect(request.url.queryParameters['directory'], session.directory);
        expect(jsonDecode(request.body), {'response': 'always'});
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
        );
      },
    );

    test('sends the wire value for every PermissionResponse', () async {
      for (final entry in const {
        PermissionResponse.once: 'once',
        PermissionResponse.always: 'always',
        PermissionResponse.reject: 'reject',
      }.entries) {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response('true', 200);
        });
        final service = OpenCodeChatService(OpenCodeTransport(client));

        await service.respondToPermission(
          profile,
          'secret',
          session,
          'perm-1',
          entry.key,
        );

        expect(jsonDecode(captured!.body), {'response': entry.value});
      }
    });

    test('rejects a non-boolean response body', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.respondToPermission(
          profile,
          'secret',
          session,
          'perm-1',
          PermissionResponse.once,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.respondToPermission(
          profile,
          'secret',
          session,
          'perm-1',
          PermissionResponse.once,
        ),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('replyToQuestion', () {
    test('posts the answers with authorization and directory', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('true', 200);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final processed = await service.replyToQuestion(
        profile,
        'secret',
        session,
        'que 1',
        [
          ['Postgres'],
          ['A free-text answer'],
        ],
      );

      expect(processed, isTrue);
      final request = captured!;
      expect(request.method, 'POST');
      expect(request.url.path, '/question/que%201/reply');
      expect(request.url.queryParameters['directory'], session.directory);
      expect(jsonDecode(request.body), {
        'answers': [
          ['Postgres'],
          ['A free-text answer'],
        ],
      });
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.replyToQuestion(profile, 'secret', session, 'que-1', [
          ['Postgres'],
        ]),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('rejectQuestion', () {
    test(
      'posts to the reject endpoint with authorization and directory',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response('true', 200);
        });
        final service = OpenCodeChatService(OpenCodeTransport(client));

        final processed = await service.rejectQuestion(
          profile,
          'secret',
          session,
          'que 1',
        );

        expect(processed, isTrue);
        final request = captured!;
        expect(request.method, 'POST');
        expect(request.url.path, '/question/que%201/reject');
        expect(request.url.queryParameters['directory'], session.directory);
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
        );
      },
    );

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.rejectQuestion(profile, 'secret', session, 'que-1'),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('fetchSessionStatuses', () {
    test('gets the status endpoint with authorization and directory', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await service.fetchSessionStatuses(
        profile,
        'secret',
        '/workspace/my project',
      );

      final request = captured!;
      expect(request.method, 'GET');
      expect(request.url.path, '/session/status');
      expect(request.url.queryParameters['directory'], '/workspace/my project');
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
      );
    });

    test('maps idle, busy, and retry status entries', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'idle-session': {'type': 'idle'},
            'busy-session': {'type': 'busy'},
            'retrying-session': {
              'type': 'retry',
              'attempt': 2,
              'message': 'rate limited',
              'next': 5000,
            },
          }),
          200,
        ),
      );
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final statuses = await service.fetchSessionStatuses(
        profile,
        'secret',
        '/workspace/project',
      );

      expect(statuses['idle-session'], isA<SessionIdle>());
      expect(statuses['busy-session'], isA<SessionBusy>());
      final retrying = statuses['retrying-session'] as SessionRetrying;
      expect(retrying.attempt, 2);
      expect(retrying.message, 'rate limited');
      expect(retrying.nextAttemptAtMillis, 5000);
    });

    test('rejects a response that is not a JSON object', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.fetchSessionStatuses(profile, 'secret', '/workspace/project'),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps an unrecognized status entry to typed unknown', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'session-1': {'type': 'unknown'},
          }),
          200,
        ),
      );
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final statuses = await service.fetchSessionStatuses(
        profile,
        'secret',
        '/workspace/project',
      );
      expect(statuses['session-1'], isA<SessionExecutionUnknown>());
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.fetchSessionStatuses(profile, 'secret', '/workspace/project'),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });
}
