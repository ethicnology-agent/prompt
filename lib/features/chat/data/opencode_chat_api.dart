import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import '../../../data/remote/opencode_tool_file_path_parser.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../../queue/queue.dart';
import '../domain/conversation_event.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import '../domain/session_execution_state.dart';

class OpenCodeChatApi {
  OpenCodeChatApi(this._transport);

  final OpenCodeTransport _transport;

  Future<OpenCodeMessagePage> listMessages(
    ServerProfile profile,
    String? password,
    OpenCodeSession session, {
    String? before,
  }) async {
    final query = Uri(
      queryParameters: {
        'directory': session.directory,
        'limit': '100',
        if (before != null && before.isNotEmpty) 'before': before,
      },
    ).query;
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/message?$query',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Messages response must be a list.');
    }
    final records = decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeMessageRecord.fromJson)
        .toList(growable: false);
    return OpenCodeMessagePage(
      records: records,
      nextCursor: _nextCursor(response.headers),
    );
  }

  String? _nextCursor(Map<String, String> headers) {
    final direct = headers.entries
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'x-next-cursor',
          orElse: () => const MapEntry('', ''),
        )
        .value
        .trim();
    if (direct.isNotEmpty) return direct;
    final link = headers.entries
        .firstWhere(
          (entry) => entry.key.toLowerCase() == 'link',
          orElse: () => const MapEntry('', ''),
        )
        .value;
    final match = RegExp(
      r'''<([^>]+)>\s*;\s*rel\s*=\s*["']next["']''',
      caseSensitive: false,
    ).firstMatch(link);
    final uri = match == null ? null : Uri.tryParse(match.group(1)!);
    final cursor = uri?.queryParameters['before']?.trim();
    return cursor == null || cursor.isEmpty ? null : cursor;
  }

  Future<List<OpenCodeTodoRecord>> listTodos(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/todo',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Todo response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeTodoRecord.fromJson)
        .toList(growable: false);
  }

  Future<List<OpenCodeFileDiffRecord>> listDiffs(
    ServerProfile profile,
    String? password,
    OpenCodeSession session, {
    String? messageId,
  }) async {
    final query = Uri(queryParameters: {'messageID': ?messageId}).query;
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/diff'
      '${query.isEmpty ? '' : '?$query'}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Diff response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeFileDiffRecord.fromJson)
        .toList(growable: false);
  }

  /// Sends [text] as a new user message to [session] without waiting for
  /// the assistant's reply. OpenCode server versions use different successful
  /// response codes, so every 2xx response is definitive acceptance.
  ///
  /// Never logs [text] or any part of the request/response.
  Future<void> sendPromptAsync(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String text, {
    String? operationId,
    List<QueuedAttachment> attachments = const <QueuedAttachment>[],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    final effort = executionOptions.reasoningEffort;
    if (effort != null &&
        (!profile.backend.isGateway ||
            profile.backend.engine == 'opencode' ||
            executionOptions.modelProviderId != profile.backend.engine ||
            executionOptions.modelId == null ||
            executionOptions.modelId == 'default' ||
            effort.isEmpty ||
            effort.length > 128 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(effort))) {
      throw const FormatException(
        'Reasoning effort requires an explicit native model.',
      );
    }
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/prompt_async?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        if (operationId != null &&
            profile.backend.isGateway &&
            profile.backend.engine != 'opencode')
          'messageID': operationId,
        'parts': [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          // OpenCode accepts file parts by URL; a `data:` URL carries the
          // bytes inline, which is how the official mobile client uploads.
          for (final attachment in attachments)
            {
              'type': 'file',
              'mime': attachment.mediaType,
              'filename': attachment.name,
              'url':
                  'data:${attachment.mediaType};base64,'
                  '${base64Encode(attachment.bytes)}',
            },
        ],
        if (executionOptions.hasModel)
          'model': {
            'providerID': executionOptions.modelProviderId,
            'modelID': executionOptions.modelId,
          },
        if (executionOptions.agentName != null)
          'agent': executionOptions.agentName,
        'reasoningEffort': ?effort,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
  }

  /// Executes a slash command selected from OpenCode's command capability.
  Future<void> executeCommand(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String command,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    if (executionOptions.reasoningEffort != null) {
      throw const FormatException(
        'Native reasoning effort is not an OpenCode command variant.',
      );
    }
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/command?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'command': command,
        'arguments': arguments,
        if (executionOptions.agentName != null)
          'agent': executionOptions.agentName,
        if (executionOptions.hasModel)
          'model': {
            'providerID': executionOptions.modelProviderId,
            'modelID': executionOptions.modelId,
          },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
  }

  /// Explicitly cancels any active generation or command execution for
  /// [session]. Returns whether the server actually aborted something.
  Future<bool> abortSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/abort?$query',
    );
    if (response.statusCode != 200) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! bool) {
      throw const FormatException('Abort response must be a boolean.');
    }
    return decoded;
  }

  /// Responds to a pending tool-call permission with [response], per `POST
  /// /session/{id}/permissions/{permissionID}`. Never logs [permissionId]
  /// or any detail about the permission.
  Future<bool> respondToPermission(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String permissionId,
    PermissionResponse response,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final httpResponse = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/permissions/'
      '${Uri.encodeComponent(permissionId)}?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'response': response.wireValue}),
    );
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
      throw OpenCodeHttpFailure(httpResponse.statusCode);
    }
    final decoded = jsonDecode(httpResponse.body);
    if (decoded is! bool) {
      throw const FormatException('Permission response must be a boolean.');
    }
    return decoded;
  }

  /// Answers a pending question request with [answers], one entry per
  /// question in the original request and in the same order, each a list
  /// of selected option labels and/or typed free-text answers. Per `POST
  /// /question/{requestID}/reply`. Never logs [requestId] or any answer.
  Future<bool> replyToQuestion(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String requestId,
    List<List<String>> answers,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final httpResponse = await _transport.post(
      profile,
      password,
      '/question/${Uri.encodeComponent(requestId)}/reply?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'answers': answers}),
    );
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
      throw OpenCodeHttpFailure(httpResponse.statusCode);
    }
    final decoded = jsonDecode(httpResponse.body);
    if (decoded is! bool) {
      throw const FormatException('Question reply response must be a boolean.');
    }
    return decoded;
  }

  /// Rejects a pending question request outright, per `POST /question/
  /// {requestID}/reject`. Never logs [requestId].
  Future<bool> rejectQuestion(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String requestId,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final httpResponse = await _transport.post(
      profile,
      password,
      '/question/${Uri.encodeComponent(requestId)}/reject?$query',
    );
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
      throw OpenCodeHttpFailure(httpResponse.statusCode);
    }
    final decoded = jsonDecode(httpResponse.body);
    if (decoded is! bool) {
      throw const FormatException(
        'Question reject response must be a boolean.',
      );
    }
    return decoded;
  }

  /// Fetches the execution state of every session known to the server for
  /// [directory], keyed by session id. A session with no ongoing or
  /// retrying work may simply be absent from the response.
  Future<Map<String, SessionExecutionState>> fetchSessionStatuses(
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
    final statuses = <String, SessionExecutionState>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Session status entry is malformed.');
      }
      statuses[entry.key] = _mapSessionExecutionState(value);
    }
    return statuses;
  }

  /// Re-fetches human interactions that may have been emitted while the app
  /// was asleep or disconnected. OpenCode keeps permissions and questions in
  /// separate global lists, both scoped by the project directory.
  Future<List<PendingApproval>> listPendingApprovals(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final responses = await Future.wait([
      _get(profile, password, '/permission?$query'),
      _get(profile, password, '/question?$query'),
    ]);
    final permissions = jsonDecode(responses[0].body);
    final questions = jsonDecode(responses[1].body);
    if (permissions is! List || questions is! List) {
      throw const FormatException(
        'Pending permission and question responses must be lists.',
      );
    }
    for (final permission in permissions) {
      if (permission is! Map<String, dynamic> ||
          permission['sessionID'] is! String) {
        throw const FormatException('Pending permission is malformed.');
      }
    }
    return [
      ...permissions
          .whereType<Map<String, dynamic>>()
          .map((json) => mapPendingPermission(json, sessionId: session.id))
          .whereType<PendingApproval>(),
      ...questions
          .whereType<Map<String, dynamic>>()
          .map((json) => mapPendingQuestion(json, sessionId: session.id))
          .whereType<PendingApproval>(),
    ];
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _transport.get(profile, password, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    return response;
  }
}

