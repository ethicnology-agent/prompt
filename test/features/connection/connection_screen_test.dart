import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/data/connection_repository.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/connection/data/server_profile_store.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/connection/presentation/connection_screen.dart';
import 'package:prompt/features/connection/presentation/connection_view_model.dart';

void main() {
  testWidgets('saved profile load failure leaves manual connection available', (
    tester,
  ) async {
    final model = _viewModel();
    addTearDown(model.dispose);
    await _pumpScreen(
      tester,
      model,
      profileLoader: () async => throw Exception('synthetic profile failure'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not load the saved connection. Enter your server details to continue.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'duplicate submissions do not repeat a pending connection check',
    () async {
      final health = _RecordingHealthService.pending();
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);
      final first = viewModel.connect(_profile(), null);
      final second = viewModel.connect(_profile(), null);
      await Future<void>.delayed(Duration.zero);
      expect(health.calls, 1);
      health.complete();
      await Future.wait([first, second]);
    },
  );

  for (final field in [1, 2]) {
    testWidgets('credential edit blocks a late profile restore field=$field', (
      tester,
    ) async {
      final restore = Completer<ServerProfile?>();
      final health = _RecordingHealthService();
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);
      await _pumpScreen(tester, viewModel, profileLoader: () => restore.future);
      await tester.enterText(
        find.byType(TextFormField).at(field),
        'user-entered',
      );
      restore.complete(_profile(username: 'saved-user'));
      await tester.pumpAndSettle();
      expect(health.calls, 0);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(TextFormField).at(field),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'user-entered',
      );
    });
  }
  for (final restore in [false, true]) {
    test(
      'reset invalidates an unfinished ${restore ? 'restore' : 'connect'}',
      () async {
        final health = _RecordingHealthService.pending();
        final viewModel = _viewModel(health: health);
        addTearDown(viewModel.dispose);
        final pending = restore
            ? viewModel.restore(_profile())
            : viewModel.connect(_profile(), 'synthetic-password');
        await Future<void>.delayed(Duration.zero);
        viewModel.reset();
        health.complete();
        await pending;
        expect(viewModel.value, isA<ConnectionIdle>());
      },
    );

    test(
      'dispose invalidates an unfinished ${restore ? 'restore' : 'connect'}',
      () async {
        final health = _RecordingHealthService.pending();
        final viewModel = _viewModel(health: health);
        final pending = restore
            ? viewModel.restore(_profile())
            : viewModel.connect(_profile(), 'synthetic-password');
        await Future<void>.delayed(Duration.zero);
        viewModel.dispose();
        health.complete();
        await expectLater(pending, completes);
      },
    );
  }

  for (final width in [320.0, 393.0]) {
    testWidgets('agent picker fits $width pixels at 200% text scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = _viewModel();
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ConnectionScreen(
            viewModel: viewModel,
            profileLoader: () async => null,
            onConnected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final picker = find.byType(DropdownButtonFormField<AgentBackend>);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final choice = find.text(AgentBackend.gatewayClaude.label).last;
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<DropdownButtonFormField<AgentBackend>>(picker)
            .initialValue,
        AgentBackend.gatewayClaude,
      );
    });
  }

  testWidgets('restored profile populates the address and username', (
    tester,
  ) async {
    final profile = _profile(username: 'restored-user');
    final viewModel = _viewModel();
    addTearDown(viewModel.dispose);

    await _pumpScreen(tester, viewModel, profileLoader: () async => profile);
    await tester.pumpAndSettle();

    expect(find.text(profile.displayOrigin), findsOneWidget);
    expect(find.text('restored-user'), findsOneWidget);
  });

  testWidgets('a user-edited address is not overwritten by late restore', (
    tester,
  ) async {
    final restore = Completer<ServerProfile?>();
    final viewModel = _viewModel();
    addTearDown(viewModel.dispose);

    await _pumpScreen(tester, viewModel, profileLoader: () => restore.future);
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://10.0.0.9:4096',
    );
    restore.complete(_profile(username: 'late-user'));
    await tester.pumpAndSettle();

    expect(find.text('http://10.0.0.9:4096'), findsOneWidget);
    expect(find.text('late-user'), findsNothing);
  });

  testWidgets('reset prevents a pending profile loader from reconnecting', (
    tester,
  ) async {
    final restore = Completer<ServerProfile?>();
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);
    await _pumpScreen(tester, viewModel, profileLoader: () => restore.future);
    viewModel.reset();
    restore.complete(_profile());
    await tester.pumpAndSettle();
    expect(health.calls, 0);
    expect(viewModel.value, isA<ConnectionIdle>());
  });

  testWidgets('reset invalidates a ready post-frame navigation callback', (
    tester,
  ) async {
    final viewModel = _viewModel();
    addTearDown(viewModel.dispose);
    var connections = 0;
    await _pumpScreen(tester, viewModel, onConnected: (_) => connections++);
    viewModel.value = ConnectionReady(_profile());
    tester.binding.addPostFrameCallback((_) => viewModel.reset());
    await tester.pump();
    await tester.pump();
    expect(connections, 0);
    expect(viewModel.value, isA<ConnectionIdle>());
  });

  testWidgets('rejects a public HTTP address without calling connect', (
    tester,
  ) async {
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);

    await _pumpScreen(tester, viewModel);
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://198.51.100.1:4096',
    );
    await tester.ensureVisible(find.text('Test private connection'));
    await tester.tap(find.text('Test private connection'));
    await tester.pump();

    expect(
      find.text(
        'HTTP is only permitted for a private WireGuard or Tailscale address.',
      ),
      findsOneWidget,
    );
    expect(health.calls, 0);
  });

  testWidgets(
    'submits a valid private origin through the repository boundary',
    (tester) async {
      final health = _RecordingHealthService();
      ServerProfile? connected;
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);

      await _pumpScreen(
        tester,
        viewModel,
        onConnected: (profile) => connected = profile,
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'http://10.0.0.8:4096',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'alice');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'temporary-input',
      );
      await tester.ensureVisible(find.text('Test private connection'));
      await tester.tap(find.text('Test private connection'));
      await tester.pumpAndSettle();

      expect(health.calls, 1);
      expect(health.profile?.origin, Uri.parse('http://10.0.0.8:4096'));
      expect(health.profile?.username, 'alice');
      expect(health.password, isNotNull);
      expect(connected?.origin, Uri.parse('http://10.0.0.8:4096'));
      expect(connected?.username, 'alice');
    },
  );

  testWidgets('disables submission and shows progress while checking', (
    tester,
  ) async {
    final health = _RecordingHealthService.pending();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);

    await _pumpScreen(tester, viewModel);
    await tester.enterText(
      find.byType(TextFormField).first,
      'http://10.0.0.7:4096',
    );
    await tester.ensureVisible(find.text('Test private connection'));
    await tester.tap(find.text('Test private connection'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    health.complete();
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ConnectionViewModel viewModel, {
  Future<ServerProfile?> Function()? profileLoader,
  ValueChanged<ServerProfile>? onConnected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ConnectionScreen(
        viewModel: viewModel,
        profileLoader: profileLoader ?? () async => null,
        onConnected: onConnected ?? (_) {},
      ),
    ),
  );
  await tester.pump();
}

ConnectionViewModel _viewModel({_RecordingHealthService? health}) {
  return ConnectionViewModel(
    ConnectionRepository(
      health ?? _RecordingHealthService(),
      _CredentialsStore(),
      InMemoryServerProfileStore(),
    ),
  );
}

ServerProfile _profile({String? username}) => ServerProfile(
  origin: Uri.parse('http://10.0.0.5:4096'),
  username: username,
);

class _RecordingHealthService extends OpenCodeHealthService {
  _RecordingHealthService()
    : _pending = false,
      super(OpenCodeTransport(MockClient((_) async => http.Response('', 200))));

  _RecordingHealthService._(this._pending)
    : super(OpenCodeTransport(MockClient((_) async => http.Response('', 200))));

  final bool _pending;
  final _completion = Completer<void>();
  int calls = 0;
  ServerProfile? profile;
  String? password;

  factory _RecordingHealthService.pending() => _RecordingHealthService._(true);

  @override
  Future<int> checkHealth(ServerProfile profile, String? password) async {
    calls++;
    this.profile = profile;
    this.password = password;
    if (_pending) {
      await _completion.future;
    }
    return 200;
  }

  void complete() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}

class _CredentialsStore implements CredentialsStore {
  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => null;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
