import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/local/prompt_database.dart' as db;
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/review/data/review_history_store.dart';
import 'package:prompt/features/review/domain/review_entities.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

void main() {
  test(
    'InMemory watch covers writes, ordering, and isolated deletes',
    () async {
      final store = InMemoryReviewHistoryStore();
      final events = <List<StoredReviewSummary>>[];
      final subscription = store.watchSummaries('p', 's').listen(events.add);
      await _turn();
      await store.save(_stored('new', 'p', 's', createdAt: DateTime.utc(2025)));
      await _turn();
      await store.save(_stored('old', 'p', 's', createdAt: DateTime.utc(2024)));
      await _turn();
      await store.save(
        _stored('tie-b', 'p', 's', createdAt: DateTime.utc(2025)),
      );
      await _turn();
      await store.replace(
        _stored(
          'old',
          'p',
          's',
          state: ReviewRunState.failed,
          createdAt: DateTime.utc(2026),
        ),
      );
      await _turn();
      expect(events.last.map((item) => item.id), ['old', 'new', 'tie-b']);
      final summary = events.last.first;
      expect(summary.fileCount, 0);
      expect(summary.passCount, 0);
      expect(summary.findingCount, 0);
      await store.save(_stored('other-profile', 'other', 's'));
      await store.save(_stored('other-session', 'p', 'other'));
      await store.delete('old');
      await _turn();
      expect((await store.listSummaries('p', 's')).map((item) => item.id), [
        'new',
        'tie-b',
      ]);
      await store.deleteForSessions('p', ['s']);
      await _turn();
      expect(events.last, isEmpty);
      expect(await store.listSummaries('other', 's'), hasLength(1));
      expect(await store.listSummaries('p', 'other'), hasLength(1));
      await store.close();
      await subscription.cancel();
    },
  );

  test(
    'Drift round-trips complete data, orders children, and cascades deletes',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/review-history-${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      final profile = ServerProfile(
        origin: Uri.parse('http://127.0.0.1:4096'),
        username: 'reviewer',
      );
      var database = db.PromptDatabase.forTesting(NativeDatabase(file));
      await database
          .into(database.serverProfiles)
          .insert(
            db.ServerProfilesCompanion.insert(
              id: profile.id,
              origin: profile.origin.toString(),
              username: Value(profile.username),
              lastAccessedAtMillis: 1,
            ),
          );
      final store = DriftReviewHistoryStore(database);
      final stored = _stored(
        'review',
        profile.id,
        'session',
        run: _completeRun(profile),
      );
      await store.save(stored);
      await store.save(
        _stored('newest', profile.id, 'session', createdAt: DateTime.utc(2027)),
      );
      await store.save(
        _stored(
          'same-time-b',
          profile.id,
          'session',
          createdAt: DateTime.utc(2027),
        ),
      );
      expect(
        (await store.listSummaries(
          profile.id,
          'session',
        )).map((item) => item.id),
        ['newest', 'same-time-b', 'review'],
      );
      final reviewSummary = (await store.listSummaries(
        profile.id,
        'session',
      )).last;
      expect(reviewSummary.fileCount, 2);
      expect(reviewSummary.passCount, 2);
      expect(reviewSummary.reviewerCount, 2);
      expect(reviewSummary.findingCount, 2);
      expect(reviewSummary.hypothesisCount, 2);
      final loaded = await store.load('review');
      _expectComplete(loaded!, profile);
      await store.delete('review');
      expect(await store.load('review'), isNull);
      for (final table in [
        'review_files',
        'review_passes',
        'review_opinions',
        'review_findings',
        'review_evidence_entries',
        'review_disagreements',
        'review_disagreement_sources',
      ]) {
        final count = await database
            .customSelect('SELECT count(*) AS c FROM $table')
            .getSingle();
        expect(count.data['c'], 0, reason: table);
      }
      await database.close();
      await file.delete();
    },
  );

  test(
    'Drift round-trips the provider failure kind without a schema change',
    () async {
      final database = db.PromptDatabase.forTesting(NativeDatabase.memory());
      final profile = ServerProfile(origin: Uri.parse('http://profile-review'));
      await database
          .into(database.serverProfiles)
          .insert(
            db.ServerProfilesCompanion.insert(
              id: profile.id,
              origin: profile.origin.toString(),
              lastAccessedAtMillis: 1,
            ),
          );
      final failure = const ReviewProviderFailure(
        'Access to this model is denied. Check access, region, or opt-in.',
        kind: ReviewProviderFailureKind.accessDenied,
      );
      final review = _stored(
        'failure-kind',
        profile.id,
        'session',
        state: ReviewRunState.failed,
        run: ReviewRun(
          state: ReviewRunState.partiallyFailed,
          passes: [
            ReviewPass(
              configuration: const ReviewReviewerConfiguration(
                role: ReviewRole.security,
                model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
              ),
              state: ReviewPassState.failed,
              error: failure,
            ),
          ],
        ),
      );
      final store = DriftReviewHistoryStore(database);
      await store.save(review);

      final loaded = await store.load('failure-kind');
      final loadedFailure =
          loaded!.run.passes.single.error! as ReviewProviderFailure;
      expect(loadedFailure.kind, ReviewProviderFailureKind.accessDenied);
      await database.close();
    },
  );

  test('Drift scoped deletion isolates profile and session history', () async {
    final database = db.PromptDatabase.forTesting(NativeDatabase.memory());
    final profile = ServerProfile(origin: Uri.parse('http://profile-a'));
    final other = ServerProfile(origin: Uri.parse('http://profile-b'));
    for (final value in [profile, other]) {
      await database
          .into(database.serverProfiles)
          .insert(
            db.ServerProfilesCompanion.insert(
              id: value.id,
              origin: value.origin.toString(),
              lastAccessedAtMillis: 1,
            ),
          );
    }
    final store = DriftReviewHistoryStore(database);
    await store.save(_stored('a1', profile.id, 'session-a'));
    await store.save(_stored('a2', profile.id, 'session-b'));
    await store.save(_stored('b1', other.id, 'session-a'));
    await store.deleteForSessions(profile.id, ['session-a']);
    expect(await store.load('a1'), isNull);
    expect(await store.load('a2'), isNotNull);
    expect(await store.load('b1'), isNotNull);
    await database.close();
  });

  test('migrates a genuine v5 review run and adds fidelity columns', () async {
    final file = File(
      '${Directory.systemTemp.path}/review-v5-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    final sqlite = sqlite3lib.sqlite3.open(file.path);
    sqlite.execute('''
      CREATE TABLE server_profiles (id TEXT PRIMARY KEY, origin TEXT NOT NULL, username TEXT, last_accessed_at_millis INTEGER NOT NULL);
      CREATE TABLE queued_prompts (
        id TEXT NOT NULL PRIMARY KEY,
        server_profile_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        directory TEXT NOT NULL,
        position INTEGER NOT NULL,
        prompt_text TEXT NOT NULL,
        operation_type TEXT NOT NULL DEFAULT 'prompt',
        command_name TEXT,
        attachments_json TEXT,
        model_provider_id TEXT,
        model_id TEXT,
        agent_name TEXT,
        state TEXT NOT NULL,
        pause_reason TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at_millis INTEGER NOT NULL,
        updated_at_millis INTEGER NOT NULL,
        sending_started_at_millis INTEGER,
        acknowledged_at_millis INTEGER,
        UNIQUE(server_profile_id, session_id, position)
      );
      CREATE TABLE review_runs (id TEXT PRIMARY KEY, server_profile_id TEXT NOT NULL, session_id TEXT NOT NULL, created_at_millis INTEGER NOT NULL, completed_at_millis INTEGER, state TEXT NOT NULL, error_type TEXT, error_message TEXT, project_id TEXT, directory TEXT, title TEXT);
      CREATE TABLE review_files (id INTEGER PRIMARY KEY AUTOINCREMENT, review_id TEXT NOT NULL, path TEXT NOT NULL, status TEXT NOT NULL, patch TEXT NOT NULL);
      CREATE TABLE review_passes (id TEXT PRIMARY KEY, review_id TEXT NOT NULL, role TEXT NOT NULL, provider_id TEXT NOT NULL, model_id TEXT NOT NULL, state TEXT NOT NULL, child_session_id TEXT, error_type TEXT, error_message TEXT, input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, reasoning_tokens INTEGER NOT NULL, cache_tokens INTEGER NOT NULL, cost REAL NOT NULL, duration_millis INTEGER);
      CREATE TABLE review_opinions (id TEXT PRIMARY KEY, pass_id TEXT NOT NULL, role TEXT NOT NULL, summary TEXT NOT NULL);
      CREATE TABLE review_findings (id TEXT PRIMARY KEY, opinion_id TEXT NOT NULL, file TEXT NOT NULL, start_line INTEGER NOT NULL, end_line INTEGER NOT NULL, side TEXT NOT NULL, category TEXT NOT NULL, severity TEXT NOT NULL, confidence REAL NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL, expected_behavior TEXT NOT NULL, observed_behavior TEXT NOT NULL, preconditions TEXT NOT NULL, reproduction TEXT NOT NULL, impact TEXT NOT NULL, suggested_test TEXT NOT NULL);
      CREATE TABLE review_evidence_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, finding_id TEXT NOT NULL, kind TEXT NOT NULL, evidence_text TEXT NOT NULL);
      CREATE TABLE review_disagreements (id TEXT PRIMARY KEY, review_id TEXT NOT NULL);
      CREATE TABLE review_disagreement_sources (id INTEGER PRIMARY KEY AUTOINCREMENT, disagreement_id TEXT NOT NULL, finding_id TEXT NOT NULL, role TEXT NOT NULL);
      INSERT INTO server_profiles VALUES ('p', 'http://v5', 'user', 1);
      INSERT INTO queued_prompts VALUES ('q', 'p', 's', '/work', 0, 'Retained prompt', 'command', 'review', '[{"name":"fixture"}]', 'provider', 'model', 'agent', 'paused', 'submissionUnknown', 1, 1000, 2000, 1500, NULL);
      INSERT INTO review_runs VALUES ('r', 'p', 's', 1000, NULL, 'completed', NULL, NULL, 'project', '/work', 'title');
      PRAGMA user_version = 5;
    ''');
    sqlite.close();
    final database = db.PromptDatabase.forTesting(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
      if (await file.exists()) await file.delete();
    });
    final loaded = await DriftReviewHistoryStore(database).load('r');
    expect(loaded!.run.snapshot, isNotNull);
    expect(loaded.run.snapshot!.files, isEmpty);
    expect(loaded.run.snapshot!.target.session.title, 'title');
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .data['user_version'],
      9,
    );
    final queued = await database.select(database.queuedPrompts).getSingle();
    expect(queued.promptText, 'Retained prompt');
    expect(queued.operationType, 'command');
    expect(queued.commandName, 'review');
    expect(queued.attachmentsJson, '[{"name":"fixture"}]');
    expect(queued.modelProviderId, 'provider');
    expect(queued.modelId, 'model');
    expect(queued.agentName, 'agent');
    expect(queued.state, 'paused');
    expect(queued.pauseReason, 'submissionUnknown');
    expect(queued.attemptCount, 1);
    expect(queued.reasoningEffort, isNull);
  });
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

