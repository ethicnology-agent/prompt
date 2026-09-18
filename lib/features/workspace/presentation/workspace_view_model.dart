import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../data/workspace_repository.dart';
import '../domain/workspace_entry.dart';
import '../domain/workspace_failure.dart';
import 'workspace_file_view_model.dart';

sealed class WorkspaceUiState {
  const WorkspaceUiState();
}

class WorkspaceIdle extends WorkspaceUiState {
  const WorkspaceIdle();
}

class WorkspaceLoading extends WorkspaceUiState {
  const WorkspaceLoading();
}

class WorkspaceReady extends WorkspaceUiState {
  const WorkspaceReady({
    required this.project,
    required this.currentPath,
    required this.snapshot,
    this.content,
    this.contentFailure,
    this.isLoadingContent = false,
    this.search = const WorkspaceSearchIdle(),
  });

  final OpenCodeProject project;
  final String currentPath;
  final WorkspaceSnapshot snapshot;
  final WorkspaceFileContent? content;
  final WorkspaceFailure? contentFailure;
  final bool isLoadingContent;
  final WorkspaceSearchState search;
}

class WorkspaceError extends WorkspaceUiState {
  const WorkspaceError(this.failure);

  final WorkspaceFailure failure;
}

sealed class WorkspaceSearchState {
  const WorkspaceSearchState();
}

class WorkspaceSearchIdle extends WorkspaceSearchState {
  const WorkspaceSearchIdle();
}

class WorkspaceSearchLoading extends WorkspaceSearchState {
  const WorkspaceSearchLoading({required this.kind, required this.query});

  final WorkspaceSearchKind kind;
  final String query;
}

class WorkspaceSearchReady extends WorkspaceSearchState {
  const WorkspaceSearchReady({
    required this.kind,
    required this.query,
    required this.results,
  });

  final WorkspaceSearchKind kind;
  final String query;
  final List<WorkspaceSearchResult> results;
}

class WorkspaceSearchError extends WorkspaceSearchState {
  const WorkspaceSearchError({
    required this.kind,
    required this.query,
    required this.failure,
  });

  final WorkspaceSearchKind kind;
  final String query;
  final WorkspaceFailure failure;
}

class WorkspaceViewModel extends ValueNotifier<WorkspaceUiState> {
  WorkspaceViewModel(this._repository) : super(const WorkspaceIdle());

  final WorkspaceRepository _repository;

  WorkspaceFileViewModel createFileViewModel() =>
      WorkspaceFileViewModel(_repository);
  final List<String> _pathHistory = [];
  Timer? _searchDebounce;
  int _searchRequest = 0;
  int _loadRequest = 0;
  int _fileRequest = 0;
  bool _disposed = false;
  String? _profileId;
  OpenCodeProject? _retryProject;
  String? _retryPath;

  bool get canGoUp =>
      !_disposed && value is WorkspaceReady && _pathHistory.length > 1;

  bool _matchesProfile(ServerProfile profile) =>
      !_disposed && _profileId == profile.id;

  @override
  void dispose() {
    _disposed = true;
    _loadRequest++;
    _fileRequest++;
    _searchRequest++;
    _searchDebounce?.cancel();
    super.dispose();
  }

  void clear() {
    if (_disposed) return;
    _searchDebounce?.cancel();
    _searchRequest++;
    _loadRequest++;
    _fileRequest++;
    _profileId = null;
    _retryProject = null;
    _retryPath = null;
    _pathHistory.clear();
    value = const WorkspaceIdle();
  }

  Future<void> selectProject(ServerProfile profile, OpenCodeProject project) {
    if (_disposed) return Future.value();
    _pathHistory
      ..clear()
      ..add(project.directory);
    return _load(profile, project, project.directory);
  }

  Future<void> openDirectory(ServerProfile profile, WorkspaceEntry entry) {
    if (!_matchesProfile(profile)) return Future.value();
    final ready = value;
    if (ready is! WorkspaceReady || !entry.isDirectory) {
      return Future.value();
    }
    _pathHistory.add(entry.path);
    return _load(profile, ready.project, entry.path);
  }