SessionExecutionState _mapSessionExecutionState(Object? value) {
  return switch (parseOpenCodeSessionStatus(value)) {
    OpenCodeSessionStatusBusy() => const SessionBusy(),
    OpenCodeSessionStatusIdle() => const SessionIdle(),
    OpenCodeSessionStatusRetry(:final attempt, :final message, :final next) =>
      SessionRetrying(
        attempt: attempt,
        message: message,
        nextAttemptAtMillis: next,
      ),
    OpenCodeSessionStatusUnknown() => const SessionExecutionUnknown(),
  };
}

class OpenCodeTodoRecord {
  const OpenCodeTodoRecord({
    this.id,
    required this.content,
    required this.status,
    required this.priority,
  });

  factory OpenCodeTodoRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final content = json['content'];
    final status = json['status'];
    final priority = json['priority'];
    // OpenCode's `Todo` schema requires only content/status/priority; `id`
    // is not part of it, so it must stay optional here.
    if (content is! String || status is! String || priority is! String) {
      throw const FormatException('Todo has invalid required fields.');
    }
    return OpenCodeTodoRecord(
      id: id is String ? id : null,
      content: content,
      status: status,
      priority: priority,
    );
  }

  final String? id;
  final String content;
  final String status;
  final String priority;
}

class OpenCodeFileDiffRecord {
  const OpenCodeFileDiffRecord({
    required this.file,
    required this.patch,
    required this.additions,
    required this.deletions,
    this.status,
  });

