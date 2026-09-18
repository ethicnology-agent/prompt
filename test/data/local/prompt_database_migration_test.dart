import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/local/prompt_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

void main() {
  late File databaseFile;
  PromptDatabase? database;

  setUp(() {
    databaseFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'prompt-database-migration-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    database = null;
  });

  tearDown(() async {
    try {
      await database?.close();
    } finally {
      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }
    }
  });

  test(
    'v7 additive effort migration retains pending operation and profile',
    () async {
      _createFixture(databaseFile, version: 7);
      database = PromptDatabase.forTesting(NativeDatabase(databaseFile));
      final row = await _readPrompt(database!);
      expect(row.reasoningEffort, isNull);
      expect(row.id, 'legacy-v7-prompt');
      expect(row.modelProviderId, 'anthropic');
      expect(row.modelId, 'claude-sonnet');
      expect(row.agentName, 'review');
      expect(row.operationType, 'command');
      expect(row.commandName, 'run-tests');
      expect(row.state, 'queued');
      expect(row.attemptCount, 3);
      expect(row.attachmentsJson, '[{"name":"retained"}]');
      final profile = await database!
          .select(database!.serverProfiles)
          .getSingle();
      expect(profile.backend, 'gatewayCodex');
      final version = await database!
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data['user_version'], 8);
      await database!.customStatement(
        'UPDATE queued_prompts SET reasoning_effort = ? WHERE id = ?',
        ['high', row.id],
      );
      await database!.close();
      database = PromptDatabase.forTesting(NativeDatabase(databaseFile));
      final reopened = await _readPrompt(database!);
      expect(reopened.reasoningEffort, 'high');
      expect(reopened.attachmentsJson, row.attachmentsJson);
      expect(reopened.commandName, row.commandName);
    },
  );

  test('migrates a v1 database and preserves its queued prompt', () async {
    _createFixture(databaseFile, version: 1);
    database = PromptDatabase.forTesting(NativeDatabase(databaseFile));

    final row = await _readPrompt(database!);

    await _expectVersion6(database!);
    expect(row.id, 'legacy-v1-prompt');
    expect(row.serverProfileId, 'legacy-profile');
    expect(row.sessionId, 'legacy-session');
    expect(row.directory, '/workspace/legacy');
    expect(row.position, 2);
    expect(row.promptText, 'Keep this v1 prompt');
    expect(row.state, 'queued');
    expect(row.attemptCount, 3);
    expect(row.createdAtMillis, 1000);
    expect(row.updatedAtMillis, 2000);
    expect(row.modelProviderId, isNull);
    expect(row.modelId, isNull);
    expect(row.agentName, isNull);
    expect(row.operationType, 'prompt');
    expect(row.commandName, isNull);
    expect(row.attachmentsJson, isNull);
  });

  test('v6 profile IDs survive additive backend migration', () async {
    _createFixture(databaseFile, version: 6);
    database = PromptDatabase.forTesting(NativeDatabase(databaseFile));
    final profile = await database!
        .select(database!.serverProfiles)
        .getSingle();
    expect(profile.id, 'legacy-profile');
    expect(profile.origin, 'http://10.80.0.1:4096');
    expect(profile.username, 'legacy-user');
    expect(profile.backend, 'directOpenCode');
    await _expectVersion6(database!);
  });

  test(
    'migrates v2 to v6 and preserves model options with default operation fields',
    () async {
      _createFixture(databaseFile, version: 2);
      database = PromptDatabase.forTesting(NativeDatabase(databaseFile));

      final row = await _readPrompt(database!);

      await _expectVersion6(database!);
      expect(row.id, 'legacy-v2-prompt');
      expect(row.serverProfileId, 'legacy-profile');
      expect(row.sessionId, 'legacy-session');
      expect(row.directory, '/workspace/legacy');
      expect(row.position, 2);
      expect(row.promptText, 'Keep this v2 prompt');
      expect(row.state, 'queued');
      expect(row.attemptCount, 3);
      expect(row.createdAtMillis, 1000);
      expect(row.updatedAtMillis, 2000);
      expect(row.modelProviderId, 'openai');
      expect(row.modelId, 'gpt-5');
      expect(row.agentName, 'build');
      expect(row.operationType, 'prompt');
      expect(row.commandName, isNull);
      expect(row.attachmentsJson, isNull);
    },
  );

  test(
    'migrates v3 to v6 and preserves operation fields with nullable attachments',
    () async {
      _createFixture(databaseFile, version: 3);
      database = PromptDatabase.forTesting(NativeDatabase(databaseFile));

      final row = await _readPrompt(database!);

      await _expectVersion6(database!);
      expect(row.id, 'legacy-v3-prompt');
      expect(row.serverProfileId, 'legacy-profile');
      expect(row.sessionId, 'legacy-session');
      expect(row.directory, '/workspace/legacy');
      expect(row.position, 2);
      expect(row.promptText, 'Keep this v3 command');
      expect(row.state, 'queued');
      expect(row.attemptCount, 3);
      expect(row.createdAtMillis, 1000);
      expect(row.updatedAtMillis, 2000);
      expect(row.modelProviderId, 'anthropic');
      expect(row.modelId, 'claude-sonnet');
      expect(row.agentName, 'review');
      expect(row.operationType, 'command');
      expect(row.commandName, 'run-tests');
      expect(row.attachmentsJson, isNull);
    },
  );

  test('migrates v4 to v6 with review tables and foreign keys enabled', () async {
    _createFixture(databaseFile, version: 4);
    database = PromptDatabase.forTesting(NativeDatabase(databaseFile));
    expect((await _readPrompt(database!)).id, 'legacy-v4-prompt');
    await _expectVersion6(database!);
    final foreignKeys = await database!
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    expect(foreignKeys.data['foreign_keys'], 1);
    final tables = await database!
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'review_%'",
        )
        .get();
    expect(
      tables.map((table) => table.data['name']),
      containsAll(<String>[
        'review_runs',
        'review_files',
        'review_passes',
        'review_opinions',
        'review_findings',
        'review_evidence_entries',
        'review_disagreements',
        'review_disagreement_sources',
      ]),
    );
  });
}

