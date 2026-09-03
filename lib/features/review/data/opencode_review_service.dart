import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../domain/review_entities.dart';
import 'review_cost_estimator.dart';
import 'review_result_parser.dart';

abstract interface class ReviewExecutionService {
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source,
  });
  Future<String> createChild(
    ReviewSnapshot snapshot,
    ReviewReviewerConfiguration config,
  );
  Future<ReviewPass> runPass(
    ReviewSnapshot snapshot,
    String childId,
    ReviewReviewerConfiguration config, {
    Duration timeout = const Duration(minutes: 30),
    bool Function()? isCancelled,
  });
  Future<void> abort(ReviewTarget target, String childId);
}

class OpenCodeReviewService implements ReviewExecutionService {
  OpenCodeReviewService(
    this.transport, {
    required this.credentialsStore,
    this.pollInterval = const Duration(milliseconds: 250),
  });
  final OpenCodeTransport transport;
  final CredentialsStore credentialsStore;
  final Duration pollInterval;

  /// Lines of unchanged context requested around each change.
  ///
  /// `GET /vcs/diff` returns close to whole-file content when this is omitted:
  /// measured against a live server, six changed files cost about 237,000
  /// patch characters unbounded and 56,613 at ten lines of context, against a
  /// snapshot budget of 200,000. Enough context to judge a change, not enough
  /// to spend the budget on code nobody touched.
  static const vcsContextLines = 6;

  @override
  Future<ReviewSnapshot> loadSnapshot(
    ReviewTarget target, {
    ReviewDiffSource source = ReviewDiffSource.session,
  }) => switch (source) {
    ReviewDiffSource.session => _loadSessionSnapshot(target),
    ReviewDiffSource.uncommitted => _loadVcsSnapshot(target, source, 'git'),
    ReviewDiffSource.branch => _loadVcsSnapshot(target, source, 'branch'),
  };

  Future<ReviewSnapshot> _loadVcsSnapshot(
    ReviewTarget target,
    ReviewDiffSource source,
    String mode,
  ) async {
    final query = Uri(
      queryParameters: {
        'directory': target.session.directory,
        'mode': mode,
        'context': '$vcsContextLines',
      },
    ).query;
    final response = await _get(target, '/vcs/diff?$query');
    return ReviewSnapshot(
      target: target,
      source: source,
      files: _parseDiff(response.body),
    );
  }

  Future<ReviewSnapshot> _loadSessionSnapshot(ReviewTarget target) async {
    final query = Uri(
      queryParameters: {'directory': target.session.directory},
    ).query;
    final messagesResponse = await _get(
      target,
      '/session/${Uri.encodeComponent(target.session.id)}/message?$query',
    );
    final messages = jsonDecode(messagesResponse.body);
    if (messages is! List) {
      throw const FormatException('Message response must be a list.');
    }

    for (final message in messages.reversed) {
      final messageId = _userMessageId(message);
      if (messageId == null) continue;
      final diffQuery = Uri(
        queryParameters: {
          'directory': target.session.directory,
          'messageID': messageId,
        },
      ).query;
      final response = await _get(
        target,
        '/session/${Uri.encodeComponent(target.session.id)}/diff?$diffQuery',
      );
      final files = _parseDiff(response.body);
      if (files.isNotEmpty) {
        return ReviewSnapshot(target: target, files: files);
      }
    }
    return ReviewSnapshot(target: target, files: const []);
  }

