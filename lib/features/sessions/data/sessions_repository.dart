import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import '../../connection/connection.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import '../domain/session_activity.dart';
import 'opencode_sessions_service.dart';

class SessionsRepository {
  SessionsRepository(
    this._sessionsService,
    this._credentialsStore, {
    this.onSessionsDeleted,
  });

  final OpenCodeSessionsService _sessionsService;
  final CredentialsStore _credentialsStore;
  final Future<void> Function(
    ServerProfile profile,
    Iterable<String> sessionIds,
  )?
  onSessionsDeleted;

  Future<SessionLoadResult> load(ServerProfile profile) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      // A project's catalog is authoritative for that worktree. The unscoped
      // index is only a fallback when a project catalog cannot be read: some
      // servers keep historical IDs in that index after a session is deleted.
      final byId = <String, OpenCodeSessionRecord>{};
      Object? firstFailure;
      var loadedAnyCatalog = false;
      var projects = <OpenCodeProjectRecord>[];
      var loadedProjects = false;
      final globalSessions = <OpenCodeSessionRecord>[];
      final unavailableCatalogDirectories = <String>{};

      Future<void> loadProjectCatalog(String directory) async {
        try {
          final catalog = await _sessionsService.listSessions(
            profile,
            password,
            directory,
          );
          loadedAnyCatalog = true;
          for (final session in catalog) {
            byId[session.id] = session;
          }
        } on Object catch (error) {
          firstFailure ??= error;
          unavailableCatalogDirectories.add(directory);
        }
      }

      try {
        globalSessions.addAll(
          await _sessionsService.listSessions(profile, password, ''),
        );
        loadedAnyCatalog = true;
      } on Object catch (error) {
        firstFailure ??= error;
      }
      try {
        projects = await _sessionsService.listProjects(profile, password);
        loadedProjects = true;
      } on Object catch (error) {
        // The global index remains the only catalog on servers that do not
        // expose, or temporarily fail, the project endpoint.
        firstFailure ??= error;
      }
      await _forEachBounded(
        projects.map((project) => project.worktree),
        loadProjectCatalog,
      );

      if (!loadedAnyCatalog && firstFailure != null) {
        throw firstFailure!;
      }

      if (!loadedProjects) {
        for (final session in globalSessions) {
          byId[session.id] = session;
        }
      } else {
        // Keep global entries only for an unavailable worktree. Every other
        // project response, including an empty one, is an explicit snapshot.
        for (final session in globalSessions) {
          if (unavailableCatalogDirectories.contains(session.directory)) {
            byId.putIfAbsent(session.id, () => session);
          }
        }
      }

