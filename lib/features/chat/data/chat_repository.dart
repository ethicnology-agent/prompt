import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../../data/remote/opencode_event_service.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../../queue/queue.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_page_result.dart';
import '../domain/chat_message.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import '../domain/session_execution_state.dart';
import '../domain/session_block_reason.dart';
import '../domain/session_artifacts.dart';
import '../domain/conversation_event.dart';
import '../domain/conversation_state.dart';
import 'opencode_chat_service.dart';
import 'chat_data_mapper.dart';
import 'conversation_sync.dart';

class ChatRepository {
  ChatRepository(this._chatService, this._credentialsStore);

  final OpenCodeChatService _chatService;
  final CredentialsStore _credentialsStore;

  final ValueNotifier<ConversationRepositoryState> _conversation =
      ValueNotifier(
        const ConversationRepositoryState(
          messages: <ChatMessage>[],
          conversation: ConversationState(),
        ),
      );
  final ValueNotifier<ConversationState> _conversationState = ValueNotifier(
    const ConversationState(),
  );
  final ValueNotifier<ChatHistoryState> _history = ValueNotifier(
    const ChatHistoryState(messages: <ChatMessage>[], hasMore: false),
  );
  final List<_RecordedEvent> _events = <_RecordedEvent>[];
  int _eventSequence = 0;
  int _loadGeneration = 0;
  Future<ChatLoadResult>? _latestLoad;
  int _latestLoadGeneration = 0;
  (String, String, String)? _latestLoadScope;
  OpenCodeSession? _activeSession;
  String? _olderCursor;
  bool _hasMore = false;
  bool _cursorUnavailable = false;
  bool _loadingOlder = false;
  ChatFailure? _historyFailure;

  ValueListenable<ConversationRepositoryState> get conversationUpdates =>
      _conversation;

  ValueListenable<ConversationState> get conversationStateUpdates =>
      _conversationState;

  ValueListenable<ChatHistoryState> get historyUpdates => _history;

  void activateConversation(OpenCodeSession session) {
    if (_activeSession?.id == session.id &&
        _activeSession?.directory == session.directory) {
      return;
    }
    _activeSession = session;
    _loadGeneration++;
    _resetPagination();
    _historyFailure = null;
    _events.clear();
    _conversation.value = const ConversationRepositoryState(
      messages: <ChatMessage>[],
      conversation: ConversationState(),
    );
    _conversationState.value = const ConversationState();
    _publishHistory(const <ChatMessage>[]);
  }

  void deactivateConversation() {
    _activeSession = null;
    _latestLoad = null;
    _latestLoadScope = null;
    _loadGeneration++;
    _resetPagination();
    _historyFailure = null;
    _events.clear();
    _conversation.value = const ConversationRepositoryState(
      messages: <ChatMessage>[],
      conversation: ConversationState(),
    );
    _conversationState.value = const ConversationState();
    _publishHistory(const <ChatMessage>[]);
  }

  void applyEvent(ConversationEvent event) {
    if (_activeSession == null || event.sessionId != _activeSession!.id) return;
    final state = reduceConversationEvent(
      _conversation.value.conversation,
      event,
    );
    _eventSequence++;
    _events.add(_RecordedEvent(_eventSequence, event));
    final messages = _applyRemoval(event, _conversation.value.messages);
    _publish(state, messages);
  }

  void applyEnvelope(OpenCodeEventEnvelope envelope, OpenCodeSession session) {
    if (_activeSession?.id != session.id) return;
    final event = mapConversationEvent(
      envelope,
      sessionId: session.id,
      directory: session.directory,
    );
    if (event != null) applyEvent(event);
  }

  void applySessionState(String sessionId, SessionExecutionState state) {
    applyEvent(SessionStatusEvent(sessionId: sessionId, state: state));
  }

  void applyBlocked(String sessionId, PendingApproval approval) {
    applyEvent(
      SessionBlockedEvent(
        sessionId: sessionId,
        reason: approval is PendingQuestionApproval
            ? SessionBlockReason.question
            : SessionBlockReason.permission,
        detail: approval,
      ),
    );
  }

