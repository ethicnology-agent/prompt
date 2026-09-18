import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import '../../connection/connection.dart';
import '../data/sessions_repository.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_activity.dart';
import '../domain/session_load_result.dart';
import '../domain/scoped_session.dart';
import '../application/load_session_catalog.dart';

sealed class SessionsUiState {
  const SessionsUiState();
}

class SessionsIdle extends SessionsUiState {
  const SessionsIdle();
}

class SessionsLoading extends SessionsUiState {
  const SessionsLoading();
}

class SessionsReady extends SessionsUiState {
  const SessionsReady(
    this.sessions,
    this.projects, {
    this.activities = const <String, SessionActivity>{},
    this.unavailableDirectories = const <String>{},
    this.catalogGroups,
  });

  final List<OpenCodeSession> sessions;
  final List<OpenCodeProject> projects;
  final Map<String, SessionActivity> activities;
  final Set<String> unavailableDirectories;
  final List<SessionCatalogGroup>? catalogGroups;

  List<ScopedSession> entriesFor(ServerProfile fallback) {
    final groups = catalogGroups;
    if (groups == null) {
      return [
        for (final session in sessions)
          ScopedSession(
            fallback,
            session,
            activity:
                activities[session.id] ??
                (unavailableDirectories.contains(session.directory)
                    ? SessionActivity.unavailable
                    : SessionActivity.unknown),
          ),
      ];
    }
    return [
      for (final group in groups)
        if (group.profile.origin == fallback.origin &&
            group.profile.username == fallback.username)
          ...group.entries,
    ]..sort(
      (left, right) =>
          right.session.updatedAt.compareTo(left.session.updatedAt),
    );
  }
}

class SessionsEmpty extends SessionsUiState {
  const SessionsEmpty();
}

class SessionsError extends SessionsUiState {
  const SessionsError(this.failure);

  final SessionsFailure failure;
}

class SessionsViewModel extends ValueNotifier<SessionsUiState> {
  SessionsViewModel(this._repository, {this._catalogLoader})
    : super(const SessionsIdle());

  final SessionsRepository _repository;
  final LoadSessionCatalog? _catalogLoader;
  ServerProfile? _catalogSource;
  bool _scopedCatalog = false;
  int _revision = 0;
  int _suggestionRevision = 0;
  ValueListenable<Map<String, OpenCodeSessionStatus>>? _liveStatuses;
  Map<String, SessionActivity> _liveActivities = const {};
  Map<String, SessionActivity> _baseActivities = const {};

  /// Binds the coordinator's existing global SSE status feed. Binding is
  /// presentation-only: this view model never starts network work.
  void bindLiveStatuses(
    ValueListenable<Map<String, OpenCodeSessionStatus>> statuses,
  ) {
    if (identical(_liveStatuses, statuses)) {
      return;
    }
    unbindLiveStatuses();
    _liveStatuses = statuses;
    _liveActivities = _toActivities(statuses.value);
    statuses.addListener(_onLiveStatusesChanged);
    _overlayCurrentState();
  }

  void unbindLiveStatuses() {
    final statuses = _liveStatuses;
    if (statuses == null) {
      return;
    }
    statuses.removeListener(_onLiveStatusesChanged);
    _liveStatuses = null;
    _liveActivities = const {};
    _overlayCurrentState();
  }

