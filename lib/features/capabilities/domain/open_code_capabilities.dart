import 'open_code_agent.dart';
import 'open_code_model.dart';
import 'open_code_slash_command.dart';
import 'permission_mode_choice.dart';

class OpenCodeCapabilities {
  const OpenCodeCapabilities({
    required this.models,
    required this.agents,
    required this.commands,
    this.permissionModes = const [],
    this.defaultPermissionModeId,
  });

  final List<OpenCodeModel> models;
  final List<OpenCodeAgent> agents;
  final List<OpenCodeSlashCommand> commands;
  final List<PermissionModeChoice> permissionModes;
  final String? defaultPermissionModeId;

  bool get isEmpty =>
      models.isEmpty &&
      agents.isEmpty &&
      commands.isEmpty &&
      permissionModes.isEmpty;
}
