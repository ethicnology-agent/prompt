import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/capabilities_load_result.dart';
import '../domain/open_code_agent.dart';
import '../domain/open_code_capabilities.dart';
import '../domain/open_code_model.dart';
import '../domain/open_code_slash_command.dart';
import 'opencode_capabilities_service.dart';

class CapabilitiesRepository {
  CapabilitiesRepository(this._service, this._credentialsStore);

  final OpenCodeCapabilitiesService _service;
  final CredentialsStore _credentialsStore;

  Future<CapabilitiesLoadResult> load(ServerProfile profile) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      final record = await _service.fetch(profile, password);
      return CapabilitiesLoaded(
        OpenCodeCapabilities(
          models: [
            for (final provider in record.providers)
              for (final model in provider.models)
                OpenCodeModel(
                  providerId: provider.id,
                  id: model.id,
                  name: model.name,
                  isProviderConnected: provider.isConnected,
                  pricing: model.pricing == null
                      ? null
                      : OpenCodeModelPricing(
                          input: model.pricing!.input,
                          output: model.pricing!.output,
                          cacheRead: model.pricing!.cacheRead,
                          cacheWrite: model.pricing!.cacheWrite,
                          experimentalOver200K:
                              model.pricing!.experimentalOver200K,
                          tiers: model.pricing!.tiers
                              .map(
                                (tier) => OpenCodeModelPricingTier(
                                  contextOver: tier.contextOver,
                                  input: tier.input,
                                  output: tier.output,
                                ),
                              )
                              .toList(growable: false),
                        ),
                  limits: model.limits == null
                      ? null
                      : OpenCodeModelLimits(
                          context: model.limits!.context,
                          input: model.limits!.input,
                          output: model.limits!.output,
                        ),
                  releaseDate: model.releaseDate,
                  status: model.status,
                  capabilities: model.capabilities,
                  executionOptions: model.executionOptions == null
                      ? null
                      : ModelExecutionOptions(
                          reasoningEfforts: List.unmodifiable(
                            model.executionOptions!.reasoningEfforts.map(
                              (choice) => ReasoningEffortChoice(
                                id: choice.id,
                                label: choice.label,
                                description: choice.description,
                              ),
                            ),
                          ),
                          defaultReasoningEffortId:
                              model.executionOptions!.defaultReasoningEffortId,
                        ),
                ),
          ],
          agents: record.agents.map(_toAgent).toList(growable: false),
          commands: record.commands.map(_toCommand).toList(growable: false),
        ),
      );
    } on OpenCodeHttpFailure catch (failure) {
      return CapabilitiesLoadFailed(
        failure.statusCode == 401 || failure.statusCode == 403
            ? CapabilitiesFailure.unauthorized
            : CapabilitiesFailure.unexpectedResponse,
      );
    } on TimeoutException {
      return const CapabilitiesLoadFailed(CapabilitiesFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const CapabilitiesLoadFailed(
        CapabilitiesFailure.unexpectedResponse,
      );
    } on http.ClientException {
      return const CapabilitiesLoadFailed(CapabilitiesFailure.unavailable);
    } on FormatException {
      return const CapabilitiesLoadFailed(
        CapabilitiesFailure.unexpectedResponse,
      );
    }
  }

  OpenCodeAgent _toAgent(OpenCodeAgentRecord record) {
    final mode = switch (record.mode) {
      'primary' => OpenCodeAgentMode.primary,
      'subagent' => OpenCodeAgentMode.subagent,
      'all' => OpenCodeAgentMode.all,
      _ => throw const FormatException('Agent mode is unsupported.'),
    };
    return OpenCodeAgent(
      name: record.name,
      description: record.description,
      mode: mode,
      isBuiltIn: record.isBuiltIn,
    );
  }

  OpenCodeSlashCommand _toCommand(OpenCodeCommandRecord record) {
    return OpenCodeSlashCommand(
      name: record.name,
      description: record.description,
      agentName: record.agentName,
      model: _modelReference(record.model),
      isSubtask: record.isSubtask,
    );
  }

  OpenCodeModelReference? _modelReference(String? value) {
    if (value == null) {
      return null;
    }
    final separator = value.indexOf('/');
    if (separator <= 0 || separator == value.length - 1) {
      throw const FormatException('Command model is malformed.');
    }
    return OpenCodeModelReference(
      providerId: value.substring(0, separator),
      modelId: value.substring(separator + 1),
    );
  }
}