  /// Maps OpenCode's `SnapshotFileDiff`, whose only required fields are
  /// `additions` and `deletions`. The unified `patch` and the file path are
  /// optional, so a diff for a renamed or binary file still parses.
  factory OpenCodeFileDiffRecord.fromJson(Map<String, dynamic> json) {
    final file = json['file'];
    final patch = json['patch'];
    final status = json['status'];
    final additions = json['additions'];
    final deletions = json['deletions'];
    if (additions is! num || deletions is! num) {
      throw const FormatException('File diff has invalid required fields.');
    }
    return OpenCodeFileDiffRecord(
      file: file is String ? file : '',
      patch: patch is String ? patch : '',
      additions: additions.toInt(),
      deletions: deletions.toInt(),
      status: status is String ? status : null,
    );
  }

  final String file;
  final String patch;
  final int additions;
  final int deletions;
  final String? status;
}

class OpenCodeMessagePage {
  const OpenCodeMessagePage({required this.records, this.nextCursor});

  final List<OpenCodeMessageRecord> records;
  final String? nextCursor;

  bool get cursorUnavailable => records.length == 100 && nextCursor == null;
}

class OpenCodeMessageRecord {
  const OpenCodeMessageRecord({
    required this.id,
    required this.role,
    required this.createdAtMillis,
    required this.text,
    required this.details,
    this.error,
  });

  factory OpenCodeMessageRecord.fromJson(Map<String, dynamic> json) {
    final info = json['info'];
    final parts = json['parts'];
    if (info is! Map<String, dynamic> || parts is! List) {
      throw const FormatException('Message is missing its info or parts.');
    }
    final id = info['id'];
    final role = info['role'];
    final time = info['time'];
    if (id is! String || role is! String || time is! Map<String, dynamic>) {
      throw const FormatException('Message has invalid required fields.');
    }
    final createdAt = time['created'];
    if (createdAt is! num) {
      throw const FormatException('Message is missing its creation time.');
    }
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((part) => part['type'] == 'text')
        .map((part) => part['text'])
        .whereType<String>()
        .join();
    final details = <OpenCodeMessageDetailRecord>[];
    for (final rawPart in parts.whereType<Map<String, dynamic>>()) {
      final id = rawPart['id'];
      final type = rawPart['type'];
      if (id is! String || type is! String) {
        continue;
      }
      if (type == 'reasoning' && rawPart['text'] is String) {
        details.add(
          OpenCodeReasoningRecord(id: id, text: rawPart['text'] as String),
        );
      } else if (type == 'tool') {
        final tool = rawPart['tool'];
        final state = rawPart['state'];
        if (tool is String && state is Map<String, dynamic>) {
          details.add(
            OpenCodeToolRecord(
              id: id,
              tool: tool,
              status: state['status'] is String
                  ? state['status'] as String
                  : 'pending',
              input: _boundedJson(state['input'], 1600),
              filePath: parseOpenCodeToolFilePath(tool, state['input']),
              output: _boundedText(state['output'], 6000),
              error: _boundedText(state['error'], 2400),
              presentation: _parseToolPresentation(tool, state),
            ),
          );
        }
      }
    }
    return OpenCodeMessageRecord(
      id: id,
      role: role,
      createdAtMillis: createdAt.toInt(),
      text: text,
      details: details,
      error: _messageError(info['error']),
    );
  }

