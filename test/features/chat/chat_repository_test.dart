import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_load_result.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/session_block_reason.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
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
    id: 'session-1',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  test(
    'permission reply replays over an in-flight transcript REST snapshot',
    () async {
      final response = Completer<http.Response>();
      final client = MockClient((_) => response.future);
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('synthetic'),
      );
      repository.activateConversation(session);
      repository.applySessionState(session.id, const SessionBusy());
      repository.applyBlocked(
        session.id,
        PendingPermissionApproval(
          sessionId: session.id,
          permissionId: 'request',
          toolType: 'bash',
          title: 'Approve',
        ),
      );
      final load = repository.load(profile, session);
      repository.applyEnvelope(
        OpenCodeEventEnvelope(
          directory: session.directory,
          payload: {
            'type': 'permission.replied',
            'properties': {'sessionID': session.id, 'requestID': 'request'},
          },
        ),
        session,
      );
      response.complete(http.Response('[]', 200));
      await load;
      final state = repository.conversationStateUpdates.value;
      expect(state.pendingApprovals, isEmpty);
      expect(state.sessionBlocks[session.id], SessionBlockReason.permission);
      expect(state.sessionStates[session.id], isA<SessionBusy>());
      client.close();
    },
  );

  test('maps text parts from user and assistant messages', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/session/session-1/message');
      expect(request.url.queryParameters['directory'], '/workspace/project');
      expect(request.url.queryParameters['limit'], '100');
      return http.Response(
        '[{"info":{"id":"user-1","role":"user",'
        '"time":{"created":1000}},"parts":['
        '{"type":"text","text":"Explain this"}]},'
        '{"info":{"id":"assistant-1","role":"assistant",'
        '"time":{"created":2000}},"parts":['
        '{"type":"reasoning","text":"Internal"},'
        '{"type":"text","text":"Here is an explanation."}]}]',
        200,
      );
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, session);

    expect(result, isA<ChatLoaded>());
    final messages = (result as ChatLoaded).messages;
    expect(messages, hasLength(2));
    expect(messages.first.role, ChatMessageRole.user);
    expect(messages.first.text, 'Explain this');
    expect(messages.last.role, ChatMessageRole.assistant);
    expect(messages.last.text, 'Here is an explanation.');
  });

  test('prepends older history and deduplicates stable message ids', () async {
    final client = MockClient((request) async {
      if (request.url.queryParameters['before'] == 'cursor-1') {
        return http.Response(
          jsonEncode([
            _messageJson('older', 500),
            _messageJson('latest', 1000),
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode([_messageJson('latest', 1000)]),
        200,
        headers: {'x-next-cursor': 'cursor-1'},
      );
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );
    repository.activateConversation(session);

    final initial = await repository.load(profile, session);
    expect((initial as ChatLoaded).hasMore, isTrue);
    final older = await repository.loadOlder(profile, session);

    expect((older as ChatOlderLoaded).hasMore, isFalse);
    expect(
      repository.historyUpdates.value.messages.map((message) => message.id),
      ['older', 'latest'],
    );
  });

  test('replays live updates and removals that race an older page', () async {
    final olderResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.queryParameters['before'] != null) {
        return olderResponse.future;
      }
      return http.Response(
        jsonEncode([_messageJson('latest', 1000)]),
        200,
        headers: {'x-next-cursor': 'cursor-1'},
      );
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );
    repository.activateConversation(session);
    await repository.load(profile, session);
    final loading = repository.loadOlder(profile, session);
    await _waitFor(() => repository.historyUpdates.value.loadingOlder);

    repository.applyEvent(
      const MessageUpdatedEvent(
        sessionId: 'session-1',
        messageId: 'latest',
        role: ConversationRole.assistant,
      ),
    );
    repository.applyEvent(
      const MessagePartUpdatedEvent(
        sessionId: 'session-1',
        part: TextMessagePart(
          id: 'part-1',
          messageId: 'latest',
          text: 'live update',
        ),
      ),
    );
    repository.applyEvent(
      const MessageRemovedEvent(sessionId: 'session-1', messageId: 'older'),
    );
    olderResponse.complete(
      http.Response(
        jsonEncode([_messageJson('older', 500), _messageJson('latest', 1000)]),
        200,
      ),
    );
    await loading;

    expect(repository.conversationUpdates.value.messages, hasLength(1));
    expect(
      repository.conversationUpdates.value.messages.single.text,
      'live update',
    );
  });

  test('discards an older page after the active session changes', () async {
    final olderResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.queryParameters['before'] != null) {
        return olderResponse.future;
      }
      return http.Response(
        jsonEncode([_messageJson('latest', 1000)]),
        200,
        headers: {'x-next-cursor': 'cursor-1'},
      );
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );
    repository.activateConversation(session);
    await repository.load(profile, session);
    final loading = repository.loadOlder(profile, session);
    await _waitFor(() => repository.historyUpdates.value.loadingOlder);

    repository.deactivateConversation();
    olderResponse.complete(
      http.Response(jsonEncode([_messageJson('older', 500)]), 200),
    );
    await loading;

    expect(repository.conversationUpdates.value.messages, isEmpty);
    expect(repository.historyUpdates.value.messages, isEmpty);
  });

  test(
    'preserves readable history and pagination after older-page failure',
    () async {
      final client = MockClient((request) async {
        if (request.url.queryParameters['before'] != null) {
          return http.Response('', 503);
        }
        return http.Response(
          jsonEncode([_messageJson('latest', 1000)]),
          200,
          headers: {'x-next-cursor': 'cursor-1'},
        );
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );
      repository.activateConversation(session);
      await repository.load(profile, session);

      final result = await repository.loadOlder(profile, session);

      expect(result, isA<ChatLoadFailed>());
      expect(repository.conversationUpdates.value.messages.single.id, 'latest');
      expect(repository.historyUpdates.value.hasMore, isTrue);
      expect(
        repository.historyUpdates.value.failure,
        ChatFailure.unexpectedResponse,
      );
    },
  );

  test('preserves the older cursor when an initial refresh fails', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode([_messageJson('latest', 1000)]),
          200,
          headers: {'x-next-cursor': 'cursor-1'},
        );
      }
      return http.Response('', 503);
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );
    repository.activateConversation(session);
    await repository.load(profile, session);

    final result = await repository.load(profile, session);

    expect(result, isA<ChatLoadFailed>());
    expect(repository.historyUpdates.value.messages.single.id, 'latest');
    expect(repository.historyUpdates.value.hasMore, isTrue);
    expect(
      repository.historyUpdates.value.failure,
      ChatFailure.unexpectedResponse,
    );
  });

  test(
    'a newer concurrent load cannot be overwritten by an older response',
    () async {
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      var requestCount = 0;
      final client = MockClient((_) {
        requestCount++;
        return requestCount == 1 ? firstResponse.future : secondResponse.future;
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final olderLoad = repository.load(profile, session);
      final newerLoad = repository.load(profile, session);
      await _waitFor(() => requestCount == 2);

      secondResponse.complete(_messageResponse('newer'));
      await newerLoad;
      firstResponse.complete(_messageResponse('older'));
      await olderLoad;

      expect(
        repository.conversationUpdates.value.messages.single.text,
        'newer',
      );
    },
  );

  test('maps rejected requests to an authorization failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, session);

    expect(result, isA<ChatLoadFailed>());
    expect((result as ChatLoadFailed).failure, ChatFailure.unauthorized);
  });

  test(
    'superseded load waits for newer snapshot instead of returning empty',
    () async {
      final first = Completer<http.Response>();
      final second = Completer<http.Response>();
      var requests = 0;
      final repository = ChatRepository(
        OpenCodeChatService(
          OpenCodeTransport(
            MockClient((_) {
              requests++;
              return requests == 1 ? first.future : second.future;
            }),
          ),
        ),
        const _PasswordStore('secret'),
      );
      var olderFinished = false;
      final older = repository.load(profile, session).then((result) {
        olderFinished = true;
        return result;
      });
      final newer = repository.load(profile, session);
      await _waitFor(() => requests == 2);
      first.complete(_messageResponse('obsolete'));
      for (var tick = 0; tick < 10; tick++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(olderFinished, isFalse);
      second.complete(_messageResponse('current'));
      final result = await older;
      await newer;
      expect((result as ChatLoaded).messages.single.text, 'current');
    },
  );

  test('maps structured tool payloads before generic bodies are bounded', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          {
            'info': {
              'id': 'assistant-1',
              'role': 'assistant',
              'time': {'created': 2000},
            },
            'parts': [
              {
                'id': 'todo-1',
                'type': 'tool',
                'tool': 'todowrite',
                'state': {
                  'status': 'completed',
                  'input': {
                    'todos': [
                      {
                        'content': '**Ship** it',
                        'status': 'completed',
                        'priority': 'high',
                      },
                    ],
                  },
                  'output':
                      '[{"content":"ignored","status":"pending","priority":"low"}]',
                },
              },
              {
                'id': 'task-1',
                'type': 'tool',
                'tool': 'task',
                'state': {
                  'status': 'completed',
                  'input': {
                    'description': 'Review changes',
                    'prompt': '**Check** the diff',
                    'subagent_type': 'reviewer',
                    'background': true,
                  },
                  'output':
                      '<task id="x" state="completed"><summary>Done</summary>'
                      '<task_result>**Looks good**\n\n```dart\n**literal**\n```</task_result></task>',
                },
              },
            ],
          },
        ]),
        200,
      );
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, session);
    final details = (result as ChatLoaded).messages.single.details;
    final todos = details.first as ChatToolDetail;
    final task = details.last as ChatToolDetail;
    expect(
      (todos.presentation as ChatTodoPresentation).items.single.content,
      '**Ship** it',
    );
    expect(
      (task.presentation as ChatTaskPresentation).description,
      'Review changes',
    );
    expect(
      (task.presentation as ChatTaskPresentation).result,
      contains('**Looks good**'),
    );
    expect(
      (task.presentation as ChatTaskPresentation).result,
      isNot(contains('<task_result>')),
    );
    expect(
      (task.presentation as ChatTaskPresentation).result,
      contains('**literal**'),
    );
  });

  test(
    'normalizes every generic OpenCode tool family without raw payloads',
    () async {
      final parts = <Map<String, dynamic>>[
        {
          'id': 'shell',
          'type': 'tool',
          'tool': 'shell',
          'state': {
            'status': 'completed',
            'input': {'command': 'pwd', 'workdir': '/workspace'},
            'output': '/workspace',
            'metadata': {'exit': 0},
          },
        },
        {
          'id': 'bash',
          'type': 'tool',
          'tool': 'bash',
          'state': {
            'status': 'completed',
            'input': {'command': 'true'},
            'output': '(no output)',
            'metadata': {'exit': 0},
          },
        },
        {
          'id': 'read',
          'type': 'tool',
          'tool': 'read',
          'state': {
            'status': 'completed',
            'input': {'filePath': '/workspace'},
            'output':
                '<path>/workspace</path>\n<type>directory</type>\n'
                '<entries>a.dart\nb.dart</entries>',
          },
        },
        {
          'id': 'glob',
          'type': 'tool',
          'tool': 'glob',
          'state': {
            'status': 'completed',
            'input': {'pattern': '*.dart', 'path': 'lib'},
            'output': '/workspace/lib/a.dart\n/workspace/lib/b.dart',
            'metadata': {'count': 2},
          },
        },
        {
          'id': 'grep',
          'type': 'tool',
          'tool': 'grep',
          'state': {
            'status': 'completed',
            'input': {'pattern': 'TODO', 'path': 'lib'},
            'output': 'Found 1 matches\nlib/a.dart:\n  Line 2: TODO',
            'metadata': {'matches': 1},
          },
        },
        {
          'id': 'edit',
          'type': 'tool',
          'tool': 'edit',
          'state': {
            'status': 'completed',
            'input': {
              'filePath': 'lib/a.dart',
              'oldString': 'a',
              'newString': 'b',
            },
            'output': 'Edit applied',
            'metadata': {'diff': '-a\n+b'},
          },
        },
        {
          'id': 'write',
          'type': 'tool',
          'tool': 'write',
          'state': {
            'status': 'completed',
            'input': {'filePath': 'lib/new.dart', 'content': 'void main() {}'},
            'output': 'Wrote file successfully.',
          },
        },
        {
          'id': 'apply_patch',
          'type': 'tool',
          'tool': 'apply_patch',
          'state': {
            'status': 'completed',
            'input': {'patchText': 'raw patch input'},
            'metadata': {
              'files': [
                {'patch': '@@ -1 +1 @@\n-old\n+new'},
              ],
            },
          },
        },
        {
          'id': 'question',
          'type': 'tool',
          'tool': 'question',
          'state': {
            'status': 'completed',
            'input': {
              'questions': [
                {
                  'question': 'Continue?',
                  'header': 'Choice',
                  'options': [
                    {'label': 'Yes', 'description': 'Continue now'},
                  ],
                },
              ],
            },
            'metadata': {
              'answers': [
                ['Yes'],
              ],
            },
          },
        },
        {
          'id': 'webfetch',
          'type': 'tool',
          'tool': 'webfetch',
          'state': {
            'status': 'completed',
            'input': {'url': 'https://example.com', 'format': 'markdown'},
            'output': '# Example',
          },
        },
        {
          'id': 'websearch',
          'type': 'tool',
          'tool': 'websearch',
          'state': {
            'status': 'completed',
            'input': {'query': 'Flutter'},
            'output': 'Flutter result',
            'metadata': {'provider': 'exa'},
          },
        },
        {
          'id': 'skill',
          'type': 'tool',
          'tool': 'skill',
          'state': {
            'status': 'completed',
            'input': {'name': 'mobile'},
            'output':
                '<skill_content name="mobile"># Instructions</skill_content>',
          },
        },
        {
          'id': 'lsp',
          'type': 'tool',
          'tool': 'lsp',
          'state': {
            'status': 'completed',
            'input': {
              'operation': 'documentSymbol',
              'filePath': 'lib/a.dart',
              'line': 1,
              'character': 1,
            },
            'output': '[{"name":"Widget","kind":5}]',
          },
        },
        {
          'id': 'plan_exit',
          'type': 'tool',
          'tool': 'plan_exit',
          'state': {
            'status': 'completed',
            'input': <String, dynamic>{},
            'output': 'Plan approved',
          },
        },
        {
          'id': 'execute',
          'type': 'tool',
          'tool': 'execute',
          'state': {
            'status': 'completed',
            'input': {'code': 'return 1'},
            'output': '{"value":1}',
          },
        },
        {
          'id': 'invalid',
          'type': 'tool',
          'tool': 'invalid',
          'state': {
            'status': 'error',
            'input': {'tool': 'broken', 'error': 'Missing argument'},
          },
        },
        {
          'id': 'plugin',
          'type': 'tool',
          'tool': 'custom_plugin',
          'state': {
            'status': 'completed',
            'input': {
              'query': 'safe query',
              'token': 'must-not-leak',
              'attachment': 'data:text/plain;base64,c2VjcmV0',
            },
            'output': 'Plugin result',
          },
        },
      ];
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'info': {
                'id': 'assistant-1',
                'role': 'assistant',
                'time': {'created': 2000},
              },
              'parts': parts,
            },
          ]),
          200,
        ),
      );
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.load(profile, session);
      final details = (result as ChatLoaded).messages.single.details
          .whereType<ChatToolDetail>();
      final presentations = {
        for (final detail in details)
          detail.tool: detail.presentation as ChatGenericToolPresentation,
      };
      String text(String tool) =>
          presentations[tool]!.blocks.map((block) => block.text).join('\n');

      expect(presentations.keys, hasLength(parts.length));
      expect(presentations['shell']!.title, r'$ pwd');
      expect(presentations['shell']!.subtitle, contains('exit: 0'));
      expect(presentations['bash']!.blocks, isEmpty);
      expect(text('read'), 'a.dart\nb.dart');
      expect(text('read'), isNot(contains('<entries>')));
      expect(text('edit'), '-a\n+b');
      expect(text('write'), 'void main() {}');
      expect(text('apply_patch'), contains('@@ -1 +1 @@'));
      expect(text('question'), contains('Continue?\n  Yes'));
      expect(text('skill'), '# Instructions');
      expect(text('skill'), isNot(contains('<skill_content')));
      expect(text('lsp'), 'Name: Widget\nKind: 5');
      expect(presentations['execute']!.blocks.first.label, 'Code');
      expect(presentations['execute']!.blocks.first.text, 'return 1');
      expect(presentations['execute']!.blocks.last.label, 'Result');
      expect(presentations['execute']!.blocks.last.text, 'Value: 1');
      expect(text('invalid'), 'Missing argument');
      expect(text('custom_plugin'), contains('Query: safe query'));
      expect(text('custom_plugin'), contains('Token: [redacted]'));
      expect(text('custom_plugin'), isNot(contains('must-not-leak')));
      expect(text('custom_plugin'), isNot(contains('data:text')));
    },
  );

  test('falls back to the output todo list when input is absent', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'info': {
              'id': 'assistant-1',
              'role': 'assistant',
              'time': {'created': 2000},
            },
            'parts': [
              {
                'id': 'todo-1',
                'type': 'tool',
                'tool': 'todowrite',
                'state': {
                  'status': 'completed',
                  'output': jsonEncode([
                    {
                      'content': 'Fallback',
                      'status': 'pending',
                      'priority': 'medium',
                    },
                  ]),
                },
              },
            ],
          },
        ]),
        200,
      ),
    );
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );
    final result = await repository.load(profile, session);
    final detail =
        (result as ChatLoaded).messages.single.details.single as ChatToolDetail;
    expect(
      (detail.presentation as ChatTodoPresentation).items.single.content,
      'Fallback',
    );
  });

  test('uses the nested task state and hides background boilerplate', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'info': {
              'id': 'assistant-1',
              'role': 'assistant',
              'time': {'created': 2000},
            },
            'parts': [
              {
                'id': 'task-1',
                'type': 'tool',
                'tool': 'task',
                'state': {
                  // The task tool itself has returned successfully, while the
                  // background subagent represented by its output is running.
                  'status': 'completed',
                  'input': {
                    'description': 'Inspect code',
                    'prompt': 'Review it',
                    'subagent_type': 'reviewer',
                    'background': true,
                  },
                  'output':
                      '<task id="child" state="running">'
                      '<summary>Background task started</summary>'
                      '<task_result>Do not poll this task.</task_result>'
                      '</task>',
                },
              },
            ],
          },
        ]),
        200,
      ),
    );
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, session);
    final detail =
        (result as ChatLoaded).messages.single.details.single as ChatToolDetail;
    final task = detail.presentation as ChatTaskPresentation;

    expect(task.status, ChatTaskStatus.running);
    expect(task.result, isNull);
    expect(task.summary, 'Background task started');
  });

  test(
    'keeps the generic tool fallback for an invalid TodoWrite schema',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'info': {
                'id': 'assistant-1',
                'role': 'assistant',
                'time': {'created': 2000},
              },
              'parts': [
                {
                  'id': 'todo-1',
                  'type': 'tool',
                  'tool': 'todowrite',
                  'state': {
                    'status': 'completed',
                    'input': {
                      'todos': [
                        {
                          'content': 'Unknown state',
                          'status': 'unexpected',
                          'priority': 'high',
                        },
                      ],
                    },
                    'output': 'not JSON',
                  },
                },
              ],
            },
          ]),
          200,
        ),
      );
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.load(profile, session);
      final detail =
          (result as ChatLoaded).messages.single.details.single
              as ChatToolDetail;

      expect(detail.presentation, isNull);
      expect(detail.input, contains('unexpected'));
    },
  );

  group('loadArtifacts', () {
    test('maps the official todo and snapshot diff schemas', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/todo')) {
          // OpenCode's `Todo` carries no id.
          return http.Response(
            '[{"content":"Ship it","status":"completed","priority":"low"}]',
            200,
          );
        }
        return http.Response(
          '[{"file":"lib/app.dart","patch":"@@ -1 +1 @@","status":"modified",'
          '"additions":2,"deletions":1}]',
          200,
        );
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.loadArtifacts(profile, session);

      expect(result, isA<Ok<SessionArtifactsReady, SessionArtifactsFailure>>());
      final artifacts =
          (result as Ok<SessionArtifactsReady, SessionArtifactsFailure>).value;
      expect(artifacts.todos.single.status, SessionTodoStatus.completed);
      expect(artifacts.todos.single.id, isNull);
      expect(artifacts.diffs.single.additions, 2);
      expect(artifacts.diffs.single.patch, '@@ -1 +1 @@');
      expect(artifacts.diffs.single.status, 'modified');
    });

    test('keeps a diff that reports only its change counters', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/todo')) {
          return http.Response('[]', 200);
        }
        return http.Response('[{"additions":3,"deletions":0}]', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.loadArtifacts(profile, session);

      final artifacts =
          (result as Ok<SessionArtifactsReady, SessionArtifactsFailure>).value;
      expect(artifacts.diffs.single.file, isEmpty);
      expect(artifacts.diffs.single.patch, isEmpty);
    });

    test('maps malformed artifacts to a typed failure', () async {
      final repository = ChatRepository(
        OpenCodeChatService(
          OpenCodeTransport(MockClient((_) async => http.Response('{}', 200))),
        ),
        const _PasswordStore('secret'),
      );

      final result = await repository.loadArtifacts(profile, session);

      expect(
        result,
        isA<Err<SessionArtifactsReady, SessionArtifactsFailure>>(),
      );
      expect(
        (result as Err<SessionArtifactsReady, SessionArtifactsFailure>).failure,
        SessionArtifactsFailure.unexpectedResponse,
      );
    });
  });

  group('sendPrompt', () {
    test('accepts a prompt on a successful response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session-1/prompt_async');
        expect(request.url.queryParameters['directory'], session.directory);
        return http.Response('', 204);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sendPrompt(
        profile,
        session,
        'Explain this',
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected send to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sendPrompt(
        profile,
        session,
        'Explain this',
      );

      expect(result, isA<Err<void, ChatFailure>>());
      expect(
        (result as Err<void, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });

    test('forwards selected execution options to the service', () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'parts': [
            {'type': 'text', 'text': 'Explain this'},
          ],
          'model': {'providerID': 'openai', 'modelID': 'gpt-5'},
          'agent': 'plan',
        });
        return http.Response('', 204);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sendPrompt(
        profile,
        session,
        'Explain this',
        executionOptions: const PromptExecutionOptions(
          modelProviderId: 'openai',
          modelId: 'gpt-5',
          agentName: 'plan',
        ),
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });
  });

  group('abortSession', () {
    test('returns the server-reported abort outcome', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session-1/abort');
        expect(request.url.queryParameters['directory'], session.directory);
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.abortSession(profile, session);

      expect(result, isA<Ok<bool, ChatFailure>>());
      expect((result as Ok<bool, ChatFailure>).value, isTrue);
    });

    test('maps a rejected abort to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.abortSession(profile, session);

      expect(result, isA<Err<bool, ChatFailure>>());
      expect(
        (result as Err<bool, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });
  });

  group('executeCommand', () {
    test('uses typed failure mapping for rejected commands', () async {
      final repository = ChatRepository(
        OpenCodeChatService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 401))),
        ),
        const _PasswordStore('secret'),
      );

      final result = await repository.executeCommand(
        profile,
        session,
        'review',
        'lib/',
      );

      expect(result, isA<Err<void, ChatFailure>>());
      expect(
        (result as Err<void, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });
  });

  group('respondToPermission', () {
    test('succeeds when the server processes the response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session-1/permissions/perm-1');
        expect(jsonDecode(request.body), {'response': 'once'});
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.respondToPermission(
        profile,
        session,
        'perm-1',
        PermissionResponse.once,
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected response to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.respondToPermission(
        profile,
        session,
        'perm-1',
        PermissionResponse.reject,
      );

      expect(result, isA<Err<void, ChatFailure>>());
      expect(
        (result as Err<void, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });
  });

  group('replyToQuestion', () {
    test('sends every question\'s answers in order', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/question/que-1/reply');
        expect(jsonDecode(request.body), {
          'answers': [
            ['Postgres'],
          ],
        });
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.replyToQuestion(
        profile,
        session,
        'que-1',
        [
          ['Postgres'],
        ],
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected reply to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.replyToQuestion(
        profile,
        session,
        'que-1',
        [
          ['Postgres'],
        ],
      );

      expect(result, isA<Err<void, ChatFailure>>());
    });
  });

  group('rejectQuestion', () {
    test('succeeds when the server rejects the question', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/question/que-1/reject');
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.rejectQuestion(profile, session, 'que-1');

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected reject call to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.rejectQuestion(profile, session, 'que-1');

      expect(result, isA<Err<void, ChatFailure>>());
    });
  });

  group('sessionStatus', () {
    for (final backend in AgentBackend.values) {
      test('missing status respects ${backend.name} contract', () async {
        final client = MockClient((_) async => http.Response('{}', 200));
        addTearDown(client.close);
        final repository = ChatRepository(
          OpenCodeChatService(OpenCodeTransport(client)),
          const _PasswordStore('synthetic'),
        );
        final active = ServerProfile(
          origin: profile.origin,
          username: profile.username,
          backend: backend,
        );
        final result = await repository.sessionStatus(active, session);
        final native =
            backend == AgentBackend.gatewayClaude ||
            backend == AgentBackend.gatewayCodex;
        expect(
          (result as Ok<SessionExecutionState, ChatFailure>).value,
          native ? isA<SessionExecutionUnknown>() : isA<SessionIdle>(),
        );
      });
    }
    test('maps this session\'s entry from the status response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/session/status');
        expect(request.url.queryParameters['directory'], session.directory);
        return http.Response(
          '{"session-1":{"type":"busy"},"session-2":{"type":"idle"}}',
          200,
        );
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sessionStatus(profile, session);

      expect(result, isA<Ok<SessionExecutionState, ChatFailure>>());
      expect(
        (result as Ok<SessionExecutionState, ChatFailure>).value,
        isA<SessionBusy>(),
      );
    });

    test(
      'defaults to idle when the session is absent from the response',
      () async {
        final client = MockClient((_) async => http.Response('{}', 200));
        final repository = ChatRepository(
          OpenCodeChatService(OpenCodeTransport(client)),
          const _PasswordStore('secret'),
        );

        final result = await repository.sessionStatus(profile, session);

        expect(result, isA<Ok<SessionExecutionState, ChatFailure>>());
        expect(
          (result as Ok<SessionExecutionState, ChatFailure>).value,
          isA<SessionIdle>(),
        );
      },
    );

    test(
      'maps a rejected status request to an authorization failure',
      () async {
        final client = MockClient((_) async => http.Response('', 401));
        final repository = ChatRepository(
          OpenCodeChatService(OpenCodeTransport(client)),
          const _PasswordStore('secret'),
        );

        final result = await repository.sessionStatus(profile, session);

        expect(result, isA<Err<SessionExecutionState, ChatFailure>>());
        expect(
          (result as Err<SessionExecutionState, ChatFailure>).failure,
          ChatFailure.unauthorized,
        );
      },
    );

    test('maps a malformed status response to an unexpected-response '
        'failure', () async {
      final client = MockClient((_) async => http.Response('not-json', 200));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sessionStatus(profile, session);

      expect(result, isA<Err<SessionExecutionState, ChatFailure>>());
      expect(
        (result as Err<SessionExecutionState, ChatFailure>).failure,
        ChatFailure.unexpectedResponse,
      );
    });
  });
}

http.Response _messageResponse(String text) => http.Response(
  jsonEncode([
    {
      'info': {
        'id': text,
        'role': 'assistant',
        'time': {'created': 2000},
      },
      'parts': [
        {'type': 'text', 'text': text},
      ],
    },
  ]),
  200,
);

Map<String, dynamic> _messageJson(String id, int created) => {
  'info': {
    'id': id,
    'role': 'assistant',
    'time': {'created': created},
  },
  'parts': [
    {'type': 'text', 'text': id},
  ],
};

Future<void> _waitFor(bool Function() condition) async {
  while (!condition()) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore(this._password);

  final String? _password;

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => _password;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