  Future<void> load(ServerProfile profile) async {
    final revision = ++_revision;
    final loader = _catalogLoader;
    _scopedCatalog = profile.backend.isGateway && loader != null;
    if (_catalogSource?.origin != profile.origin ||
        _catalogSource?.username != profile.username) {
      value = const SessionsLoading();
    }
    _catalogSource = profile;
    if (_scopedCatalog) {
      final previous = value is SessionsReady
          ? (value as SessionsReady).catalogGroups ??
                const <SessionCatalogGroup>[]
          : const <SessionCatalogGroup>[];
      if (value is! SessionsReady) value = const SessionsLoading();
      final loaded = await loader!(profile);
      if (revision != _revision) return;
      final groups = <SessionCatalogGroup>[
        for (final group in loaded)
          if (group.failure != null)
            previous
                    .where((old) => old.profile.id == group.profile.id)
                    .firstOrNull
                    ?.failed(group.failure!) ??
                group
          else
            group,
        for (final old in previous)
          if (!loaded.any((group) => group.profile.id == old.profile.id))
            old.failed(SessionsFailure.unavailable),
      ];
      _publishGroups(groups);
      return;
    }
    if (value is! SessionsReady) {
      value = const SessionsLoading();
    }
    final result = await _repository.load(profile);
    if (revision != _revision) {
      return;
    }
    switch (result) {
      case SessionsLoaded(
        :final sessions,
        :final projects,
        :final activities,
        :final unavailableDirectories,
      ):
        _baseActivities = Map.unmodifiable(activities);
        value = sessions.isEmpty
            ? SessionsReady(
                const [],
                projects,
                activities: _overlayActivities(activities),
                unavailableDirectories: unavailableDirectories,
              )
            : SessionsReady(
                sessions,
                projects,
                activities: _overlayActivities(activities),
                unavailableDirectories: unavailableDirectories,
              );
      case SessionsLoadFailed(:final failure):
        value = SessionsError(failure);
    }
  }

  Future<Result<OpenCodeSession, SessionsFailure>> create(
    ServerProfile profile,
    String directory, {
    String? title,
  }) async {
    final revision = ++_revision;
    final result = await _repository.create(
      profile,
      directory.trim(),
      title: title,
    );
    if (revision == _revision) {
      if (result case Ok<OpenCodeSession, SessionsFailure>(:final value)) {
        _addSession(profile, value);
      }
    }
    return result;
  }

  Future<Result<List<String>, SessionsFailure>?> suggestDirectories(
    ServerProfile profile,
    String input,
  ) async {
    final revision = ++_suggestionRevision;
    final result = await _repository.suggestDirectories(profile, input);
    return revision == _suggestionRevision ? result : null;
  }

  void _onLiveStatusesChanged() {
    final statuses = _liveStatuses;
    if (statuses == null) return;
    _liveActivities = _toActivities(statuses.value);
    _overlayCurrentState();
  }

  Map<String, SessionActivity> _toActivities(
    Map<String, OpenCodeSessionStatus> statuses,
  ) => {
    for (final entry in statuses.entries)
      entry.key: switch (entry.value) {
        OpenCodeSessionStatusBusy() => SessionActivity.working,
        OpenCodeSessionStatusIdle() => SessionActivity.idle,
        OpenCodeSessionStatusRetry() => SessionActivity.retrying,
        OpenCodeSessionStatusUnknown() => SessionActivity.unknown,
      },
  };

  Map<String, SessionActivity> _overlayActivities(
    Map<String, SessionActivity> activities,
  ) => Map.unmodifiable({...activities, ..._liveActivities});

  void _overlayCurrentState() {
    // Coordinator statuses have no profile identity. Never apply them to an
    // aggregated gateway catalog, even when IDs happen to be different today.
    if (_scopedCatalog ||
        (value is SessionsReady &&
            (value as SessionsReady).catalogGroups != null)) {
      return;
    }
    if (value case SessionsReady(
      :final sessions,
      :final projects,
      :final unavailableDirectories,
    )) {
      value = SessionsReady(
        sessions,
        projects,
        activities: _overlayActivities(_baseActivities),
        unavailableDirectories: unavailableDirectories,
      );
    }
  }

  Future<SessionsFailure?> rename(
    ServerProfile profile,
    OpenCodeSession session,
    String title,
  ) async {
    final revision = ++_revision;
    final result = await _repository.rename(profile, session, title);
    if (result case Err<void, SessionsFailure>(:final failure)) {
      return failure;
    }
    if (revision == _revision) {
      _replaceSession(
        profile,
        session,
        OpenCodeSession(
          id: session.id,
          projectId: session.projectId,
          directory: session.directory,
          title: title,
          createdAt: session.createdAt,
          updatedAt: DateTime.now(),
          parentId: session.parentId,
          changedFiles: session.changedFiles,
          additions: session.additions,
          deletions: session.deletions,
          shareUrl: session.shareUrl,
          modelProviderId: session.modelProviderId,
          modelId: session.modelId,
          agentName: session.agentName,
        ),
      );
    }
    return null;
  }

