import 'dart:convert';

import '../../../data/remote/opencode_transport.dart';
import '../domain/agent_backend.dart';
import '../domain/server_profile.dart';

AttachmentConstraints? _attachmentConstraints(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final mimeTypes = value['mimeTypes'];
  final count = value['maxCount'];
  final perFile = value['maxBytesPerAttachment'];
  final total = value['maxTotalBytes'];
  if (mimeTypes is! List ||
      mimeTypes.isEmpty ||
      mimeTypes.length > 16 ||
      mimeTypes.any((mime) => mime is! String || mime.length > 128) ||
      count is! int ||
      count < 1 ||
      count > 5 ||
      perFile is! int ||
      perFile < 1 ||
      perFile > 10 * 1024 * 1024 ||
      total is! int ||
      total < 1 ||
      total > 25 * 1024 * 1024) {
    return null;
  }
  return AttachmentConstraints(
    mimeTypes: mimeTypes.cast<String>(),
    maxCount: count,
    maxBytesPerAttachment: perFile,
    maxTotalBytes: total,
  );
}

class OpenCodeHealthService {
  OpenCodeHealthService(this._transport);

  final OpenCodeTransport _transport;

  /// Detects the protocol on this exact origin, without asking the user to
  /// select an engine or forwarding credentials to any other endpoint.
  Future<ServerProfile?> detectProfile(
    ServerProfile source,
    String? password,
  ) async {
    final response = await _transport.get(
      source,
      password,
      '/prompt/capabilities',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    final backends = response.statusCode == 200
        ? _parseBackends(response.body)
        : <AgentBackend, BackendCapabilities>{};
    if (backends.isNotEmpty) {
      final backend = backends.containsKey(source.backend)
          ? source.backend
          : backends.keys.first;
      return ServerProfile(
        origin: source.origin,
        username: source.username,
        backend: backend,
        capabilities: backends[backend],
      );
    }
    // A direct server may return its web shell for an unknown path. Only a
    // genuine OpenCode health payload confirms this compatibility path.
    final absentGateway =
        response.statusCode == 404 ||
        (response.statusCode == 200 &&
            (response.headers['content-type'] ?? '').startsWith('text/html'));
    if (!absentGateway) return null;
    final direct = ServerProfile(
      origin: source.origin,
      username: source.username,
    );
    final health = await _transport.get(direct, password, '/global/health');
    if (health.statusCode == 401 || health.statusCode == 403) {
      throw OpenCodeHttpFailure(health.statusCode);
    }
    if (health.statusCode != 200) return null;
    try {
      final body = jsonDecode(health.body);
      return body is Map<String, dynamic> && body['healthy'] == true
          ? direct
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> redeemPairing(ServerProfile profile, String ticket) async {
    if (!profile.backend.isGateway) return null;
    final response = await _transport.post(
      profile,
      null,
      '/prompt/pairings/exchange',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'ticket': ticket, 'backend': profile.backend.engine}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    if (response.statusCode != 200) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body.keys.toSet().difference({
            'username',
            'token',
            'backend',
          }).isNotEmpty ||
          body['username'] != profile.username ||
          body['backend'] != profile.backend.engine ||
          body['token'] is! String ||
          !RegExp(
            r'^p1\.[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{43}$',
          ).hasMatch(body['token'] as String)) {
        return null;
      }
      return body['token'] as String;
    } on FormatException {
      return null;
    }
  }

  Future<int> checkHealth(ServerProfile profile, String? password) async {
    final response = await _transport.get(profile, password, '/global/health');
    return response.statusCode;
  }

  Future<BackendCapabilities?> checkCapabilities(
    ServerProfile profile,
    String? password,
  ) async => (await discoverBackends(profile, password))[profile.backend];

  Future<Map<AgentBackend, BackendCapabilities>> discoverBackends(
    ServerProfile profile,
    String? password,
  ) async {
    if (!profile.backend.isGateway) {
      return {AgentBackend.directOpenCode: BackendCapabilities.directOpenCode};
    }
    final response = await _transport.get(
      profile,
      password,
      '/prompt/capabilities',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    if (response.statusCode != 200) return {};
    return _parseBackends(response.body);
  }

  Map<AgentBackend, BackendCapabilities> _parseBackends(String payload) {
    try {
      final body = jsonDecode(payload);
      if (body is! Map<String, dynamic> || body['protocolVersion'] != 1) {
        return {};
      }
      final engines = body['engines'];
      if (engines is! Map<String, dynamic>) return {};
      final result = <AgentBackend, BackendCapabilities>{};
      for (final backend in AgentBackend.values.where(
        (value) => value.isGateway,
      )) {
        final engine = engines[backend.engine];
        if (engine is! Map<String, dynamic> || engine['available'] != true) {
          continue;
        }
        final features = engine['features'];
        if (features is! List) continue;
        final capabilities = BackendCapabilities(
          BackendFeature.values.where(
            (feature) => features.contains(feature.name),
          ),
          attachmentConstraints: _attachmentConstraints(
            engine['attachmentConstraints'],
          ),
        );
        if ([
          BackendFeature.sessions,
          BackendFeature.text,
          BackendFeature.abort,
        ].every(capabilities.supports)) {
          result[backend] = capabilities;
        }
      }
      return Map.unmodifiable(result);
    } on FormatException {
      return {};
    }
  }
}
