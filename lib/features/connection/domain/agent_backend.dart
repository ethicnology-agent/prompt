enum AgentBackend {
  directOpenCode('OpenCode · direct', null),
  gatewayOpenCode('OpenCode · private gateway', 'opencode'),
  gatewayClaude('Claude · private gateway', 'claude'),
  gatewayCodex('Codex · private gateway', 'codex');

  const AgentBackend(this.label, this.engine);
  final String label;
  final String? engine;
  bool get isGateway => engine != null;

  static AgentBackend? fromStorage(String value) {
    for (final backend in values) {
      if (backend.name == value) return backend;
    }
    return null;
  }
}

enum BackendFeature {
  sessions,
  text,
  abort,
  permissions,
  permissionAlways,
  questions,
  attachments,
  terminal,
  review,
  workspace,
  configuration,
  commands,
  sessionFork,
  sessionShare,
  sessionRevert,
  sessionDelete,
  sessionRename,
}

/// Runtime-verified features. Gateway advertisements are never persisted:
/// every reconnection verifies the engine again before queue dispatch.
class BackendCapabilities {
  BackendCapabilities(Iterable<BackendFeature> features)
    : _features = List.unmodifiable(features);
  static final directOpenCode = BackendCapabilities(BackendFeature.values);
  static final unavailable = BackendCapabilities([]);
  final List<BackendFeature> _features;
  bool supports(BackendFeature feature) => _features.contains(feature);
}
