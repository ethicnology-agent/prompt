import 'dart:convert';

import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/session_worktree.dart';

class WorktreeServiceFailure implements Exception {
  const WorktreeServiceFailure(this.code);
  final String code;
}

class WorktreeService {
  WorktreeService(this._transport);
  final OpenCodeTransport _transport;

  Future<bool> supported(ServerProfile profile, String? password) async {
    if (!profile.backend.isGateway) return false;
    final response = await _transport.get(
      profile,
      password,
      '/prompt/capabilities',
    );
    if (response.statusCode != 200) {
      throw const WorktreeServiceFailure('unavailable');
    }
    final value = jsonDecode(response.body);
    return value is Map<String, dynamic> &&
        value['protocolVersion'] == 1 &&
        value['machine'] is Map<String, dynamic> &&
        value['machine']['worktrees'] == true;
  }

  Future<SessionWorktreeCatalog> list(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final response = await _transport.get(
      profile,
      password,
      '/prompt/worktrees?${Uri(queryParameters: {'directory': directory}).query}',
    );
    final value = _decode(response.statusCode, response.body);
    if (value is! Map<String, dynamic> ||
        value['worktrees'] is! List ||
        (value['worktrees'] as List).length > 1000 ||
        value['canCreate'] is! bool) {
      throw const FormatException();
    }
    return SessionWorktreeCatalog(
      worktrees: List.unmodifiable((value['worktrees'] as List).map(_record)),
      canCreate: value['canCreate'] as bool,
    );
  }

  Future<SessionWorktree> create(
    ServerProfile profile,
    String? password,
    String directory,
    String name,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/prompt/worktrees',
      body: jsonEncode({'directory': directory, 'name': name}),
      headers: {'content-type': 'application/json'},
    );
    return _record(_decode(response.statusCode, response.body));
  }

  Object? _decode(int status, String body) {
    final value = jsonDecode(body);
    if (status < 200 || status >= 300) {
      throw WorktreeServiceFailure(
        value is Map<String, dynamic> && value['error'] is String
            ? value['error'] as String
            : 'unavailable',
      );
    }
    return value;
  }

  SessionWorktree _record(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['directory'] is! String ||
        !(value['directory'] as String).startsWith('/') ||
        (value['directory'] as String).length > 4096 ||
        (value['branch'] != null && value['branch'] is! String) ||
        value['detached'] is! bool ||
        value['locked'] is! bool) {
      throw const FormatException();
    }
    return SessionWorktree(
      directory: value['directory'] as String,
      branch: value['branch'] as String?,
      detached: value['detached'] as bool,
      locked: value['locked'] as bool,
    );
  }
}