  void clearApproval(String sessionId) {
    final state = clearPendingApproval(
      _conversation.value.conversation,
      sessionId,
    );
    _publish(state, _conversation.value.messages);
  }

  Future<ChatLoadResult> load(ServerProfile profile, OpenCodeSession session) {
    final result = _load(profile, session);
    _latestLoad = result;
    _latestLoadGeneration = _loadGeneration;
    _latestLoadScope = (profile.id, session.id, session.directory);
    return result;
  }

  Future<ChatLoadResult> _load(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    _activeSession ??= session;
    final loadGeneration = ++_loadGeneration;
    // These two values are one explicit snapshot boundary. Events newer than
    // this pair are replayed after REST, while older events are already in the
    // captured conversation state.
    final snapshotStart = _eventSequence;
    final stateAtSnapshotStart = _conversation.value.conversation;
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      final page = await _chatService.listMessages(profile, password, session);
      if (loadGeneration != _loadGeneration) {
        // Startup/reconnect and the visible screen can request overlapping
        // snapshots. Never report an empty successful transcript merely
        // because a newer authoritative request has not finished yet.
        if (_latestLoadGeneration > loadGeneration &&
            _latestLoadScope == (profile.id, session.id, session.directory)) {
          return _latestLoad!;
        }
        return ChatLoaded(
          _conversation.value.messages,
          hasMore: _hasMore,
          cursorUnavailable: _cursorUnavailable,
        );
      }
      final messages = page.records
          .where(
            (record) => record.role == 'user' || record.role == 'assistant',
          )
          .map(mapChatMessage)
          .toList(growable: false);
      final replay = _events.where((event) => event.sequence > snapshotStart);
      var state = ConversationState(
        sessionStates: stateAtSnapshotStart.sessionStates,
        sessionBlocks: stateAtSnapshotStart.sessionBlocks,
        pendingApprovals: stateAtSnapshotStart.pendingApprovals,
      );
      var consolidatedMessages = messages;
      for (final event in replay) {
        state = reduceConversationEvent(state, event.event);
        consolidatedMessages = _applyRemoval(event.event, consolidatedMessages);
      }
      _events.removeWhere((event) => event.sequence <= snapshotStart);
      _publish(state, consolidatedMessages);
      _olderCursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _cursorUnavailable = page.cursorUnavailable;
      _historyFailure = null;
      _publishHistory(_conversation.value.messages);
      return ChatLoaded(
        _conversation.value.messages,
        hasMore: _hasMore,
        cursorUnavailable: _cursorUnavailable,
      );
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return _loadFailure(ChatFailure.unauthorized);
      }
      return _loadFailure(ChatFailure.unexpectedResponse);
    } on TimeoutException {
      return _loadFailure(ChatFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return _loadFailure(ChatFailure.unexpectedResponse);
    } on http.ClientException {
      return _loadFailure(ChatFailure.unavailable);
    } on FormatException {
      return _loadFailure(ChatFailure.unexpectedResponse);
    }
  }

  Future<ChatLoadResult> loadOlder(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    final cursor = _olderCursor;
    final loadGeneration = _loadGeneration;
    if (_activeSession?.id != session.id ||
        _activeSession?.directory != session.directory ||
        cursor == null ||
        _loadingOlder) {
      return ChatOlderLoaded(
        _conversation.value.messages,
        hasMore: _hasMore,
        cursorUnavailable: _cursorUnavailable,
      );
    }
    _loadingOlder = true;
    _historyFailure = null;
    _publishHistory(_conversation.value.messages);
    final snapshotStart = _eventSequence;
    final stateAtSnapshotStart = _conversation.value.conversation;
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      final page = await _chatService.listMessages(
        profile,
        password,
        session,
        before: cursor,
      );
      if (loadGeneration != _loadGeneration ||
          _activeSession?.id != session.id ||
          _activeSession?.directory != session.directory) {
        return ChatOlderLoaded(
          _conversation.value.messages,
          hasMore: _hasMore,
          cursorUnavailable: _cursorUnavailable,
        );
      }
      final replay = _events.where((event) => event.sequence > snapshotStart);
      var state = stateAtSnapshotStart;
      for (final event in replay) {
        state = reduceConversationEvent(state, event.event);
      }
      final current = _conversation.value.messages;
      final existing = current.map((message) => message.id).toSet();
      var merged = [
        ...page.records
            .where(
              (record) => record.role == 'user' || record.role == 'assistant',
            )
            .map(mapChatMessage)
            .where((message) => !existing.contains(message.id)),
        ...current,
      ];
      for (final event in replay) {
        merged = _applyRemoval(event.event, merged);
      }
      _events.removeWhere((event) => event.sequence <= snapshotStart);
      _publish(state, merged);
      _olderCursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _cursorUnavailable = page.cursorUnavailable;
      _historyFailure = null;
      _publishHistory(_conversation.value.messages);
      return ChatOlderLoaded(
        _conversation.value.messages,
        hasMore: _hasMore,
        cursorUnavailable: _cursorUnavailable,
      );
    } on OpenCodeHttpFailure catch (failure) {
      return _olderFailure(_chatFailureForHttp(failure));
    } on TimeoutException {
      return _olderFailure(ChatFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return _olderFailure(ChatFailure.unexpectedResponse);
    } on http.ClientException {
      return _olderFailure(ChatFailure.unavailable);
    } on FormatException {
      return _olderFailure(ChatFailure.unexpectedResponse);
    } finally {
      _loadingOlder = false;
      _publishHistory(_conversation.value.messages);
    }
  }

  void _publish(ConversationState state, List<ChatMessage> restMessages) {
    final messages = mergeConversationMessages(restMessages, state.messages);
    _conversation.value = ConversationRepositoryState(
      messages: List.unmodifiable(messages),
      conversation: state,
    );
    _conversationState.value = state;
    _publishHistory(_conversation.value.messages);
  }

  void _resetPagination() {
    _olderCursor = null;
    _hasMore = false;
    _cursorUnavailable = false;
    _loadingOlder = false;
  }

  void _publishHistory(List<ChatMessage> messages, {ChatFailure? failure}) {
    _history.value = ChatHistoryState(
      messages: List.unmodifiable(messages),
      hasMore: _hasMore,
      loadingOlder: _loadingOlder,
      failure: failure ?? _historyFailure,
    );
  }

  ChatLoadFailed _loadFailure(ChatFailure failure) {
    _historyFailure = failure;
    _publishHistory(_conversation.value.messages);
    return ChatLoadFailed(failure);
  }

  ChatLoadResult _olderFailure(ChatFailure failure) {
    _historyFailure = failure;
    _publishHistory(_conversation.value.messages);
    return ChatLoadFailed(failure);
  }

  ChatFailure _chatFailureForHttp(OpenCodeHttpFailure failure) {
    return failure.statusCode == 401 || failure.statusCode == 403
        ? ChatFailure.unauthorized
        : ChatFailure.unexpectedResponse;
  }

  List<ChatMessage> _applyRemoval(
    ConversationEvent event,
    List<ChatMessage> messages,
  ) {
    if (event case MessageRemovedEvent(:final messageId)) {
      return messages.where((message) => message.id != messageId).toList();
    }
    if (event case MessagePartRemovedEvent(:final messageId, :final partId)) {
      return [
        for (final message in messages)
          if (message.id == messageId)
            ChatMessage(
              id: message.id,
              role: message.role,
              createdAt: message.createdAt,
              text: message.text,
              error: message.error,
              details: message.details
                  .where((detail) => detail.id != partId)
                  .toList(growable: false),
            )
          else
            message,
      ];
    }
    return messages;
  }

  Future<Result<SessionArtifactsReady, SessionArtifactsFailure>> loadArtifacts(
    ServerProfile profile,
    OpenCodeSession session, {
    String? messageId,
  }) {
    return _runArtifacts(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      final results = await Future.wait([
        _chatService.listTodos(profile, password, session),
        _chatService.listDiffs(
          profile,
          password,
          session,
          messageId: messageId,
        ),
      ]);
      return SessionArtifactsReady(
        todos: results[0]
            .cast<OpenCodeTodoRecord>()
            .map(mapSessionTodo)
            .toList(growable: false),
        diffs: results[1]
            .cast<OpenCodeFileDiffRecord>()
            .map(mapSessionDiff)
            .toList(growable: false),
      );
    });
  }

  /// Sends [text] to [session] without waiting for the assistant's reply.
  /// Never logs [text]; a caller must not log the returned failure's raw
  /// server detail either, since none is carried on [ChatFailure].
  Future<Result<void, ChatFailure>> sendPrompt(
    ServerProfile profile,
    OpenCodeSession session,
    String text, {
    String? operationId,
    List<QueuedAttachment> attachments = const <QueuedAttachment>[],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.sendPromptAsync(
        profile,
        password,
        session,
        text,
        operationId: operationId,
        attachments: attachments,
        executionOptions: executionOptions,
      );
    });
  }

  Future<Result<void, ChatFailure>> executeCommand(
    ServerProfile profile,
    OpenCodeSession session,
    String command,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.executeCommand(
        profile,
        password,
        session,
        command,
        arguments,
        executionOptions: executionOptions,
      );
    });
  }

  /// Explicitly cancels [session]'s active generation. The success value
  /// reports whether the server actually aborted something.
  Future<Result<bool, ChatFailure>> abortSession(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      return _chatService.abortSession(profile, password, session);
    });
  }

  /// Responds to a pending tool-call permission with [response]. Never
  /// logs [permissionId] or any permission detail; a caller must not log
  /// the returned failure's raw server detail either, since none is
  /// carried on [ChatFailure].
  Future<Result<void, ChatFailure>> respondToPermission(
    ServerProfile profile,
    OpenCodeSession session,
    String permissionId,
    PermissionResponse response,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.respondToPermission(
        profile,
        password,
        session,
        permissionId,
        response,
      );
    });
  }

  /// Answers a pending question request with [answers]. Never logs
  /// [requestId] or any answer text.
  Future<Result<void, ChatFailure>> replyToQuestion(
    ServerProfile profile,
    OpenCodeSession session,
    String requestId,
    List<List<String>> answers,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.replyToQuestion(
        profile,
        password,
        session,
        requestId,
        answers,
      );
    });
  }

  /// Rejects a pending question request outright. Never logs [requestId].
  Future<Result<void, ChatFailure>> rejectQuestion(
    ServerProfile profile,
    OpenCodeSession session,
    String requestId,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.rejectQuestion(profile, password, session, requestId);
    });
  }

  /// The execution state of [session], as reported by the authoritative
  /// `GET /session/status` endpoint rather than an SSE event. A session the
  /// server omits from its response has no active or retrying work.
  Future<Result<SessionExecutionState, ChatFailure>> sessionStatus(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      final statuses = await _chatService.fetchSessionStatuses(
        profile,
        password,
        session.directory,
      );
      return statuses[session.id] ?? const SessionIdle();
    });
  }

  Future<Result<List<PendingApproval>, ChatFailure>> pendingApprovals(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      return _chatService.listPendingApprovals(profile, password, session);
    });
  }

  Future<Result<T, ChatFailure>> _run<T>(Future<T> Function() operation) async {
    try {
      return Ok(await operation());
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const Err(ChatFailure.unauthorized);
      }
      return const Err(ChatFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(ChatFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(ChatFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(ChatFailure.unavailable);
    } on FormatException {
      return const Err(ChatFailure.unexpectedResponse);
    }
  }

  Future<Result<T, SessionArtifactsFailure>> _runArtifacts<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return Ok(await operation());
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const Err(SessionArtifactsFailure.unauthorized);
      }
      return const Err(SessionArtifactsFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(SessionArtifactsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(SessionArtifactsFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(SessionArtifactsFailure.unavailable);
    } on FormatException {
      return const Err(SessionArtifactsFailure.unexpectedResponse);
    }
  }
}

class _RecordedEvent {
  const _RecordedEvent(this.sequence, this.event);

  final int sequence;
  final ConversationEvent event;
}
