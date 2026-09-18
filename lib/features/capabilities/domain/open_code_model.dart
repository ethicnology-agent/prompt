class OpenCodeModel {
  const OpenCodeModel({
    required this.providerId,
    required this.id,
    required this.name,
    required this.isProviderConnected,
    this.pricing,
    this.limits,
    this.releaseDate,
    this.status,
    this.capabilities = const [],
    this.executionOptions,
  });

  final String providerId;
  final String id;
  final String name;
  final bool isProviderConnected;
  final OpenCodeModelPricing? pricing;
  final OpenCodeModelLimits? limits;
  final String? releaseDate;
  final String? status;
  final List<String> capabilities;
  final ModelExecutionOptions? executionOptions;

  @override
  bool operator ==(Object other) =>
      other is OpenCodeModel &&
      providerId == other.providerId &&
      id == other.id &&
      name == other.name &&
      isProviderConnected == other.isProviderConnected &&
      pricing == other.pricing &&
      limits == other.limits &&
      releaseDate == other.releaseDate &&
      status == other.status &&
      executionOptions == other.executionOptions &&
      _listEquals(capabilities, other.capabilities);

  @override
  int get hashCode => Object.hash(
    providerId,
    id,
    name,
    isProviderConnected,
    pricing,
    limits,
    releaseDate,
    status,
    executionOptions,
    Object.hashAll(capabilities),
  );
}

/// Choices reported by the selected native engine, never a global enum.
class ModelExecutionOptions {
  const ModelExecutionOptions({
    required this.reasoningEfforts,
    this.defaultReasoningEffortId,
  });
  final List<ReasoningEffortChoice> reasoningEfforts;
  final String? defaultReasoningEffortId;
  bool supports(String id) => reasoningEfforts.any((choice) => choice.id == id);
  @override
  bool operator ==(Object other) =>
      other is ModelExecutionOptions &&
      defaultReasoningEffortId == other.defaultReasoningEffortId &&
      _listEquals(reasoningEfforts, other.reasoningEfforts);
  @override
  int get hashCode =>
      Object.hash(defaultReasoningEffortId, Object.hashAll(reasoningEfforts));
}

class ReasoningEffortChoice {
  const ReasoningEffortChoice({
    required this.id,
    required this.label,
    this.description,
  });
  final String id;
  final String label;
  final String? description;
  @override
  bool operator ==(Object other) =>
      other is ReasoningEffortChoice &&
      id == other.id &&
      label == other.label &&
      description == other.description;
  @override
  int get hashCode => Object.hash(id, label, description);
}

class OpenCodeModelPricing {
  const OpenCodeModelPricing({
    this.input,
    this.output,
    this.cacheRead,
    this.cacheWrite,
    this.tiers = const [],
    this.experimentalOver200K = false,
  });

  final double? input;
  final double? output;
  final double? cacheRead;
  final double? cacheWrite;
  final List<OpenCodeModelPricingTier> tiers;
  final bool experimentalOver200K;

  @override
  bool operator ==(Object other) =>
      other is OpenCodeModelPricing &&
      input == other.input &&
      output == other.output &&
      cacheRead == other.cacheRead &&
      cacheWrite == other.cacheWrite &&
      experimentalOver200K == other.experimentalOver200K &&
      _listEquals(tiers, other.tiers);

  @override
  int get hashCode => Object.hash(
    input,
    output,
    cacheRead,
    cacheWrite,
    experimentalOver200K,
    Object.hashAll(tiers),
  );
}

class OpenCodeModelPricingTier {
  const OpenCodeModelPricingTier({
    required this.contextOver,
    this.input,
    this.output,
  });
  final int contextOver;
  final double? input;
  final double? output;

  @override
  bool operator ==(Object other) =>
      other is OpenCodeModelPricingTier &&
      contextOver == other.contextOver &&
      input == other.input &&
      output == other.output;
  @override
  int get hashCode => Object.hash(contextOver, input, output);
}

class OpenCodeModelLimits {
  const OpenCodeModelLimits({this.context, this.input, this.output});
  final int? context;
  final int? input;
  final int? output;

  @override
  bool operator ==(Object other) =>
      other is OpenCodeModelLimits &&
      context == other.context &&
      input == other.input &&
      output == other.output;
  @override
  int get hashCode => Object.hash(context, input, output);
}

bool _listEquals<T>(List<T> a, List<T> b) =>
    a.length == b.length && a.indexed.every((entry) => entry.$2 == b[entry.$1]);
