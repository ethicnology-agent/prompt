import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../../core/async/result.dart';
import '../domain/agent_backend.dart';
import '../domain/connection_result.dart';
import '../domain/connection_origin_policy.dart';
import '../domain/server_profile.dart';
import 'opencode_health_service.dart';
import 'server_profile_store.dart';

class ConnectionRepository {
  ConnectionRepository(
    this._healthService,
    this._credentialsStore,
    this._profileStore,
  );

  final OpenCodeHealthService _healthService;
  final CredentialsStore _credentialsStore;
  final ServerProfileStore _profileStore;

  Future<Result<List<AgentBackend>, ConnectionFailure>> availableBackends(
    ServerProfile source,
  ) async {
    try {
      if (!ConnectionOriginPolicy.supports(source.origin)) {
        return const Err(ConnectionFailure.invalidAddress);
      }
      final password = await _credentialsStore.readPassword(source.id);
      final backends = await _healthService.discoverBackends(source, password);
      return Ok(List.unmodifiable(backends.keys));
    } on OpenCodeHttpFailure catch (failure) {
      return Err(
        failure.statusCode == 401 || failure.statusCode == 403
            ? ConnectionFailure.unauthorized
            : ConnectionFailure.unexpectedResponse,
      );
    } on TimeoutException {
      return const Err(ConnectionFailure.unavailable);
    } on http.ClientException {
      return const Err(ConnectionFailure.unavailable);
    } on Exception {
      return const Err(ConnectionFailure.secureStorageUnavailable);
    }
  }

  /// Derives only an engine namespace on the already authenticated endpoint.
  /// No caller-provided target origin or username can receive its credential.
  /// Selection never changes the persisted last-active profile.
  Future<ConnectionResult> prepareBackend(
    ServerProfile source,
    AgentBackend backend,
  ) async {
    if (!ConnectionOriginPolicy.supports(source.origin)) {
      return const ConnectionFailed(ConnectionFailure.invalidAddress);
    }
    if (source.backend.isGateway != backend.isGateway) {
      return const ConnectionFailed(ConnectionFailure.unsupportedBackend);
    }
    final target = ServerProfile(
      origin: source.origin,
      username: source.username,
      backend: backend,
    );
    try {
      final password = await _credentialsStore.readPassword(source.id);
      final capabilities = await _healthService.checkCapabilities(
        target,
        password,
      );
      if (capabilities == null) {
        return const ConnectionFailed(ConnectionFailure.unsupportedBackend);
      }
      final status = await _healthService.checkHealth(target, password);
      if (status == 401 || status == 403) {
        return const ConnectionFailed(ConnectionFailure.unauthorized);
      }
      if (status < 200 || status >= 300) {
        return const ConnectionFailed(ConnectionFailure.unexpectedResponse);
      }
      if (source.id != target.id) {
        await _credentialsStore.savePassword(target.id, password);
      }
      return ConnectionSucceeded(
        profile: target.withCapabilities(capabilities),
      );
    } on OpenCodeHttpFailure catch (failure) {
      return ConnectionFailed(
        failure.statusCode == 401 || failure.statusCode == 403
            ? ConnectionFailure.unauthorized
            : ConnectionFailure.unexpectedResponse,
      );
    } on TimeoutException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on http.ClientException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on Exception {
      return const ConnectionFailed(ConnectionFailure.secureStorageUnavailable);
    }
  }

  Future<void> rememberActiveProfile(ServerProfile profile) =>
      _profileStore.save(profile);

  Future<ConnectionResult> test(ServerProfile profile, String? password) async {
    if (!ConnectionOriginPolicy.supports(profile.origin)) {
      return const ConnectionFailed(ConnectionFailure.invalidAddress);
    }

    try {
      final capabilities = await _healthService.checkCapabilities(
        profile,
        password,
      );
      if (capabilities == null) {
        return const ConnectionFailed(ConnectionFailure.unsupportedBackend);
      }
      final statusCode = await _healthService.checkHealth(profile, password);
      if (statusCode >= 200 && statusCode < 300) {
        await _credentialsStore.savePassword(profile.id, password);
        await _profileStore.save(profile);
        return ConnectionSucceeded(
          profile: profile.withCapabilities(capabilities),
        );
      }
      if (statusCode == 401 || statusCode == 403) {
        return const ConnectionFailed(ConnectionFailure.unauthorized);
      }
      return const ConnectionFailed(ConnectionFailure.unexpectedResponse);
    } on TimeoutException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on OpenCodeHttpFailure catch (failure) {
      return ConnectionFailed(
        failure.statusCode == 401 || failure.statusCode == 403
            ? ConnectionFailure.unauthorized
            : ConnectionFailure.unexpectedResponse,
      );
    } on InvalidOpenCodeOrigin {
      return const ConnectionFailed(ConnectionFailure.invalidAddress);
    } on http.ClientException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on Exception {
      return const ConnectionFailed(ConnectionFailure.secureStorageUnavailable);
    }
  }

  Future<ConnectionResult> pair(ServerProfile profile, String ticket) async {
    if (!profile.backend.isGateway ||
        !ConnectionOriginPolicy.supports(profile.origin)) {
      return const ConnectionFailed(ConnectionFailure.invalidAddress);
    }
    try {
      final credential = await _healthService.redeemPairing(profile, ticket);
      if (credential == null) {
        return const ConnectionFailed(ConnectionFailure.pairingRejected);
      }
      return test(profile, credential);
    } on TimeoutException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on OpenCodeHttpFailure {
      return const ConnectionFailed(ConnectionFailure.pairingRejected);
    } on InvalidOpenCodeOrigin {
      return const ConnectionFailed(ConnectionFailure.invalidAddress);
    } on http.ClientException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on Exception {
      return const ConnectionFailed(ConnectionFailure.unexpectedResponse);
    }
  }

  Future<ConnectionResult> restore(ServerProfile profile) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      return test(profile, password);
    } on Exception {
      return const ConnectionFailed(ConnectionFailure.secureStorageUnavailable);
    }
  }
}
