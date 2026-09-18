import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../diff/diff.dart';
import '../domain/session_artifacts.dart';

/// A read-only snapshot reported by the session, not the current file content.
class SessionFileDiffScreen extends StatefulWidget {
  const SessionFileDiffScreen({required this.diff, this.onOpenFile, super.key});
  final SessionFileDiff diff;
  final VoidCallback? onOpenFile;
  @override
  State<SessionFileDiffScreen> createState() => _SessionFileDiffScreenState();
}

class _SessionFileDiffScreenState extends State<SessionFileDiffScreen> {
  late final Future<DiffDocument> _document = compute(_parse, widget.diff);
  late final List<String> _rawLines = widget.diff.patch.split('\n');
  bool _raw = false;
  static DiffDocument _parse(SessionFileDiff diff) =>
      UnifiedDiffParser.parseFile(diff.file, diff.patch);

  Widget _header() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          widget.diff.file.isEmpty ? 'Changed file' : widget.diff.file,
        ),
        const SizedBox(height: 4),
        Text(
          'Session snapshot · +${widget.diff.additions} −${widget.diff.deletions}',
        ),
        Wrap(
          spacing: 8,
          children: [
            if (widget.onOpenFile != null && widget.diff.file.isNotEmpty)
              AppButton(
                label: 'Current file',
                variant: AppButtonVariant.tertiary,
                icon: Icons.description_outlined,
                onPressed: widget.onOpenFile,
              ),
            if (widget.diff.patch.isNotEmpty)
              AppButton(
                label: _raw ? 'Formatted diff' : 'Raw patch',
                variant: AppButtonVariant.tertiary,
                onPressed: () => setState(() => _raw = !_raw),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _notice(String text) => ListView(
    children: [
      _header(),
      Padding(padding: const EdgeInsets.all(24), child: Text(text)),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('File changes')),
    body: SafeArea(
      top: false,
      child: widget.diff.patch.isEmpty
          ? _notice('The server reported no patch for this file.')
          : _raw
          ? CodeLineViewer(lines: _rawLines, header: _header())
          : FutureBuilder<DiffDocument>(
              future: _document,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _notice(
                    'Cannot render this patch. Use Raw patch to inspect it.',
                  );
                }
                final document = snapshot.data;
                if (document == null) {
                  return ListView(
                    children: [
                      _header(),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  );
                }
                if (document.files.isEmpty) {
                  return _notice(
                    'No formatted diff is available. Use Raw patch to inspect the server response.',
                  );
                }
                return DiffViewer(document: document, header: _header());
              },
            ),
    ),
  );
}
