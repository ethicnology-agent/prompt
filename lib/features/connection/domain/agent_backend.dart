enum AgentBackend {
  directOpenCode('OpenCode · direct', null),
  gatewayOpenCode('OpenCode · private gateway', 'opencode'),
  gatewayClaude('Claude · private gateway', 'claude'),
  gatewayCodex('Codex · private gateway', 'codex');

  const AgentBackend(this.label, this.engine);
  final String label;
  final String? engine;
  bool get isGateway => engine != null;

  /// Honest fallback shown while an engine has not advertised selectable
  /// permission policies. Native CLI gateways still require explicit approval
  /// for uncertain tool use; OpenCode keeps its own server-side default.
  String get defaultPermissionLabel => switch (this) {
    gatewayClaude || gatewayCodex => 'Auto',
    directOpenCode || gatewayOpenCode => 'Default',
  };

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
  imageAttachments,
  terminal,
  sessionArtifacts,
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
  BackendCapabilities(
    Iterable<BackendFeature> features, {
    this.attachmentConstraints,
  }) : _features = List.unmodifiable(features);
  static final directOpenCode = BackendCapabilities(
    BackendFeature.values.where(
      (feature) => feature != BackendFeature.imageAttachments,
    ),
  );
  static final unavailable = BackendCapabilities([]);
  final List<BackendFeature> _features;
  final AttachmentConstraints? attachmentConstraints;
  bool supports(BackendFeature feature) => _features.contains(feature);
}

/// Runtime-advertised upload bounds; no transport data or URLs are retained.
class AttachmentConstraints {
  AttachmentConstraints({
    required Iterable<String> mimeTypes,
    required this.maxCount,
    required this.maxBytesPerAttachment,
    required this.maxTotalBytes,
  }) : mimeTypes = List.unmodifiable(mimeTypes);
  final List<String> mimeTypes;
  final int maxCount;
  final int maxBytesPerAttachment;
  final int maxTotalBytes;
}