StoredReview _stored(
  String id,
  String profile,
  String session, {
  DateTime? createdAt,
  ReviewRunState state = ReviewRunState.completed,
  ReviewRun? run,
}) => StoredReview(
  id: id,
  serverProfileId: profile,
  sessionId: session,
  createdAt: createdAt ?? DateTime.utc(2024),
  run: run ?? ReviewRun(state: state),
);

ReviewRun _completeRun(ServerProfile profile) {
  final session = OpenCodeSession(
    id: 'session',
    projectId: 'project',
    directory: '/work',
    title: 'Title',
    createdAt: DateTime.utc(2024, 1, 2),
    updatedAt: DateTime.utc(2024, 1, 3),
    parentId: 'parent',
    changedFiles: 2,
    additions: 3,
    deletions: 4,
    shareUrl: 'https://share.example/review',
    modelProviderId: 'provider',
    modelId: 'model',
    agentName: 'agent',
  );
  final first = ReviewFinding(
    file: 'a.dart',
    startLine: 1,
    endLine: 2,
    side: 'RIGHT',
    category: ReviewFindingCategory.security,
    severity: ReviewSeverity.high,
    confidence: .91,
    title: 'first',
    description: 'description',
    expectedBehavior: 'expected',
    observedBehavior: 'observed',
    preconditions: 'preconditions',
    reproduction: 'reproduction',
    impact: 'impact',
    suggestedTest: 'test',
    evidence: const [
      ReviewEvidence(kind: ReviewEvidenceKind.diff, text: 'diff evidence'),
      ReviewEvidence(kind: ReviewEvidenceKind.test, text: 'test evidence'),
    ],
  );
  final second = ReviewFinding(
    file: 'b.dart',
    startLine: 3,
    endLine: 4,
    side: 'LEFT',
    category: ReviewFindingCategory.correctness,
    severity: ReviewSeverity.low,
    confidence: .42,
    title: 'second',
    description: 'description 2',
    expectedBehavior: 'expected 2',
    observedBehavior: 'observed 2',
    preconditions: 'preconditions 2',
    reproduction: 'reproduction 2',
    impact: 'impact 2',
    suggestedTest: 'test 2',
    evidence: const [
      ReviewEvidence(
        kind: ReviewEvidenceKind.external,
        text: 'external evidence',
      ),
    ],
  );
  return ReviewRun(
    state: ReviewRunState.partiallyFailed,
    snapshot: ReviewSnapshot.stored(
      target: ReviewTarget(profile: profile, session: session),
      files: const [
        ReviewFile(path: 'b.dart', status: 'modified', patch: 'patch b'),
        ReviewFile(path: 'a.dart', status: 'added', patch: 'patch a'),
      ],
    ),
    passes: [
      ReviewPass(
        configuration: const ReviewReviewerConfiguration(
          role: ReviewRole.correctness,
          model: ReviewModelConfiguration(providerId: 'p1', modelId: 'm1'),
        ),
        state: ReviewPassState.succeeded,
        childSessionId: 'child-1',
        opinion: ReviewOpinion(
          role: ReviewRole.correctness,
          summary: 'summary 1',
          findings: [first, second],
        ),
        metrics: const ReviewPassMetrics(
          inputTokens: 10,
          outputTokens: 20,
          reasoningTokens: 30,
          cacheTokens: 40,
          cost: 1.5,
          duration: Duration(milliseconds: 55),
        ),
      ),
      const ReviewPass(
        configuration: ReviewReviewerConfiguration(
          role: ReviewRole.testsAndRegressions,
          model: ReviewModelConfiguration(providerId: 'p2', modelId: 'm2'),
        ),
        state: ReviewPassState.timedOut,
        childSessionId: 'child-2',
        error: ReviewTimeoutFailure('timed out'),
        metrics: ReviewPassMetrics(
          inputTokens: 11,
          outputTokens: 21,
          reasoningTokens: 31,
          cacheTokens: 41,
          cost: 2.5,
          duration: Duration(seconds: 2),
        ),
      ),
    ],
    disagreements: [
      ReviewDisagreement(
        sources: [
          ReviewFindingSource(role: ReviewRole.correctness, finding: first),
          ReviewFindingSource(role: ReviewRole.correctness, finding: second),
        ],
      ),
    ],
    error: const ReviewProviderFailure('run failed'),
  );
}

