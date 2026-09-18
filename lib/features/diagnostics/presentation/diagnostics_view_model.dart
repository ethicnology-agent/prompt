import 'package:flutter/foundation.dart';

import '../../connection/connection.dart';
import '../data/diagnostics_repository.dart';
import '../domain/diagnostics_load_result.dart';
import '../domain/diagnostics_snapshot.dart';

sealed class DiagnosticsUiState {
  const DiagnosticsUiState();
}

class DiagnosticsIdle extends DiagnosticsUiState {
  const DiagnosticsIdle();
}

class DiagnosticsLoading extends DiagnosticsUiState {
  const DiagnosticsLoading();
}

class DiagnosticsReady extends DiagnosticsUiState {
  const DiagnosticsReady(this.snapshot);

  final DiagnosticsSnapshot snapshot;
}

class DiagnosticsError extends DiagnosticsUiState {
  const DiagnosticsError(this.failure);

  final DiagnosticsFailure failure;
}

class DiagnosticsViewModel extends ValueNotifier<DiagnosticsUiState> {
  DiagnosticsViewModel(this._repository) : super(const DiagnosticsIdle());

  final DiagnosticsRepository _repository;
  ServerProfile? _profile;
  int _request = 0;
  bool _disposed = false;

  Future<void> load(ServerProfile profile) async {
    if (_disposed) return;
    _profile = profile;
    final request = ++_request;
    value = const DiagnosticsLoading();
    final result = await _repository.load(profile);
    if (_disposed || request != _request) {
      return;
    }
    value = switch (result) {
      DiagnosticsLoaded(:final snapshot) => DiagnosticsReady(snapshot),
      DiagnosticsLoadFailed(:final failure) => DiagnosticsError(failure),
    };
  }

  Future<void> refresh() async {
    final profile = _profile;
    if (profile != null) {
      await load(profile);
    }
  }

  Future<DiagnosticsReloadResult> reload({
    ServerProfile? expectedProfile,
  }) async {
    final profile = _profile;
    if (_disposed ||
        profile == null ||
        (expectedProfile != null && expectedProfile.id != profile.id)) {
      return const DiagnosticsReloadFailed(
        DiagnosticsFailure.unexpectedResponse,
      );
    }
    final request = _request;
    final result = await _repository.reload(profile);
    if (_disposed || request != _request) {
      return const DiagnosticsReloadFailed(
        DiagnosticsFailure.unexpectedResponse,
      );
    }
    if (result is DiagnosticsReloaded) {
      await load(profile);
      if (_disposed || request + 1 != _request) {
        return const DiagnosticsReloadFailed(
          DiagnosticsFailure.unexpectedResponse,
        );
      }
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
