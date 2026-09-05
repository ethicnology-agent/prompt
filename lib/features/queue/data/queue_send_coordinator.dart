/// Orchestrates when Prompt's durable per-session queue may dispatch a
/// prompt to OpenCode.
///
/// This is deliberately a use case, not a repository: it composes
/// [QueuePromptsRepository] (the durable queue), [ChatRepository]
/// (conversation truth and `sendPrompt`/`abortSession`/`sessionStatus`), and
/// [OpenCodeEventService] (the live SSE feed). Conversation reduction remains
/// exclusively inside [ChatRepository].
///
/// Rules this type enforces:
/// - Exactly one session is coordinated at a time ("one active session
///   scope"); activating a new session tears down the previous one first.
/// - A `sending` prompt found persisted at activation is reconciled to
///   `paused`/`submissionUnknown` before anything else happens, because a
///   prior send's outcome is unknown after a restart or reactivation.
/// - The queue head only dispatches once the session's authoritative
///   status is idle and no prompt in the session is paused with
///   `submissionUnknown`; a normal enqueue never triggers an abort.
/// - `sendNow` explicitly aborts the active generation, then waits for the
///   session to settle idle before dispatching the chosen prompt.
/// - A `prompt_async` success (`204`) is definitive acceptance and marks the
///   prompt `acknowledged`; any other outcome is transport-uncertain and
///   moves the prompt to `paused`/`submissionUnknown` instead of retrying.
/// - A `permission.updated` SSE event pauses every currently `queued`
///   prompt in the active session with `permissionPending`/
///   `questionPending` and blocks all dispatch. This is a foundation only:
///   no approval UI exists yet, so `permission.replied` is never reduced or
///   acted on here. The block is lifted only when a fresh, authoritative
///   `session.status`/`session.idle` event arrives, at which point every
///   prompt this coordinator paused for that reason (and only those) moves
///   back to `queued`.
/// - Unrelated SSE events are ignored; only session status/idle updates
///   gate the queue.
/// - Nothing here logs prompt text, a permission's title/pattern/metadata,
///   or raw failure detail.
///
/// ## Lifecycle-aware reconnect
///
/// A dropped SSE connection is never silently discarded. [notifyAppInactive]
/// and [notifyAppForeground] let the app's lifecycle owner (the composition
/// root observing `AppLifecycleState`) drive this coordinator explicitly:
///
/// - Going inactive cancels the live SSE subscription and any pending
///   reconnect timer immediately; no reconnect is attempted while the app
///   is backgrounded, matching this app's battery/data budget.
/// - Returning to the foreground reconnects immediately if a session is
///   still active.
/// - An unexpected drop while foreground (a transport error, or the
///   stream simply ending) schedules a bounded exponential-backoff-with-
///   jitter reconnect via [backoffPolicy], surfaced on [connectionState] as
///   [SseReconnecting]. Retrying stops, surfaced as [SseDisconnected], once
///   [backoffPolicy] no longer permits another attempt.
/// - Every reconnect (as opposed to the very first connection of an
///   [activate] call, which trusts the status [activate] already fetched
///   moments before) re-fetches the session's authoritative status before
///   trusting anything from the new connection; [connectionState] reports
///   [SseReconciling] for that whole window. [_maybeDispatch] never
///   dispatches unless [connectionState] is [SseConnected], so queued
///   prompts never send against a connection whose missed events have not
///   yet been reconciled.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/async/reconnect_backoff.dart';
import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_event_service.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import '../../chat/chat.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../domain/queue_approval_failure.dart';
import '../domain/queue_failure.dart';
import '../domain/queue_send_now_failure.dart';
import '../domain/queued_prompt.dart';
import '../domain/sse_connection_state.dart';
import 'queue_prompts_repository.dart';

class QueueSendCoordinator {
  QueueSendCoordinator({
    required this._queueRepository,
    required this._chatRepository,
    required this._eventService,
    required this._credentialsStore,
    this.backoffPolicy = const ReconnectBackoffPolicy(),
    this.onGenerationFinished,
    math.Random? random,
    Timer Function(Duration duration, void Function() callback)?
    reconnectTimerFactory,
  }) : _random = random ?? math.Random(),
       _reconnectTimerFactory = reconnectTimerFactory ?? Timer.new;

  final QueuePromptsRepository _queueRepository;
  final ChatRepository _chatRepository;
  final OpenCodeEventService _eventService;
  final CredentialsStore _credentialsStore;

  /// Governs how long a reconnect attempt waits after an unexpected SSE
  /// drop. Injectable so a test can use a tiny bound instead of the
  /// production default.
  final ReconnectBackoffPolicy backoffPolicy;

  /// Invoked when the active session stops generating. Carries no session
  /// text, id, or failure detail: it exists so the app can raise a generic
  /// local notification while the user is looking elsewhere.
  final void Function({required bool failed})? onGenerationFinished;

