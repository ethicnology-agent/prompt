import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/data/local/prompt_database.dart' show PromptDatabase;
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/data/in_memory_queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_repository.dart';
import 'package:prompt/features/queue/domain/queue_failure.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

/// Lets a Drift `watch()` stream's `Timer.run`-scheduled re-query and
/// notification reach this test's listener before the next assertion.
/// `InMemoryQueuePromptsDao`'s stream is synchronous, so this is a no-op
/// delay for it, which is harmless.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // Both backends must satisfy `QueuePromptsRepository` identically:
  // `DriftQueuePromptsDao` is Android/Linux's encrypted, on-disk storage,
  // and `InMemoryQueuePromptsDao` is Web's memory-only default. Running
  // the exact same test bodies against both is what actually guarantees
  // Web never diverges from the state machine Android/Linux enforces.
  group('DriftQueuePromptsDao', () {
    late PromptDatabase database;
    _runQueuePromptsRepositoryTests(
      createDao: () {
        database = PromptDatabase.forTesting(NativeDatabase.memory());
        return DriftQueuePromptsDao(database);
      },
      tearDownDao: () => database.close(),
    );
  });

  group('InMemoryQueuePromptsDao', () {
    _runQueuePromptsRepositoryTests(createDao: () => InMemoryQueuePromptsDao());
  });

  test('migrates version 1 queued prompts without execution options', () async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'prompt-queue-migration-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    final sqlite = sqlite3lib.sqlite3.open(file.path);
    sqlite.execute('''
      CREATE TABLE server_profiles (
        id TEXT NOT NULL PRIMARY KEY,
        origin TEXT NOT NULL,
        username TEXT NULL,
        last_accessed_at_millis INTEGER NOT NULL
      );
      INSERT INTO server_profiles VALUES ('profile', 'http://10.0.0.1:4096', NULL, 1);
      CREATE TABLE queued_prompts (
        id TEXT NOT NULL PRIMARY KEY,
        server_profile_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        directory TEXT NOT NULL,
        position INTEGER NOT NULL,
        prompt_text TEXT NOT NULL,
        state TEXT NOT NULL,
        pause_reason TEXT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at_millis INTEGER NOT NULL,
        updated_at_millis INTEGER NOT NULL,
        sending_started_at_millis INTEGER NULL,
        acknowledged_at_millis INTEGER NULL,
        UNIQUE (server_profile_id, session_id, position)
      );
      INSERT INTO queued_prompts VALUES (
        'old-prompt', 'profile', 'session', '/workspace', 0, 'existing',
        'queued', NULL, 0, 1, 1, NULL, NULL
      );
      PRAGMA user_version = 1;
    ''');
    sqlite.close();
    final database = PromptDatabase.forTesting(NativeDatabase(file));

    final row = await (database.select(
      database.queuedPrompts,
    )..where((table) => table.id.equals('old-prompt'))).getSingle();

    expect(row.modelProviderId, isNull);
    expect(row.modelId, isNull);
    expect(row.agentName, isNull);
    await database.close();
    await file.delete();
  });
}