  String? _userMessageId(Object? raw) {
    if (raw is! Map) return null;
    final info = raw['info'];
    if (info is! Map || info['role'] != 'user') return null;
    final id = info['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  List<ReviewFile> _parseDiff(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Diff response must be a list.');
    }
    // The server marks only additions and deletions as required on a file
    // diff, so a binary or unreadable file can arrive without a patch. Drop
    // only the entries we cannot anchor, and keep the rest of the snapshot:
    // failing the whole review over one unusual file loses everything.
    return decoded
        .whereType<Map<Object?, Object?>>()
        .where(
          (raw) => raw['file'] is String && (raw['file'] as String).isNotEmpty,
        )
        .map(
          (raw) => ReviewFile(
            path: raw['file'] as String,
            status: raw['status'] is String
                ? raw['status'] as String
                : 'modified',
            patch: raw['patch'] is String ? raw['patch'] as String : '',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String> createChild(
    ReviewSnapshot snapshot,
    ReviewReviewerConfiguration config,
  ) async {
    final response = await transport.post(
      snapshot.target.profile,
      await credentialsStore.readPassword(snapshot.target.profile.id),
      '/session?directory=${Uri.encodeQueryComponent(snapshot.target.session.directory)}',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'parentID': snapshot.target.session.id,
        'title': 'Contingent review: ${config.role.name}',
        'model': {
          'providerID': config.model.providerId,
          'id': config.model.modelId,
        },
        'permission': [
          {'permission': '*', 'pattern': '*', 'action': 'deny'},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['id'] is! String) {
      throw const FormatException('Child session response is malformed.');
    }
    return body['id'] as String;
  }

  @override
  Future<ReviewPass> runPass(
    ReviewSnapshot snapshot,
    String childId,
    ReviewReviewerConfiguration config, {
    Duration timeout = const Duration(minutes: 30),
    bool Function()? isCancelled,
  }) async {
    final started = DateTime.now();
    final target = snapshot.target;
    final query = Uri(
      queryParameters: {'directory': target.session.directory},
    ).query;
    final request = jsonDecode(serializeReviewPrompt(snapshot, config));
    if (isCancelled?.call() ?? false) {
      throw const ReviewCancelledFailure();
    }
    final deadline = DateTime.now().add(timeout);
    final requestFuture = transport
        .post(
          target.profile,
          await credentialsStore.readPassword(target.profile.id),
          '/session/${Uri.encodeComponent(childId)}/message?$query',
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(request),
          timeout: timeout,
        )
        .then<Object?>(
          (response) => response,
          onError: (Object error, StackTrace stack) {
            return _ObservedRequestError(error, stack);
          },
        );

    while (true) {
      if (isCancelled?.call() ?? false) {
        throw const ReviewCancelledFailure();
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const ReviewTimeoutFailure('Reviewer timed out.');
      }
      final wait = pollInterval < remaining ? pollInterval : remaining;
      final completed = await Future.any<Object?>([
        requestFuture,
        Future<Object?>.delayed(wait, () => null),
      ]);
      if (completed is _ObservedRequestError) {
        if (completed.error is TimeoutException) {
          throw const ReviewTimeoutFailure('Reviewer timed out.');
        }
        Error.throwWithStackTrace(completed.error, completed.stack);
      }
      if (completed is http.Response) {
        if (completed.statusCode < 200 || completed.statusCode >= 300) {
          throw OpenCodeHttpFailure(completed.statusCode);
        }
        final info = _assistantInfo(jsonDecode(completed.body));
        final metrics = _metrics(info, started);
        if (info['error'] != null) {
          throw ReviewProviderFailure(
            _providerErrorMessage(info['error']),
            kind: _providerErrorKind(info['error']),
            metrics: metrics,
          );
        }
        late final ReviewOpinion opinion;
        try {
          final structured = info['structured'];
          if (structured == null) {
            throw const FormatException('Structured review result is missing.');
          }
          opinion = parseReviewResult(structured, config.role, snapshot.files);
        } on FormatException {
          throw ReviewProviderFailure(
            'The model returned invalid structured output. Choose another model.',
            kind: ReviewProviderFailureKind.structuredOutputInvalid,
            metrics: metrics,
          );
        }
        return ReviewPass(
          configuration: config,
          state: ReviewPassState.succeeded,
          childSessionId: childId,
          opinion: opinion,
          metrics: metrics,
        );
      }
    }
  }

  @override
  Future<void> abort(ReviewTarget target, String childId) async {
    final response = await transport.post(
      target.profile,
      await credentialsStore.readPassword(target.profile.id),
      '/session/${Uri.encodeComponent(childId)}/abort?directory=${Uri.encodeQueryComponent(target.session.directory)}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    if (jsonDecode(response.body) != true) {
      throw const FormatException('Abort response must be true.');
    }
  }

  Future<http.Response> _get(ReviewTarget target, String path) async {
    final response = await transport.get(
      target.profile,
      await credentialsStore.readPassword(target.profile.id),
      path,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    return response;
  }

  Map<String, dynamic> _assistantInfo(Object value) {
    if (value is! Map || value['info'] is! Map) {
      throw const FormatException('Message response must contain an info map.');
    }
    final info = (value['info'] as Map).cast<String, dynamic>();
    if (info['role'] != 'assistant') {
      throw const FormatException('Message info must describe an assistant.');
    }
    if (info['structured'] != null) return info;
    final parts = value['parts'];
    if (parts is List) {
      for (final part in parts) {
        if (part is Map &&
            (part['type'] == 'structured' ||
                part['type'] == 'structured_output') &&
            part['value'] != null) {
          return {...info, 'structured': part['value']};
        }
      }
    }
    return info;
  }

  ReviewPassMetrics _metrics(Map<String, dynamic> info, DateTime started) {
    final tokens = info['tokens'] is Map ? info['tokens'] as Map : const {};
    int number(String key) => (tokens[key] as num?)?.toInt() ?? 0;
    final cache = tokens['cache'];
    final cacheTokens = cache is Map
        ? (cache['read'] as num? ?? 0).toInt() +
              (cache['write'] as num? ?? 0).toInt()
        : (cache as num?)?.toInt() ?? 0;
    return ReviewPassMetrics(
      inputTokens: number('input'),
      outputTokens: number('output'),
      reasoningTokens: number('reasoning'),
      cacheTokens: cacheTokens,
      cost: (info['cost'] as num?)?.toDouble() ?? 0,
      duration: DateTime.now().difference(started),
    );
  }

  ReviewProviderFailureKind _providerErrorKind(Object? error) {
    if (error is! Map) return ReviewProviderFailureKind.unknown;
    final name = error['name'];
    final data = error['data'];
    final status = data is Map ? (data['statusCode'] as num?)?.toInt() : null;
    if (name == 'StructuredOutputError') {
      return ReviewProviderFailureKind.structuredOutputFailed;
    }
    if (status == 401 || status == 403) {
      return ReviewProviderFailureKind.accessDenied;
    }
    if (status == 429) return ReviewProviderFailureKind.rateLimited;
    if (status == 404 || status != null && status >= 500) {
      return ReviewProviderFailureKind.unavailable;
    }
    if (data is Map && data['isRetryable'] == true) {
      return ReviewProviderFailureKind.unavailable;
    }
    return ReviewProviderFailureKind.unknown;
  }

  String _providerErrorMessage(Object? error) {
    switch (_providerErrorKind(error)) {
      case ReviewProviderFailureKind.structuredOutputFailed:
        return 'The model did not produce the structured output required for review. Choose another model.';
      case ReviewProviderFailureKind.accessDenied:
        return 'Access to this model is denied. Check access, region, or opt-in.';
      case ReviewProviderFailureKind.rateLimited:
        return 'The model is rate limited. Try again later.';
      case ReviewProviderFailureKind.unavailable:
        return 'The model is temporarily unavailable. Try again later.';
      case ReviewProviderFailureKind.structuredOutputInvalid:
        return 'The model returned invalid structured output. Choose another model.';
      case ReviewProviderFailureKind.unknown:
        return 'The model provider returned an error. Try another model.';
    }
  }
}

final class _ObservedRequestError {
  const _ObservedRequestError(this.error, this.stack);

  final Object error;
  final StackTrace stack;
}
