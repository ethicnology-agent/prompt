import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/connection.dart';
import '../data/terminal_repository.dart';
import '../domain/remote_terminal.dart';

sealed class TerminalUiState {
  const TerminalUiState();
}

class TerminalIdle extends TerminalUiState {
  const TerminalIdle();
}

class TerminalLoading extends TerminalUiState {
  const TerminalLoading();
}

class TerminalUnavailable extends TerminalUiState {
  const TerminalUnavailable(this.failure);
  final RemoteTerminalFailure failure;
}

class TerminalReady extends TerminalUiState {
  const TerminalReady({
    required this.directory,
    required this.terminals,
    this.activeId,
    this.output = '',
    this.connecting = false,
    this.busy = false,
    this.failure,
  });
  final String directory;
  final List<RemoteTerminal> terminals;
  final String? activeId;
  final String output;
  final bool connecting;
  final bool busy;
  final RemoteTerminalFailure? failure;
}

class TerminalViewModel extends ValueNotifier<TerminalUiState> {
  TerminalViewModel(
    this._repository, {
    this.publishInterval = const Duration(milliseconds: 16),
    Timer Function(Duration, void Function())? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.new,
       super(const TerminalIdle());
  static const maxOutputBytes = 100 * 1024;
  final TerminalRepository _repository;
  final Duration publishInterval;
  final Timer Function(Duration, void Function()) _timerFactory;
  final _TerminalOutputBuffer _outputBuffer = _TerminalOutputBuffer(
    maxOutputBytes,
  );
  StreamSubscription<List<int>>? _subscription;
  Timer? _publishTimer;
  bool _publishPending = false;
  bool _disposed = false;
  int _epoch = 0;
  String? _profileId;
  String? _connectedId;
  Future<void> _socketWork = Future<void>.value();

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  Future<void> _serializeSocket(Future<void> Function() operation) {
    final next = _socketWork.then((_) => operation());
    _socketWork = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Starts a fresh route scope, without retaining another route's output.
  void reset(ServerProfile profile) {
    if (_disposed) return;
    _epoch++;
    _profileId = profile.id;
    _connectedId = null;
    _publishTimer?.cancel();
    _publishTimer = null;
    _publishPending = false;
    _outputBuffer.clear();
    value = const TerminalIdle();
    unawaited(_serializeSocket(_disconnect));
  }

  TerminalReady? _actionState(ServerProfile profile) {
    final state = value;
    return !_disposed &&
            _profileId == profile.id &&
            state is TerminalReady &&
            !state.busy &&
            !state.connecting
        ? state
        : null;
  }

  TerminalReady _update(
    TerminalReady state, {
    List<RemoteTerminal>? terminals,
    bool? busy,
    RemoteTerminalFailure? failure,
  }) => TerminalReady(
    directory: state.directory,
    terminals: terminals ?? state.terminals,
    activeId: state.activeId,
    output: state.output,
    connecting: state.connecting,
    busy: busy ?? state.busy,
    failure: failure,
  );

  Future<void> load(ServerProfile profile, String directory) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    _profileId = profile.id;
    _connectedId = null;
    _outputBuffer.clear();
    value = const TerminalLoading();
    await _serializeSocket(_disconnect);
    if (!_current(epoch)) return;
    final result = await _repository.list(profile, directory);
    if (!_current(epoch)) return;
    value = switch (result) {
      Ok<List<RemoteTerminal>, RemoteTerminalFailure>(:final value) =>
        TerminalReady(directory: directory, terminals: value),
      Err<List<RemoteTerminal>, RemoteTerminalFailure>(:final failure) =>
        TerminalUnavailable(failure),
    };
  }

  Future<void> create(ServerProfile profile) async {
    final state = _actionState(profile);
    if (state == null) return;
    final epoch = _epoch;
    value = _update(state, busy: true);
    final result = await _repository.create(profile, state.directory);
    if (!_current(epoch) || value is! TerminalReady) return;
    final current = value as TerminalReady;
    if (result case Ok<RemoteTerminal, RemoteTerminalFailure>(
      value: final terminal,
    )) {
      value = _update(
        current,
        terminals: [
          ...current.terminals.where((item) => item.id != terminal.id),
          terminal,
        ],
        busy: false,
      );
    } else if (result case Err<RemoteTerminal, RemoteTerminalFailure>(
      :final failure,
    )) {
      value = _update(current, busy: false, failure: failure);
    }
  }

  Future<void> connect(ServerProfile profile, String id) async {
    final state = _actionState(profile);
    if (state == null ||
        !state.terminals.any((item) => item.id == id && item.isRunning)) {
      return;
    }
    final epoch = ++_epoch;
    _connectedId = null;
    _outputBuffer.clear();
    value = TerminalReady(
      directory: state.directory,
      terminals: state.terminals,
      activeId: id,
      connecting: true,
    );
    await _serializeSocket(() async {
      await _disconnect();
      if (!_current(epoch)) return;
      final result = await _repository.connect(profile, state.directory, id);
      if (!_current(epoch)) {
        await _repository.disconnect();
        return;
      }
      if (result case Ok<Stream<List<int>>, RemoteTerminalFailure>(
        :final value,
      )) {
        _connectedId = id;
        this.value = TerminalReady(
          directory: state.directory,
          terminals: state.terminals,
          activeId: id,
        );
        _subscription = value.listen(
          (chunk) {
            if (_current(epoch)) _append(chunk);
          },
          onError: (_, _) {
            if (_current(epoch)) {
              _connectionEnded(RemoteTerminalFailure.connectionFailed);
            }
          },
          onDone: () {
            if (_current(epoch)) _connectionEnded();
          },
        );
      } else if (result case Err<Stream<List<int>>, RemoteTerminalFailure>(
        :final failure,
      )) {
        value = TerminalReady(
          directory: state.directory,
          terminals: state.terminals,
          failure: failure,
        );
      }
    });
  }

  Future<void> close(ServerProfile profile, String id) async {
    final state = _actionState(profile);
    if (state == null || !state.terminals.any((item) => item.id == id)) return;
    final epoch = _epoch;
    value = _update(state, busy: true);
    if (state.activeId == id) {
      _markDisconnected();
      await _serializeSocket(_disconnect);
    }
    if (!_current(epoch)) return;
    final result = await _repository.close(profile, state.directory, id);
    if (!_current(epoch) || value is! TerminalReady) return;
    final current = value as TerminalReady;
    if (result case Ok<void, RemoteTerminalFailure>()) {
      value = _update(
        current,
        terminals: current.terminals
            .where((terminal) => terminal.id != id)
            .toList(growable: false),
        busy: false,
      );
    } else if (result case Err<void, RemoteTerminalFailure>(:final failure)) {
      value = _update(current, busy: false, failure: failure);
    }
  }

  bool send(String input) {
    final state = value;
    if (_disposed ||
        input.isEmpty ||
        state is! TerminalReady ||
        state.connecting ||
        state.activeId == null ||
        state.activeId != _connectedId) {
      return false;
    }
    try {
      _repository.send(utf8.encode(input));
      return true;
    } on StateError {
      _connectionEnded(RemoteTerminalFailure.connectionFailed);
      return false;
    }
  }

  Future<void> deactivate() {
    if (_disposed) return Future<void>.value();
    _epoch++;
    _markDisconnected(null, true);
    return _serializeSocket(_disconnect);
  }

  void _markDisconnected([
    RemoteTerminalFailure? failure,
    bool clearBusy = false,
  ]) {
    _connectedId = null;
    _publishTimer?.cancel();
    _publishTimer = null;
    final state = value;
    if (!_disposed && state is TerminalReady) {
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        output: _publishPending ? _outputBuffer.decode() : state.output,
        busy: clearBusy ? false : state.busy,
        failure: failure,
      );
    }
    _publishPending = false;
  }

  void _connectionEnded([RemoteTerminalFailure? failure]) {
    _markDisconnected(failure);
    unawaited(_serializeSocket(_disconnect));
  }

  void _append(List<int> chunk) {
    if (_disposed || value is! TerminalReady) return;
    _outputBuffer.append(chunk);
    _publishPending = true;
    _publishTimer ??= _timerFactory(publishInterval, _flush);
  }

  void _flush([RemoteTerminalFailure? failure]) {
    _publishTimer?.cancel();
    _publishTimer = null;
    final state = value;
    if (!_disposed &&
        state is TerminalReady &&
        (_publishPending || failure != null)) {
      _publishPending = false;
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        activeId: state.activeId,
        connecting: state.connecting,
        busy: state.busy,
        output: _outputBuffer.decode(),
        failure: failure ?? state.failure,
      );
    }
  }

