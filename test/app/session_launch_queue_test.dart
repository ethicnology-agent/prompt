import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/data/local/prompt_local_storage_handle.dart';
import 'package:prompt/data/local/prompt_database.dart' as db;
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/chat/chat.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unavailable reconciliation fails closed on subsequent save attempts',
    () async {
      final dao = _CommitThenFailDao(reconciliationUnavailable: true);
      final dependencies = _dependencies(dao);
      addTearDown(dependencies.dispose);
      final launch = SessionLaunch(
        profile: _profile(AgentBackend.gatewayCodex),
        session: _session(),
        draft: 'Only once',
        options: const PromptExecutionOptions(),
        submitDraft: true,
      );
      expect(await dependencies.queueLaunchDraft(launch), isFalse);
      expect(await dependencies.queueLaunchDraft(launch), isFalse);
      expect(dao.calls, 1);
    },
  );

  test(
    'commit then error reconciles exact first prompt without duplicate',
    () async {
      final dao = _CommitThenFailDao();
      final dependencies = _dependencies(dao);
      addTearDown(dependencies.dispose);
      final launch = SessionLaunch(
        profile: _profile(AgentBackend.gatewayCodex),
        session: _session(),
        draft: 'Only once',
        options: const PromptExecutionOptions(),
        submitDraft: true,
      );
      expect(await dependencies.queueLaunchDraft(launch), isTrue);
      expect(await dependencies.queueLaunchDraft(launch), isTrue);
      expect(dao.calls, 1);
    },
  );

  test(
    'image-only creation is durable before releasing selection and deduplicates released buffers',
    () async {
      final dao = InMemoryQueuePromptsDao();
      final dependencies = _dependencies(dao);
      addTearDown(dependencies.dispose);
      final attachment = PromptAttachment(
        name: 'fixture.png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final launch = SessionLaunch(
        profile: _profile(AgentBackend.gatewayClaude),
        session: _session(),
        draft: '',
        options: const PromptExecutionOptions(),
        submitDraft: true,
        attachments: [attachment],
      );
      expect(await dependencies.queueLaunchDraft(launch), isTrue);
      expect(attachment.isReleased, isTrue);
      expect(await dependencies.queueLaunchDraft(launch), isTrue);
      final queue = await QueuePromptsRepository(
        dao,
      ).watchQueue(profile: launch.profile, session: launch.session).first;
      expect(queue, hasLength(1));
      expect(queue.single.attachments.single.bytes, [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    },
  );

  test('known storage opening failure permits same launch retry', () async {
    final dao = InMemoryQueuePromptsDao();
    var opens = 0;
    final dependencies = AppDependencies.create(
      httpClient: MockClient((_) async => throw StateError('No network')),
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.light),
      openStorage: () async {
        if (++opens == 1) throw Exception('Synthetic opening failure');
        return PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: dao,
          reviewHistory: InMemoryReviewHistoryStore(),
          closeHandle: () async {},
        );
      },
    );
    addTearDown(dependencies.dispose);
    final launch = SessionLaunch(
      profile: _profile(AgentBackend.gatewayCodex),
      session: _session(),
      draft: 'Retained',
      options: const PromptExecutionOptions(),
      submitDraft: true,
    );
    expect(await dependencies.queueLaunchDraft(launch), isFalse);
    expect(await dependencies.queueLaunchDraft(launch), isTrue);
    expect(
      await QueuePromptsRepository(
        dao,
      ).watchQueue(profile: launch.profile, session: launch.session).first,
      hasLength(1),
    );
  });

  test(
    'storage rejection does not accept or discard the launch draft',
    () async {
      final dependencies = AppDependencies.create(
        httpClient: MockClient(
          (_) async => throw StateError('No network expected'),
        ),
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.light),
        openStorage: () async =>
            throw Exception('Synthetic unavailable storage'),
      );
      addTearDown(dependencies.dispose);
      final launch = SessionLaunch(
        profile: _profile(AgentBackend.gatewayCodex),
        session: _session(),
        draft: 'Retained draft',
        options: const PromptExecutionOptions(),
        submitDraft: true,
      );
      expect(await dependencies.queueLaunchDraft(launch), isFalse);
      expect(launch.draft, 'Retained draft');
    },
  );

  test(
    'explicit launch queues target once without touching source queue',
    () async {
      final dao = InMemoryQueuePromptsDao();
      final dependencies = _dependencies(dao);
      addTearDown(dependencies.dispose);
      final repository = QueuePromptsRepository(dao);
      final source = _profile(AgentBackend.gatewayCodex);
      final target = _profile(AgentBackend.gatewayClaude);
      final session = _session();
      await repository.enqueue(
        profile: source,
        session: session,
        promptText: 'Existing queue',
      );
      const options = PromptExecutionOptions(
        modelProviderId: 'claude',
        modelId: 'configured',
      );
      final launch = SessionLaunch(
        profile: target,
        session: session,
        draft: 'First prompt',
        options: options,
        submitDraft: true,
      );
      expect(
        await Future.wait([
          dependencies.queueLaunchDraft(launch),
          dependencies.queueLaunchDraft(launch),
        ]),
        [true, true],
      );
      expect(await dependencies.queueLaunchDraft(launch), isTrue);
      final targetQueue = await repository
          .watchQueue(profile: target, session: session)
          .first;
      expect(targetQueue, hasLength(1));
      expect(targetQueue.single.promptText, 'First prompt');
      expect(targetQueue.single.executionOptions.modelProviderId, 'claude');
      final sourceQueue = await repository
          .watchQueue(profile: source, session: session)
          .first;
      expect(sourceQueue, hasLength(1));
      expect(sourceQueue.single.promptText, 'Existing queue');
      expect(sourceQueue.single.state, QueuedPromptState.queued);
    },
  );

  test('creation without explicit send leaves queue empty', () async {
    final dao = InMemoryQueuePromptsDao();
    final dependencies = _dependencies(dao);
    addTearDown(dependencies.dispose);
    final launch = SessionLaunch(
      profile: _profile(AgentBackend.gatewayCodex),
      session: _session(),
      draft: 'Draft only',
      options: const PromptExecutionOptions(),
    );
    expect(await dependencies.queueLaunchDraft(launch), isFalse);
    expect(
      await QueuePromptsRepository(
        dao,
      ).watchQueue(profile: launch.profile, session: launch.session).first,
      isEmpty,
    );
  });
}

