class SessionWorktree {
  const SessionWorktree({
    required this.directory,
    this.branch,
    this.detached = false,
    this.locked = false,
  });
  final String directory;
  final String? branch;
  final bool detached;
  final bool locked;
}

enum WorktreePhase { idle, loading, ready, creating, unsupported, failed }

enum WorktreeFailure {
  unsupported,
  notGitRepository,
  unsafeRepository,
  forbidden,
  invalidName,
  busy,
  unavailable,
  creationUncertain;

  String get message => switch (this) {
    unsupported => 'This server does not support creating worktrees.',
    notGitRepository => 'This folder is not a Git repository.',
    unsafeRepository =>
      'This repository configuration is not supported for safe worktree creation.',
    forbidden => 'This folder is outside the configured workspace roots.',
    invalidName =>
      'Use 1–40 letters, digits, underscores or hyphens; begin with a letter or digit.',
    busy =>
      'Another worktree operation is already running for this repository.',
    unavailable =>
      'Worktrees could not be loaded. Your session choices have been kept.',
    creationUncertain =>
      'Creation could not be confirmed. Refresh the worktrees before trying again.',
  };
}

class SessionWorktreeCatalog {
  const SessionWorktreeCatalog({
    required this.worktrees,
    required this.canCreate,
  });
  final List<SessionWorktree> worktrees;
  final bool canCreate;
}
