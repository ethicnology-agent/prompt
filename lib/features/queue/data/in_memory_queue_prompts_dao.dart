import 'dart:async';

import '../../../data/local/prompt_database.dart' as db;
import '../domain/queued_prompt.dart'
    show QueuedAttachment, QueuedOperationType, QueuedPromptState;
import 'queued_attachment_codec.dart';
import '../domain/prompt_execution_options.dart';
import 'queue_prompts_dao.dart';

/// Web's memory-only default [QueuePromptsDao]: implements the exact same
/// state machine and validation rules as [DriftQueuePromptsDao], entirely
/// in process memory. Nothing here is written to browser storage; every
/// queued prompt is lost when the page is closed or reloaded, matching
/// Web's default of never persisting prompt content.
///
/// This never logs [db.QueuedPrompt.promptText] and never sends network
/// requests, exactly like the Drift-backed implementation.
class InMemoryQueuePromptsDao implements QueuePromptsDao {
  final List<db.QueuedPrompt> _rows = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Set<(String, String)> _deletingSessions = {};

  @override
  Future<db.QueuedPrompt> merge({
    required String targetId,
    required String sourceId,
    required DateTime now,
  }) async {
    final target = _requireRow(targetId);
    final source = _requireRow(sourceId);
    _requireSessionWritable(source.serverProfileId, source.sessionId, sourceId);
    final rows = _rows
        .where(
          (row) =>
              row.serverProfileId == source.serverProfileId &&
              row.sessionId == source.sessionId,
        )
        .toList();
    validateQueuedPromptMerge(target, source, rows);
    final merged = target.copyWith(
      promptText: '${target.promptText}\n\n${source.promptText}',
      updatedAtMillis: now.millisecondsSinceEpoch,
    );
    _rows[_rows.indexOf(target)] = merged;
    _rows.removeWhere((row) => row.id == sourceId);
    _notify();
    return merged;
  }

  @override
  Future<void> pauseForSessionDeletion(
    String serverProfileId,
    Set<String> sessionIds,
  ) async {
    _deletingSessions.addAll(sessionIds.map((id) => (serverProfileId, id)));
    for (final row in _rows.toList()) {
      if (row.serverProfileId == serverProfileId &&
          sessionIds.contains(row.sessionId) &&
          row.state != 'acknowledged') {
        _transition(
          row.id,
          from: {row.state},
          to: 'paused',
          now: DateTime.now(),
          pauseReason: 'sessionDeleted',
        );
      }
    }
  }

  @override
  Future<void> deleteForSessions(
    String serverProfileId,
    Set<String> sessionIds,
  ) async {
    _deletingSessions.addAll(sessionIds.map((id) => (serverProfileId, id)));
    _rows.removeWhere(
      (row) =>
          row.serverProfileId == serverProfileId &&
          sessionIds.contains(row.sessionId),
    );
    _notify();
  }

  void _requireSessionWritable(
    String profileId,
    String sessionId,
    String promptId,
  ) {
    if (_deletingSessions.contains((profileId, sessionId)) ||
        _rows.any(
          (row) =>
              row.serverProfileId == profileId &&
              row.sessionId == sessionId &&
              row.pauseReason == 'sessionDeleted',
        )) {
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
  }) async {
    _requireSessionWritable(serverProfileId, sessionId, id);
    final nowMillis = now.millisecondsSinceEpoch;
    final row = db.QueuedPrompt(
      id: id,
      serverProfileId: serverProfileId,
      sessionId: sessionId,
      directory: directory,
      position: _nextPosition(serverProfileId, sessionId),
      promptText: promptText,
      operationType: operationType.name,
      commandName: commandName,
      attachmentsJson: encodeQueuedAttachments(attachments),
      modelProviderId: executionOptions.modelProviderId,
      modelId: executionOptions.modelId,
      agentName: executionOptions.agentName,
      reasoningEffort: executionOptions.reasoningEffort,
      state: QueuedPromptState.queued.name,
      attemptCount: 0,
      createdAtMillis: nowMillis,
      updatedAtMillis: nowMillis,
    );
    _rows.add(row);
    _notify();
    return row;
  }

