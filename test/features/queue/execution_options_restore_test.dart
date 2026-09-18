import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/data/local/prompt_database.dart' show PromptDatabase;
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/data/queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_repository.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/queue/domain/queue_failure.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart'
    show QueuedOperationType;
import 'package:prompt/features/sessions/domain/open_code_session.dart';

void main() {
  test(
    'database reopen restores last normal submission and explicit null reset',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'prompt-options-test-',
      );
      addTearDown(() => scratch.delete(recursive: true));
      final file = File('${scratch.path}/queue.sqlite');
      var database = PromptDatabase.forTesting(NativeDatabase(file));
      addTearDown(() => database.close());
      var dao = DriftQueuePromptsDao(database);
      final profile = ServerProfile(origin: Uri.parse('http://10.0.0.1:4097'));
      final session = OpenCodeSession(
        id: 'session',
        projectId: 'project',
        directory: '/workspace',
        title: 'Session',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      const chosen = PromptExecutionOptions(
        modelProviderId: 'codex',
        modelId: 'actual',
        agentName: 'codex',
        reasoningEffort: 'low',
      );
      Future<void> insert(
        String id,
        DateTime time,
        PromptExecutionOptions options, {
        String? profileId,
        String? sessionId,
        QueuedOperationType operation = QueuedOperationType.prompt,
      }) => dao.enqueue(
        id: id,
        serverProfileId: profileId ?? profile.id,
        sessionId: sessionId ?? session.id,
        directory: session.directory,
        promptText: 'Synthetic text',
        executionOptions: options,
        operationType: operation,
        commandName: operation == QueuedOperationType.command
            ? 'synthetic'
            : null,
        now: time,
      );
      await insert('submitted', DateTime(2024), chosen);
      await dao.markSending('submitted', now: DateTime(2024));
      await dao.markAcknowledged('submitted', now: DateTime(2024));
      await insert(
        'command',
        DateTime(2025),
        const PromptExecutionOptions(
          modelProviderId: 'other',
          modelId: 'command-override',
        ),
        operation: QueuedOperationType.command,
      );
      await insert(
        'other-profile',
        DateTime(2025),
        const PromptExecutionOptions(
          modelProviderId: 'other',
          modelId: 'foreign',
        ),
        profileId: 'foreign',
      );
      await insert(
        'other-session',
        DateTime(2025),
        const PromptExecutionOptions(
          modelProviderId: 'other',
          modelId: 'foreign',
        ),
        sessionId: 'foreign',
      );
      await database.close();
      database = PromptDatabase.forTesting(NativeDatabase(file));
      dao = DriftQueuePromptsDao(database);
      Future<PromptExecutionOptions?> restore() async =>
          (await QueuePromptsRepository(
                    dao,
                  ).latestExecutionOptions(profile: profile, session: session)
                  as Ok<PromptExecutionOptions?, QueueFailure>)
              .value;
      final restored = (await restore())!;
      expect(restored.modelId, 'actual');
      expect(restored.modelProviderId, 'codex');
      expect(restored.agentName, 'codex');
      expect(restored.reasoningEffort, 'low');
      // Same timestamp uses ID, not mutable dispatch position or acknowledgment.
      await insert('a-option', DateTime(2026), chosen);
      await insert('z-reset', DateTime(2026), const PromptExecutionOptions());
      await database.close();
      database = PromptDatabase.forTesting(NativeDatabase(file));
      dao = DriftQueuePromptsDao(database);
      expect(await restore(), isNotNull);
      expect((await restore())!.isEmpty, isTrue);
    },
  );
}
