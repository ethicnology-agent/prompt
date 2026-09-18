import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../connection/connection.dart';
import '../domain/session_worktree.dart';
import 'worktree_service.dart';

class WorktreeRepository {
  WorktreeRepository(this._service, this._credentials);
  final WorktreeService _service;
  final CredentialsStore _credentials;

  Future<Result<SessionWorktreeCatalog, WorktreeFailure>> load(
    ServerProfile profile,
    String directory,
  ) async {
    if (!profile.backend.isGateway) {
      return const Err(WorktreeFailure.unsupported);
    }
    try {
      final password = await _credentials.readPassword(profile.id);
      if (!await _service.supported(profile, password)) {
        return const Err(WorktreeFailure.unsupported);
      }
      return Ok(await _service.list(profile, password, directory));
    } on WorktreeServiceFailure catch (failure) {
      return Err(_failure(failure.code, false));
    } on Exception {
      return const Err(WorktreeFailure.unavailable);
    }
  }

  Future<Result<SessionWorktree, WorktreeFailure>> create(
    ServerProfile profile,
    String directory,
    String name,
  ) async {
    if (!profile.backend.isGateway) {
      return const Err(WorktreeFailure.unsupported);
    }
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$').hasMatch(name)) {
      return const Err(WorktreeFailure.invalidName);
    }
    var dispatched = false;
    try {
      final password = await _credentials.readPassword(profile.id);
      if (!await _service.supported(profile, password)) {
        return const Err(WorktreeFailure.unsupported);
      }
      dispatched = true;
      return Ok(await _service.create(profile, password, directory, name));
    } on WorktreeServiceFailure catch (failure) {
      return Err(_failure(failure.code, dispatched));
    } on Exception {
      return Err(
        dispatched
            ? WorktreeFailure.creationUncertain
            : WorktreeFailure.unavailable,
      );
    }
  }

  WorktreeFailure _failure(String code, bool creating) => switch (code) {
    'worktrees_unavailable' => WorktreeFailure.unsupported,
    'not_git_repository' => WorktreeFailure.notGitRepository,
    'unsafe_repository_configuration' => WorktreeFailure.unsafeRepository,
    'directory_not_allowed' ||
    'worktree_root_changed' => WorktreeFailure.forbidden,
    'invalid_worktree_name' => WorktreeFailure.invalidName,
    'worktree_busy' => WorktreeFailure.busy,
    _ =>
      creating
          ? WorktreeFailure.creationUncertain
          : WorktreeFailure.unavailable,
  };
}