Future<QueuedPrompt> _readPrompt(PromptDatabase database) {
  return (database.select(database.queuedPrompts)..limit(1)).getSingle();
}

Future<void> _expectVersion6(PromptDatabase database) async {
  final version = await database
      .customSelect('PRAGMA user_version')
      .getSingle();
  expect(version.data['user_version'], 8);
  final profiles = await database.select(database.serverProfiles).get();
  expect(profiles.single.backend, 'directOpenCode');
}

void _createFixture(File file, {required int version}) {
  final sqlite = sqlite3lib.sqlite3.open(file.path);
  final operationColumns = version >= 3
      ? "operation_type TEXT NOT NULL DEFAULT 'prompt', command_name TEXT NULL,"
      : '';
  final modelColumns = version >= 2
      ? 'model_provider_id TEXT NULL, model_id TEXT NULL, agent_name TEXT NULL,'
      : '';
  final operationInsertColumns = version >= 3
      ? 'operation_type, command_name,'
      : '';
  final modelInsertColumns = version >= 2
      ? 'model_provider_id, model_id, agent_name,'
      : '';
  final operationValues = version >= 3 ? "'command', 'run-tests'," : '';
  final modelValues = version >= 2
      ? "'${version == 2 ? 'openai' : 'anthropic'}', "
            "'${version == 2 ? 'gpt-5' : 'claude-sonnet'}', "
            "'${version == 2 ? 'build' : 'review'}',"
      : '';
  final promptText =
      'Keep this v$version ${version >= 3 ? 'command' : 'prompt'}';
  try {
    sqlite.execute('''
      CREATE TABLE server_profiles (
        id TEXT NOT NULL PRIMARY KEY,
        origin TEXT NOT NULL,
        username TEXT NULL,
        ${version >= 7 ? "backend TEXT NOT NULL DEFAULT 'directOpenCode'," : ''}
        last_accessed_at_millis INTEGER NOT NULL
      );
      CREATE TABLE queued_prompts (
        id TEXT NOT NULL PRIMARY KEY,
        server_profile_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        directory TEXT NOT NULL,
        position INTEGER NOT NULL,
        prompt_text TEXT NOT NULL,
        $operationColumns
        $modelColumns
        ${version >= 4 ? 'attachments_json TEXT NULL,' : ''}
        state TEXT NOT NULL,
        pause_reason TEXT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at_millis INTEGER NOT NULL,
        updated_at_millis INTEGER NOT NULL,
        sending_started_at_millis INTEGER NULL,
        acknowledged_at_millis INTEGER NULL,
        UNIQUE (server_profile_id, session_id, position)
      );
      INSERT INTO server_profiles VALUES
        ('legacy-profile', 'http://10.80.0.1:4096', 'legacy-user', ${version >= 7 ? "'gatewayCodex'," : ''} 900);
      INSERT INTO queued_prompts (
        id, server_profile_id, session_id, directory, position, prompt_text,
        $operationInsertColumns
        $modelInsertColumns
        ${version >= 4 ? 'attachments_json,' : ''}
        state, pause_reason, attempt_count, created_at_millis, updated_at_millis,
        sending_started_at_millis, acknowledged_at_millis
      ) VALUES (
        'legacy-v$version-prompt', 'legacy-profile', 'legacy-session',
        '/workspace/legacy', 2, '$promptText',
        $operationValues
        $modelValues
        ${version >= 4 ? "'[{\"name\":\"retained\"}]'," : ''}
        'queued', NULL, 3, 1000, 2000, NULL, NULL
      );
      PRAGMA user_version = $version;
    ''');
  } finally {
    sqlite.close();
  }
}