  @override
  Future<db.QueuedPrompt> editText({
    required String id,
    required String promptText,
    required DateTime now,
  }) async {
    final row = _requireRow(id);
    _requireState(row, const {'queued', 'paused'});
    return _replace(
      db.QueuedPrompt(
        id: row.id,
        serverProfileId: row.serverProfileId,
        sessionId: row.sessionId,
        directory: row.directory,
        position: row.position,
        promptText: promptText,
        operationType: row.operationType,
        commandName: row.commandName,
        attachmentsJson: row.attachmentsJson,
        modelProviderId: row.modelProviderId,
        modelId: row.modelId,
        agentName: row.agentName,
        reasoningEffort: row.reasoningEffort,
        state: row.state,
        pauseReason: row.pauseReason,
        attemptCount: row.attemptCount,
        createdAtMillis: row.createdAtMillis,
        updatedAtMillis: now.millisecondsSinceEpoch,
        sendingStartedAtMillis: row.sendingStartedAtMillis,
        acknowledgedAtMillis: row.acknowledgedAtMillis,
      ),
    );
  }

  @override
  Future<db.QueuedPrompt> remove(String id) async {
    final row = _requireRow(id);
    if (row.state == 'sending') {
      throw InvalidQueuedPromptTransition(id, row.state);
    }
    _rows.removeWhere((candidate) => candidate.id == id);
    _notify();
    return row;
  }