  final math.Random _random;

  /// Builds the timer that fires a scheduled reconnect attempt. Injectable
  /// so a test can observe the requested delay without a real timer
  /// slowing the test down.
  final Timer Function(Duration duration, void Function() callback)
  _reconnectTimerFactory;

  ServerProfile? _profile;
  OpenCodeSession? _session;
  String? _liveStatusProfileId;
  final ValueNotifier<Map<String, OpenCodeSessionStatus>> _liveStatuses =
      ValueNotifier(const <String, OpenCodeSessionStatus>{});

  StreamSubscription<List<QueuedPrompt>>? _queueSubscription;
  StreamSubscription<OpenCodeEventEnvelope>? _sseSubscription;

  List<QueuedPrompt> _queue = const <QueuedPrompt>[];

  /// Backs [conversationStateUpdates]. Never read from outside this class;
  /// external callers only ever get the read-only [ValueListenable] view.
  /// Read-only, session-scoped view of the active session's live
  /// conversation, reduced from `message.updated`, `message.part.updated`,
  /// and the other conversation SSE events since it was [activate]d. Carries
  /// only reduced conversation domain data (message ids, roles, parts) —
  /// never queued prompt text, raw OpenCode JSON, or failure detail — so a
  /// listener must never log its value.
  ///
  /// Resets to an empty [ConversationState] on [deactivate] (and therefore
  /// on every [activate] switching to a different session), so a listener
  /// that stays subscribed across a session switch sees the next session's
  /// state rebuilt from scratch rather than a mix of two sessions. A
  /// [ValueListenable] already coalesces to "latest value wins": a burst of
  /// token-level part updates between two rebuilds still yields a single
  /// rebuild carrying the final text, not one per token.
  ValueListenable<ConversationState> get conversationStateUpdates =>
      _chatRepository.conversationStateUpdates;

  /// Latest valid execution status observed for each session in the active
  /// server profile. This is fed by the same global SSE connection used for
  /// conversation coordination.
  ValueListenable<Map<String, OpenCodeSessionStatus>> get liveStatuses =>
      _liveStatuses;

  bool _dispatchInProgress = false;
  String? _pendingSendNowPromptId;
  Future<void> _blockTransitionTail = Future<void>.value();
  final Set<String> _blockPausedPromptIds = <String>{};

  /// Bumped by every [activate] and [deactivate] call. Any pending
  /// continuation that captured an earlier value is stale and must not
  /// mutate state or trigger a dispatch.
  int _activationToken = 0;

  bool _disposed = false;

  /// Whether the app is currently foreground, as last reported by
  /// [notifyAppInactive]/[notifyAppForeground]. Assumed `true` until told
  /// otherwise, so a caller that never wires a lifecycle owner (for
  /// example most existing tests) keeps today's always-foreground
  /// behavior.
  bool _appForeground = true;

  /// 1-based count of consecutive failed reconnect attempts for the
  /// current activation. Reset on every successful connect, and on
  /// [activate]/[deactivate].
  int _reconnectAttempt = 0;

  Timer? _reconnectTimer;

  /// Bumped by every [_connect] call and by [_handleSseDrop]. Lets a
  /// slow-resolving reconnect continuation (still awaiting the
  /// authoritative status fetch) recognize that a *different* attempt —
  /// its own subscription dropping again, or a newer [_connect] — has
  /// already superseded it, so it never clobbers [connectionState] or
  /// [_reconnectAttempt] with a stale success after that.
  int _connectAttemptToken = 0;

  /// Backs [connectionState]. Never read from outside this class; external
  /// callers only ever get the read-only [ValueListenable] view.
  final ValueNotifier<SseConnectionState> _connectionState = ValueNotifier(
    const SseSuspended(),
  );

  /// The active session's live SSE connection status. See
  /// `sse_connection_state.dart` for what each value means and how
  /// [_maybeDispatch] uses it to gate dispatch.
  ValueListenable<SseConnectionState> get connectionState => _connectionState;

  /// Whether a session is currently activated.
  bool get hasActiveSession => _profile != null && _session != null;

  /// The active session's authoritative execution state, or `null` before
  /// the first status is known.
  SessionExecutionState? get currentSessionState {
    final session = _session;
    if (session == null) {
      return null;
    }
    return _chatRepository.conversationStateUpdates.value.sessionStates[session
        .id];
  }

  /// Why the active session's queue is currently blocked awaiting a human
  /// decision, or `null` if it is not blocked. Set only by a
  /// `permission.updated` SSE event; cleared only by the next authoritative
  /// `session.status`/`session.idle` event, never by `permission.replied`
  /// alone.
  SessionBlockReason? get currentSessionBlockReason {
    final session = _session;
    if (session == null) {
      return null;
    }
    return _chatRepository.conversationStateUpdates.value.sessionBlocks[session
        .id];
  }

