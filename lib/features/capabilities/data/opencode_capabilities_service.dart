import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';

class OpenCodeCapabilitiesService {
  OpenCodeCapabilitiesService(this._transport);

  final OpenCodeTransport _transport;

  Future<OpenCodeCapabilitiesRecord> fetch(
    ServerProfile profile,
    String? password,
  ) async {
    final responses = await Future.wait([
      _get(profile, password, '/provider'),
      _get(profile, password, '/agent'),
      _get(profile, password, '/command'),
    ]);
    return OpenCodeCapabilitiesRecord(
      providers: _parseProviders(
        jsonDecode(responses[0].body),
        native:
            profile.backend.isGateway && profile.backend.engine != 'opencode',
      ),
      agents: _parseAgents(jsonDecode(responses[1].body)),
      commands: _parseCommandsBestEffort(jsonDecode(responses[2].body)),
    );
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _transport.get(profile, password, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    return response;
  }
}

class OpenCodeCapabilitiesRecord {
  const OpenCodeCapabilitiesRecord({
    required this.providers,
    required this.agents,
    required this.commands,
  });

  final List<OpenCodeProviderRecord> providers;
  final List<OpenCodeAgentRecord> agents;
  final List<OpenCodeCommandRecord> commands;
}

class OpenCodeProviderRecord {
  const OpenCodeProviderRecord({
    required this.id,
    required this.isConnected,
    required this.models,
  });

  final String id;
  final bool isConnected;
  final List<OpenCodeModelRecord> models;
}

class OpenCodeModelRecord {
  const OpenCodeModelRecord({
    required this.id,
    required this.name,
    this.pricing,
    this.limits,
    this.releaseDate,
    this.status,
    this.capabilities = const [],
    this.executionOptions,
  });

  final String id;
  final String name;
  final OpenCodeModelPricingRecord? pricing;
  final OpenCodeModelLimitsRecord? limits;
  final String? releaseDate;
  final String? status;
  final List<String> capabilities;
  final ModelExecutionOptionsRecord? executionOptions;
}

class ModelExecutionOptionsRecord {
  const ModelExecutionOptionsRecord(
    this.reasoningEfforts,
    this.defaultReasoningEffortId,
  );
  final List<ReasoningEffortChoiceRecord> reasoningEfforts;
  final String? defaultReasoningEffortId;
}

class ReasoningEffortChoiceRecord {
  const ReasoningEffortChoiceRecord(this.id, this.label, this.description);
  final String id;
  final String label;
  final String? description;
}

ModelExecutionOptionsRecord? _parseExecutionOptions(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['version'] != 1 ||
      value['reasoningEfforts'] is! List) {
    return null;
  }
  final entries = value['reasoningEfforts'] as List;
  if (entries.isEmpty || entries.length > 32) return null;
  bool valid(Object? candidate, int maximum) =>
      candidate is String &&
      candidate.isNotEmpty &&
      candidate.length <= maximum &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(candidate);
  final choices = <String, ReasoningEffortChoiceRecord>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic> ||
        !valid(entry['id'], 128) ||
        !valid(entry['label'], 128)) {
      return null;
    }
    final description = entry['description'];
    if (description != null && !valid(description, 512)) return null;
    final id = entry['id'] as String;
    if (choices.containsKey(id)) return null;
    choices[id] = ReasoningEffortChoiceRecord(
      id,
      entry['label'] as String,
      description as String?,
    );
  }
  final defaultId = value['defaultReasoningEffortId'];
  return ModelExecutionOptionsRecord(
    List.unmodifiable(choices.values),
    defaultId is String && choices.containsKey(defaultId) ? defaultId : null,
  );
}

