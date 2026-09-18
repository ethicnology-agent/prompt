import 'package:drift/drift.dart';

part 'prompt_database.g.dart';

class ServerProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get origin => text()();
  TextColumn get username => text().nullable()();
  TextColumn get backend =>
      text().withDefault(const Constant('directOpenCode'))();
  IntColumn get lastAccessedAtMillis => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class QueuedPrompts extends Table {
  TextColumn get id => text()();
  TextColumn get serverProfileId => text()();
  TextColumn get sessionId => text()();
  TextColumn get directory => text()();
  IntColumn get position => integer()();
  TextColumn get promptText => text()();
  TextColumn get operationType =>
      text().withDefault(const Constant('prompt'))();
  TextColumn get commandName => text().nullable()();

  /// JSON array of `{name, mediaType, base64}` objects, or null when the
  /// prompt carries no file. Stored in the encrypted database exactly like
  /// [promptText], and never logged or exported.
  TextColumn get attachmentsJson => text().nullable()();
  TextColumn get modelProviderId => text().nullable()();
  TextColumn get modelId => text().nullable()();
  TextColumn get agentName => text().nullable()();
  TextColumn get reasoningEffort => text().nullable()();
  TextColumn get state => text()();
  TextColumn get pauseReason => text().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAtMillis => integer()();
  IntColumn get updatedAtMillis => integer()();
  IntColumn get sendingStartedAtMillis => integer().nullable()();
  IntColumn get acknowledgedAtMillis => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {serverProfileId, sessionId, position},
  ];
}

