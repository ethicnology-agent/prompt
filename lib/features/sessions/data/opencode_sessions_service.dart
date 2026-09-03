import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import '../../connection/connection.dart';
import '../domain/open_code_session.dart';

class OpenCodeSessionsService {
  OpenCodeSessionsService(this._transport);

  final OpenCodeTransport _transport;

  Future<List<OpenCodeProjectRecord>> listProjects(
    ServerProfile profile,
    String? password,
  ) async {
    final response = await _get(profile, password, '/project');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Projects response must be a list.');
    }
    return decoded
        .map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Project entry must be an object.');
          }
          return OpenCodeProjectRecord.fromJson(entry);
        })
        .toList(growable: false);
  }

  Future<List<String>> suggestDirectories(
    ServerProfile profile,
    String? password,
    String input,
  ) async {
    final parsed = _directoryQuery(input);
    final response = await _get(
      profile,
      password,
      '/file?${Uri(queryParameters: {'directory': parsed.parent, 'path': '.'}).query}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Directory response must be a list.');
    }
    final matches = <String>{};
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Directory entry must be an object.');
      }
      final type = entry['type'];
      final absolute = entry['absolute'];
      if (type is! String ||
          absolute is! String ||
          (type != 'file' && type != 'directory')) {
        throw const FormatException('Directory entry has invalid fields.');
      }
      if (type == 'directory' &&
          _basename(absolute).toLowerCase().startsWith(parsed.prefix)) {
        matches.add(absolute);
      }
    }
    final result = matches.toList()..sort();
    return result.take(20).toList(growable: false);
  }

  Future<List<OpenCodeSessionRecord>> listSessions(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final path = directory.isEmpty
        ? '/session'
        : '/session?${Uri(queryParameters: {
            'directory': directory,
            // A project can retain sessions from a renamed or secondary
            // worktree. Ask OpenCode for its complete project catalog rather
            // than filtering it to the current worktree path.
            'scope': 'project',
          }).query}';
    final response = await _get(profile, password, path);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Sessions response must be a list.');
    }
    return decoded
        .map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Session entry must be an object.');
          }
          return OpenCodeSessionRecord.fromJson(entry);
        })
        .toList(growable: false);
  }

  Future<OpenCodeSessionRecord> createSession(
    ServerProfile profile,
    String? password,
    String directory, {
    String? title,
  }) async {
    final query = Uri(queryParameters: {'directory': directory}).query;
    final normalizedTitle = title?.trim();
    final response = await _transport.post(
      profile,
      password,
      '/session?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        if (normalizedTitle != null && normalizedTitle.isNotEmpty)
          'title': normalizedTitle,
      }),
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Created session response must be an object.',
      );
    }
    return OpenCodeSessionRecord.fromJson(decoded);
  }

  Future<Map<String, OpenCodeSessionStatus>> fetchSessionActivities(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final query = Uri(queryParameters: {'directory': directory}).query;
    final response = await _get(profile, password, '/session/status?$query');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Session status response must be a map.');
    }
    return {
      for (final entry in decoded.entries)
        entry.key: parseOpenCodeSessionStatus(entry.value),
    };
  }

  /// Whether [session] is generating right now, or null if it cannot be told.
  ///
  /// `/session/status` only covers the sessions its own server runs, so a
  /// session driven by another OpenCode process is missing from it. The
  /// message stream lives in storage that every process shares: an assistant
  /// message that has been created and not completed is a generation in
  /// flight. Only the newest message is fetched.
  Future<bool?> fetchIsGenerating(
    ServerProfile profile,
    String? password,
    String sessionId,
    String directory,
  ) async {
    final query = Uri(
      queryParameters: {'directory': directory, 'limit': '1'},
    ).query;
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(sessionId)}/message?$query',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;
    final last = decoded.last;
    if (last is! Map) return null;
    final info = last['info'];
    if (info is! Map) return null;
    if (info['role'] != 'assistant') return false;
    final time = info['time'];
    if (time is! Map) return null;
    return time['completed'] == null;
  }

  Future<void> renameSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String title,
  ) async {
    final response = await _transport.patch(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}?${Uri(queryParameters: {'directory': session.directory}).query}',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'title': title}),
    );
    _requireSuccess(response);
  }

  Future<void> deleteSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _transport.delete(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}?${Uri(queryParameters: {'directory': session.directory}).query}',
    );
    _requireSuccess(response);
  }

  Future<bool> abortSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/abort?${Uri(queryParameters: {'directory': session.directory}).query}',
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! bool) {
      throw const FormatException('Abort response must be a boolean.');
    }
    return decoded;
  }

  Future<OpenCodeSessionRecord> forkSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) => _postSession(profile, password, session, 'fork');

  Future<OpenCodeSessionRecord> shareSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) => _postSession(profile, password, session, 'share');

  Future<void> unshareSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _transport.delete(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/share?'
      '${Uri(queryParameters: {'directory': session.directory}).query}',
    );
    _requireSuccess(response);
  }

  Future<bool> revertMessage(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String messageId,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/revert?'
      '${Uri(queryParameters: {'directory': session.directory}).query}',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'messageID': messageId}),
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! bool) {
      throw const FormatException('Revert response must be a boolean.');
    }
    return decoded;
  }

  Future<OpenCodeSessionRecord> _postSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String action,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/$action?'
      '${Uri(queryParameters: {'directory': session.directory}).query}',
      headers: const {'content-type': 'application/json'},
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$action response must be a session.');
    }
    return OpenCodeSessionRecord.fromJson(decoded);
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _transport.get(profile, password, path);
    _requireSuccess(response);
    return response;
  }

  void _requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
  }

  static _DirectoryQuery _directoryQuery(String input) {
    final value = input.trim();
    final separator = value.lastIndexOf(RegExp(r'[/\\]'));
    if (separator < 0) {
      return const _DirectoryQuery('/', '');
    }
    final parentWithSeparator = value.substring(0, separator + 1);
    final prefix = value.substring(separator + 1).toLowerCase();
    if (parentWithSeparator == '/' ||
        RegExp(r'^[A-Za-z]:[/\\]$').hasMatch(parentWithSeparator)) {
      return _DirectoryQuery(parentWithSeparator, prefix);
    }
    return _DirectoryQuery(
      parentWithSeparator.substring(0, parentWithSeparator.length - 1),
      prefix,
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    return trimmed.substring(trimmed.lastIndexOf('/') + 1);
  }
}

