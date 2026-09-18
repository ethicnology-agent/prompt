import 'package:drift/drift.dart';

import '../../../data/local/prompt_database.dart' as db;
import '../domain/queued_prompt.dart'
    show QueuedAttachment, QueuedOperationType, QueuedPromptState;
import 'queued_attachment_codec.dart';
import '../domain/prompt_execution_options.dart';

/// Thrown when a queue operation targets a prompt id that no longer exists.
class QueuedPromptNotFound implements Exception {
  const QueuedPromptNotFound(this.id);

  final String id;
}

/// Thrown when a queue operation is not a valid transition from the
/// prompt's current stored state.
class InvalidQueuedPromptTransition implements Exception {
  const InvalidQueuedPromptTransition(this.id, this.fromState);

  final String id;
  final String fromState;
}

/// Thrown when a reorder does not exactly match the session's currently
/// reorderable prompts, or a prompt in that session is `sending`.
class InvalidQueueReorder implements Exception {
  const InvalidQueueReorder();
}

/// Prompt states that a queue mutation is allowed to reorder or remove
/// without racing an in-flight send.
const _reorderableStates = {'queued', 'paused', 'failed'};

/// Checks fresh stored rows before either storage implementation merges them.
void validateQueuedPromptMerge(
  db.QueuedPrompt target,
  db.QueuedPrompt source,
  List<db.QueuedPrompt> rows,
) {
  final active = rows.where((row) => row.state != 'acknowledged').toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  final index = active.indexWhere((row) => row.id == source.id);
  if (target.id == source.id ||
      target.serverProfileId != source.serverProfileId ||
      target.sessionId != source.sessionId ||
      target.directory != source.directory ||
      index <= 0 ||
      active[index - 1].id != target.id ||
      !_reorderableStates.contains(target.state) ||
      !_reorderableStates.contains(source.state) ||
      target.operationType != 'prompt' ||
      source.operationType != 'prompt' ||
      target.pauseReason == 'submissionUnknown' ||
      source.pauseReason == 'submissionUnknown' ||
      target.pauseReason == 'sessionDeleted' ||
      source.pauseReason == 'sessionDeleted' ||
      source.attachmentsJson != null) {
    throw InvalidQueuedPromptTransition(source.id, source.state);
  }
}

/// Backing storage for the local prompt queue.
///
/// [DriftQueuePromptsDao] is the Android/Linux implementation, backed by
/// an encrypted on-disk Drift database. [InMemoryQueuePromptsDao] (in
/// `in_memory_queue_prompts_dao.dart`) is Web's memory-only default: it
/// implements the exact same state machine without persisting anything,
/// since Web has no equivalent to SQLite3MultipleCiphers-at-rest
/// encryption in this build.
///
/// No implementation may log [db.QueuedPrompt.promptText] or send network
/// requests; each only reads and writes its own local storage.
abstract interface class QueuePromptsDao {
  /// Durably abandons pending work before a session deletion is attempted.
  Future<void> pauseForSessionDeletion(
    String serverProfileId,
    Set<String> sessionIds,
  );

  /// Removes sensitive content only after remote deletion is confirmed.
  Future<void> deleteForSessions(
    String serverProfileId,
    Set<String> sessionIds,
  );

  Future<db.QueuedPrompt> enqueue({
    required String id,
    required String serverProfileId,
    required String sessionId,
    required String directory,
    required String promptText,
    QueuedOperationType operationType = QueuedOperationType.prompt,
    String? commandName,
    List<QueuedAttachment> attachments = const <QueuedAttachment>[],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
    required DateTime now,
  });

  Future<db.QueuedPrompt> editText({
    required String id,
    required String promptText,
    required DateTime now,
  });

  /// Deletes the prompt and returns the row as it was immediately before
  /// deletion. Rejects removing a prompt that is currently `sending`.
  Future<db.QueuedPrompt> remove(String id);

  /// Appends source text and deletes source atomically, using current rows.
  Future<db.QueuedPrompt> merge({
    required String targetId,
    required String sourceId,
    required DateTime now,
  });

  Stream<List<db.QueuedPrompt>> watchQueue({
    required String serverProfileId,
    required String sessionId,
  });

  /// Reassigns positions for the session's `queued`, `paused`, and `failed`
  /// prompts to match [orderedIds]. Rejects the reorder unless [orderedIds]
  /// is exactly the set of that session's reorderable prompt ids, and
  /// unless none of that session's prompts are currently `sending`.
  Future<List<db.QueuedPrompt>> reorder({
    required String serverProfileId,
    required String sessionId,
    required List<String> orderedIds,
  });

