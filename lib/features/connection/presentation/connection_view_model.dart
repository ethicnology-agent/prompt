import 'package:flutter/foundation.dart';

import '../data/connection_repository.dart';
import '../domain/connection_result.dart';
import '../domain/server_profile.dart';

sealed class ConnectionUiState {
  const ConnectionUiState();
}

class ConnectionIdle extends ConnectionUiState {
  const ConnectionIdle();
}

class ConnectionChecking extends ConnectionUiState {
  const ConnectionChecking();
}

class ConnectionReady extends ConnectionUiState {
  const ConnectionReady(this.profile);

  final ServerProfile profile;
}

class ConnectionError extends ConnectionUiState {
  const ConnectionError(this.failure);

  final ConnectionFailure failure;
}

class ConnectionViewModel extends ValueNotifier<ConnectionUiState> {
  ConnectionViewModel(this._repository) : super(const ConnectionIdle());

  final ConnectionRepository _repository;
  int _operationGeneration = 0;
  bool _disposed = false;

  /// Invalidates pending screen/profile-loader callbacks as well as requests.
  int get operationGeneration => _operationGeneration;

  Future<void> connect(ServerProfile profile, String? password) async {
    if (_disposed || value is ConnectionChecking) return;
    final generation = ++_operationGeneration;
    value = const ConnectionChecking();
    final result = await _repository.test(profile, password);
    if (_disposed || generation != _operationGeneration) return;

    switch (result) {
      case ConnectionSucceeded(profile: final verified):
        value = ConnectionReady(verified ?? profile);
      case ConnectionFailed(:final failure):
        value = ConnectionError(failure);
    }
  }

  Future<void> restore(ServerProfile profile) async {
    if (_disposed || value is ConnectionChecking) return;
    final generation = ++_operationGeneration;
    value = const ConnectionChecking();
    final result = await _repository.restore(profile);
    if (_disposed || generation != _operationGeneration) return;
    switch (result) {
      case ConnectionSucceeded(profile: final verified):
        value = ConnectionReady(verified ?? profile);
      case ConnectionFailed(:final failure):
        value = ConnectionError(failure);
    }
  }

  void reset() {
    if (_disposed) return;
    _operationGeneration++;
    value = const ConnectionIdle();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    super.dispose();
  }
}
