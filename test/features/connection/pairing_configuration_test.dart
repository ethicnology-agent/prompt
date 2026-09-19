import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/connection/domain/pairing_configuration.dart';

void main() {
  const ticket = 'abcdefghijklmnopqrstuvwxyzABCDEFGH123456789';

  test('accepts one strict private gateway pairing payload', () {
    final uri = Uri(
      scheme: 'prompt',
      host: 'connect',
      queryParameters: {
        'v': '1',
        'origin': 'http://100.64.0.8:4097',
        'backend': 'codex',
        'username': 'prompt',
        'ticket': ticket,
      },
    );

    final result = PairingConfiguration.parse(uri.toString());

    expect(result, isA<PairingCodeAccepted>());
    final configuration = (result as PairingCodeAccepted).configuration;
    expect(configuration.profile.origin, Uri.parse('http://100.64.0.8:4097'));
    expect(configuration.profile.backend, AgentBackend.gatewayCodex);
    expect(configuration.profile.username, 'prompt');
    expect(configuration.ticket, ticket);
  });

  test('supports every private gateway engine and IPv6 ULA', () {
    for (final backend in ['opencode', 'claude', 'codex']) {
      final uri = Uri(
        scheme: 'prompt',
        host: 'connect',
        queryParameters: {
          'v': '1',
          'origin': 'http://[fd00::8]:4097',
          'backend': backend,
          'username': 'prompt-user',
          'ticket': ticket,
        },
      );
      expect(
        PairingConfiguration.parse(uri.toString()),
        isA<PairingCodeAccepted>(),
        reason: backend,
      );
    }
  });

  test('fails closed for malformed or expanded payloads', () {
    for (final raw in [
      '',
      'https://connect?v=1',
      'prompt://other?v=1',
      'prompt://user@connect?v=1',
      'prompt://connect/path?v=1',
      'prompt://connect?v=2&origin=http%3A%2F%2F10.0.0.2%3A4097&backend=codex&username=prompt&ticket=$ticket',
      'prompt://connect?v=1&origin=http%3A%2F%2F198.51.100.2%3A4097&backend=codex&username=prompt&ticket=$ticket',
      'prompt://connect?v=1&origin=http%3A%2F%2F10.0.0.2%3A4097&backend=direct&username=prompt&ticket=$ticket',
      'prompt://connect?v=1&origin=http%3A%2F%2F10.0.0.2%3A4097&backend=codex&username=bad%3Auser&ticket=$ticket',
      'prompt://connect?v=1&origin=http%3A%2F%2F10.0.0.2%3A4097&backend=codex&username=prompt&ticket=short',
      'prompt://connect?v=1&origin=http%3A%2F%2F10.0.0.2%3A4097&backend=codex&username=prompt&ticket=$ticket&extra=value',
      'prompt://connect?v=1&v=1&origin=http%3A%2F%2F10.0.0.2%3A4097&backend=codex&username=prompt&ticket=$ticket',
    ]) {
      expect(
        PairingConfiguration.parse(raw),
        isA<PairingCodeRejected>(),
        reason: raw,
      );
    }
  });
}
