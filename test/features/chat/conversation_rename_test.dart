import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/sessions/sessions.dart';

class _Credentials implements CredentialsStore {
  const _Credentials();
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
  @override
  Future<void> clearPassword(String profileId) async {}
}

class _Picker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session-1',
    projectId: 'project-1',
    directory: '/fixture',
    title: 'Original',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    parentId: 'parent',
    changedFiles: 2,
    additions: 3,
    deletions: 1,
    modelProviderId: 'provider',
    modelId: 'model',
    agentName: 'agent',
  );
  late ConversationViewModel model;
  late QueueSendCoordinator coordinator;
  late Completer<http.Response> response;
  late List<http.Request> mutations;
  setUp(() {
    response = Completer<http.Response>();
    mutations = [];
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        mutations.add(request);
        return response.future;
      }
      if (request.url.path.endsWith('/status')) {
        return http.Response('{"session-1":{"type":"busy"}}', 200);
      }
      return http.Response('[]', 200);
    });
    final transport = OpenCodeTransport(client);
    final chat = ChatRepository(
      OpenCodeChatService(transport),
      const _Credentials(),
    );
    final queue = QueuePromptsRepository(InMemoryQueuePromptsDao());
    coordinator = QueueSendCoordinator(
      queueRepository: queue,
      chatRepository: chat,
      eventService: OpenCodeEventService(transport),
      credentialsStore: const _Credentials(),
    );
    model = ConversationViewModel(
      chatRepository: chat,
      sessionsRepository: SessionsRepository(
        OpenCodeSessionsService(transport),
        const _Credentials(),
      ),
      queueRepositoryProvider: () async => queue,
      queueCoordinatorProvider: () async => coordinator,
      attachmentPicker: _Picker(),
    );
  });
  tearDown(() async {
    await model.dispose();
    await coordinator.dispose();
  });

  test(
    'rename trims title and preserves metadata and original route ownership',
    () async {
      await model.open(profile, session);
      expect(model.sessionMetadata.value, same(session));
      final pending = model.renameSession('  Renamed  ');
      await Future<void>.delayed(Duration.zero);
      expect(model.renamingSession.value, isTrue);
      expect(jsonDecode(mutations.single.body), {'title': 'Renamed'});
      response.complete(http.Response('{}', 200));
      expect(await pending, isA<Ok<void, SessionsFailure>>());
      final updated = model.sessionMetadata.value!;
      expect(updated.title, 'Renamed');
      expect(updated.parentId, session.parentId);
      expect(updated.modelId, session.modelId);
      expect(updated.changedFiles, session.changedFiles);
      expect(model.renamingSession.value, isFalse);
      await model.leaveSession(session);
      expect(model.sessionMetadata.value, isNull);
    },
  );

  test(
    'invalid, unchanged, unopened and disposed renames never issue requests',
    () async {
      expect(await model.renameSession('Name'), isNull);
      await model.open(profile, session);
      expect(
        await model.renameSession('   '),
        isA<Err<void, SessionsFailure>>(),
      );
      expect(
        await model.renameSession('x' * 257),
        isA<Err<void, SessionsFailure>>(),
      );
      expect(
        await model.renameSession(' Original '),
        isA<Ok<void, SessionsFailure>>(),
      );
      await model.dispose();
      expect(await model.renameSession('Name'), isNull);
      expect(mutations, isEmpty);
    },
  );

  test(
    'failure preserves metadata and allows retry without concurrent requests',
    () async {
      await model.open(profile, session);
      final pending = model.renameSession('Renamed');
      expect(await model.renameSession('Concurrent'), isNull);
      response.complete(http.Response('', 401));
      expect(await pending, isA<Err<void, SessionsFailure>>());
      expect(model.sessionMetadata.value, same(session));
      expect(model.renamingSession.value, isFalse);
      response = Completer<http.Response>()..complete(http.Response('{}', 200));
      expect(
        await model.renameSession('Retry'),
        isA<Ok<void, SessionsFailure>>(),
      );
      expect(mutations, hasLength(2));
    },
  );

  test('unadvertised rename capability never issues a request', () async {
    await model.open(
      ServerProfile(
        origin: profile.origin,
        username: profile.username,
        backend: AgentBackend.gatewayCodex,
        capabilities: BackendCapabilities.unavailable,
      ),
      session,
    );
    expect(await model.renameSession('Unsupported'), isNull);
    expect(mutations, isEmpty);
    expect(model.sessionMetadata.value, same(session));
  });

  test(
    'stale route session or profile cannot rename the active owner',
    () async {
      await model.open(profile, session);
      expect(
        await model.renameSession(
          'Wrong session',
          expectedSession: session.withTitle('Other route'),
          expectedProfile: profile,
        ),
        isNull,
      );
      expect(
        await model.renameSession(
          'Wrong profile',
          expectedSession: session,
          expectedProfile: ServerProfile(
            origin: profile.origin,
            username: profile.username,
          ),
        ),
        isNull,
      );
      expect(mutations, isEmpty);
      response.complete(http.Response('{}', 200));
      expect(
        await model.renameSession(
          'Correct scope',
          expectedSession: session,
          expectedProfile: profile,
        ),
        isA<Ok<void, SessionsFailure>>(),
      );
    },
  );

  for (final leave in [false, true]) {
    test('late rename cannot update a changed owner leave=$leave', () async {
      await model.open(profile, session);
      final pending = model.renameSession('Old completion');
      await Future<void>.delayed(Duration.zero);
      if (leave) {
        await model.leave();
      } else {
        await model.open(
          ServerProfile(
            origin: Uri.parse('http://10.80.0.2:4096'),
            username: 'opencode',
          ),
          session,
        );
      }
      response.complete(http.Response('{}', 200));
      await pending;
      expect(model.sessionMetadata.value?.title, leave ? null : 'Original');
      expect(model.renamingSession.value, isFalse);
    });
  }

  test(
    'dispose during rename ignores completion without notifier errors',
    () async {
      await model.open(profile, session);
      final pending = model.renameSession('Later');
      await model.dispose();
      response.complete(http.Response('{}', 200));
      await pending;
    },
  );
}
