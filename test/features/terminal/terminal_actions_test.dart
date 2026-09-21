import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/terminal/data/terminal_repository.dart';
import 'package:prompt/features/terminal/domain/remote_terminal.dart';
import 'package:prompt/features/terminal/presentation/terminal_view_model.dart';
import 'package:prompt/features/terminal/presentation/terminal_screen.dart';

final _profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
const _a = RemoteTerminal(
  id: 'a',
  title: 'A',
  command: 'sh',
  args: [],
  cwd: '/work',
  isRunning: true,
  pid: 1,
);
const _b = RemoteTerminal(
  id: 'b',
  title: 'B',
  command: 'sh',
  args: [],
  cwd: '/work',
  isRunning: true,
  pid: 2,
);

void main() {
  testWidgets(
    'Send rejects a disconnected stale callback without losing draft',
    (tester) async {
      final repository = _Repository();
      final vm = TerminalViewModel(repository);
      await tester.pumpWidget(
        MaterialApp(
          home: TerminalScreen(profile: _profile, viewModel: vm),
        ),
      );
      await tester.runAsync(() async {
        await vm.load(_profile, '/work');
        await vm.connect(_profile, 'a');
      });
      await tester.pump();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Terminal input',
      );
      await tester.enterText(input, 'pending command');
      final submit = tester.widget<TextField>(input).onSubmitted!;
      await tester.runAsync(vm.deactivate);
      submit('pending command');
      await tester.pump();
      expect(repository.sent, isEmpty);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'pending command',
      );
      expect(tester.widget<TextField>(input).enabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    },
  );

  testWidgets('opening another profile clears prior terminal rows and output', (
    tester,
  ) async {
    final repository = _Repository();
    final vm = TerminalViewModel(repository);
    await tester.runAsync(() async {
      await vm.load(_profile, '/work');
      await vm.connect(_profile, 'a');
    });
    final other = ServerProfile(origin: Uri.parse('http://10.80.0.2:4096'));
    await tester.pumpWidget(
      MaterialApp(
        home: TerminalScreen(profile: other, viewModel: vm),
      ),
    );
    await tester.pump();
    expect(find.text('A'), findsNothing);
    expect(
      find.text('Choose a server directory to list its terminals.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
  });

  testWidgets(
    'terminal controls remain reachable with keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vm = TerminalViewModel(_Repository());
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 300),
            ),
            child: child!,
          ),
          home: TerminalScreen(profile: _profile, viewModel: vm),
        ),
      );
      await tester.runAsync(() => vm.load(_profile, '/work'));
      await tester.runAsync(() => vm.connect(_profile, 'a'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Terminal input',
        ),
      );
      await tester.pump();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Terminal input',
      );
      expect(input.hitTestable(), findsOneWidget);
      await tester.tap(input);
      await tester.enterText(input, 'keyboard fixture');
      expect(
        tester.widget<TextField>(input).controller!.text,
        'keyboard fixture',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    },
  );

  for (final event in ['deactivate', 'done', 'error']) {
    test('$event disables sending to an inactive terminal', () async {
      final repository = _Repository();
      final vm = TerminalViewModel(repository);
      addTearDown(vm.dispose);
      await vm.load(_profile, '/work');
      await vm.connect(_profile, 'a');
      if (event == 'deactivate') {
        await vm.deactivate();
      } else if (event == 'done') {
        await repository.stream.close();
      } else {
        repository.stream.addError(StateError('fixture disconnected'));
      }
      await Future<void>.delayed(Duration.zero);
      expect((vm.value as TerminalReady).activeId, isNull);
      vm.send('must remain local');
      expect(repository.sent, isEmpty);
    });
  }

  for (final action in ['create', 'close other']) {
    test('$action preserves the active terminal and output', () async {
      final repository = _Repository();
      final vm = TerminalViewModel(repository, publishInterval: Duration.zero);
      addTearDown(vm.dispose);
      await vm.load(_profile, '/work');
      await vm.connect(_profile, 'a');
      repository.stream.add([65]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      if (action == 'create') {
        await vm.create(_profile);
      } else {
        await vm.close(_profile, 'b');
      }
      final ready = vm.value as TerminalReady;
      expect(ready.activeId, 'a');
      expect(ready.output, 'A');
    });
  }

  test('late connect cannot reactivate after leaving the route', () async {
    final repository = _Repository()..connectGate = Completer();
    final vm = TerminalViewModel(repository);
    addTearDown(vm.dispose);
    await vm.load(_profile, '/work');
    final connecting = vm.connect(_profile, 'a');
    await Future<void>.delayed(Duration.zero);
    final deactivating = vm.deactivate();
    repository.connectGate!.complete(Ok(repository.stream.stream));
    await connecting;
    await deactivating;
    expect((vm.value as TerminalReady).activeId, isNull);
    expect(repository.connected, isFalse);
  });

  test('late load completion is ignored after disposal', () async {
    final repository = _Repository()..listGate = Completer();
    final vm = TerminalViewModel(repository);
    final loading = vm.load(_profile, '/work');
    await Future<void>.delayed(Duration.zero);
    vm.dispose();
    repository.listGate!.complete(const Ok([_a, _b]));
    await loading;
  });

  test('late creation cannot replace a newly loaded profile', () async {
    final repository = _Repository()..createGate = Completer();
    final vm = TerminalViewModel(repository);
    addTearDown(vm.dispose);
    await vm.load(_profile, '/work');
    final creating = vm.create(_profile);
    final other = ServerProfile(origin: Uri.parse('http://10.80.0.2:4096'));
    await vm.load(other, '/other');
    repository.createGate!.complete(const Ok(_b));
    await creating;
    expect((vm.value as TerminalReady).directory, '/other');
    expect((vm.value as TerminalReady).terminals, [_a, _b]);
  });

  test('sending to a synchronously closed sink is rejected safely', () async {
    final repository = _Repository()..rejectSend = true;
    final vm = TerminalViewModel(repository);
    addTearDown(vm.dispose);
    await vm.load(_profile, '/work');
    await vm.connect(_profile, 'a');
    expect(vm.send('local draft'), isFalse);
    expect((vm.value as TerminalReady).activeId, isNull);
    expect(repository.sent, isEmpty);
  });

  test('terminal actions reject another profile before a fresh load', () async {
    final repository = _Repository();
    final vm = TerminalViewModel(repository);
    addTearDown(vm.dispose);
    await vm.load(_profile, '/work');
    final other = ServerProfile(origin: Uri.parse('http://10.80.0.2:4096'));
    await vm.create(other);
    await vm.close(other, 'a');
    await vm.connect(other, 'a');
    expect(repository.actions, isEmpty);
  });

  test('repeated create while pending creates only one terminal', () async {
    final repository = _Repository()..createGate = Completer();
    final vm = TerminalViewModel(repository);
    addTearDown(vm.dispose);
    await vm.load(_profile, '/work');
    final first = vm.create(_profile);
    final second = vm.create(_profile);
    repository.createGate!.complete(const Ok(_b));
    await Future.wait([first, second]);
    expect(repository.actions, ['create']);
  });
}

