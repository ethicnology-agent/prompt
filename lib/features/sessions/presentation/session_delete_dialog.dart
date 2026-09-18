import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../domain/session_load_result.dart';

/// Explicit confirmation shared by the catalog and session details.
class SessionDeleteDialog extends StatefulWidget {
  const SessionDeleteDialog({
    required this.title,
    required this.backendLabel,
    required this.onDelete,
    super.key,
  });

  final String title;
  final String backendLabel;
  final Future<SessionsFailure?> Function() onDelete;

  @override
  State<SessionDeleteDialog> createState() => _SessionDeleteDialogState();
}

class _SessionDeleteDialogState extends State<SessionDeleteDialog> {
  bool _deleting = false;
  SessionsFailure? _failure;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _failure = null;
    });
    final failure = await widget.onDelete();
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _failure = failure;
    });
    if (failure == null) {
      final route = ModalRoute.of(context);
      final navigator = route?.navigator;
      if (navigator != null) navigator.removeRoute(route!, true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: AppDialog(
      title: const Text('Delete session?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete "${widget.title}" and its child sessions from ${widget.backendLabel}? Queued work stops and is discarded after deletion. If deletion fails, it stays paused. This cannot be undone.',
            ),
            if (_failure case final failure?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  failure.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.tertiary,
          onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Delete',
          variant: AppButtonVariant.destructive,
          busy: _deleting,
          onPressed: _delete,
        ),
      ],
    ),
  );
}