class _DirectoryQuery {
  const _DirectoryQuery(this.parent, this.prefix);

  final String parent;
  final String prefix;
}

class OpenCodeProjectRecord {
  const OpenCodeProjectRecord({required this.id, required this.worktree});

  factory OpenCodeProjectRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final worktree = json['worktree'];
    if (id is! String || worktree is! String) {
      throw const FormatException('Project is missing an id or worktree.');
    }
    return OpenCodeProjectRecord(id: id, worktree: worktree);
  }

  final String id;
  final String worktree;
}

class OpenCodeSessionRecord {
  const OpenCodeSessionRecord({
    required this.id,
    required this.projectId,
    required this.directory,
    required this.title,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.parentId,
    this.changedFiles,
    this.additions,
    this.deletions,
    this.shareUrl,
    this.modelProviderId,
    this.modelId,
    this.agentName,
  });

  factory OpenCodeSessionRecord.fromJson(Map<String, dynamic> json) {
    final time = json['time'];
    if (time is! Map<String, dynamic>) {
      throw const FormatException('Session is missing its timestamps.');
    }
    final id = json['id'];
    final projectId = json['projectID'];
    final directory = json['directory'];
    final title = json['title'];
    final createdAt = time['created'];
    final updatedAt = time['updated'];
    if (id is! String ||
        projectId is! String ||
        directory is! String ||
        title is! String ||
        createdAt is! num ||
        updatedAt is! num) {
      throw const FormatException('Session has invalid required fields.');
    }

    final summaryMap = _optionalMap(json, 'summary');
    final shareMap = _optionalMap(json, 'share');
    final modelMap = _optionalMap(json, 'model');
    return OpenCodeSessionRecord(
      id: id,
      projectId: projectId,
      directory: directory,
      title: title,
      createdAtMillis: createdAt.toInt(),
      updatedAtMillis: updatedAt.toInt(),
      parentId: _optionalString(json, 'parentID'),
      changedFiles: _optionalInt(summaryMap, 'files'),
      additions: _optionalInt(summaryMap, 'additions'),
      deletions: _optionalInt(summaryMap, 'deletions'),
      shareUrl: _optionalString(shareMap, 'url'),
      modelProviderId: _optionalString(modelMap, 'providerID'),
      modelId: _optionalString(modelMap, 'id'),
      agentName: _optionalString(json, 'agent'),
    );
  }

  final String id;
  final String projectId;
  final String directory;
  final String title;
  final int createdAtMillis;
  final int updatedAtMillis;
  final String? parentId;
  final int? changedFiles;
  final int? additions;
  final int? deletions;
  final String? shareUrl;
  final String? modelProviderId;
  final String? modelId;
  final String? agentName;

  static String? _optionalString(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Session field $key must be a string.');
    }
    return value;
  }

  static Map<String, dynamic>? _optionalMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw FormatException('Session field $key must be an object.');
    }
    return value;
  }

  static int? _optionalInt(Map<String, dynamic>? json, String key) {
    final value = json?[key];
    if (value == null) return null;
    if (value is! num) {
      throw FormatException('Session field $key must be a number.');
    }
    return value.toInt();
  }
}