class _Repository implements TerminalRepository {
  final stream = StreamController<List<int>>();
  final sent = <List<int>>[];
  final actions = <String>[];
  bool connected = false;
  bool rejectSend = false;
  Completer<Result<List<RemoteTerminal>, RemoteTerminalFailure>>? listGate;
  Completer<Result<Stream<List<int>>, RemoteTerminalFailure>>? connectGate;
  Completer<Result<RemoteTerminal, RemoteTerminalFailure>>? createGate;

  @override
  Future<Result<List<RemoteTerminal>, RemoteTerminalFailure>> list(
    ServerProfile profile,
    String directory,
  ) async => listGate == null ? const Ok([_a, _b]) : await listGate!.future;

  @override
  Future<Result<Stream<List<int>>, RemoteTerminalFailure>> connect(
    ServerProfile profile,
    String directory,
    String id,
  ) async {
    actions.add('connect');
    final Result<Stream<List<int>>, RemoteTerminalFailure> result =
        connectGate == null ? Ok(stream.stream) : await connectGate!.future;
    connected = true;
    return result;
  }

  @override
  Future<Result<RemoteTerminal, RemoteTerminalFailure>> create(
    ServerProfile profile,
    String directory,
  ) async {
    actions.add('create');
    return createGate == null ? const Ok(_b) : await createGate!.future;
  }

  @override
  Future<Result<void, RemoteTerminalFailure>> close(
    ServerProfile profile,
    String directory,
    String id,
  ) async {
    actions.add('close');
    return const Ok(null);
  }

  @override
  Future<void> disconnect() async => connected = false;
  @override
  void send(List<int> bytes) {
    if (rejectSend) throw StateError('fixture sink closed');
    sent.add(bytes);
  }
}
