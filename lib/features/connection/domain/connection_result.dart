import 'server_profile.dart';

sealed class ConnectionResult {
  const ConnectionResult();
}

class ConnectionSucceeded extends ConnectionResult {
  const ConnectionSucceeded({this.profile});
  final ServerProfile? profile;
}

class ConnectionFailed extends ConnectionResult {
  const ConnectionFailed(this.failure);

  final ConnectionFailure failure;
}

enum ConnectionFailure {
  invalidAddress,
  unauthorized,
  unavailable,
  unexpectedResponse,
  secureStorageUnavailable,
  unsupportedBackend,
  pairingRejected,
}

extension ConnectionFailureMessage on ConnectionFailure {
  String get message {
    return switch (this) {
      ConnectionFailure.invalidAddress =>
        'Enter a private WireGuard or Tailscale HTTP address, or a valid HTTPS address.',
      ConnectionFailure.unauthorized =>
        'The server rejected these credentials.',
      ConnectionFailure.unavailable =>
        'Prompt cannot reach this server. Check WireGuard or Tailscale and the address.',
      ConnectionFailure.unexpectedResponse =>
        'The server responded, but is not ready for Prompt.',
      ConnectionFailure.secureStorageUnavailable =>
        'Prompt cannot store the server credential securely on this device.',
      ConnectionFailure.unsupportedBackend =>
        'This gateway has not verified support for the selected agent. Check its configuration.',
      ConnectionFailure.pairingRejected =>
        'This pairing code expired or was already used. Create a new code on your machine.',
    };
  }
}