      final sessions = byId.values.map(_toDomain).toList()
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final activities = <String, SessionActivity>{};
      final unreported = <String>{};
      final unavailableActivityDirectories = <String>{};
      final sessionsByDirectory = <String, List<String>>{};
      for (final session in sessions) {
        sessionsByDirectory
            .putIfAbsent(session.directory, () => <String>[])
            .add(session.id);
      }
      await _forEachBounded(sessionsByDirectory.keys, (directory) async {
        try {
          final statuses = await _sessionsService.fetchSessionActivities(
            profile,
            password,
            directory,
          );
          for (final sessionId in sessionsByDirectory[directory]!) {
            final status = statuses[sessionId];
            if (status != null) {
              activities[sessionId] = _toActivity(status);
            } else {
              unreported.add(sessionId);
            }
          }
        } on OpenCodeHttpFailure {
          unavailableActivityDirectories.add(directory);
        } on OpenCodeTransportFailure {
          unavailableActivityDirectories.add(directory);
        } on TimeoutException {
          unavailableActivityDirectories.add(directory);
        } on http.ClientException {
          unavailableActivityDirectories.add(directory);
        } on FormatException {
          unavailableActivityDirectories.add(directory);
        }
        if (unavailableActivityDirectories.contains(directory)) {
          for (final sessionId in sessionsByDirectory[directory]!) {
            unreported.remove(sessionId);
            activities[sessionId] = SessionActivity.unavailable;
          }
        }
      });
      await _resolveUnreported(
        profile,
        password,
        sessions,
        unreported,
        activities,
      );
      return SessionsLoaded(
        List.unmodifiable(sessions),
        projects: List.unmodifiable(
          projects.map(
            (project) =>
                OpenCodeProject(id: project.id, directory: project.worktree),
          ),
        ),
        activities: Map.unmodifiable(activities),
        unavailableDirectories: Set.unmodifiable(
          unavailableActivityDirectories,
        ),
      );
    } on OpenCodeHttpFailure catch (failure) {
      return SessionsLoadFailed(_httpFailure(failure.statusCode));
    } on OpenCodeTransportFailure catch (failure) {
      return SessionsLoadFailed(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const SessionsLoadFailed(SessionsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const SessionsLoadFailed(SessionsFailure.unexpectedResponse);
    } on http.ClientException {
      return const SessionsLoadFailed(SessionsFailure.unavailable);
    } on FormatException {
      return const SessionsLoadFailed(SessionsFailure.unexpectedResponse);
    } on TypeError {
      return const SessionsLoadFailed(SessionsFailure.unexpectedResponse);
    }
  }

  /// How recently a session must have moved to be worth asking about.
  ///
  /// A session's timestamp advances when a message is created, so a generation
  /// in flight keeps the timestamp of its start. The window has to outlast a
  /// long run while still excluding the archive.
  static const unreportedRecency = Duration(hours: 6);

  /// Ceiling on the extra requests one catalog load may spend.
  static const unreportedProbeLimit = 12;

  /// Decides the activity of the sessions `/session/status` said nothing about.
  ///
  /// That endpoint only covers the sessions its own server runs, so a session
  /// driven by another OpenCode process is missing from it, and calling that
  /// idle was wrong exactly when it mattered. For the recently active ones the
  /// shared message stream answers the question outright; a session untouched
  /// for hours is left as idle, since nothing has been recorded for it in far
  /// longer than a generation lasts.
  Future<void> _resolveUnreported(
    ServerProfile profile,
    String? password,
    List<OpenCodeSession> sessions,
    Set<String> unreported,
    Map<String, SessionActivity> activities,
  ) async {
    if (unreported.isEmpty) return;
    final now = DateTime.now();
    final candidates = <OpenCodeSession>[];
    for (final session in sessions) {
      if (!unreported.contains(session.id)) continue;
      if (now.difference(session.updatedAt) <= unreportedRecency) {
        candidates.add(session);
      } else {
        activities[session.id] = SessionActivity.idle;
      }
    }
    // `sessions` is already newest first, so the ceiling drops the stalest.
    for (final session in candidates.skip(unreportedProbeLimit)) {
      activities[session.id] = SessionActivity.idle;
    }
    await _forEachBounded(candidates.take(unreportedProbeLimit), (
      session,
    ) async {
      try {
        final generating = await _sessionsService.fetchIsGenerating(
          profile,
          password,
          session.id,
          session.directory,
        );
        activities[session.id] = switch (generating) {
          true => SessionActivity.working,
          false => SessionActivity.idle,
          null => SessionActivity.unknown,
        };
      } on OpenCodeHttpFailure {
        activities[session.id] = SessionActivity.unknown;
      } on OpenCodeTransportFailure {
        activities[session.id] = SessionActivity.unknown;
      } on TimeoutException {
        activities[session.id] = SessionActivity.unknown;
      } on http.ClientException {
        activities[session.id] = SessionActivity.unknown;
      } on FormatException {
        activities[session.id] = SessionActivity.unknown;
      }
    });
  }

  /// Runs [action] over [values] with a bounded number of in-flight requests so
  /// a large project catalog cannot open one connection per project at once.
  static Future<void> _forEachBounded<T>(
    Iterable<T> values,
    Future<void> Function(T value) action, {
    int concurrency = 4,
  }) async {
    final pending = values.toList(growable: false);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= pending.length) {
          return;
        }
        await action(pending[index]);
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < concurrency && i < pending.length; i++) worker(),
    ];
    await Future.wait(workers);
  }

  Future<SessionMutationResult> rename(
    ServerProfile profile,
    OpenCodeSession session,
    String title,
  ) {
    return _mutate(
      () async => _sessionsService.renameSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        session,
        title,
      ),
    );
  }

  Future<SessionCreateResult> create(
    ServerProfile profile,
    String directory, {
    String? title,
  }) async {
    try {
      final record = await _sessionsService.createSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        directory.trim(),
        title: title,
      );
      return Ok(_toDomain(record));
    } on OpenCodeHttpFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on OpenCodeTransportFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(SessionsFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    } on FormatException {
      return const Err(SessionsFailure.unexpectedResponse);
    } on TypeError {
      return const Err(SessionsFailure.unexpectedResponse);
    }
  }

  Future<Result<List<String>, SessionsFailure>> suggestDirectories(
    ServerProfile profile,
    String input,
  ) async {
    try {
      return Ok(
        await _sessionsService.suggestDirectories(
          profile,
          await _credentialsStore.readPassword(profile.id),
          input,
        ),
      );
    } on OpenCodeHttpFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on OpenCodeTransportFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(SessionsFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    } on FormatException {
      return const Err(SessionsFailure.unexpectedResponse);
    } on TypeError {
      return const Err(SessionsFailure.unexpectedResponse);
    }
  }

  Future<SessionMutationResult> delete(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _mutate(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      final catalog = await _sessionsService.listSessions(
        profile,
        password,
        session.directory,
      );
      final byParent = <String, List<OpenCodeSessionRecord>>{};
      for (final candidate in catalog) {
        final parentId = candidate.parentId;
        if (parentId != null) {
          byParent.putIfAbsent(parentId, () => []).add(candidate);
        }
      }

      final deletedIds = <String>[];
      Future<void> deleteTree(OpenCodeSession target) async {
        for (final child in byParent[target.id] ?? const []) {
          await deleteTree(_toDomain(child));
        }
        await _sessionsService.abortSession(profile, password, target);
        await _sessionsService.deleteSession(profile, password, target);
        deletedIds.add(target.id);
      }

      // Deleting a busy session alone does not guarantee that its running
      // process is stopped. Descendants are independent OpenCode sessions, so
      // delete them first and let OpenCode cascade each session's DB records.
      try {
        await deleteTree(session);
      } catch (_) {
        // Preserve history for nodes whose remote deletion did not complete,
        // while cleaning the descendants already confirmed by the server.
        try {
          await onSessionsDeleted?.call(profile, deletedIds);
        } catch (_) {}
        rethrow;
      }
      try {
        await onSessionsDeleted?.call(profile, deletedIds);
      } catch (_) {
        // Remote deletion succeeded; local cleanup is best effort and must not
        // turn a successful server mutation into a false remote failure.
      }
    });
  }

  Future<SessionCreateResult> fork(
    ServerProfile profile,
    OpenCodeSession session,
  ) => _runSession(
    () async => _toDomain(
      await _sessionsService.forkSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        session,
      ),
    ),
  );

  Future<SessionShareResult> share(
    ServerProfile profile,
    OpenCodeSession session,
  ) => _runSession(() async {
    final updated = await _sessionsService.shareSession(
      profile,
      await _credentialsStore.readPassword(profile.id),
      session,
    );
    return _safeShareUrl(updated.shareUrl);
  });

  Future<SessionMutationResult> unshare(
    ServerProfile profile,
    OpenCodeSession session,
  ) => _mutate(
    () async => _sessionsService.unshareSession(
      profile,
      await _credentialsStore.readPassword(profile.id),
      session,
    ),
  );

  Future<SessionRevertResult> revert(
    ServerProfile profile,
    OpenCodeSession session,
    String messageId,
  ) => _runSession(
    () async => _sessionsService.revertMessage(
      profile,
      await _credentialsStore.readPassword(profile.id),
      session,
      messageId,
    ),
  );

  Future<SessionMutationResult> _mutate(Future<void> Function() action) async {
    try {
      await action();
      return const Ok(null);
    } on OpenCodeHttpFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on OpenCodeTransportFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    } on FormatException {
      return const Err(SessionsFailure.unexpectedResponse);
    } on TypeError {
      return const Err(SessionsFailure.unexpectedResponse);
    }
  }

  Future<Result<T, SessionsFailure>> _runSession<T>(
    Future<T> Function() action,
  ) async {
    try {
      return Ok(await action());
    } on OpenCodeHttpFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on OpenCodeTransportFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    } on FormatException {
      return const Err(SessionsFailure.unexpectedResponse);
    } on TypeError {
      return const Err(SessionsFailure.unexpectedResponse);
    }
  }

  String? _safeShareUrl(String? value) {
    if (value == null) {
      return null;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.isAbsolute &&
            uri.scheme == 'https' &&
            uri.userInfo.isEmpty
        ? uri.toString()
        : null;
  }

  SessionsFailure _httpFailure(int statusCode) =>
      statusCode == 401 || statusCode == 403
      ? SessionsFailure.unauthorized
      : SessionsFailure.unexpectedResponse;

  OpenCodeSession _toDomain(OpenCodeSessionRecord record) {
    return OpenCodeSession(
      id: record.id,
      projectId: record.projectId,
      directory: record.directory,
      title: record.title,
      createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAtMillis),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(record.updatedAtMillis),
      parentId: record.parentId,
      changedFiles: record.changedFiles,
      additions: record.additions,
      deletions: record.deletions,
      shareUrl: _safeShareUrl(record.shareUrl),
      modelProviderId: record.modelProviderId,
      modelId: record.modelId,
      agentName: record.agentName,
    );
  }

  SessionActivity _toActivity(OpenCodeSessionStatus status) => switch (status) {
    OpenCodeSessionStatusBusy() => SessionActivity.working,
    OpenCodeSessionStatusIdle() => SessionActivity.idle,
    OpenCodeSessionStatusRetry() => SessionActivity.retrying,
    OpenCodeSessionStatusUnknown() => SessionActivity.unknown,
  };
}
