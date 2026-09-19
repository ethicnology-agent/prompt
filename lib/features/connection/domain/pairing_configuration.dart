import 'agent_backend.dart';
import 'connection_origin_policy.dart';
import 'server_profile.dart';

sealed class PairingCodeResult {
  const PairingCodeResult();
}

final class PairingCodeAccepted extends PairingCodeResult {
  const PairingCodeAccepted(this.configuration);

  final PairingConfiguration configuration;
}

final class PairingCodeRejected extends PairingCodeResult {
  const PairingCodeRejected();
}

class PairingConfiguration {
  const PairingConfiguration({required this.profile, required this.ticket});

  final ServerProfile profile;
  final String ticket;

  static PairingCodeResult parse(String raw) {
    if (raw.length > 2048 || raw.contains('\u0000')) {
      return const PairingCodeRejected();
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'prompt' ||
        uri.host != 'connect' ||
        uri.path.isNotEmpty ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return const PairingCodeRejected();
    }

    const requiredKeys = {'v', 'origin', 'backend', 'username', 'ticket'};
    final values = uri.queryParametersAll;
    if (values.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(values.keys.toSet()).isNotEmpty ||
        values.values.any((items) => items.length != 1)) {
      return const PairingCodeRejected();
    }
    if (values['v']!.single != '1') return const PairingCodeRejected();

    final backend = switch (values['backend']!.single) {
      'opencode' => AgentBackend.gatewayOpenCode,
      'claude' => AgentBackend.gatewayClaude,
      'codex' => AgentBackend.gatewayCodex,
      _ => null,
    };
    final origin = Uri.tryParse(values['origin']!.single);
    final username = values['username']!.single;
    final ticket = values['ticket']!.single;
    if (backend == null ||
        origin == null ||
        !ConnectionOriginPolicy.supports(origin) ||
        !_validUsername(username) ||
        !_validTicket(ticket)) {
      return const PairingCodeRejected();
    }

    return PairingCodeAccepted(
      PairingConfiguration(
        profile: ServerProfile(
          origin: origin,
          username: username,
          backend: backend,
        ),
        ticket: ticket,
      ),
    );
  }

  static bool _validUsername(String value) =>
      value.isNotEmpty &&
      value.length <= 64 &&
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

  static bool _validTicket(String value) =>
      value.length == 43 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
}