  Future<db.QueuedPrompt> markSending(String id, {required DateTime now});

  Future<db.QueuedPrompt> markAcknowledged(String id, {required DateTime now});

  Future<db.QueuedPrompt> markFailed(
    String id, {
    String? reason,
    required DateTime now,
  });

  Future<db.QueuedPrompt> markPaused(
    String id, {
    required String reason,
    required DateTime now,
  });

  Future<db.QueuedPrompt> markQueued(String id, {required DateTime now});

  /// Transitions a `sending` prompt directly to `paused` with reason
  /// `submissionUnknown`, without touching [db.QueuedPrompt.attemptCount].
  ///
  /// Callers use this both to reconcile a `sending` prompt found persisted
  /// at activation (the app restarted, or the session was reactivated,
  /// while a send was in flight) and after a transport-uncertain failure
  /// from `prompt_async` itself. Either way, whether the server actually
  /// received the prompt is genuinely unknown; no implementation retries
  /// this automatically, and a human must resume or remove it after
  /// checking the conversation.
  Future<db.QueuedPrompt> markSubmissionUnknown(
    String id, {
    required DateTime now,
  });
}

/// Drift-backed access to the `QueuedPrompts` table. Every mutation that
/// checks or changes a prompt's state runs inside a single transaction so
/// concurrent callers never observe or act on a half-applied change.
///
/// This DAO never logs [db.QueuedPrompt.promptText] and never sends
/// network requests; it only reads and writes the local database.
class DriftQueuePromptsDao implements QueuePromptsDao {
  DriftQueuePromptsDao(this._database);

  final db.PromptDatabase _database;
  final Set<(String, String)> _deletingSessions = {};

  @override
  Future<db.QueuedPrompt> merge({
    required String targetId,
    required String sourceId,
    required DateTime now,
  }) => _database.transaction(() async {
    final target = await _requireRow(targetId);
    final source = await _requireRow(sourceId);
    await _requireSessionWritable(
      source.serverProfileId,
      source.sessionId,
      sourceId,
    );
    final rows =
        await (_database.select(_database.queuedPrompts)..where(
              (row) =>
                  row.serverProfileId.equals(source.serverProfileId) &
                  row.sessionId.equals(source.sessionId),
            ))
            .get();
    validateQueuedPromptMerge(target, source, rows);
    await _updateRow(
      targetId,
      db.QueuedPromptsCompanion(
        promptText: Value('${target.promptText}\n\n${source.promptText}'),
        updatedAtMillis: Value(now.millisecondsSinceEpoch),
      ),
    );
    await (_database.delete(
      _database.queuedPrompts,
    )..where((row) => row.id.equals(sourceId))).go();
    return _requireRow(targetId);
  });