void _expectComplete(StoredReview loaded, ServerProfile profile) {
  final snapshot = loaded.run.snapshot!;
  expect(snapshot.target.profile.id, profile.id);
  expect(snapshot.target.profile.username, 'reviewer');
  expect(snapshot.target.session.parentId, 'parent');
  expect(snapshot.target.session.changedFiles, 2);
  expect(snapshot.target.session.additions, 3);
  expect(snapshot.target.session.deletions, 4);
  expect(snapshot.target.session.shareUrl, 'https://share.example/review');
  expect(snapshot.target.session.modelProviderId, 'provider');
  expect(snapshot.target.session.modelId, 'model');
  expect(snapshot.target.session.agentName, 'agent');
  expect(snapshot.files.map((file) => file.path), ['b.dart', 'a.dart']);
  expect(loaded.run.passes.map((pass) => pass.configuration.role), [
    ReviewRole.correctness,
    ReviewRole.testsAndRegressions,
  ]);
  expect(loaded.run.passes.map((pass) => pass.state), [
    ReviewPassState.succeeded,
    ReviewPassState.timedOut,
  ]);
  expect(loaded.run.passes.map((pass) => pass.childSessionId), [
    'child-1',
    'child-2',
  ]);
  expect(loaded.run.passes.first.metrics.reasoningTokens, 30);
  expect(loaded.run.passes.first.metrics.cacheTokens, 40);
  expect(
    loaded.run.passes.first.metrics.duration,
    const Duration(milliseconds: 55),
  );
  expect(loaded.run.passes.first.opinion!.summary, 'summary 1');
  expect(
    loaded.run.passes.first.opinion!.findings.map((finding) => finding.title),
    ['first', 'second'],
  );
  expect(
    loaded.run.passes.first.opinion!.findings.first.evidence.map(
      (entry) => entry.text,
    ),
    ['diff evidence', 'test evidence'],
  );
  expect(loaded.run.disagreements.single.sources.map((source) => source.role), [
    ReviewRole.correctness,
    ReviewRole.correctness,
  ]);
  expect(
    loaded.run.disagreements.single.findings.map((finding) => finding.title),
    ['first', 'second'],
  );
  expect(loaded.run.error!.message, 'run failed');
}
