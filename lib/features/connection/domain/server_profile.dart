import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'agent_backend.dart';

class ServerProfile {
  ServerProfile({
    required this.origin,
    this.username,
    this.backend = AgentBackend.directOpenCode,
    BackendCapabilities? capabilities,
  }) : capabilities =
           capabilities ??
           (backend.isGateway
               ? BackendCapabilities.unavailable
               : BackendCapabilities.directOpenCode),
       id = sha256
           .convert(
             utf8.encode(
               '$origin\u0000${username ?? ''}'
               '${backend.isGateway ? '\u0000${backend.name}' : ''}',
             ),
           )
           .toString();

  final String id;
  final Uri origin;
  final String? username;
  final AgentBackend backend;
  final BackendCapabilities capabilities;

  ServerProfile withCapabilities(BackendCapabilities value) => ServerProfile(
    origin: origin,
    username: username,
    backend: backend,
    capabilities: value,
  );

  String get displayOrigin => origin.toString();
}