  final String id;
  final String role;
  final int createdAtMillis;
  final String text;
  final List<OpenCodeMessageDetailRecord> details;
  final String? error;
}

OpenCodeToolPresentationRecord? _parseToolPresentation(
  String tool,
  Map<String, dynamic> state,
) {
  if (tool == 'todowrite') {
    final input = state['input'];
    final inputItems = input is Map<String, dynamic>
        ? _parseTodoItems(input['todos'])
        : null;
    final outputItems = _parseTodoItems(_decodeJson(state['output']));
    final items = inputItems ?? outputItems;
    return items == null ? null : OpenCodeTodoPresentationRecord(items);
  }
  if (tool != 'task') return _parseGenericToolPresentation(tool, state);
  final input = state['input'] is Map<String, dynamic>
      ? state['input'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final output = _parseTaskOutput(state['output']);
  final description = _boundedString(input['description'], 600);
  final subagentType = _boundedString(input['subagent_type'], 160);
  final prompt = _boundedString(input['prompt'], 6000);
  final background = input['background'] == true || state['background'] == true;
  final summary = output.summary ?? _boundedString(state['summary'], 1200);
  final error = output.error ?? _boundedString(state['error'], 2400);
  final status =
      output.status ??
      (state['status'] is String ? state['status'] as String : 'pending');
  if (description == null &&
      subagentType == null &&
      prompt == null &&
      output.result == null &&
      error == null &&
      summary == null &&
      !background) {
    return null;
  }
  return OpenCodeTaskPresentationRecord(
    status: status,
    description: description,
    subagentType: subagentType,
    prompt: prompt,
    // A background task returns a successful tool call immediately, but its
    // nested task state is still `running`. Its task_result is boilerplate for
    // the model, not a result for the user.
    result: status == 'running' || _isAbsentOutput(output.result)
        ? null
        : output.result,
    error: error,
    background: background,
    summary: summary,
  );
}

OpenCodeGenericToolPresentationRecord _parseGenericToolPresentation(
  String tool,
  Map<String, dynamic> state,
) {
  final input = _asMap(state['input']);
  final metadata = _asMap(state['metadata']);
  var output = _stripToolWrappers(_boundedText(state['output'], 6000) ?? '');
  if (_isAbsentOutput(output)) output = '';
  if (tool == 'lsp' || tool == 'execute') {
    output = _humanizeStructuredOutput(output);
  }
  final error = _boundedText(state['error'], 2400);
  final title = _genericTitle(tool, input, metadata, state);
  final subtitle = _genericSubtitle(tool, input, metadata, state);
  final body = <OpenCodeToolBlockRecord>[];
  if (tool == 'execute' && input['code'] is String) {
    body.add(
      OpenCodeToolBlockRecord(
        kind: OpenCodeToolBlockKindRecord.code,
        text: _truncate(_redact(input['code'] as String), 6000),
        label: 'Code',
      ),
    );
  }
  if (!_knownToolIds.contains(tool) && input.isNotEmpty) {
    final flattenedInput = _truncate(_flattenValue(input), 2400).trim();
    if (flattenedInput.isNotEmpty) {
      body.add(
        OpenCodeToolBlockRecord(
          kind: OpenCodeToolBlockKindRecord.plain,
          text: flattenedInput,
          label: 'Input',
        ),
      );
    }
  }
  var bodyText = tool == 'read' ? _stripXmlContent(output) : output;
  if (tool == 'edit' && metadata['diff'] is String) {
    bodyText = metadata['diff'] as String;
  }
  if (tool == 'apply_patch' && metadata['files'] is List) {
    bodyText = (metadata['files'] as List)
        .whereType<Map>()
        .map((file) => file['patch'] is String ? file['patch'] as String : '')
        .where((patch) => patch.isNotEmpty)
        .join('\n');
  }
  if (tool == 'write' && input['content'] is String) {
    bodyText = input['content'] as String;
  }
  if (tool == 'question' && input['questions'] is List) {
    final answers = metadata['answers'] is List
        ? metadata['answers'] as List
        : const [];
    bodyText = (input['questions'] as List).indexed
        .map((entry) {
          final question = _asMap(entry.$2);
          final answer = entry.$1 < answers.length && answers[entry.$1] is List
              ? (answers[entry.$1] as List).whereType<String>().join(', ')
              : '';
          final options = question['options'] is List && answer.isEmpty
              ? (question['options'] as List)
                    .whereType<Map>()
                    .map(
                      (option) =>
                          '  • ${option['label'] ?? ''}: ${option['description'] ?? ''}'
                              .trimRight(),
                    )
                    .where((option) => option != '• :')
                    .join('\n')
              : '';
          return '? ${question['question'] ?? 'Question ${entry.$1 + 1}'}'
              '${answer.isEmpty ? '' : '\n  $answer'}'
              '${options.isEmpty ? '' : '\n$options'}';
        })
        .join('\n');
  }
  if (tool == 'invalid' && input['error'] is String) {
    bodyText = input['error'] as String;
  }
  if (bodyText.trim().isNotEmpty) {
    body.add(
      OpenCodeToolBlockRecord(
        kind: _blockKind(tool, bodyText),
        text: _truncate(_redact(bodyText), 6000),
        label: _blockLabel(tool),
      ),
    );
  }
  if (error != null && error.trim().isNotEmpty) {
    body.add(
      OpenCodeToolBlockRecord(
        kind: OpenCodeToolBlockKindRecord.plain,
        text: _truncate(_redact(error), 2400),
        label: 'Error',
      ),
    );
  }
  return OpenCodeGenericToolPresentationRecord(
    title: title,
    subtitle: subtitle,
    blocks: body,
  );
}

const _knownToolIds = {
  'invalid',
  'shell',
  'bash',
  'read',
  'glob',
  'grep',
  'edit',
  'write',
  'apply_patch',
  'question',
  'webfetch',
  'websearch',
  'skill',
  'lsp',
  'plan_exit',
  'execute',
};

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

String _genericTitle(
  String tool,
  Map<String, dynamic> input,
  Map<String, dynamic> metadata,
  Map<String, dynamic> state,
) {
  final value = switch (tool) {
    'shell' || 'bash' =>
      input['command'] is String
          ? '\$ ${_displayValue(input['command'])}'
          : 'Shell',
    'read' => 'Read ${_displayValue(input['filePath'])}'.trim(),
    'glob' => 'Glob ${_displayValue(input['pattern'])}'.trim(),
    'grep' => 'Grep ${_displayValue(input['pattern'])}'.trim(),
    'edit' => 'Edit ${_displayValue(input['filePath'])}'.trim(),
    'write' => 'Write ${_displayValue(input['filePath'])}'.trim(),
    'apply_patch' => 'Apply patch',
    'question' => 'Questions',
    'webfetch' => 'WebFetch ${_displayValue(input['url'])}'.trim(),
    'websearch' => 'Search ${_displayValue(input['query'])}'.trim(),
    'skill' => 'Skill ${_displayValue(input['name'])}'.trim(),
    'lsp' =>
      'LSP ${_displayValue(input['operation'], fallback: 'request')}'.trim(),
    'plan_exit' => 'Plan',
    'execute' => 'Execute',
    'invalid' => 'Invalid ${_displayValue(input['tool'])}'.trim(),
    _ =>
      (state['title'] is String && (state['title'] as String).trim().isNotEmpty)
          ? state['title'] as String
          : _titlecase(tool),
  };
  return _truncate(value, 300);
}

String? _genericSubtitle(
  String tool,
  Map<String, dynamic> input,
  Map<String, dynamic> metadata,
  Map<String, dynamic> state,
) {
  final parts = <String>[];
  if (input['workdir'] is String) {
    parts.add('in ${_displayValue(input['workdir'])}');
  }
  if (input['format'] is String) parts.add(_displayValue(input['format']));
  for (final key in [
    'exit',
    'exitCode',
    'truncated',
    'count',
    'matches',
    'provider',
  ]) {
    final value = metadata[key] ?? state[key];
    if (value != null) parts.add('$key: ${_displayValue(value)}');
  }
  return parts.isEmpty ? null : _truncate(parts.join(' · '), 300);
}

String _displayValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final displayed = _redact(value.toString()).trim();
  return displayed.isEmpty ? fallback : displayed;
}