  @override
  Future<void> pauseForSessionDeletion(
    String serverProfileId,
    Set<String> sessionIds,
  ) {
    _deletingSessions.addAll(sessionIds.map((id) => (serverProfileId, id)));
    return _database.transaction(() async {
      await (_database.update(_database.queuedPrompts)..where(
            (t) =>
                t.serverProfileId.equals(serverProfileId) &
                t.sessionId.isIn(sessionIds) &
                t.state.equals('acknowledged').not(),
          ))
          .write(
            db.QueuedPromptsCompanion(
              state: const Value('paused'),
              pauseReason: const Value('sessionDeleted'),
              updatedAtMillis: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    });
  }

  @override
  Future<void> deleteForSessions(
    String serverProfileId,
    Set<String> sessionIds,
  ) async {
    _deletingSessions.addAll(sessionIds.map((id) => (serverProfileId, id)));
    await (_database.delete(_database.queuedPrompts)..where(
          (t) =>
              t.serverProfileId.equals(serverProfileId) &
              t.sessionId.isIn(sessionIds),
        ))
        .go();
  }

  Future<void> _requireSessionWritable(
    String profileId,
    String sessionId,
    String promptId,
  ) async {
    final blocked =
        _deletingSessions.contains((profileId, sessionId)) ||
        await (_database.select(_database.queuedPrompts)
                  ..where(
                    (t) =>
                        t.serverProfileId.equals(profileId) &
                        t.sessionId.equals(sessionId) &
                        t.pauseReason.equals('sessionDeleted'),
                  )
                  ..limit(1))
                .getSingleOrNull() !=
            null;
    if (blocked) {
      throw InvalidQueuedPromptTransition(promptId, 'sessionDeleted');
    }
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
    List<QueuedAttachment> attachments = const <QueuedAttachment>[],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
    required DateTime now,
  }) {
    return _database.transaction(() async {
      await _requireSessionWritable(serverProfileId, sessionId, id);
      final nextPosition = await _nextPosition(serverProfileId, sessionId);
      final nowMillis = now.millisecondsSinceEpoch;
      await _database
          .into(_database.queuedPrompts)
          .insert(
            db.QueuedPromptsCompanion.insert(
              id: id,
              serverProfileId: serverProfileId,
              sessionId: sessionId,
              directory: directory,
              position: nextPosition,
              promptText: promptText,
              operationType: Value(operationType.name),
              commandName: Value(commandName),
              attachmentsJson: Value(encodeQueuedAttachments(attachments)),
              modelProviderId: Value(executionOptions.modelProviderId),
              modelId: Value(executionOptions.modelId),
              agentName: Value(executionOptions.agentName),
              reasoningEffort: Value(executionOptions.reasoningEffort),
              state: QueuedPromptState.queued.name,
              createdAtMillis: nowMillis,
              updatedAtMillis: nowMillis,
            ),
          );
      return _requireRow(id);
    });
  }

  @override
  Future<db.QueuedPrompt> editText({
    required String id,
    required String promptText,
    required DateTime now,
  }) {
    return _database.transaction(() async {
      final row = await _requireRow(id);
      _requireState(row, const {'queued', 'paused'});
      await _updateRow(
        id,
        db.QueuedPromptsCompanion(
          promptText: Value(promptText),
          updatedAtMillis: Value(now.millisecondsSinceEpoch),
        ),
      );
      return _requireRow(id);
    });
  }

  @override
  Future<db.QueuedPrompt> remove(String id) {
    return _database.transaction(() async {
      final row = await _requireRow(id);
      if (row.state == 'sending') {
        throw InvalidQueuedPromptTransition(id, row.state);
      }
      await (_database.delete(
        _database.queuedPrompts,
      )..where((t) => t.id.equals(id))).go();
      return row;
    });
  }

  @override
  Stream<List<db.QueuedPrompt>> watchQueue({
    required String serverProfileId,
    required String sessionId,
  }) {
    return (_database.select(_database.queuedPrompts)
          ..where(
            (t) =>
                t.serverProfileId.equals(serverProfileId) &
                t.sessionId.equals(sessionId),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  @override
  Future<List<db.QueuedPrompt>> reorder({
    required String serverProfileId,
    required String sessionId,
    required List<String> orderedIds,
  }) {
    return _database.transaction(() async {
      final rows =
          await (_database.select(_database.queuedPrompts)..where(
                (t) =>
                    t.serverProfileId.equals(serverProfileId) &
                    t.sessionId.equals(sessionId),
              ))
              .get();

      if (rows.any((row) => row.state == 'sending')) {
        throw const InvalidQueueReorder();
      }

      final reorderable = rows
          .where((row) => _reorderableStates.contains(row.state))
          .toList();
      final reorderableIds = reorderable.map((row) => row.id).toSet();
      if (reorderableIds.length != orderedIds.length ||
          reorderableIds.length != orderedIds.toSet().length ||
          !reorderableIds.containsAll(orderedIds)) {
        throw const InvalidQueueReorder();
      }

      // The reorderable prompts keep the same set of position "slots" they
      // already occupy; only the assignment of ids to slots changes. This
      // guarantees no collision with the position of a fixed (`sending` or
      // `acknowledged`) row, without renumbering the whole session.
      final slots = reorderable.map((row) => row.position).toList()..sort();

      // First pass moves every reordered row to a temporary negative slot
      // so the unique (serverProfileId, sessionId, position) index never
      // sees two rows share a position mid-transaction.
      for (var i = 0; i < orderedIds.length; i++) {
        await _updateRow(
          orderedIds[i],
          db.QueuedPromptsCompanion(position: Value(-(i + 1))),
        );
      }
      for (var i = 0; i < orderedIds.length; i++) {
        await _updateRow(
          orderedIds[i],
          db.QueuedPromptsCompanion(position: Value(slots[i])),
        );
      }

      return (_database.select(_database.queuedPrompts)
            ..where(
              (t) =>
                  t.serverProfileId.equals(serverProfileId) &
                  t.sessionId.equals(sessionId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();
    });
  }

  @override
  Future<db.QueuedPrompt> markSending(String id, {required DateTime now}) {
    return _transition(
      id,
      from: const {'queued'},
      to: 'sending',
      apply: (companion) => companion.copyWith(
        sendingStartedAtMillis: Value(now.millisecondsSinceEpoch),
      ),
      now: now,
      incrementAttempt: true,
    );
  }

  @override
  Future<db.QueuedPrompt> markAcknowledged(String id, {required DateTime now}) {
    return _transition(
      id,
      from: const {'sending'},
      to: 'acknowledged',
      apply: (companion) => companion.copyWith(
        acknowledgedAtMillis: Value(now.millisecondsSinceEpoch),
        pauseReason: const Value(null),
        // The server has accepted the prompt, so queued attachment bytes are
        // no longer required for recovery. Retaining them would unnecessarily
        // keep user file content in the durable queue.
        attachmentsJson: const Value(null),
      ),
      now: now,
    );
  }

  @override
  Future<db.QueuedPrompt> markFailed(
    String id, {
    String? reason,
    required DateTime now,
  }) {
    return _transition(
      id,
      from: const {'sending'},
      to: 'failed',
      apply: (companion) => companion.copyWith(pauseReason: Value(reason)),
      now: now,
    );
  }

  @override
  Future<db.QueuedPrompt> markPaused(
    String id, {
    required String reason,
    required DateTime now,
  }) {
    return _transition(
      id,
      from: const {'queued', 'failed'},
      to: 'paused',
      apply: (companion) => companion.copyWith(pauseReason: Value(reason)),
      now: now,
    );
  }

  @override
  Future<db.QueuedPrompt> markQueued(String id, {required DateTime now}) {
    return _transition(
      id,
      from: const {'paused'},
      to: 'queued',
      apply: (companion) => companion.copyWith(pauseReason: const Value(null)),
      now: now,
    );
  }

  /// `prompt_async` is fire-and-forget: a transport failure, an app
  /// restart, or reactivating a session never tells Prompt whether the
  /// server actually received the prompt. This transition is the only way
  /// a `sending` row leaves that state without a definitive server
  /// response, and it never retries automatically.
  @override
  Future<db.QueuedPrompt> markSubmissionUnknown(
    String id, {
    required DateTime now,
  }) {
    return _transition(
      id,
      from: const {'sending'},
      to: 'paused',
      apply: (companion) =>
          companion.copyWith(pauseReason: const Value('submissionUnknown')),
      now: now,
    );
  }

  Future<db.QueuedPrompt> _transition(
    String id, {
    required Set<String> from,
    required String to,
    required DateTime now,
    db.QueuedPromptsCompanion Function(db.QueuedPromptsCompanion companion)?
    apply,
    bool incrementAttempt = false,
  }) {
    return _database.transaction(() async {
      final row = await _requireRow(id);
      _requireState(row, from);
      if (to == 'queued' || to == 'sending') {
        await _requireSessionWritable(row.serverProfileId, row.sessionId, id);
      }
      var companion = db.QueuedPromptsCompanion(
        state: Value(to),
        updatedAtMillis: Value(now.millisecondsSinceEpoch),
        attemptCount: incrementAttempt
            ? Value(row.attemptCount + 1)
            : const Value.absent(),
      );
      if (apply != null) {
        companion = apply(companion);
      }
      await _updateRow(id, companion);
      return _requireRow(id);
    });
  }

  Future<int> _nextPosition(String serverProfileId, String sessionId) async {
    final maxPositionExpression = _database.queuedPrompts.position.max();
    final query = _database.selectOnly(_database.queuedPrompts)
      ..addColumns([maxPositionExpression])
      ..where(
        _database.queuedPrompts.serverProfileId.equals(serverProfileId) &
            _database.queuedPrompts.sessionId.equals(sessionId),
      );
    final row = await query.getSingle();
    final maxPosition = row.read(maxPositionExpression);
    return (maxPosition ?? -1) + 1;
  }

  Future<db.QueuedPrompt> _requireRow(String id) async {
    final row = await (_database.select(
      _database.queuedPrompts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw QueuedPromptNotFound(id);
    }
    return row;
  }

  void _requireState(db.QueuedPrompt row, Set<String> allowed) {
    if (!allowed.contains(row.state)) {
      throw InvalidQueuedPromptTransition(row.id, row.state);
    }
  }

  Future<void> _updateRow(String id, db.QueuedPromptsCompanion companion) {
    return (_database.update(
      _database.queuedPrompts,
    )..where((t) => t.id.equals(id))).write(companion);
  }
}
