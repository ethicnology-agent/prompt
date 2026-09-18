import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/connection.dart';
import '../data/workspace_repository.dart';
import '../domain/workspace_entry.dart';
import '../domain/workspace_failure.dart';

sealed class WorkspaceFileState {
  const WorkspaceFileState();
}

class WorkspaceFileIdle extends WorkspaceFileState {
  const WorkspaceFileIdle();
}

class WorkspaceFileLoading extends WorkspaceFileState {
  const WorkspaceFileLoading();
}

class WorkspaceFileReady extends WorkspaceFileState {
  WorkspaceFileReady(this.content)
    : lines = List.unmodifiable(
        content.isText && content.value!.isNotEmpty
            ? content.value!.split(RegExp(r'\r\n|\n|\r'))
            : const <String>[],
      );

  final WorkspaceFileContent content;
  final List<String> lines;
}

class WorkspaceFileError extends WorkspaceFileState {
  const WorkspaceFileError(this.failure);
  final WorkspaceFailure failure;
}

class WorkspaceFileViewModel extends ValueNotifier<WorkspaceFileState> {
  WorkspaceFileViewModel(this._repository) : super(const WorkspaceFileIdle());

  final WorkspaceRepository _repository;
  int _generation = 0;
  bool _disposed = false;

  Future<void> load(
    ServerProfile profile,
    String directory,
    String path,
  ) async {
    if (_disposed) return;
    final generation = ++_generation;
    value = const WorkspaceFileLoading();
    final result = await _repository.readFile(profile, directory, path);
    if (_disposed || generation != _generation) return;
    value = switch (result) {
      Ok(:final value) => WorkspaceFileReady(value),
      Err(:final failure) => WorkspaceFileError(failure),
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
