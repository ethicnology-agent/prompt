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
    try {
      final body = jsonDecode(response.body);
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
