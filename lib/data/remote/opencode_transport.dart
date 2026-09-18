import 'package:http/http.dart' as http;

import '../../core/network/opencode_authorization.dart';
import '../../features/connection/connection.dart';

class InvalidOpenCodeOrigin implements Exception {
  const InvalidOpenCodeOrigin();
}

class OpenCodeTransportFailure implements Exception {
  const OpenCodeTransportFailure(this.statusCode);

  final int statusCode;
}

class OpenCodeHttpFailure implements Exception {
  const OpenCodeHttpFailure(this.statusCode);

  final int statusCode;
}

class OpenCodeTransport {
  OpenCodeTransport(http.Client client) : _client = _PrivateRouteClient(client);

  final http.Client _client;

  Future<http.Response> get(
    ServerProfile profile,
    String? password,
    String path,
  ) {
    return _client
        .get(_uri(profile, path), headers: _headers(profile, password))
        .timeout(const Duration(seconds: 15));
  }

  Future<http.Response> post(
    ServerProfile profile,
    String? password,
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _client
        .post(
          _uri(profile, path),
          headers: {..._headers(profile, password), ...?headers},
          body: body,
        )
        .timeout(timeout);
  }

  Future<http.Response> patch(
    ServerProfile profile,
    String? password,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) {
    return _client
        .patch(
          _uri(profile, path),
          headers: {..._headers(profile, password), ...?headers},
          body: body,
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<http.Response> delete(
    ServerProfile profile,
    String? password,
    String path,
  ) {
    return _client
        .delete(_uri(profile, path), headers: _headers(profile, password))
        .timeout(const Duration(seconds: 15));
  }

  Future<http.StreamedResponse> send(
    ServerProfile profile,
    String? password,
    String path, {
    Map<String, String>? headers,
  }) {
    final request = http.Request('GET', _uri(profile, path));
    request.headers.addAll({..._headers(profile, password), ...?headers});
    return _client.send(request).timeout(const Duration(seconds: 15));
  }

  Uri _uri(ServerProfile profile, String path) {
    if (!ConnectionOriginPolicy.supports(profile.origin)) {
      throw const InvalidOpenCodeOrigin();
    }
    final relative = Uri.parse(path);
    // Validate raw segments before Uri normalization can erase traversal.
    final decodedPath = Uri.decodeComponent(
      path.split('?').first.split('#').first,
    );
    if (relative.hasScheme ||
        relative.hasAuthority ||
        !path.startsWith('/') ||
        path.startsWith('//') ||
        relative.pathSegments.contains('..') ||
        decodedPath.split('/').contains('..') ||
        decodedPath.contains('\\') ||
        decodedPath.codeUnits.any((unit) => unit < 32 || unit == 127) ||
        decodedPath.toLowerCase().contains('%2e') ||
        decodedPath.toLowerCase().contains('%2f') ||
        decodedPath.toLowerCase().contains('%5c')) {
      throw const InvalidOpenCodeOrigin();
    }
    final machineRoute =
        relative.path == '/prompt/capabilities' ||
        relative.path == '/prompt/worktrees';
    final routed = profile.backend.isGateway && !machineRoute
        ? '/prompt/${profile.backend.engine}$path'
        : path;
    return profile.origin.resolve(routed);
  }

  Map<String, String> _headers(ServerProfile profile, String? password) {
    return openCodeAuthorizationHeaders(
      username: profile.username,
      password: password,
    );
  }
}

/// A configured private endpoint may not redirect credentials or content to
/// another origin, including a public HTTPS origin. Ownership stays with the
/// composition root; this wrapper never disposes the injected client.
class _PrivateRouteClient extends http.BaseClient {
  _PrivateRouteClient(this._delegate);
  final http.Client _delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return _delegate.send(request);
  }
}