String? _blockLabel(String tool) => switch (tool) {
  'shell' || 'bash' => 'Output',
  'read' => 'Content',
  'glob' || 'grep' || 'websearch' => 'Results',
  'edit' || 'apply_patch' => 'Diff',
  'write' => 'Content',
  'webfetch' || 'lsp' || 'plan_exit' => 'Result',
  'skill' => 'Skill',
  'execute' => 'Result',
  'invalid' => 'Error',
  _ => 'Result',
};

OpenCodeToolBlockKindRecord _blockKind(String tool, String text) {
  if (tool == 'edit' || tool == 'apply_patch') {
    return OpenCodeToolBlockKindRecord.diff;
  }
  if (tool == 'write' ||
      tool == 'execute' ||
      text.trimLeft().startsWith('```')) {
    return OpenCodeToolBlockKindRecord.code;
  }
  return tool == 'shell' || tool == 'bash' || tool == 'lsp'
      ? OpenCodeToolBlockKindRecord.plain
      : OpenCodeToolBlockKindRecord.markdown;
}

String _stripToolWrappers(String value) => value
    .replaceAll(
      RegExp(r'<shell_metadata[^>]*>.*?</shell_metadata>', dotAll: true),
      '',
    )
    .replaceAll(
      RegExp(r'<skill_content[^>]*>|</skill_content>', dotAll: true),
      '',
    )
    .replaceAll(RegExp(r'<task_result[^>]*>|</task_result>', dotAll: true), '')
    .trim();

