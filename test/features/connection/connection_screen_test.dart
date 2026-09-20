import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/data/connection_repository.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/connection/data/pairing_code_scanner.dart';
import 'package:prompt/features/connection/data/server_profile_store.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/connection/presentation/connection_screen.dart';
import 'package:prompt/features/connection/presentation/connection_view_model.dart';

void main() {
  testWidgets(
    'address alone connects without credentials or engine selection',
    (tester) async {
      final health = _RecordingHealthService();
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);
      ServerProfile? connected;
      await _pumpScreen(
        tester,
        viewModel,
        manual: false,
        onConnected: (profile) => connected = profile,
      );
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(ChoiceField<AgentBackend>), findsNothing);
      await tester.enterText(
        find.byType(TextFormField),
        'http://100.64.0.5:4096',
      );
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(health.detections, 1);
      expect(health.calls, 1);
      expect(health.password, isNull);
      expect(connected?.username, isNull);
      expect(connected?.origin.toString(), 'http://100.64.0.5:4096');
    },
  );

  testWidgets('returning to network identity clears entered credentials', (
    tester,
  ) async {
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);
    await _pumpScreen(tester, viewModel);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'http://100.64.0.5:4096',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'old-user');
    await tester.enterText(find.byType(TextFormField).at(2), 'old-password');
    await tester.ensureVisible(find.text('Use network identity'));
    await tester.tap(find.text('Use network identity'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(health.calls, 1);
    expect(health.profile?.username, isNull);
    expect(health.password, isNull);
  });

  testWidgets(
    'unavailable scanner opens manual setup without a dead QR action',
    (tester) async {
      final health = _RecordingHealthService();
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);
      await _pumpScreen(
        tester,
        viewModel,
        pairingCodeScanner: const UnavailablePairingCodeScanner(),
        scanAutomatically: true,
        manual: false,
      );
      expect(find.text('Scan pairing QR'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        find.text('Enter the address of your private server to connect.'),
        findsOneWidget,
      );
      expect(find.textContaining('phone'), findsNothing);
      expect(health.calls, 0);
      await tester.tap(find.text('How do I connect?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not set up your VPN or expose your server'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('connection opened from settings has an explicit back action', (
    tester,
  ) async {
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              label: 'Open connection',
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ConnectionScreen(
                      viewModel: viewModel,
                      profileLoader: () async => null,
                      onConnected: (_) {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open connection'), findsOneWidget);
    expect(find.text('Connect a machine'), findsNothing);
    expect(health.calls, 0);
  });

  testWidgets(
    'first connection needs only the address without engine or automatic camera',
    (tester) async {
      final health = _RecordingHealthService();
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);
      final scanner = _PairingCodeScanner(const PairingScanCancelled());
      await _pumpScreen(
        tester,
        viewModel,
        pairingCodeScanner: scanner,
        manual: false,
      );
      expect(find.text('Connect a machine'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(ChoiceField<AgentBackend>), findsNothing);
      expect(scanner.calls, 0);
      expect(health.calls, 0);
      await tester.tap(find.text('How do I connect?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No extra login is needed'), findsOneWidget);
      await tester.ensureVisible(find.text('Server requires credentials?'));
      await tester.tap(find.text('Server requires credentials?'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(health.calls, 0);
    },
  );

  testWidgets(
    'QR-first flow reviews the machine without exposing credentials',
    (tester) async {
      final health = _RecordingHealthService();
      final viewModel = _viewModel(health: health);
      addTearDown(viewModel.dispose);
      const ticket = 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789';
      final scanner = _PairingCodeScanner(
        PairingScanCompleted(
          Uri(
            scheme: 'prompt',
            host: 'connect',
            queryParameters: const {
              'v': '1',
              'origin': 'http://100.64.0.8:4097',
              'backend': 'claude',
              'username': 'prompt',
              'ticket': ticket,
            },
          ).toString(),
        ),
      );
      await _pumpScreen(
        tester,
        viewModel,
        pairingCodeScanner: scanner,
        manual: false,
      );
      await tester.ensureVisible(find.text('Scan pairing QR'));
      await tester.tap(find.text('Scan pairing QR'));
      await tester.pumpAndSettle();
      expect(find.text('Machine found'), findsOneWidget);
      expect(find.text('http://100.64.0.8:4097'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining(ticket), findsNothing);
      expect(health.calls, 0);
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(health.calls, 1);
      expect(health.pairingTicket, ticket);
    },
  );

  testWidgets('starting a scan prevents a late saved-profile connection', (
    tester,
  ) async {
    final saved = Completer<ServerProfile?>();
    final scanner = _PendingPairingCodeScanner();
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);
    await _pumpScreen(
      tester,
      viewModel,
      manual: false,
      profileLoader: () => saved.future,
      pairingCodeScanner: scanner,
    );
    await tester.ensureVisible(find.text('Scan pairing QR'));
    await tester.tap(find.text('Scan pairing QR'));
    await tester.pump();
    saved.complete(_profile());
    await tester.pump();
    expect(health.calls, 0);
    scanner.complete(const PairingScanCancelled());
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Server requires credentials?'), findsOneWidget);
    expect(health.calls, 0);
  });

  testWidgets('pairing scan fills the form without connecting automatically', (
    tester,
  ) async {
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);
    final scanner = _PairingCodeScanner(
      PairingScanCompleted(
        Uri(
          scheme: 'prompt',
          host: 'connect',
          queryParameters: const {
            'v': '1',
            'origin': 'http://100.64.0.8:4097',
            'backend': 'claude',
            'username': 'prompt',
            'ticket': 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
          },
        ).toString(),
      ),
    );
    await _pumpScreen(tester, viewModel, pairingCodeScanner: scanner);

    await tester.ensureVisible(find.text('Scan pairing QR'));
    await tester.tap(find.text('Scan pairing QR'));
    await tester.pumpAndSettle();

    expect(scanner.calls, 1);
    expect(health.calls, 0);
    expect(find.text('http://100.64.0.8:4097'), findsOneWidget);
    expect(find.text('prompt'), findsOneWidget);
    expect(find.byType(ChoiceField<AgentBackend>), findsNothing);
    expect(
      find.text(
        'Pairing code loaded. Review the private server, then connect.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(health.calls, 1);
    expect(health.profile?.backend, AgentBackend.gatewayClaude);
    expect(health.pairingTicket, 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789');
    expect(
      health.password,
      'p1.abcdefghijklmnopqrstuvwx.abcdefghijklmnopqrstuvwxyzABCDEFGH123456789',
    );
  });

  testWidgets('invalid pairing scan neither edits nor connects', (
    tester,
  ) async {
    final health = _RecordingHealthService();
    final viewModel = _viewModel(health: health);
    addTearDown(viewModel.dispose);
    await _pumpScreen(
      tester,
      viewModel,
      pairingCodeScanner: _PairingCodeScanner(
        const PairingScanCompleted('https://public.example/pair'),
      ),
    );

    await tester.ensureVisible(find.text('Scan pairing QR'));
    await tester.tap(find.text('Scan pairing QR'));
    await tester.pumpAndSettle();

    expect(health.calls, 0);
    expect(
      find.text(
        'This pairing code is invalid or does not use a private server.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byType(TextFormField).first,
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('pairing scanner prevents duplicate pending launches', (
    tester,
  ) async {
    final scanner = _PendingPairingCodeScanner();
    final viewModel = _viewModel();
    addTearDown(viewModel.dispose);
    await _pumpScreen(tester, viewModel, pairingCodeScanner: scanner);

    await tester.ensureVisible(find.text('Scan pairing QR'));
    await tester.tap(find.text('Scan pairing QR'));
    await tester.pump();
    await tester.tap(find.text('Scan pairing QR'), warnIfMissed: false);
    await tester.pump();
    expect(scanner.calls, 1);

    scanner.complete(const PairingScanCancelled());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('explicit pairing route can launch the scanner after opening', (
    tester,
  ) async {
    final scanner = _PairingCodeScanner(const PairingScanCancelled());
    final viewModel = _viewModel();
    addTearDown(viewModel.dispose);

    await _pumpScreen(
      tester,
      viewModel,
      pairingCodeScanner: scanner,
      scanAutomatically: true,
    );
    await tester.pumpAndSettle();

    expect(scanner.calls, 1);
  });

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
    testWidgets('machine connection fits $width pixels at 200% text scale', (
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
      await tester.ensureVisible(find.text('Server requires credentials?'));
      await tester.tap(find.text('Server requires credentials?'));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceField<AgentBackend>), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.ensureVisible(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Connect').hitTestable(), findsOneWidget);
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
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(
      find.text('Use a private IP address, not a public address or hostname.'),
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
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(health.calls, 1);
      expect(health.detections, 1);
      expect(find.byType(ChoiceField<AgentBackend>), findsNothing);
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
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
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
  PairingCodeScanner? pairingCodeScanner,
  bool scanAutomatically = false,
  bool manual = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ConnectionScreen(
        viewModel: viewModel,
        profileLoader: profileLoader ?? () async => null,
        onConnected: onConnected ?? (_) {},
        pairingCodeScanner: pairingCodeScanner,
        scanAutomatically: scanAutomatically,
      ),
    ),
  );
  await tester.pump();
  if (manual &&
      find.text('Server requires credentials?').evaluate().isNotEmpty) {
    await tester.ensureVisible(find.text('Server requires credentials?'));
    await tester.tap(find.text('Server requires credentials?'));
    await tester.pump();
  }
  if (manual && find.text('Enter details manually').evaluate().isNotEmpty) {
    await tester.ensureVisible(find.text('Enter details manually'));
    await tester.tap(find.text('Enter details manually'));
    await tester.pump();
    await tester.ensureVisible(find.text('Scan pairing QR'));
    await tester.pump();
  }
}

class _PairingCodeScanner implements PairingCodeScanner {
  @override
  bool get isAvailable => true;
  _PairingCodeScanner(this.result);

  final PairingScanResult result;
  int calls = 0;

  @override
  Future<PairingScanResult> scan() async {
    calls++;
    return result;
  }
}

class _PendingPairingCodeScanner implements PairingCodeScanner {
  @override
  bool get isAvailable => true;
  final _result = Completer<PairingScanResult>();
  int calls = 0;

  @override
  Future<PairingScanResult> scan() {
    calls++;
    return _result.future;
  }

  void complete(PairingScanResult result) => _result.complete(result);
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
  int detections = 0;
  ServerProfile? profile;
  String? password;
  String? pairingTicket;

  factory _RecordingHealthService.pending() => _RecordingHealthService._(true);

  @override
  Future<ServerProfile?> detectProfile(
    ServerProfile source,
    String? password,
  ) async {
    detections++;
    return source;
  }

  @override
  Future<String?> redeemPairing(ServerProfile profile, String ticket) async {
    pairingTicket = ticket;
    return 'p1.abcdefghijklmnopqrstuvwx.abcdefghijklmnopqrstuvwxyzABCDEFGH123456789';
  }

  @override
  Future<BackendCapabilities?> checkCapabilities(
    ServerProfile profile,
    String? password,
  ) async => profile.backend.isGateway
      ? BackendCapabilities([
          BackendFeature.sessions,
          BackendFeature.text,
          BackendFeature.abort,
        ])
      : BackendCapabilities.directOpenCode;

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
