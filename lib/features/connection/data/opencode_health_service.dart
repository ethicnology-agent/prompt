import 'dart:convert';

import '../../../data/remote/opencode_transport.dart';
import '../domain/agent_backend.dart';
import '../domain/server_profile.dart';

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
  ) async {
    if (!profile.backend.isGateway) return BackendCapabilities.directOpenCode;
    final response = await _transport.get(
      profile,
      password,
      '/prompt/capabilities',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    if (response.statusCode != 200) return null;
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['protocolVersion'] != 1) {
        return null;
      }
      final engines = body['engines'];
      if (engines is! Map<String, dynamic>) return null;
      final engine = engines[profile.backend.engine];
      if (engine is! Map<String, dynamic> || engine['available'] != true) {
        return null;
      }
      final features = engine['features'];
      if (features is! List) return null;
      final capabilities = BackendCapabilities(
        List.unmodifiable(
          BackendFeature.values.where(
            (feature) => features.contains(feature.name),
          ),
        ),
      );
      if (![
        BackendFeature.sessions,
        BackendFeature.text,
        BackendFeature.abort,
      ].every(capabilities.supports)) {
        return null;
      }
      return capabilities;
    } on FormatException {
      return null;
    }
  }
}