  Future<void> _disconnect() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _repository.disconnect();
  }

  @override
  void dispose() {
    _flush();
    _disposed = true;
    _epoch++;
    _connectedId = null;
    _publishTimer?.cancel();
    _publishTimer = null;
    _publishPending = false;
    unawaited(_serializeSocket(_disconnect));
    super.dispose();
  }
}

class _TerminalOutputBuffer {
  _TerminalOutputBuffer(this.maxBytes);

  final int maxBytes;
  final List<int> _bytes = <int>[];
  List<int> _pending = const <int>[];

  void clear() {
    _bytes.clear();
    _pending = const <int>[];
  }

  void append(List<int> chunk) {
    if (chunk.isEmpty) return;
    final input = <int>[..._pending, ...chunk];
    final incomplete = _incompleteSuffixLength(input);
    final completeLength = input.length - incomplete;
    if (completeLength > 0) _bytes.addAll(input.getRange(0, completeLength));
    _pending = incomplete == 0 ? const <int>[] : input.sublist(completeLength);
    if (_bytes.length > maxBytes) {
      _bytes.removeRange(0, _bytes.length - maxBytes);
    }
  }

  String decode() => utf8.decode(_bytes, allowMalformed: true);

  int _incompleteSuffixLength(List<int> input) {
    var continuationCount = 0;
    for (
      var index = input.length - 1;
      index >= 0 && continuationCount < 3 && _isContinuation(input[index]);
      index--
    ) {
      continuationCount++;
    }
    if (continuationCount == 0 || continuationCount == input.length) return 0;
    final lead = input[input.length - continuationCount - 1];
    final expected = lead <= 0x7f
        ? 1
        : lead >= 0xc2 && lead <= 0xdf
        ? 2
        : lead >= 0xe0 && lead <= 0xef
        ? 3
        : lead >= 0xf0 && lead <= 0xf4
        ? 4
        : 0;
    return expected > continuationCount + 1 ? continuationCount + 1 : 0;
  }

  bool _isContinuation(int byte) => byte & 0xc0 == 0x80;
}