void _runQueuePromptsRepositoryTests({
  required QueuePromptsDao Function() createDao,
  Future<void> Function()? tearDownDao,
}) {
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
  final otherSession = OpenCodeSession(
    id: 'session-2',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'Another session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  late QueuePromptsRepository repository;
  var nextId = 0;

  setUp(() {
    nextId = 0;
    repository = QueuePromptsRepository(
      createDao(),
      idGenerator: () => 'prompt-${nextId++}',
    );
  });

  tearDown(() async {
    await tearDownDao?.call();
  });

  Future<QueuedPrompt> enqueue(
    String text, {
    OpenCodeSession? forSession,
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    final result = await repository.enqueue(
      profile: profile,
      session: forSession ?? session,
      promptText: text,
      executionOptions: executionOptions,
    );
    expect(result, isA<Ok<QueuedPrompt, QueueFailure>>());
    return (result as Ok<QueuedPrompt, QueueFailure>).value;
  }

  test(
    'merge preserves target options and publishes no intermediate duplicate',
    () async {
      const options = PromptExecutionOptions(
        modelProviderId: 'local',
        modelId: 'model',
      );
      final target = await enqueue('first', executionOptions: options);
      final source = await enqueue('second');
      final snapshots = <List<QueuedPrompt>>[];
      final subscription = repository
          .watchQueue(profile: profile, session: session)
          .listen(snapshots.add);
      addTearDown(subscription.cancel);
      await _settle();
      final result = await repository.merge(
        targetId: target.id,
        sourceId: source.id,
      );
      expect(result, isA<Ok<QueuedPrompt, QueueFailure>>());
      await _settle();
      expect(snapshots.last.single.promptText, 'first\n\nsecond');
      final restored = snapshots.last.single.executionOptions;
      expect(restored.modelProviderId, options.modelProviderId);
      expect(restored.modelId, options.modelId);
      expect(restored.agentName, options.agentName);
      expect(restored.reasoningEffort, options.reasoningEffort);
      expect(
        snapshots.any(
          (rows) => rows.length == 2 && rows.first.promptText != 'first',
        ),
        isFalse,
      );
      expect(
        await repository.merge(targetId: target.id, sourceId: source.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        (await repository.watchQueue(profile: profile, session: session).first)
            .single
            .promptText,
        'first\n\nsecond',
      );
    },
  );

  test(
    'merge rejects nonadjacent, cross-session, sending and deleted rows',
    () async {
      final first = await enqueue('first');
      final middle = await enqueue('middle');
      final last = await enqueue('last');
      final other = await enqueue('other', forSession: otherSession);
      for (final target in [first.id, other.id, last.id]) {
        expect(
          await repository.merge(targetId: target, sourceId: last.id),
          isA<Err<QueuedPrompt, QueueFailure>>(),
        );
      }
      await repository.markSending(last.id);
      expect(
        await repository.merge(targetId: middle.id, sourceId: last.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      await repository.pauseForSessionDeletion(profile, {session.id});
      expect(
        await repository.merge(targetId: first.id, sourceId: middle.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        (await repository.watchQueue(profile: profile, session: session).first)
            .map((row) => row.promptText),
        ['first', 'middle', 'last'],
      );
    },
  );

  for (final kind in ['attachments', 'command', 'uncertain']) {
    test('merge refuses a $kind source without changing either row', () async {
      final target = await enqueue('first');
      final Result<QueuedPrompt, QueueFailure> result;
      if (kind == 'command') {
        result = await repository.enqueueCommand(
          profile: profile,
          session: session,
          commandName: 'review',
          arguments: 'second',
        );
      } else {
        result = await repository.enqueue(
          profile: profile,
          session: session,
          promptText: 'second',
          attachments: kind == 'attachments'
              ? [
                  QueuedAttachment(
                    name: 'test.txt',
                    mediaType: 'text/plain',
                    bytes: Uint8List.fromList([65]),
                  ),
                ]
              : [],
        );
      }
      final source = (result as Ok<QueuedPrompt, QueueFailure>).value;
      if (kind == 'uncertain') {
        await repository.markPaused(
          source.id,
          reason: QueuePauseReason.submissionUnknown,
        );
      }
      expect(
        await repository.merge(targetId: target.id, sourceId: source.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      final rows = await repository
          .watchQueue(profile: profile, session: session)
          .first;
      expect(rows.map((row) => row.promptText), ['first', 'second']);
    });
  }

  test(
    'session deletion pauses all pending states and cleans only confirmed scoped IDs',
    () async {
      final otherProfile = ServerProfile(
        origin: Uri.parse('http://10.80.0.2:4096'),
        username: 'opencode',
      );
      final queued = await enqueue('queued');
      final sending = await enqueue('sending');
      await repository.markSending(sending.id);
      final paused = await enqueue('paused');
      await repository.markPaused(
        paused.id,
        reason: QueuePauseReason.permissionPending,
      );
      final failed = await enqueue('failed');
      await repository.markSending(failed.id);
      await repository.markFailed(failed.id);
      final acknowledged = await enqueue('acknowledged');
      await repository.markSending(acknowledged.id);
      await repository.markAcknowledged(acknowledged.id);
      final child = await enqueue('child', forSession: otherSession);
      final other = await repository.enqueue(
        profile: otherProfile,
        session: session,
        promptText: 'unrelated',
      );
      expect(other, isA<Ok<QueuedPrompt, QueueFailure>>());

      expect(
        await repository.pauseForSessionDeletion(profile, [
          session.id,
          otherSession.id,
        ]),
        isA<Ok<void, QueueFailure>>(),
      );
      final stopped = await repository
          .watchQueue(profile: profile, session: session)
          .first;
      for (final row in stopped.where((row) => row.id != acknowledged.id)) {
        expect(row.state, QueuedPromptState.paused);
        expect(row.pauseReason, QueuePauseReason.sessionDeleted);
      }
      expect(
        await repository.markQueued(queued.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        await repository.markAcknowledged(sending.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        await repository.markPaused(
          paused.id,
          reason: QueuePauseReason.questionPending,
        ),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        await repository.enqueue(
          profile: profile,
          session: session,
          promptText: 'late',
        ),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );

      // A child was deleted, but deleting the parent failed. Only the child's
      // content is removed; parent work stays stopped and cannot auto-resume.
      expect(
        await repository.deleteForSessions(profile, [otherSession.id]),
        isA<Ok<void, QueueFailure>>(),
      );
      expect(
        await repository
            .watchQueue(profile: profile, session: otherSession)
            .first,
        isEmpty,
      );
      expect(
        await repository.markQueued(child.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        await repository.watchQueue(profile: profile, session: session).first,
        hasLength(5),
      );
      expect(
        (await repository
                .watchQueue(profile: otherProfile, session: session)
                .first)
            .single
            .state,
        QueuedPromptState.queued,
      );
      await repository.deleteForSessions(profile, [session.id]);
      expect(
        await repository.watchQueue(profile: profile, session: session).first,
        isEmpty,
      );
      expect(
        await repository
            .watchQueue(profile: otherProfile, session: session)
            .first,
        hasLength(1),
      );
      expect(
        await repository.enqueue(
          profile: profile,
          session: session,
          promptText: 'stale view',
        ),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
    },
  );

  group('enqueue', () {
    test('assigns increasing positions per session', () async {
      final first = await enqueue('first prompt');
      final second = await enqueue('second prompt');

      expect(first.position, 0);
      expect(second.position, 1);
      expect(first.state, QueuedPromptState.queued);
      expect(first.serverProfileId, profile.id);
      expect(first.sessionId, session.id);
      expect(first.directory, session.directory);
    });

    test('rejects blank prompt text without touching the database', () async {
      final result = await repository.enqueue(
        profile: profile,
        session: session,
        promptText: '   ',
      );

      expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
      expect(
        (result as Err<QueuedPrompt, QueueFailure>).failure,
        QueueFailure.emptyPromptText,
      );
    });

    test('keeps separate position sequences per session', () async {
      final inFirstSession = await enqueue('a');
      final inOtherSession = await enqueue('b', forSession: otherSession);

      expect(inFirstSession.position, 0);
      expect(inOtherSession.position, 0);
      expect(inOtherSession.sessionId, otherSession.id);
    });

    test(
      'keeps selected execution options through storage and queue reads',
      () async {
        final prompt = await enqueue(
          'selected prompt',
          executionOptions: const PromptExecutionOptions(
            modelProviderId: 'anthropic',
            modelId: 'claude-sonnet-4',
            agentName: 'build',
            reasoningEffort: 'high',
            permissionModeId: 'auto',
          ),
        );

        expect(prompt.executionOptions.modelProviderId, 'anthropic');
        expect(prompt.executionOptions.modelId, 'claude-sonnet-4');
        expect(prompt.executionOptions.agentName, 'build');
        expect(prompt.executionOptions.reasoningEffort, 'high');
        expect(prompt.executionOptions.permissionModeId, 'auto');
        final stored = await repository
            .watchQueue(profile: profile, session: session)
            .first;
        expect(stored.single.executionOptions.modelProviderId, 'anthropic');
        expect(stored.single.executionOptions.modelId, 'claude-sonnet-4');
        expect(stored.single.executionOptions.agentName, 'build');
        expect(stored.single.executionOptions.reasoningEffort, 'high');
        expect(stored.single.executionOptions.permissionModeId, 'auto');
        await repository.edit(promptId: prompt.id, promptText: 'edited');
        final edited = await repository
            .watchQueue(profile: profile, session: session)
            .first;
        expect(edited.single.executionOptions.reasoningEffort, 'high');
        expect(edited.single.executionOptions.permissionModeId, 'auto');
        await repository.reorder(
          profile: profile,
          session: session,
          orderedPromptIds: [prompt.id],
        );
        await repository.markSending(prompt.id);
        await repository.markSubmissionUnknown(prompt.id);
        final paused = await repository
            .watchQueue(profile: profile, session: session)
            .first;
        expect(paused.single.executionOptions.reasoningEffort, 'high');
        expect(paused.single.executionOptions.permissionModeId, 'auto');
        expect(paused.single.state, QueuedPromptState.paused);
      },
    );
  });

  group('edit', () {
    test('replaces text while queued', () async {
      final prompt = await enqueue('original');

      final result = await repository.edit(
        promptId: prompt.id,
        promptText: 'updated',
      );

      expect(result, isA<Ok<QueuedPrompt, QueueFailure>>());
      final updated = (result as Ok<QueuedPrompt, QueueFailure>).value;
      expect(updated.promptText, 'updated');
      expect(updated.state, QueuedPromptState.queued);
    });

    test('rejects editing a prompt that is sending', () async {
      final prompt = await enqueue('original');
      await repository.markSending(prompt.id);

      final result = await repository.edit(
        promptId: prompt.id,
        promptText: 'updated',
      );

      expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
      expect(
        (result as Err<QueuedPrompt, QueueFailure>).failure,
        QueueFailure.invalidTransition,
      );
    });

    test('reports not found for an unknown id', () async {
      final result = await repository.edit(
        promptId: 'missing',
        promptText: 'updated',
      );

      expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
      expect(
        (result as Err<QueuedPrompt, QueueFailure>).failure,
        QueueFailure.notFound,
      );
    });
  });

  group('remove', () {
    test('deletes a queued prompt and returns its last values', () async {
      final prompt = await enqueue('to remove');

      final result = await repository.remove(prompt.id);

      expect(result, isA<Ok<QueuedPrompt, QueueFailure>>());
      expect((result as Ok<QueuedPrompt, QueueFailure>).value.id, prompt.id);
      final queue = await repository
          .watchQueue(profile: profile, session: session)
          .first;
      expect(queue, isEmpty);
    });

    test('rejects removing a prompt that is sending', () async {
      final prompt = await enqueue('in flight');
      await repository.markSending(prompt.id);

      final result = await repository.remove(prompt.id);

      expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
      expect(
        (result as Err<QueuedPrompt, QueueFailure>).failure,
        QueueFailure.invalidTransition,
      );
    });
  });

  group('state transitions', () {
    test('follows queued -> sending -> acknowledged', () async {
      final prompt = await enqueue('go');

      final sending = await repository.markSending(prompt.id);
      expect(
        (sending as Ok<QueuedPrompt, QueueFailure>).value.state,
        QueuedPromptState.sending,
      );
      expect(sending.value.attemptCount, 1);
      expect(sending.value.sendingStartedAt, isNotNull);

      final acknowledged = await repository.markAcknowledged(prompt.id);
      expect(
        (acknowledged as Ok<QueuedPrompt, QueueFailure>).value.state,
        QueuedPromptState.acknowledged,
      );
      expect(acknowledged.value.acknowledgedAt, isNotNull);
    });

    test('removes attachment bytes once a prompt is acknowledged', () async {
      final queued = await repository.enqueue(
        profile: profile,
        session: session,
        promptText: 'Review this file',
        attachments: [
          QueuedAttachment(
            name: 'notes.txt',
            mediaType: 'text/plain',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );
      final prompt = (queued as Ok<QueuedPrompt, QueueFailure>).value;

      await repository.markSending(prompt.id);
      final acknowledged = await repository.markAcknowledged(prompt.id);

      expect(
        (acknowledged as Ok<QueuedPrompt, QueueFailure>).value.attachments,
        isEmpty,
      );
    });

    test('follows queued -> sending -> failed -> paused', () async {
      final prompt = await enqueue('go');
      await repository.markSending(prompt.id);

      final failed = await repository.markFailed(
        prompt.id,
        reason: QueuePauseReason.networkUnavailable,
      );
      expect(
        (failed as Ok<QueuedPrompt, QueueFailure>).value.state,
        QueuedPromptState.failed,
      );
      expect(failed.value.pauseReason, QueuePauseReason.networkUnavailable);

      final paused = await repository.markPaused(
        prompt.id,
        reason: QueuePauseReason.permissionPending,
      );
      expect(
        (paused as Ok<QueuedPrompt, QueueFailure>).value.state,
        QueuedPromptState.paused,
      );

      final resumed = await repository.markQueued(prompt.id);
      expect(
        (resumed as Ok<QueuedPrompt, QueueFailure>).value.state,
        QueuedPromptState.queued,
      );
      expect(resumed.value.pauseReason, isNull);
      expect(resumed.value.position, prompt.position);
    });

    test('rejects marking an already-acknowledged prompt as sending', () async {
      final prompt = await enqueue('go');
      await repository.markSending(prompt.id);
      await repository.markAcknowledged(prompt.id);

      final result = await repository.markSending(prompt.id);

      expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
      expect(
        (result as Err<QueuedPrompt, QueueFailure>).failure,
        QueueFailure.invalidTransition,
      );
    });

    test('rejects pausing a prompt that is sending', () async {
      final prompt = await enqueue('go');
      await repository.markSending(prompt.id);

      final result = await repository.markPaused(
        prompt.id,
        reason: QueuePauseReason.permissionPending,
      );

      expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
      expect(
        (result as Err<QueuedPrompt, QueueFailure>).failure,
        QueueFailure.invalidTransition,
      );
    });

    test('follows queued -> sending -> paused(submissionUnknown)', () async {
      final prompt = await enqueue('go');
      await repository.markSending(prompt.id);

      final result = await repository.markSubmissionUnknown(prompt.id);

      expect(result, isA<Ok<QueuedPrompt, QueueFailure>>());
      final unknown = (result as Ok<QueuedPrompt, QueueFailure>).value;
      expect(unknown.state, QueuedPromptState.paused);
      expect(unknown.pauseReason, QueuePauseReason.submissionUnknown);
      // Never counted as a retry attempt: no send was ever confirmed.
      expect(unknown.attemptCount, 1);

      final resumed = await repository.markQueued(prompt.id);
      expect(
        (resumed as Ok<QueuedPrompt, QueueFailure>).value.state,
        QueuedPromptState.queued,
      );
    });

    test(
      'rejects marking submission-unknown from a non-sending state',
      () async {
        final prompt = await enqueue('go');

        final result = await repository.markSubmissionUnknown(prompt.id);

        expect(result, isA<Err<QueuedPrompt, QueueFailure>>());
        expect(
          (result as Err<QueuedPrompt, QueueFailure>).failure,
          QueueFailure.invalidTransition,
        );
      },
    );

    test('does not retry automatically after a failure', () async {
      final prompt = await enqueue('go');
      await repository.markSending(prompt.id);
      await repository.markFailed(
        prompt.id,
        reason: QueuePauseReason.networkUnavailable,
      );

      final queue = await repository
          .watchQueue(profile: profile, session: session)
          .first;

      expect(queue.single.state, QueuedPromptState.failed);
      expect(queue.single.attemptCount, 1);
    });
  });

  group('reorder', () {
    test('reassigns positions to match the requested order', () async {
      final first = await enqueue('first');
      final second = await enqueue('second');
      final third = await enqueue('third');

      final result = await repository.reorder(
        profile: profile,
        session: session,
        orderedPromptIds: [third.id, first.id, second.id],
      );

      expect(result, isA<Ok<List<QueuedPrompt>, QueueFailure>>());
      final reordered = (result as Ok<List<QueuedPrompt>, QueueFailure>).value;
      expect(reordered.map((prompt) => prompt.id).toList(), [
        third.id,
        first.id,
        second.id,
      ]);
      expect(reordered.map((prompt) => prompt.position).toList(), [0, 1, 2]);
    });

    test('rejects a reorder while a prompt is sending', () async {
      final first = await enqueue('first');
      final second = await enqueue('second');
      await repository.markSending(first.id);

      final result = await repository.reorder(
        profile: profile,
        session: session,
        orderedPromptIds: [second.id],
      );

      expect(result, isA<Err<List<QueuedPrompt>, QueueFailure>>());
      expect(
        (result as Err<List<QueuedPrompt>, QueueFailure>).failure,
        QueueFailure.invalidReorder,
      );
    });

    test('rejects a reorder that omits an existing prompt', () async {
      final first = await enqueue('first');
      await enqueue('second');

      final result = await repository.reorder(
        profile: profile,
        session: session,
        orderedPromptIds: [first.id],
      );

      expect(result, isA<Err<List<QueuedPrompt>, QueueFailure>>());
      expect(
        (result as Err<List<QueuedPrompt>, QueueFailure>).failure,
        QueueFailure.invalidReorder,
      );
    });
  });

  group('watchQueue', () {
    test('emits an update after every mutation', () async {
      final emissions = <int>[];
      final subscription = repository
          .watchQueue(profile: profile, session: session)
          .listen((queue) => emissions.add(queue.length));
      await _settle();

      final prompt = await enqueue('go');
      await _settle();
      await repository.markSending(prompt.id);
      await _settle();
      await repository.markAcknowledged(prompt.id);
      await _settle();
      await repository.remove(prompt.id);
      await _settle();

      expect(emissions, [0, 1, 1, 1, 0]);
      await subscription.cancel();
    });

    test('never includes prompts from another session', () async {
      await enqueue('in first session');
      await enqueue('in other session', forSession: otherSession);

      final queue = await repository
          .watchQueue(profile: profile, session: session)
          .first;

      expect(queue, hasLength(1));
      expect(queue.single.sessionId, session.id);
    });
  });
}
