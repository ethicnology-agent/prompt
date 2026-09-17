import 'dart:async';
import 'dart:convert';

import '../../features/connection/connection.dart';
import 'opencode_transport.dart';

class OpenCodeEventEnvelope {
  const OpenCodeEventEnvelope({required this.directory, required this.payload});

  final String? directory;
  final Map<String, dynamic> payload;

  String? get type {
    final value = payload['type'];
    return value is String ? value : null;
  }
}

class OpenCodeEventService {
  OpenCodeEventService(this._transport);

  final OpenCodeTransport _transport;

  Stream<OpenCodeEventEnvelope> connect(
    ServerProfile profile,
    String? password,
  ) async* {
    final connection = await open(profile, password);
    try {
      yield* connection.events;
    } finally {
      await connection.close();
    }
  }

  /// Completes only after an authenticated successful HTTP response. The
  /// connection owns the raw subscription, independently of decoder progress.
  Future<OpenCodeEventConnection> open(
    ServerProfile profile,
    String? password,
  ) async {
    final response = await _transport.send(
      profile,
      password,
      '/global/event',
      headers: const {'accept': 'text/event-stream'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      throw OpenCodeTransportFailure(response.statusCode);
    }
    return OpenCodeEventConnection(response.stream);
  }

  static Stream<OpenCodeEventEnvelope> decode(Stream<List<int>> bytes) async* {
    final dataLines = <String>[];

    Future<OpenCodeEventEnvelope?> flush() async {
      if (dataLines.isEmpty) {
        return null;
      }
      final jsonText = dataLines.join('\n');
      dataLines.clear();
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map<String, dynamic>) {
          return null;
        }
        final directory = decoded['directory'];
        if (directory != null && directory is! String) {
          return null;
        }
        final payload = decoded['payload'];
        if (payload is! Map<String, dynamic>) {
          return null;
        }
        return OpenCodeEventEnvelope(
          directory: directory as String?,
          payload: payload,
        );
      } on FormatException {
        return null;
      }
    }

    await for (final line
        in utf8.decoder.bind(bytes).transform(const LineSplitter())) {
      if (line.isEmpty) {
        final event = await flush();
        if (event != null) {
          yield event;
        }
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    final event = await flush();
    if (event != null) {
      yield event;
    }
  }
}

class OpenCodeEventConnection {
  OpenCodeEventConnection(Stream<List<int>> bytes) {
    _subscription = bytes.listen(
      _bytes.add,
      onError: _bytes.addError,
      onDone: _bytes.close,
    );
  }

  final _bytes = StreamController<List<int>>();
  late final StreamSubscription<List<int>> _subscription;
  bool _closed = false;
  Stream<OpenCodeEventEnvelope> get events =>
      OpenCodeEventService.decode(_bytes.stream);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    // A caller may close a superseded connection before attaching a decoder.
    // Closing an unlistened controller must not block lifecycle teardown.
    unawaited(_bytes.close());
  }
}