class OpenCodeModelPricingRecord {
  const OpenCodeModelPricingRecord({
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
  final List<OpenCodeModelPricingTierRecord> tiers;
  final bool experimentalOver200K;
}

class OpenCodeModelPricingTierRecord {
  const OpenCodeModelPricingTierRecord({
    required this.contextOver,
    this.input,
    this.output,
  });
  final int contextOver;
  final double? input;
  final double? output;
}

class OpenCodeModelLimitsRecord {
  const OpenCodeModelLimitsRecord({this.context, this.input, this.output});
  final int? context;
  final int? input;
  final int? output;
}

class OpenCodeAgentRecord {
  const OpenCodeAgentRecord({
    required this.name,
    required this.mode,
    required this.isBuiltIn,
    this.description,
  });

  final String name;
  final String? description;
  final String mode;
  final bool isBuiltIn;
}

class OpenCodeCommandRecord {
  const OpenCodeCommandRecord({
    required this.name,
    required this.isSubtask,
    this.description,
    this.agentName,
    this.model,
  });

  final String name;
  final String? description;
  final String? agentName;
  final String? model;
  final bool isSubtask;
}

List<OpenCodeProviderRecord> _parseProviders(
  Object? value, {
  required bool native,
}) {
  if (value is! Map<String, dynamic> ||
      value['all'] is! List ||
      value['connected'] is! List) {
    throw const FormatException('Provider response is malformed.');
  }
  final connected = value['connected'];
  if (connected is! List || connected.any((id) => id is! String)) {
    throw const FormatException('Provider response is malformed.');
  }
  final connectedIds = connected.cast<String>().toSet();
  final providers = value['all'] as List;
  return providers
      .map<OpenCodeProviderRecord>(
        (provider) => _parseProvider(provider, connectedIds, native: native),
      )
      .toList(growable: false);
}

OpenCodeProviderRecord _parseProvider(
  Object? value,
  Set<String> connectedIds, {
  required bool native,
}) {
  if (value is! Map<String, dynamic> ||
      value['id'] is! String ||
      value['models'] is! Map<String, dynamic>) {
    throw const FormatException('Provider is malformed.');
  }
  final id = value['id'] as String;
  final models = value['models'] as Map<String, dynamic>;
  return OpenCodeProviderRecord(
    id: id,
    isConnected: connectedIds.contains(id),
    models: models.entries
        .map((entry) => _parseModel(entry.key, entry.value, native: native))
        .toList(growable: false),
  );
}

OpenCodeModelRecord _parseModel(
  String id,
  Object? value, {
  required bool native,
}) {
  if (value is! Map<String, dynamic> || value['name'] is! String) {
    throw const FormatException('Model is malformed.');
  }
  return OpenCodeModelRecord(
    id: id,
    name: value['name'] as String,
    pricing: _parsePricing(value['cost']),
    limits: _parseLimits(value['limit']),
    releaseDate: value['releaseDate'] is String
        ? value['releaseDate'] as String
        : null,
    status: value['status'] is String ? value['status'] as String : null,
    capabilities: _parseStrings(value['capabilities']),
    executionOptions: native && id != 'default'
        ? _parseExecutionOptions(value['executionOptions'])
        : null,
  );
}

double? _price(Object? value) {
  final number = value is num ? value.toDouble() : null;
  return number != null && number.isFinite && number > 0 ? number : null;
}

OpenCodeModelPricingRecord? _parsePricing(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final tiers = <OpenCodeModelPricingTierRecord>[];
  if (value['tiers'] is List) {
    for (final item in value['tiers'] as List) {
      if (item is Map<String, dynamic> && item['contextOver'] is num) {
        tiers.add(
          OpenCodeModelPricingTierRecord(
            contextOver: (item['contextOver'] as num).toInt(),
            input: _price(item['input']),
            output: _price(item['output']),
          ),
        );
      }
    }
  }
  final cache = value['cache'];
  final cacheMap = cache is Map<String, dynamic>
      ? cache
      : const <String, dynamic>{};
  return OpenCodeModelPricingRecord(
    input: _price(value['input']),
    output: _price(value['output']),
    cacheRead: _price(cacheMap['read']),
    cacheWrite: _price(cacheMap['write']),
    tiers: List.unmodifiable(tiers),
    experimentalOver200K:
        value['experimentalOver200K'] is bool &&
        value['experimentalOver200K'] as bool,
  );
}

OpenCodeModelLimitsRecord? _parseLimits(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  int? positive(Object? candidate) =>
      candidate is num && candidate.isFinite && candidate > 0
      ? candidate.toInt()
      : null;
  return OpenCodeModelLimitsRecord(
    context: positive(value['context']),
    input: positive(value['input']),
    output: positive(value['output']),
  );
}

List<String> _parseStrings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

List<OpenCodeAgentRecord> _parseAgents(Object? value) {
  if (value is! List) {
    throw const FormatException('Agent response must be a list.');
  }
  return value.map<OpenCodeAgentRecord>(_parseAgent).toList(growable: false);
}

OpenCodeAgentRecord _parseAgent(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['name'] is! String ||
      value['mode'] is! String ||
      (value['builtIn'] != null && value['builtIn'] is! bool) ||
      (value['description'] != null && value['description'] is! String)) {
    throw const FormatException('Agent is malformed.');
  }
  return OpenCodeAgentRecord(
    name: value['name'] as String,
    description: value['description'] as String?,
    mode: value['mode'] as String,
    isBuiltIn: value['builtIn'] as bool? ?? false,
  );
}

List<OpenCodeCommandRecord> _parseCommandsBestEffort(Object? value) {
  if (value is! List) {
    return const [];
  }
  final commands = <OpenCodeCommandRecord>[];
  for (final candidate in value) {
    try {
      commands.add(_parseCommand(candidate));
    } on FormatException {
      // Slash commands are optional convenience data. A command introduced by
      // a newer server must not disable model and agent selection.
    }
  }
  return commands;
}

OpenCodeCommandRecord _parseCommand(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['name'] is! String ||
      value['template'] is! String ||
      (value['description'] != null && value['description'] is! String) ||
      (value['agent'] != null && value['agent'] is! String) ||
      (value['model'] != null && value['model'] is! String) ||
      (value['subtask'] != null && value['subtask'] is! bool)) {
    throw const FormatException('Command is malformed.');
  }
  return OpenCodeCommandRecord(
    name: value['name'] as String,
    description: value['description'] as String?,
    agentName: value['agent'] as String?,
    model: value['model'] as String?,
    isSubtask: value['subtask'] as bool? ?? false,
  );
}
