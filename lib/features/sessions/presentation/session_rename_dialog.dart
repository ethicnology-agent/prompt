import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../domain/session_load_result.dart';

/// Shared title editor for catalog and conversation actions.
class SessionRenameDialog extends StatefulWidget {
  const SessionRenameDialog({
    required this.initialTitle,
    this.onSave,
    super.key,
  });

  final String initialTitle;
  final Future<SessionsFailure?> Function(String title)? onSave;

  @override
  State<SessionRenameDialog> createState() => _SessionRenameDialogState();
}

class _SessionRenameDialogState extends State<SessionRenameDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _controller.text.trim();
    if (title.isEmpty || title.length > 256) {
      setState(() => _error = 'Enter a title between 1 and 256 characters.');
      return;
    }
    if (title == widget.initialTitle) {
      Navigator.of(context).pop();
      return;
    }
    if (widget.onSave == null) {
      Navigator.of(context).pop(title);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await widget.onSave!(title);
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure == null) {
      final route = ModalRoute.of(context);
      final navigator = route?.navigator;
      if (navigator != null) navigator.removeRoute(route!, title);
    } else {
      setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AppDialog(
      title: const Text('Rename session'),
      content: SingleChildScrollView(
        child: AppTextField(
          controller: _controller,
          autofocus: true,
          readOnly: _saving,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          label: 'Title',
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.tertiary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(label: 'Rename', busy: _saving, onPressed: _save),
      ],
    ),
  );
}