bool _isAbsentOutput(String? value) {
  if (value == null) return true;
  return const {
    '',
    '(no output)',
    'no output',
    'no output.',
    '<no output>',
  }.contains(value.trim().toLowerCase());
}

String _stripXmlContent(String value) {
  final match = RegExp(
    r'<(?:content|entries)>(.*?)</(?:content|entries)>',
    dotAll: true,
  ).firstMatch(value);
  if (match != null) return match.group(1)!.trim();
  return value
      .replaceAll(RegExp(r'</?(?:path|type|content|entries)>'), '')
      .trim();
}

String _titlecase(String value) => value
    .split(RegExp('[-_]'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

List<OpenCodeTodoPresentationItemRecord>? _parseTodoItems(Object? value) {
  if (value is! List) return null;
  final items = <OpenCodeTodoPresentationItemRecord>[];
  for (final raw in value) {
    if (raw is! Map<String, dynamic> ||
        raw['content'] is! String ||
        raw['status'] is! String ||
        raw['priority'] is! String) {
      return null;
    }
    final status = raw['status'] as String;
    final priority = raw['priority'] as String;
    if (!const [
          'pending',
          'in_progress',
          'completed',
          'cancelled',
        ].contains(status) ||
        !const ['high', 'medium', 'low'].contains(priority)) {
      return null;
    }
    items.add(
      OpenCodeTodoPresentationItemRecord(
        content: _truncate(raw['content'] as String, 1200),
        status: status,
        priority: priority,
      ),
    );
  }
  return items;
}

Object? _decodeJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

({String? result, String? error, String? summary, String? status})
_parseTaskOutput(Object? value) {
  if (value is! String || value.isEmpty) {
    return (result: null, error: null, summary: null, status: null);
  }
  final taskMatch = RegExp(
    r'''<task\b[^>]*\bstate=["'](running|completed|error)["'][^>]*>''',
  ).firstMatch(value);
  final resultMatch = RegExp(
    r'<task_result>(.*?)</task_result>',
    dotAll: true,
  ).firstMatch(value);
  final errorMatch = RegExp(
    r'<task_error>(.*?)</task_error>',
    dotAll: true,
  ).firstMatch(value);
  final summaryMatch = RegExp(
    r'<summary>(.*?)</summary>',
    dotAll: true,
  ).firstMatch(value);
  return (
    result: _boundedString(resultMatch?.group(1)?.trim(), 6000),
    error: _boundedString(errorMatch?.group(1)?.trim(), 2400),
    summary: _boundedString(summaryMatch?.group(1)?.trim(), 1200),
    status: taskMatch?.group(1),
  );
}

String? _boundedString(Object? value, int maxLength) =>
    value is String && value.trim().isNotEmpty
    ? _truncate(value, maxLength)
    : null;

sealed class OpenCodeMessageDetailRecord {
  const OpenCodeMessageDetailRecord({required this.id});

  final String id;
}

class OpenCodeReasoningRecord extends OpenCodeMessageDetailRecord {
  const OpenCodeReasoningRecord({required super.id, required this.text});

  final String text;
}

class OpenCodeToolRecord extends OpenCodeMessageDetailRecord {
  const OpenCodeToolRecord({
    required super.id,
    required this.tool,
    required this.status,
    this.input,
    this.output,
    this.error,
    this.presentation,
    this.filePath,
  });

  final String tool;
  final String status;
  final String? input;
  final String? output;
  final String? error;
  final OpenCodeToolPresentationRecord? presentation;
  final String? filePath;
}

sealed class OpenCodeToolPresentationRecord {
  const OpenCodeToolPresentationRecord();
}

enum OpenCodeToolBlockKindRecord { markdown, plain, code, diff }

class OpenCodeToolBlockRecord {
  const OpenCodeToolBlockRecord({
    required this.kind,
    required this.text,
    this.label,
  });
  final OpenCodeToolBlockKindRecord kind;
  final String text;
  final String? label;
}

class OpenCodeGenericToolPresentationRecord
    extends OpenCodeToolPresentationRecord {
  const OpenCodeGenericToolPresentationRecord({
    required this.title,
    this.subtitle,
    this.blocks = const [],
  });
  final String title;
  final String? subtitle;
  final List<OpenCodeToolBlockRecord> blocks;
}

class OpenCodeTodoPresentationRecord extends OpenCodeToolPresentationRecord {
  const OpenCodeTodoPresentationRecord(this.items);

  final List<OpenCodeTodoPresentationItemRecord> items;
}

class OpenCodeTodoPresentationItemRecord {
  const OpenCodeTodoPresentationItemRecord({
    required this.content,
    required this.status,
    required this.priority,
  });

  final String content;
  final String status;
  final String priority;
}

class OpenCodeTaskPresentationRecord extends OpenCodeToolPresentationRecord {
  const OpenCodeTaskPresentationRecord({
    required this.status,
    this.description,
    this.subagentType,
    this.prompt,
    this.result,
    this.error,
    this.background = false,
    this.summary,
  });

  final String status;
  final String? description;
  final String? subagentType;
  final String? prompt;
  final String? result;
  final String? error;
  final bool background;
  final String? summary;
}

String? _boundedJson(Object? value, int maxLength) {
  if (value == null) {
    return null;
  }
  try {
    return _truncate(_flattenValue(value), maxLength);
  } on JsonUnsupportedObjectError {
    return null;
  }
}

String _flattenValue(Object? value, [String prefix = '']) {
  if (value is Map) {
    return value.entries
        .map((entry) {
          final key = entry.key.toString();
          if (RegExp(
            r'(password|token|secret|authorization|api.?key)',
            caseSensitive: false,
          ).hasMatch(key)) {
            return '${_titlecase(key)}: [redacted]';
          }
          return _flattenValue(entry.value, key);
        })
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
  if (value is List) {
    return value
        .map((item) => _flattenValue(item, prefix))
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
  if (value == null) return '';
  final key = prefix.isEmpty ? '' : '${_titlecase(prefix)}: ';
  return '$key${_redact(value.toString())}';
}

String _redact(String value) {
  return value
      .replaceAll(RegExp(r'data:[^\s]+', caseSensitive: false), '[redacted]')
      .replaceAllMapped(
        RegExp(
          r'(password|token|secret|authorization|api[-_ ]?key)\s*[:=]\s*[^\s,;]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}: [redacted]',
      )
      .replaceAllMapped(
        RegExp(
          r'(--?(?:password|token|secret|authorization|api[-_]?key))\s+\S+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)} [redacted]',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer [redacted]',
      );
}

String _humanizeStructuredOutput(String value) {
  if (value.trim().isEmpty) return value;
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map || decoded is List) return _flattenValue(decoded);
  } on FormatException {
    // Tool output is allowed to be ordinary text.
  }
  return value;
}

String? _boundedText(Object? value, int maxLength) {
  return value is String && value.isNotEmpty
      ? _truncate(value, maxLength)
      : null;
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}\n… output truncated';
}

String? _messageError(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is Map<String, dynamic>) {
    final data = value['data'];
    if (data is Map<String, dynamic> && data['message'] is String) {
      return data['message'] as String;
    }
    if (value['message'] is String) {
      return value['message'] as String;
    }
    if (value['name'] is String) {
      return value['name'] as String;
    }
  }
  return null;
}
