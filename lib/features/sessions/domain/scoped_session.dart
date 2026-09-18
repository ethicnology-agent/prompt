import '../../connection/connection.dart';
import 'open_code_project.dart';
import 'open_code_session.dart';
import 'session_activity.dart';
import 'session_load_result.dart';

/// A server session ID is unique only inside its authenticated engine profile.
class ScopedSession {
  const ScopedSession(
    this.profile,
    this.session, {
    this.activity = SessionActivity.unknown,
  });
  final ServerProfile profile;
  final OpenCodeSession session;
  final SessionActivity activity;
  (String, String) get identity => (profile.id, session.id);
  String get projectKey => scopedProjectKey(profile, session.projectId);
}

String scopedProjectKey(ServerProfile profile, String projectId) =>
    '${profile.id}:$projectId';

class SessionCatalogGroup {
  const SessionCatalogGroup({
    required this.profile,
    this.sessions = const [],
    this.projects = const [],
    this.activities = const {},
    this.unavailableDirectories = const {},
    this.failure,
  });
  final ServerProfile profile;
  final List<OpenCodeSession> sessions;
  final List<OpenCodeProject> projects;
  final Map<String, SessionActivity> activities;
  final Set<String> unavailableDirectories;
  final SessionsFailure? failure;

  List<ScopedSession> get entries => [
    for (final session in sessions)
      ScopedSession(
        profile,
        session,
        activity:
            failure != null ||
                unavailableDirectories.contains(session.directory)
            ? SessionActivity.unavailable
            : activities[session.id] ?? SessionActivity.unknown,
      ),
  ];

  SessionCatalogGroup failed(SessionsFailure reason) => SessionCatalogGroup(
    profile: profile,
    sessions: sessions,
    projects: projects,
    failure: reason,
  );
}
