import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
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

  Future<ConnectionResult> restore(ServerProfile profile) async {
    final password = await _credentialsStore.readPassword(profile.id);
    return test(profile, password);
  }
}