  /// Full detail of the active session's pending permission or question,
  /// for an approval UI to render — reduced only from a live
  /// `permission.updated`/`question.asked` SSE event received since
  /// [activate], never fetched or cached beyond that. `null` whenever the
  /// session is not blocked, and also `null` once this coordinator's own
  /// [respondToPermission]/[replyToQuestion]/[rejectQuestion] call
  /// succeeds — even though [currentSessionBlockReason] stays set until an
  /// authoritative `session.status`/`session.idle` event confirms the
  /// session actually moved past it. See `pending_approval.dart`: never
  /// log or persist this value.
  PendingApproval? get currentPendingApproval {
    final session = _session;
    if (session == null) {
      return null;
    }
    return _chatRepository
        .conversationStateUpdates
        .value
        .pendingApprovals[session.id];
  }

  /// Activates queue coordination for [session] on [profile], tearing down
  /// any previously active session first.
  ///
  /// In order:
  /// 1. Reconciles any persisted `sending` prompt in this session's queue
  ///    to `paused`/`submissionUnknown`.
  /// 2. Fetches the session's authoritative execution state over REST.
  /// 3. Subscribes to the durable queue and to the live SSE feed, gating
  ///    automatic dispatch on both from then on.
  ///
  /// Pending permissions and questions are re-fetched before dispatch is
  /// enabled, so a decision emitted while the app was asleep is restored and
  /// a stale locally-paused queue can resume when the server no longer has a
  /// matching request.
  Future<void> activate({
    required ServerProfile profile,
    required OpenCodeSession session,
  }) async {
    _requireNotDisposed();
    final previousProfileId = _liveStatusProfileId;
    await deactivate();

    if (previousProfileId != profile.id) {
      _liveStatuses.value = const <String, OpenCodeSessionStatus>{};
    }
    _liveStatusProfileId = profile.id;

    _activationToken++;
    final token = _activationToken;
    _profile = profile;
    _session = session;
    _chatRepository.activateConversation(session);

    final initialQueue = await _queueRepository
        .watchQueue(profile: profile, session: session)
        .first;
    if (_isStale(token)) {
      return;
    }
    _queue = initialQueue;

    for (final prompt in initialQueue) {
      if (prompt.state == QueuedPromptState.sending) {
        await _queueRepository.markSubmissionUnknown(prompt.id);
        if (_isStale(token)) {
          return;
        }
      }
    }

    final statusResult = await _chatRepository.sessionStatus(profile, session);
    if (_isStale(token)) {
      return;
    }
    if (statusResult case Ok<SessionExecutionState, ChatFailure>(
      value: final state,
    )) {
      await _applySessionState(session.id, state);
      if (_isStale(token)) {
        return;
      }
    }
    await _reconcilePendingApprovals(profile, session, token);
    if (_isStale(token)) {
      return;
    }

    _queueSubscription = _queueRepository
        .watchQueue(profile: profile, session: session)
        .listen((rows) {
          if (_isStale(token)) {
            return;
          }
          _queue = rows;
          // A prompt enqueued (or otherwise turned `queued`) while the
          // session is already blocked must not silently bypass the block
          // that would have paused it had it existed at the time the
          // block was first observed.
          final blockReason = currentSessionBlockReason;
          if (blockReason != null) {
            unawaited(
              _serializeBlockTransition(
                () => _pauseQueuedPromptsForBlock(blockReason, token),
              ),
            );
          }
          _maybeDispatch();
        });

    // The initial connect trusts the status just fetched above, so it
    // skips the reconciliation window a reconnect goes through; see
    // `_connectAsync`.
    _connect(token: token, attempt: 0);

    _maybeDispatch();
  }

  /// Tears down the active session scope: cancels the SSE subscription,
  /// any pending reconnect timer, and the queue watch, and drops in-memory
  /// state. Safe to call when nothing is active. Does not change any
  /// persisted queue row; a prompt left `sending` here is reconciled the
  /// next time its session is activated.
  Future<void> deactivate() async {
    _activationToken++;
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    // Not awaited: an `async*`/`await for` SSE decoder paused between
    // events only processes a downstream cancellation once it resumes
    // (the next event, or the connection closing), so awaiting this could
    // block deactivation indefinitely on an idle connection. The token
    // bump above already makes every later callback from this
    // subscription a no-op, so dropping the future here is safe.
    unawaited(_sseSubscription?.cancel());
    _sseSubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _profile = null;
    _session = null;
    _queue = const <QueuedPrompt>[];
    _chatRepository.deactivateConversation();
    _setConnectionState(const SseSuspended());
    _dispatchInProgress = false;
    _pendingSendNowPromptId = null;
    _blockPausedPromptIds.clear();
  }