@TableIndex(
  name: 'review_runs_scope_idx',
  columns: {#serverProfileId, #sessionId, #createdAtMillis},
)
class ReviewRuns extends Table {
  TextColumn get id => text()();
  TextColumn get serverProfileId =>
      text().references(ServerProfiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get sessionId => text()();
  IntColumn get createdAtMillis => integer()();
  IntColumn get completedAtMillis => integer().nullable()();
  TextColumn get state => text()();
  TextColumn get errorType => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get directory => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get profileOrigin => text().nullable()();
  TextColumn get profileUsername => text().nullable()();
  IntColumn get sessionCreatedAtMillis => integer().nullable()();
  IntColumn get sessionUpdatedAtMillis => integer().nullable()();
  TextColumn get parentId => text().nullable()();
  IntColumn get changedFiles => integer().nullable()();
  IntColumn get additions => integer().nullable()();
  IntColumn get deletions => integer().nullable()();
  TextColumn get shareUrl => text().nullable()();
  TextColumn get modelProviderId => text().nullable()();
  TextColumn get modelId => text().nullable()();
  TextColumn get agentName => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'review_files_review_idx', columns: {#reviewId})
class ReviewFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get reviewId =>
      text().references(ReviewRuns, #id, onDelete: KeyAction.cascade)();
  TextColumn get path => text()();
  TextColumn get status => text()();
  TextColumn get patch => text()();
}

@TableIndex(name: 'review_passes_review_idx', columns: {#reviewId})
class ReviewPasses extends Table {
  TextColumn get id => text()();
  TextColumn get reviewId =>
      text().references(ReviewRuns, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get providerId => text()();
  TextColumn get modelId => text()();
  TextColumn get state => text()();
  TextColumn get childSessionId => text().nullable()();
  TextColumn get errorType => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get inputTokens => integer()();
  IntColumn get outputTokens => integer()();
  IntColumn get reasoningTokens => integer()();
  IntColumn get cacheTokens => integer()();
  RealColumn get cost => real()();
  IntColumn get durationMillis => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'review_opinions_pass_idx', columns: {#passId})
class ReviewOpinions extends Table {
  TextColumn get id => text()();
  TextColumn get passId =>
      text().references(ReviewPasses, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get summary => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {passId},
  ];
}

@TableIndex(name: 'review_findings_opinion_idx', columns: {#opinionId})
class ReviewFindings extends Table {
  TextColumn get id => text()();
  TextColumn get opinionId =>
      text().references(ReviewOpinions, #id, onDelete: KeyAction.cascade)();
  TextColumn get file => text()();
  IntColumn get startLine => integer()();
  IntColumn get endLine => integer()();
  TextColumn get side => text()();
  TextColumn get category => text()();
  TextColumn get severity => text()();
  RealColumn get confidence => real()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get expectedBehavior => text()();
  TextColumn get observedBehavior => text()();
  TextColumn get preconditions => text()();
  TextColumn get reproduction => text()();
  TextColumn get impact => text()();
  TextColumn get suggestedTest => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(name: 'review_evidence_finding_idx', columns: {#findingId})
class ReviewEvidenceEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get findingId =>
      text().references(ReviewFindings, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get evidenceText => text()();
}

@TableIndex(name: 'review_disagreements_review_idx', columns: {#reviewId})
class ReviewDisagreements extends Table {
  TextColumn get id => text()();
  TextColumn get reviewId =>
      text().references(ReviewRuns, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex(
  name: 'review_disagreement_sources_disagreement_idx',
  columns: {#disagreementId},
)
@TableIndex(
  name: 'review_disagreement_sources_finding_idx',
  columns: {#findingId},
)
class ReviewDisagreementSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get disagreementId => text().references(
    ReviewDisagreements,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get findingId =>
      text().references(ReviewFindings, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
}

@DriftDatabase(
  tables: [
    ServerProfiles,
    QueuedPrompts,
    ReviewRuns,
    ReviewFiles,
    ReviewPasses,
    ReviewOpinions,
    ReviewFindings,
    ReviewEvidenceEntries,
    ReviewDisagreements,
    ReviewDisagreementSources,
  ],
)
class PromptDatabase extends _$PromptDatabase {
  /// Opens a [PromptDatabase] over an already-configured [QueryExecutor].
  ///
  /// Production code never opens a [QueryExecutor] here directly: see
  /// `prompt_local_storage.dart`, whose platform-specific implementations
  /// apply Android/Linux's encryption pragmas (or Web's in-memory-only
  /// default) before this class runs any query.
  PromptDatabase.opened(super.executor);

  /// Opens a [PromptDatabase] over an explicit [QueryExecutor]. Tests use
  /// this to run against an in-memory Drift executor.
  PromptDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 8) {
          await migrator.addColumn(
            queuedPrompts,
            queuedPrompts.reasoningEffort,
          );
        }
        if (from < 7) {
          await migrator.addColumn(serverProfiles, serverProfiles.backend);
        }
        if (from < 2) {
          await migrator.addColumn(
            queuedPrompts,
            queuedPrompts.modelProviderId,
          );
          await migrator.addColumn(queuedPrompts, queuedPrompts.modelId);
          await migrator.addColumn(queuedPrompts, queuedPrompts.agentName);
        }
        if (from < 3) {
          await migrator.addColumn(queuedPrompts, queuedPrompts.operationType);
          await migrator.addColumn(queuedPrompts, queuedPrompts.commandName);
        }
        if (from < 4) {
          await migrator.addColumn(
            queuedPrompts,
            queuedPrompts.attachmentsJson,
          );
        }
        if (from < 5) {
          await migrator.createAll();
        }
        // v5 databases already have review tables; older databases get those
        // tables from createAll above, including the current columns.
        if (from == 5) {
          for (final column in [
            reviewRuns.profileOrigin,
            reviewRuns.profileUsername,
            reviewRuns.sessionCreatedAtMillis,
            reviewRuns.sessionUpdatedAtMillis,
            reviewRuns.parentId,
            reviewRuns.changedFiles,
            reviewRuns.additions,
            reviewRuns.deletions,
            reviewRuns.shareUrl,
            reviewRuns.modelProviderId,
            reviewRuns.modelId,
            reviewRuns.agentName,
          ]) {
            await migrator.addColumn(reviewRuns, column);
          }
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