  Future<SessionsFailure?> delete(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    final revision = ++_revision;
    final result = await _repository.delete(profile, session);
    if (result case Err<void, SessionsFailure>(:final failure)) {
      return failure;
    }
    if (revision == _revision) {
      if (value case SessionsReady(catalogGroups: final groups?)) {
        _publishGroups([
          for (final group in groups)
            group.profile.id == profile.id
                ? SessionCatalogGroup(
                    profile: group.profile,
                    sessions: group.sessions
                        .where((item) => item.id != session.id)
                        .toList(),
                    projects: group.projects,
                    activities: group.activities,
                    unavailableDirectories: group.unavailableDirectories,
                    failure: group.failure,
                  )
                : group,
        ]);
        return null;
      }
      if (value case SessionsReady(
        :final sessions,
        :final projects,
        :final unavailableDirectories,
      )) {
        final nextActivities = Map<String, SessionActivity>.from(
          _baseActivities,
        )..remove(session.id);
        _baseActivities = Map.unmodifiable(nextActivities);
        value = SessionsReady(
          List.unmodifiable(
            sessions.where((candidate) => candidate.id != session.id),
          ),
          projects,
          activities: _overlayActivities(_baseActivities),
          unavailableDirectories: unavailableDirectories,
        );
      }
    }
    return null;
  }

  void _addSession(ServerProfile profile, OpenCodeSession session) {
    if (_mutateScoped(profile, session, add: true)) return;
    if (value case SessionsReady(
      :final sessions,
      :final projects,
      :final unavailableDirectories,
    )) {
      final updated = [
        session,
        ...sessions.where((candidate) => candidate.id != session.id),
      ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      value = SessionsReady(
        List.unmodifiable(updated),
        projects,
        activities: _overlayActivities(_baseActivities),
        unavailableDirectories: unavailableDirectories,
      );
    }
  }

  void _replaceSession(
    ServerProfile profile,
    OpenCodeSession previous,
    OpenCodeSession replacement,
  ) {
    if (_mutateScoped(profile, replacement)) return;
    if (value case SessionsReady(
      :final sessions,
      :final projects,
      :final unavailableDirectories,
    )) {
      final updated = [
        for (final session in sessions)
          if (session.id == previous.id) replacement else session,
      ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      value = SessionsReady(
        List.unmodifiable(updated),
        projects,
        activities: _overlayActivities(_baseActivities),
        unavailableDirectories: unavailableDirectories,
      );
    }
  }

  @override
  void dispose() {
    _revision++;
    _suggestionRevision++;
    unbindLiveStatuses();
    super.dispose();
  }

  bool _mutateScoped(
    ServerProfile profile,
    OpenCodeSession replacement, {
    bool add = false,
  }) {
    if (value case SessionsReady(catalogGroups: final groups?)) {
      _publishGroups([
        for (final group in groups)
          group.profile.id == profile.id
              ? SessionCatalogGroup(
                  profile: group.profile,
                  sessions: [
                    if (add) replacement,
                    for (final item in group.sessions)
                      if (item.id != replacement.id)
                        item
                      else if (!add)
                        replacement,
                  ],
                  projects: group.projects,
                  activities: group.activities,
                  unavailableDirectories: group.unavailableDirectories,
                  failure: group.failure,
                )
              : group,
      ]);
      return true;
    }
    return false;
  }

  void _publishGroups(List<SessionCatalogGroup> groups) {
    final sessions = [for (final group in groups) ...group.sessions]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    value = SessionsReady(
      List.unmodifiable(sessions),
      List.unmodifiable([
        for (final group in groups)
          for (final project in group.projects)
            OpenCodeProject(
              id: scopedProjectKey(group.profile, project.id),
              directory: project.directory,
            ),
      ]),
      catalogGroups: List.unmodifiable(groups),
    );
  }
}