class _CommitThenFailDao extends InMemoryQueuePromptsDao {
  _CommitThenFailDao({this.reconciliationUnavailable = false});
  final bool reconciliationUnavailable;
  int calls = 0;
  @override
  Stream<List<db.QueuedPrompt>> watchQueue({
    required String serverProfileId,
    required String sessionId,
  }) {
    if (reconciliationUnavailable) {
      return Stream.error(Exception('Synthetic unavailable read'));
    }
    return super.watchQueue(
      serverProfileId: serverProfileId,
      sessionId: sessionId,
    );
  }

  @override
  Future<db.QueuedPrompt> enqueue({
    required String id,
    required String serverProfileId,
    required String sessionId,
    required String directory,
    required String promptText,
    QueuedOperationType operationType = QueuedOperationType.prompt,
    String? commandName,
    List<QueuedAttachment> attachments = const [],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
    required DateTime now,
  }) async {
    calls++;
    await super.enqueue(
      id: id,
      serverProfileId: serverProfileId,
      sessionId: sessionId,
      directory: directory,
      promptText: promptText,
      operationType: operationType,
      commandName: commandName,
      attachments: attachments,
      executionOptions: executionOptions,
      now: now,
    );
    throw Exception('Synthetic failure after commit');
  }
}

AppDependencies _dependencies(InMemoryQueuePromptsDao dao) =>
    AppDependencies.create(
      httpClient: MockClient(
        (_) async => throw StateError('Enqueue must not use the network'),
      ),
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.light),
      openStorage: () async => PromptLocalStorageHandle(
        serverProfiles: InMemoryServerProfileStore(),
        queuedPrompts: dao,
        reviewHistory: InMemoryReviewHistoryStore(),
        closeHandle: () async {},
      ),
    );

ServerProfile _profile(AgentBackend backend) => ServerProfile(
  origin: Uri.parse('http://10.0.0.5:4097'),
  username: 'operator',
  backend: backend,
);
OpenCodeSession _session() => OpenCodeSession(
  id: 'isolated-session',
  projectId: 'root',
  directory: '/workspace',
  title: 'New',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
