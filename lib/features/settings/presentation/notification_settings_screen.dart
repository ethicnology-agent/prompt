import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../../core/platform/local_notification_service.dart';
import '../../../core/platform/local_notification_types.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({required this.service, super.key});

  final LocalNotificationService service;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  var _requesting = false;
  LocalNotificationPermission? _permission;

  Future<void> _enableNotifications() async {
    setState(() => _requesting = true);
    final permission = await widget.service.requestPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _requesting = false;
      _permission = permission;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (_permission) {
      LocalNotificationPermission.granted => 'Notifications are enabled.',
      LocalNotificationPermission.denied =>
        'Notifications are blocked. Enable them in system or browser settings.',
      LocalNotificationPermission.unavailable =>
        'Notifications are unavailable on this platform.',
      null => 'Notifications are off until you enable them.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Session alerts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Prompt alerts you when the open session finishes generating '
            'while the app is in the background.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Alerts never include prompts, messages, tool output, file names, '
            'paths, or credentials.',
          ),
          const SizedBox(height: 20),
          Semantics(
            liveRegion: true,
            label: 'Notification permission: $status',
            child: Text(
              status,
              key: const ValueKey('notification-permission-status'),
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Enable notifications',
            busy: _requesting,
            onPressed: _requesting ? null : _enableNotifications,
          ),
        ],
      ),
    );
  }
}
