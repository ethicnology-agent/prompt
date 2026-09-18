import '../../../core/async/result.dart';
import '../../connection/connection.dart';
import '../data/sessions_repository.dart';
import '../domain/scoped_session.dart';
import '../domain/session_load_result.dart';

/// Loads only advertised engines on one authenticated gateway. It never
/// activates a conversation, changes the last profile, or opens an SSE feed.
class LoadSessionCatalog {
  LoadSessionCatalog(this._connections, this._sessions);
  final ConnectionRepository _connections;
  final SessionsRepository _sessions;

  Future<List<SessionCatalogGroup>> call(ServerProfile source) async {
    final discovered = await _connections.availableBackends(source);
    if (discovered case Err()) {
      return [
        SessionCatalogGroup(
          profile: source,
          failure: SessionsFailure.unavailable,
        ),
      ];
    }
    final backends = (discovered as Ok<List<AgentBackend>, ConnectionFailure>)
        .value
        .where((backend) => backend.isGateway)
        .toSet();
    // At most the three gateway engine kinds. No caller-controlled origins.
    final groups = <SessionCatalogGroup>[];
    for (final backend in backends) {
      final prepared = await _connections.prepareBackend(source, backend);
      if (prepared case ConnectionSucceeded(profile: final profile?)) {
        final result = await _sessions.load(profile);
        groups.add(switch (result) {
          SessionsLoaded(
            :final sessions,
            :final projects,
            :final activities,
            :final unavailableDirectories,
          ) =>
            SessionCatalogGroup(
              profile: profile,
              sessions: sessions,
              projects: projects,
              activities: activities,
              unavailableDirectories: unavailableDirectories,
            ),
          SessionsLoadFailed(:final failure) => SessionCatalogGroup(
            profile: profile,
            failure: failure,
          ),
        });
      } else {
        groups.add(
          SessionCatalogGroup(
            profile: ServerProfile(
              origin: source.origin,
              username: source.username,
              backend: backend,
            ),
            failure: SessionsFailure.unavailable,
          ),
        );
      }
    }
    if (groups.isEmpty) {
      return [
        SessionCatalogGroup(
          profile: source,
          failure: SessionsFailure.unavailable,
        ),
      ];
    }
    return List.unmodifiable(groups);
  }
}