  /// Called by the app's lifecycle owner when the app becomes inactive
  /// (backgrounded, hidden, or about to be paused). Cancels the active SSE
  /// subscription and any pending reconnect timer immediately; no
  /// reconnect is attempted again until [notifyAppForeground] is called.
  /// A no-op when the app is already marked inactive.
  void notifyAppInactive() {
    if (_disposed || !_appForeground) {
      return;
    }
    _appForeground = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // Not awaited for the same reason as `deactivate`'s SSE cancel: an
    // idle `async*` decoder only notices the cancellation once it next
    // resumes, which must not block this call.
    unawaited(_sseSubscription?.cancel());
    _sseSubscription = null;
    if (hasActiveSession) {
      _setConnectionState(const SseSuspended());
    }
  }

  /// Called by the app's lifecycle owner when the app returns to the
  /// foreground. Reconnects immediately if a session is active — any
  /// *subsequent* failed attempt is governed by [backoffPolicy] as usual.
  /// A no-op when the app is already marked foreground, or nothing is
  /// active (a freshly opened session connects on its own via [activate]).
  void notifyAppForeground() {
    if (_disposed || _appForeground) {
      return;
    }
    _appForeground = true;
    if (!hasActiveSession) {
      return;
    }
    _reconnectAttempt = 0;
    // Not attempt 0: unlike the very first connect inside `activate`, the
    // app may have missed events for as long as it was inactive, so this
    // reconnect must go through the same authoritative reconciliation
    // window as any other reconnect before dispatch may resume.
    _connect(token: _activationToken, attempt: 1);
  }