  Future<void> goUp(ServerProfile profile) {
    if (!_matchesProfile(profile)) return Future.value();
    final ready = value;
    if (ready is! WorkspaceReady || _pathHistory.length < 2) {
      return Future.value();
    }
    _pathHistory.removeLast();
    return _load(profile, ready.project, _pathHistory.last);
  }

  Future<void> refresh(ServerProfile profile) {
    if (!_matchesProfile(profile) || value is WorkspaceLoading) {
      return Future.value();
    }
    final project = _retryProject;
    final path = _retryPath;
    if (project == null || path == null) {
      return Future.value();
    }
    return _load(profile, project, path);
  }

  Future<void> openFile(ServerProfile profile, WorkspaceEntry entry) async {
    if (!_matchesProfile(profile)) return;
    final ready = value;
    if (ready is! WorkspaceReady || entry.isDirectory) {
      return;
    }
    final request = ++_fileRequest;
    final scope = _loadRequest;
    value = WorkspaceReady(
      project: ready.project,
      currentPath: ready.currentPath,
      snapshot: ready.snapshot,
      isLoadingContent: true,
      search: ready.search,
    );
    final result = await _repository.readFile(
      profile,
      ready.project.directory,
      entry.path,
    );
    if (_disposed ||
        request != _fileRequest ||
        scope != _loadRequest ||
        value is! WorkspaceReady) {
      return;
    }
    switch (result) {
      case Ok<WorkspaceFileContent, WorkspaceFailure>(value: final content):
        final current = value as WorkspaceReady;
        value = WorkspaceReady(
          project: current.project,
          currentPath: current.currentPath,
          snapshot: current.snapshot,
          content: content,
          search: current.search,
        );
      case Err<WorkspaceFileContent, WorkspaceFailure>(:final failure):
        final current = value as WorkspaceReady;
        value = WorkspaceReady(
          project: current.project,
          currentPath: current.currentPath,
          snapshot: current.snapshot,
          contentFailure: failure,
          search: current.search,
        );
    }
  }

  void search(ServerProfile profile, WorkspaceSearchKind kind, String query) {
    if (!_matchesProfile(profile)) return;
    _searchDebounce?.cancel();
    final request = ++_searchRequest;
    final ready = value;
    if (ready is! WorkspaceReady) {
      return;
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      value = _withSearch(ready, const WorkspaceSearchIdle());
      return;
    }
    value = _withSearch(
      ready,
      WorkspaceSearchLoading(kind: kind, query: trimmed),
    );
    final directory = ready.currentPath;
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final result = await _repository.search(
        profile,
        directory,
        kind,
        trimmed,
      );
      if (_disposed || request != _searchRequest || value is! WorkspaceReady) {
        return;
      }
      final current = value as WorkspaceReady;
      value = _withSearch(current, switch (result) {
        Ok<List<WorkspaceSearchResult>, WorkspaceFailure>(:final value) =>
          WorkspaceSearchReady(kind: kind, query: trimmed, results: value),
        Err<List<WorkspaceSearchResult>, WorkspaceFailure>(:final failure) =>
          WorkspaceSearchError(kind: kind, query: trimmed, failure: failure),
      });
    });
  }

  Future<void> _load(
    ServerProfile profile,
    OpenCodeProject project,
    String path,
  ) async {
    if (_disposed) return;
    final request = ++_loadRequest;
    _fileRequest++;
    _profileId = profile.id;
    _retryProject = project;
    _retryPath = path;
    value = const WorkspaceLoading();
    _searchDebounce?.cancel();
    _searchRequest++;
    final result = await _repository.load(profile, project.directory, path);
    if (_disposed || request != _loadRequest) return;
    switch (result) {
      case Ok<WorkspaceSnapshot, WorkspaceFailure>(:final value):
        this.value = WorkspaceReady(
          project: project,
          currentPath: path,
          snapshot: value,
        );
      case Err<WorkspaceSnapshot, WorkspaceFailure>(:final failure):
        value = WorkspaceError(failure);
    }
  }

  WorkspaceReady _withSearch(
    WorkspaceReady ready,
    WorkspaceSearchState search,
  ) => WorkspaceReady(
    project: ready.project,
    currentPath: ready.currentPath,
    snapshot: ready.snapshot,
    content: ready.content,
    contentFailure: ready.contentFailure,
    isLoadingContent: ready.isLoadingContent,
    search: search,
  );
}
