import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../connection/connection.dart';
import '../domain/session_launch.dart';
import 'session_creation_dock.dart';
import 'session_creation_view_model.dart';

/// A full-page preparation surface; only the shared dock can start a session.
class SessionCreationScreen extends StatelessWidget {
  const SessionCreationScreen({
    required this.profile,
    required this.viewModel,
    required this.controller,
    required this.focusNode,
    required this.onLaunch,
    this.initialDirectory = '',
    super.key,
  });

  final ServerProfile profile;
  final SessionCreationViewModel viewModel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<SessionLaunch> onLaunch;
  final String initialDirectory;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New session')),
    body: SafeArea(
      top: false,
      child: ContentColumn(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SessionCreationDock(
            profile: profile,
            viewModel: viewModel,
            controller: controller,
            focusNode: focusNode,
            pageMode: true,
            initialDirectory: initialDirectory,
            onExpandedChanged: (_) {},
            onLaunch: onLaunch,
          ),
        ),
      ),
    ),
  );
}