  /// Starts an SSE (re)connection attempt for the currently active
  /// session. [attempt] `0` is the very first connection of an [activate]
  /// call; any other value is a reconnect and goes through
  /// [SseReconciling] before [connectionState] reports [SseConnected]. See
  /// `_connectAsync`, which does the actual work once the credentials
  /// store resolves.
  void _connect({required int token, required int attempt}) {
    if (_isStale(token) || !_appForeground) {
      return;
    }
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return;
    }
    final connectToken = ++_connectAttemptToken;
    if (attempt == 0) {
      _setConnectionState(const SseConnecting());
    }
    unawaited(
      _connectAsync(
        profile,
        session,
        token: token,
        attempt: attempt,
        connectToken: connectToken,
      ),
    );
  }

  Future<void> _connectAsync(
    ServerProfile profile,
    OpenCodeSession session, {
    required int token,
    required int attempt,
    required int connectToken,
  }) async {
    final password = await _credentialsStore.readPassword(profile.id);
    if (_isStale(token) ||
        !_appForeground ||
        _isSupersededConnect(connectToken)) {
      return;
    }

    unawaited(_sseSubscription?.cancel());
    _sseSubscription = _eventService
        .connect(profile, password)
        .listen(
          (envelope) => _handleEnvelope(envelope, session, token),
          onError: (Object _) => _handleSseDrop(token, connectToken),
          onDone: () => _handleSseDrop(token, connectToken),
        );

    if (attempt == 0) {
      // `activate` already fetched an authoritative session status
      // moments before calling this; the initial connection can be
      // trusted immediately.
      _reconnectAttempt = 0;
      _setConnectionState(const SseConnected());
      _maybeDispatch();
      return;
    }

    // A reconnect: events may have been missed while the connection was
    // down (or the app was inactive), so nothing from it is trusted, and
    // dispatch stays blocked (`_maybeDispatch` checks `connectionState`),
    // until a fresh authoritative status is fetched.
    _setConnectionState(const SseReconciling());
    // The repository owns the REST/SSE merge. The SSE subscription is already
    // live, so events emitted while this snapshot is in flight are journaled
    // and replayed only after the snapshot boundary.
    await _chatRepository.load(profile, session);
    final statusResult = await _chatRepository.sessionStatus(profile, session);
    if (_isStale(token) ||
        !_appForeground ||
        _isSupersededConnect(connectToken)) {
      return;
    }
    if (statusResult case Ok<SessionExecutionState, ChatFailure>(
      value: final state,
    )) {
      await _applySessionState(session.id, state);
      if (_isStale(token) ||
          !_appForeground ||
          _isSupersededConnect(connectToken)) {
        return;
      }
    }
    await _reconcilePendingApprovals(profile, session, token);
    if (_isStale(token) ||
        !_appForeground ||
        _isSupersededConnect(connectToken)) {
      return;
    }
    _reconnectAttempt = 0;
    _setConnectionState(const SseConnected());
    _maybeDispatch();
  }

  /// Whether [connectToken] no longer identifies the connect attempt this
  /// coordinator currently considers current — either a newer [_connect]
  /// call replaced it, or [_handleSseDrop] already invalidated it after
  /// its own subscription dropped again while this continuation was still
  /// awaiting the reconciliation fetch.
  bool _isSupersededConnect(int connectToken) =>
      connectToken != _connectAttemptToken;

  void _handleEnvelope(
    OpenCodeEventEnvelope envelope,
    OpenCodeSession session,
    int token,
  ) {
    if (_isStale(token)) {
      return;
    }
    final liveStatus = parseOpenCodeGlobalSessionStatus(envelope.payload);
    if (liveStatus != null) {
      _publishLiveStatus(liveStatus.sessionId, liveStatus.status);
    }
    final previousState = _chatRepository.conversationStateUpdates.value;
    _chatRepository.applyEnvelope(envelope, session);
    final nextState = _chatRepository.conversationStateUpdates.value;
    if (identical(previousState, nextState)) return;
    unawaited(
      _serializeBlockTransition(
        () =>
            _handleBlockTransition(session.id, previousState, nextState, token),
      ),
    );
    _maybeDispatch();
  }

  /// A dropped SSE connection — a transport error, or the stream simply
  /// ending — is never silently discarded: it is surfaced on
  /// [connectionState] and retried with bounded backoff while the app
  /// stays foreground, via [_beginReconnect].
  ///
  /// [connectToken] identifies the connect attempt this drop belongs to.
  /// If it no longer matches [_connectAttemptToken], this call is either a
  /// stale subscription's belated event (already superseded by a newer
  /// [_connect]), or — for an uncaught error inside [OpenCodeEventService
  /// .connect]'s stream, which Dart follows with an immediate `onDone` for
  /// the same subscription — simply the `onDone` half of a drop this
  /// method already processed via its `onError` half moments earlier. Both
  /// cases are a no-op; only the first callback for a given attempt is
  /// ever acted on.
  void _handleSseDrop(int token, int connectToken) {
    if (connectToken != _connectAttemptToken) {
      return;
    }
    _connectAttemptToken++;
    _sseSubscription = null;
    if (_isStale(token) || !_appForeground) {
      // Already superseded by a newer activation, torn down, or the app
      // is inactive — `notifyAppInactive` already cancelled the
      // subscription itself in the last case, so this is just the
      // subscription's own belated error/done callback catching up.
      return;
    }
    _beginReconnect(token: token);
  }

  /// Schedules the next bounded reconnect attempt after an unexpected
  /// drop, using [backoffPolicy] for the delay and [_reconnectTimerFactory]
  /// to schedule it. Surfaces [SseReconnecting] while waiting, or
  /// [SseDisconnected] once [backoffPolicy] no longer permits another
  /// attempt.
  void _beginReconnect({required int token}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final attempt = ++_reconnectAttempt;
    if (!backoffPolicy.shouldRetry(attempt)) {
      _setConnectionState(const SseDisconnected());
      return;
    }
    final delay = backoffPolicy.delayForAttempt(attempt, _random);
    _setConnectionState(
      SseReconnecting(attempt: attempt, retryAt: DateTime.now().add(delay)),
    );
    _reconnectTimer = _reconnectTimerFactory(delay, () {
      _connect(token: token, attempt: attempt);
    });
  }

  void _setConnectionState(SseConnectionState next) {
    _connectionState.value = next;
  }

  /// Immediately retries a connection after bounded automatic retries stop.
  /// The retry always goes through authoritative REST reconciliation before
  /// queue dispatch can resume.
  void retryConnection() {
    if (_disposed || !_appForeground || !hasActiveSession) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    unawaited(_sseSubscription?.cancel());
    _sseSubscription = null;
    _connect(token: _activationToken, attempt: 1);
  }

  /// Explicitly cancels the active session's current generation, then
  /// dispatches [promptId] once the session settles idle. [promptId] must
  /// currently be `queued` in the active session.
  ///
  /// This never retries: if the abort call itself fails, `sendNow` returns
  /// a failure immediately and the normal queue-head dispatch resumes.
  Future<Result<void, QueueSendNowFailure>> sendNow(String promptId) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return const Err(QueueSendNowFailure.noActiveSession);
    }

    final prompt = _findPrompt(promptId);
    if (prompt == null) {
      return const Err(QueueSendNowFailure.promptNotFound);
    }
    if (prompt.state != QueuedPromptState.queued) {
      return const Err(QueueSendNowFailure.promptNotQueued);
    }

    final token = _activationToken;
    // Set before aborting so a session-status update that races the abort
    // call is gated on this pending send-now instead of dispatching the
    // normal queue head.
    _pendingSendNowPromptId = promptId;

    final abortResult = await _chatRepository.abortSession(profile, session);
    if (_isStale(token)) {
      return const Err(QueueSendNowFailure.noActiveSession);
    }
    if (abortResult is Err<bool, ChatFailure>) {
      _pendingSendNowPromptId = null;
      return const Err(QueueSendNowFailure.abortFailed);
    }
    if (abortResult case Ok<bool, ChatFailure>(value: final didAbort)) {
      if (!didAbort) {
        _pendingSendNowPromptId = null;
        return const Err(QueueSendNowFailure.abortFailed);
      }
    }

    final statusResult = await _chatRepository.sessionStatus(profile, session);
    if (_isStale(token)) {
      return const Err(QueueSendNowFailure.noActiveSession);
    }
    if (statusResult case Ok<SessionExecutionState, ChatFailure>(
      value: final state,
    )) {
      await _applySessionState(session.id, state);
      if (_isStale(token)) {
        return const Err(QueueSendNowFailure.noActiveSession);
      }
    } else {
      _pendingSendNowPromptId = null;
      return const Err(QueueSendNowFailure.statusUnavailable);
    }

    _maybeDispatch();
    return const Ok(null);
  }

  /// Responds to the active session's pending tool-call permission with
  /// [response]. Fails with [QueueApprovalFailure.noActiveSession] with no
  /// active session; does not otherwise validate that [permissionId]
  /// matches [currentPendingApproval] before calling OpenCode, since the
  /// server is authoritative for whether it still exists.
  ///
  /// On success, clears [currentPendingApproval] — the dock this was
  /// answering has nothing left to show — but never touches
  /// [currentSessionBlockReason] or the queue's pause state directly; both
  /// stay exactly as an authoritative `session.status`/`session.idle`
  /// event leaves them.
  Future<Result<void, QueueApprovalFailure>> respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) {
    return _submitApprovalReply(
      permissionId,
      (profile, session) => _chatRepository.respondToPermission(
        profile,
        session,
        permissionId,
        response,
      ),
    );
  }

  /// Answers the active session's pending question request with [answers],
  /// one entry per question in the original request, in the same order.
  /// See [respondToPermission] for the failure and clearing rules; they
  /// apply identically here.
  Future<Result<void, QueueApprovalFailure>> replyToQuestion(
    String requestId,
    List<List<String>> answers,
  ) {
    return _submitApprovalReply(
      requestId,
      (profile, session) =>
          _chatRepository.replyToQuestion(profile, session, requestId, answers),
    );
  }

  /// Rejects the active session's pending question request outright. See
  /// [respondToPermission] for the failure and clearing rules; they apply
  /// identically here.
  Future<Result<void, QueueApprovalFailure>> rejectQuestion(String requestId) {
    return _submitApprovalReply(
      requestId,
      (profile, session) =>
          _chatRepository.rejectQuestion(profile, session, requestId),
    );
  }

  Future<Result<void, QueueApprovalFailure>> _submitApprovalReply(
    String approvalId,
    Future<Result<void, ChatFailure>> Function(
      ServerProfile profile,
      OpenCodeSession session,
    )
    call,
  ) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return const Err(QueueApprovalFailure.noActiveSession);
    }
    final token = _activationToken;
    final result = await call(profile, session);
    if (_isStale(token)) {
      return const Err(QueueApprovalFailure.noActiveSession);
    }
    if (result is Err<void, ChatFailure>) {
      return const Err(QueueApprovalFailure.requestFailed);
    }
    _chatRepository.clearApproval(session.id);
    await _reconcilePendingApprovals(
      profile,
      session,
      token,
      resumeWhenEmpty: false,
      excludedApprovalId: approvalId,
    );
    if (_isStale(token)) {
      return const Err(QueueApprovalFailure.noActiveSession);
    }
    return const Ok(null);
  }

  /// Permanently disposes this coordinator. Cancels any subscription and
  /// releases every reference; [activate] must not be called afterwards.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await deactivate();
    _disposed = true;
    _connectionState.dispose();
    _liveStatuses.dispose();
  }

  /// Applies a fresh authoritative execution state for [sessionId] — from
  /// the `GET /session/status` REST call or a synthesized local update —
  /// exactly as a `session.status` SSE event would. Also handles any
  /// resulting block transition, since [reduceConversationEvent] clears a
  /// pending permission/question for [sessionId] whenever a status is
  /// applied, the same way it would for the SSE event itself.
  Future<void> _applySessionState(
    String sessionId,
    SessionExecutionState state,
  ) async {
    _publishLiveStatus(sessionId, _toOpenCodeStatus(state));
    final previousState = _chatRepository.conversationStateUpdates.value;
    _chatRepository.applySessionState(sessionId, state);
    final nextState = _chatRepository.conversationStateUpdates.value;
    _notifyGenerationFinished(sessionId, previousState, nextState);
    await _serializeBlockTransition(
      () => _handleBlockTransition(
        sessionId,
        previousState,
        nextState,
        _activationToken,
      ),
    );
  }

  void _publishLiveStatus(String sessionId, OpenCodeSessionStatus status) {
    if (_liveStatusProfileId == null ||
        status is OpenCodeSessionStatusUnknown) {
      return;
    }
    final next = <String, OpenCodeSessionStatus>{
      ..._liveStatuses.value,
      sessionId: status,
    };
    _liveStatuses.value = Map.unmodifiable(next);
  }

  OpenCodeSessionStatus _toOpenCodeStatus(SessionExecutionState state) {
    return switch (state) {
      SessionBusy() => const OpenCodeSessionStatusBusy(),
      SessionIdle() => const OpenCodeSessionStatusIdle(),
      SessionRetrying(
        :final attempt,
        :final message,
        :final nextAttemptAtMillis,
      ) =>
        OpenCodeSessionStatusRetry(
          attempt: attempt,
          message: message,
          next: nextAttemptAtMillis,
        ),
      SessionExecutionUnknown() => const OpenCodeSessionStatusUnknown(),
    };
  }

  Future<void> _serializeBlockTransition(Future<void> Function() operation) {
    final next = _blockTransitionTail.then((_) => operation());
    _blockTransitionTail = next;
    return next;
  }

  /// Reports a busy-to-idle transition once, so a caller can raise a generic
  /// completion notification. Nothing is reported while the app is
  /// foreground: the user can already see the transcript.
  void _notifyGenerationFinished(
    String sessionId,
    ConversationState previous,
    ConversationState next,
  ) {
    final callback = onGenerationFinished;
    if (callback == null || _appForeground) {
      return;
    }
    final wasBusy = previous.sessionStates[sessionId] is SessionBusy;
    final isIdle = next.sessionStates[sessionId] is SessionIdle;
    if (wasBusy && isIdle) {
      callback(failed: false);
    }
  }

  Future<void> _reconcilePendingApprovals(
    ServerProfile profile,
    OpenCodeSession session,
    int token, {
    bool resumeWhenEmpty = true,
    String? excludedApprovalId,
  }) async {
    final result = await _chatRepository.pendingApprovals(profile, session);
    if (_isStale(token)) {
      return;
    }
    switch (result) {
      case Ok<List<PendingApproval>, ChatFailure>(:final value):
        final remaining = excludedApprovalId == null
            ? value
            : value
                  .where((candidate) => candidate.id != excludedApprovalId)
                  .toList(growable: false);
        final approval = remaining.isEmpty ? null : remaining.first;
        if (approval == null) {
          if (resumeWhenEmpty) {
            await _resumeBlockedPrompts(token);
          }
          return;
        }
        final previous = _chatRepository.conversationStateUpdates.value;
        _chatRepository.applyBlocked(session.id, approval);
        final next = _chatRepository.conversationStateUpdates.value;
        await _handleBlockTransition(session.id, previous, next, token);
      case Err<List<PendingApproval>, ChatFailure>():
        // Fail closed: persisted permission/question pauses remain paused.
        // A live SSE event can still restore presentation detail, and a
        // later reconnect retries this authoritative fetch.
        return;
    }
  }

  /// Reacts to [sessionId]'s block state changing between [previous] and
  /// [next]:
  /// - Newly blocked: pauses every currently `queued` prompt in this
  ///   session with the matching [QueuePauseReason].
  /// - Newly unblocked (a `session.status`/`session.idle` event just
  ///   reduced past it): resumes only the prompts this coordinator paused
  ///   for that reason, back to `queued`.
  ///
  /// A no-op, harmless call when neither transition applies (for example
  /// every other `session.status` update while nothing is blocked).
  Future<void> _handleBlockTransition(
    String sessionId,
    ConversationState previous,
    ConversationState next,
    int token,
  ) async {
    final wasBlocked = previous.sessionBlocks.containsKey(sessionId);
    final blockReason = next.sessionBlocks[sessionId];
    if (!wasBlocked && blockReason != null) {
      await _pauseQueuedPromptsForBlock(blockReason, token);
    } else if (wasBlocked && blockReason == null) {
      await _resumeBlockedPrompts(token);
    }
    if (_isStale(token)) {
      return;
    }
    _maybeDispatch();
  }

  Future<void> _pauseQueuedPromptsForBlock(
    SessionBlockReason reason,
    int token,
  ) async {
    final pauseReason = reason == SessionBlockReason.question
        ? QueuePauseReason.questionPending
        : QueuePauseReason.permissionPending;
    for (final prompt in List<QueuedPrompt>.of(_queue)) {
      if (_isStale(token)) {
        return;
      }
      if (prompt.state == QueuedPromptState.queued) {
        await _queueRepository.markPaused(prompt.id, reason: pauseReason);
        _blockPausedPromptIds.add(prompt.id);
      }
    }
  }

  Future<void> _resumeBlockedPrompts(int token) async {
    for (final promptId in List<String>.of(_blockPausedPromptIds)) {
      if (_isStale(token)) {
        return;
      }
      await _queueRepository.markQueued(promptId);
      _blockPausedPromptIds.remove(promptId);
    }
    // A queue refresh may have arrived before the serialized pause operation
    // recorded its id. Preserve the existing safeguard for those rows.
    for (final prompt in List<QueuedPrompt>.of(_queue)) {
      if (prompt.state == QueuedPromptState.paused &&
          _isBlockPauseReason(prompt.pauseReason) &&
          !_blockPausedPromptIds.contains(prompt.id)) {
        await _queueRepository.markQueued(prompt.id);
      }
    }
  }

  bool _isBlockPauseReason(QueuePauseReason? reason) {
    return reason == QueuePauseReason.permissionPending ||
        reason == QueuePauseReason.questionPending;
  }

  void _maybeDispatch() {
    if (_disposed || _dispatchInProgress) {
      return;
    }
    if (_profile == null || _session == null) {
      return;
    }
    if (_connectionState.value is! SseConnected) {
      // Held during the initial connection, any reconnect backoff wait,
      // and the authoritative-reconciliation window right after a
      // reconnect (`SseReconciling`); only a confirmed, reconciled
      // connection may dispatch. This is what actually prevents a queued
      // prompt from sending against a connection whose missed events
      // have not yet been reconciled, whatever the app's lifecycle state.
      return;
    }
    if (currentSessionBlockReason != null) {
      // A pending permission or question blocks every dispatch, including
      // an explicit `sendNow`, until an authoritative session status/idle
      // event confirms the block is gone.
      return;
    }

    final pendingSendNowId = _pendingSendNowPromptId;
    if (pendingSendNowId != null) {
      if (currentSessionState is! SessionIdle) {
        return;
      }
      _pendingSendNowPromptId = null;
      final prompt = _findPrompt(pendingSendNowId);
      if (prompt == null || prompt.state != QueuedPromptState.queued) {
        return;
      }
      unawaited(_dispatch(prompt));
      return;
    }

    if (currentSessionState is! SessionIdle) {
      return;
    }
    if (_hasSendingPrompt() || _hasPendingSubmissionUnknown()) {
      return;
    }
    final head = _headQueuedPrompt();
    if (head == null) {
      return;
    }
    unawaited(_dispatch(head));
  }

  Future<void> _dispatch(QueuedPrompt prompt) async {
    _dispatchInProgress = true;
    final token = _activationToken;
    final profile = _profile!;
    final session = _session!;

    final sendingResult = await _queueRepository.markSending(prompt.id);
    if (_isStale(token)) {
      return;
    }
    if (sendingResult is Err<QueuedPrompt, QueueFailure>) {
      // Another writer already moved this prompt out of `queued` (for
      // example it was removed); drop this attempt and let the next queue
      // update decide what to dispatch.
      _dispatchInProgress = false;
      return;
    }

    final sendResult = await switch (prompt.operationType) {
      QueuedOperationType.prompt => _chatRepository.sendPrompt(
        profile,
        session,
        prompt.promptText,
        attachments: prompt.attachments,
        executionOptions: prompt.executionOptions,
      ),
      QueuedOperationType.command => _chatRepository.executeCommand(
        profile,
        session,
        prompt.commandName!,
        prompt.promptText,
        executionOptions: prompt.executionOptions,
      ),
    };
    if (_isStale(token)) {
      return;
    }

    if (sendResult is Ok<void, ChatFailure>) {
      // A 2xx response from `prompt_async` is the server's definitive
      // acceptance across supported OpenCode server versions.
      await _queueRepository.markAcknowledged(prompt.id);
      // Do not dispatch the next queue entry until the server reports an
      // explicit terminal state. The busy event may arrive after this 204.
      await _applySessionState(session.id, const SessionBusy());
    } else {
      // Any other outcome leaves acceptance genuinely unknown; Prompt
      // never retries automatically.
      await _queueRepository.markSubmissionUnknown(prompt.id);
    }
    if (_isStale(token)) {
      return;
    }

    _dispatchInProgress = false;
    _maybeDispatch();
  }

  QueuedPrompt? _headQueuedPrompt() {
    for (final prompt in _queue) {
      if (prompt.state == QueuedPromptState.queued) {
        return prompt;
      }
    }
    return null;
  }

  QueuedPrompt? _findPrompt(String id) {
    for (final prompt in _queue) {
      if (prompt.id == id) {
        return prompt;
      }
    }
    return null;
  }

  bool _hasSendingPrompt() {
    return _queue.any((prompt) => prompt.state == QueuedPromptState.sending);
  }

  bool _hasPendingSubmissionUnknown() {
    return _queue.any(
      (prompt) =>
          prompt.state == QueuedPromptState.paused &&
          prompt.pauseReason == QueuePauseReason.submissionUnknown,
    );
  }

  bool _isStale(int token) => _disposed || token != _activationToken;

  void _requireNotDisposed() {
    if (_disposed) {
      throw StateError('QueueSendCoordinator was already disposed.');
    }
  }
}