  @override
  Stream<List<db.QueuedPrompt>> watchQueue({
    required String serverProfileId,
    required String sessionId,
  }) {
    late final StreamController<List<db.QueuedPrompt>> controller;
    StreamSubscription<void>? subscription;
    controller = StreamController<List<db.QueuedPrompt>>(
      onListen: () {
        controller.add(_snapshot(serverProfileId, sessionId));
        subscription = _changes.stream.listen((_) {
          controller.add(_snapshot(serverProfileId, sessionId));
        });
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<db.QueuedPrompt>> reorder({
    required String serverProfileId,
    required String sessionId,
    required List<String> orderedIds,
  }) async {
    final rows = _rowsFor(serverProfileId, sessionId);
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

    final slots = reorderable.map((row) => row.position).toList()..sort();
    for (var i = 0; i < orderedIds.length; i++) {
      final row = _requireRow(orderedIds[i]);
      _replaceSilently(
        db.QueuedPrompt(
          id: row.id,
          serverProfileId: row.serverProfileId,
          sessionId: row.sessionId,
          directory: row.directory,
          position: slots[i],
          promptText: row.promptText,
          operationType: row.operationType,
          commandName: row.commandName,
          attachmentsJson: row.attachmentsJson,
          modelProviderId: row.modelProviderId,
          modelId: row.modelId,
          agentName: row.agentName,
          reasoningEffort: row.reasoningEffort,
          state: row.state,
          pauseReason: row.pauseReason,
          attemptCount: row.attemptCount,
          createdAtMillis: row.createdAtMillis,
          updatedAtMillis: row.updatedAtMillis,
          sendingStartedAtMillis: row.sendingStartedAtMillis,
          acknowledgedAtMillis: row.acknowledgedAtMillis,
        ),
      );
    }
    _notify();
    return _snapshot(serverProfileId, sessionId);
  }

  @override
  Future<db.QueuedPrompt> markSending(
    String id, {
    required DateTime now,
  }) async {
    return _transition(
      id,
      from: const {'queued'},
      to: 'sending',
      now: now,
      incrementAttempt: true,
      sendingStartedAtMillis: now.millisecondsSinceEpoch,
    );
  }

  @override
  Future<db.QueuedPrompt> markAcknowledged(
    String id, {
    required DateTime now,
  }) async {
    return _transition(
      id,
      from: const {'sending'},
      to: 'acknowledged',
      now: now,
      acknowledgedAtMillis: now.millisecondsSinceEpoch,
      pauseReason: null,
      attachmentsJson: null,
    );
  }

  @override
  Future<db.QueuedPrompt> markFailed(
    String id, {
    String? reason,
    required DateTime now,
  }) async {
    return _transition(
      id,
      from: const {'sending'},
      to: 'failed',
      now: now,
      pauseReason: reason,
    );
  }

  @override
  Future<db.QueuedPrompt> markPaused(
    String id, {
    required String reason,
    required DateTime now,
  }) async {
    return _transition(
      id,
      from: const {'queued', 'failed'},
      to: 'paused',
      now: now,
      pauseReason: reason,
    );
  }

  @override
  Future<db.QueuedPrompt> markQueued(String id, {required DateTime now}) async {
    return _transition(
      id,
      from: const {'paused'},
      to: 'queued',
      now: now,
      pauseReason: null,
    );
  }

  @override
  Future<db.QueuedPrompt> markSubmissionUnknown(
    String id, {
    required DateTime now,
  }) async {
    return _transition(
      id,
      from: const {'sending'},
      to: 'paused',
      now: now,
      pauseReason: 'submissionUnknown',
    );
  }

  /// Applies a state transition. [pauseReason] and [attachmentsJson] use
  /// [_unset] as their default so a transition that never mentions either
  /// value (such as
  /// [markSending]) leaves the row's existing pause reason untouched,
  /// while a transition that explicitly passes `null` (such as
  /// [markAcknowledged] and [markQueued]) clears it - mirroring how
  /// `DriftQueuePromptsDao` distinguishes `Value.absent()` from
  /// `Value(null)`.
  db.QueuedPrompt _transition(
    String id, {
    required Set<String> from,
    required String to,
    required DateTime now,
    bool incrementAttempt = false,
    Object? pauseReason = _unset,
    Object? attachmentsJson = _unset,
    int? sendingStartedAtMillis,
    int? acknowledgedAtMillis,
  }) {
    final row = _requireRow(id);
    _requireState(row, from);
    if (to == 'queued' || to == 'sending') {
      _requireSessionWritable(row.serverProfileId, row.sessionId, id);
    }
    final replaced = db.QueuedPrompt(
      id: row.id,
      serverProfileId: row.serverProfileId,
      sessionId: row.sessionId,
      directory: row.directory,
      position: row.position,
      promptText: row.promptText,
      operationType: row.operationType,
      commandName: row.commandName,
      attachmentsJson: identical(attachmentsJson, _unset)
          ? row.attachmentsJson
          : attachmentsJson as String?,
      modelProviderId: row.modelProviderId,
      modelId: row.modelId,
      agentName: row.agentName,
      reasoningEffort: row.reasoningEffort,
      state: to,
      pauseReason: identical(pauseReason, _unset)
          ? row.pauseReason
          : pauseReason as String?,
      attemptCount: incrementAttempt ? row.attemptCount + 1 : row.attemptCount,
      createdAtMillis: row.createdAtMillis,
      updatedAtMillis: now.millisecondsSinceEpoch,
      sendingStartedAtMillis:
          sendingStartedAtMillis ?? row.sendingStartedAtMillis,
      acknowledgedAtMillis: acknowledgedAtMillis ?? row.acknowledgedAtMillis,
    );
    return _replace(replaced);
  }

  int _nextPosition(String serverProfileId, String sessionId) {
    final positions = _rowsFor(
      serverProfileId,
      sessionId,
    ).map((row) => row.position);
    return positions.isEmpty
        ? 0
        : positions.reduce((a, b) => a > b ? a : b) + 1;
  }

  List<db.QueuedPrompt> _rowsFor(String serverProfileId, String sessionId) {
    return _rows
        .where(
          (row) =>
              row.serverProfileId == serverProfileId &&
              row.sessionId == sessionId,
        )
        .toList();
  }

  List<db.QueuedPrompt> _snapshot(String serverProfileId, String sessionId) {
    final rows = _rowsFor(serverProfileId, sessionId)
      ..sort((a, b) => a.position.compareTo(b.position));
    return List.unmodifiable(rows);
  }

  db.QueuedPrompt _requireRow(String id) {
    for (final row in _rows) {
      if (row.id == id) {
        return row;
      }
    }
    throw QueuedPromptNotFound(id);
  }

  void _requireState(db.QueuedPrompt row, Set<String> allowed) {
    if (!allowed.contains(row.state)) {
      throw InvalidQueuedPromptTransition(row.id, row.state);
    }
  }

  db.QueuedPrompt _replace(db.QueuedPrompt row) {
    final replaced = _replaceSilently(row);
    _notify();
    return replaced;
  }

  db.QueuedPrompt _replaceSilently(db.QueuedPrompt row) {
    final index = _rows.indexWhere((candidate) => candidate.id == row.id);
    if (index == -1) {
      throw QueuedPromptNotFound(row.id);
    }
    _rows[index] = row;
    return row;
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

/// Prompt states that a queue mutation is allowed to reorder or remove
/// without racing an in-flight send. Kept identical to
/// `queue_prompts_dao.dart`'s private constant so both implementations
/// enforce the same rule.
const _reorderableStates = {'queued', 'paused', 'failed'};

/// Sentinel distinguishing "leave the pause reason as-is" from
/// "explicitly set the pause reason to null" in [InMemoryQueuePromptsDao].
const Object _unset = Object();
