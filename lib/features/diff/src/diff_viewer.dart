import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:design_system/design_system.dart';

import 'diff_model.dart';
import 'syntax_highlighter.dart';

class DiffViewer extends StatefulWidget {
  const DiffViewer({required this.document, this.header, super.key});
  final DiffDocument document;
  final Widget? header;
  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer> {
  final _expanded = <String, bool>{};
  final _wrapped = <String, bool>{};

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Material(
      color: Colors.transparent,
      child: SizedBox(
        width: constraints.maxWidth,
        // One selection region for the whole diff: rows used to hold a
        // SelectableText each, so a selection could never cross a line and
        // copying a block of code was impossible.
        child: SelectionArea(
          child: CustomScrollView(
            key: const ValueKey('diff-scroll'),
            slivers: [
              if (widget.header != null)
                SliverToBoxAdapter(child: widget.header),
              for (final file in widget.document.files) ...[
                SliverToBoxAdapter(
                  child: _FileHeader(
                    file: file,
                    expanded: _expanded[file.id] ?? true,
                    onToggle: () => setState(
                      () => _expanded[file.id] = !(_expanded[file.id] ?? true),
                    ),
                  ),
                ),
                if (_expanded[file.id] ?? true)
                  SliverList.builder(
                    key: ValueKey('diff-rows-${file.id}'),
                    itemCount: file.rows.length,
                    itemBuilder: (context, index) {
                      final row = file.rows[index];
                      return _DiffRowView(
                        key: ValueKey('diff-row-${row.id}'),
                        row: row,
                        wrapped: _wrapped[row.id] ?? false,
                        onWrap: () => setState(
                          () => _wrapped[row.id] = !(_wrapped[row.id] ?? false),
                        ),
                        path: file.path,
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.file,
    required this.expanded,
    required this.onToggle,
  });
  final DiffFile file;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A rename keeps both paths on the single header line rather than adding a
    // second line under it.
    // A patch names the other side even when there is no rename: an unchanged
    // path for a modification, and /dev/null when the file is added.
    final renamedFrom =
        file.oldPath != null &&
            file.oldPath != file.path &&
            file.oldPath != '/dev/null'
        ? file.oldPath
        : null;
    final title = renamedFrom == null
        ? file.path
        : '$renamedFrom → ${file.path}';
    return Semantics(
      container: true,
      button: true,
      toggled: expanded,
      label: '${file.path}, ${expanded ? 'expanded' : 'collapsed'}',
      child: InkWell(
        key: ValueKey('diff-file-${file.id}'),
        // The whole header toggles, not just the chevron: aiming for a small
        // icon is the wrong ask on a phone.
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                key: ValueKey('diff-file-toggle-${file.id}'),
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffRowView extends StatelessWidget {
  const _DiffRowView({
    super.key,
    required this.row,
    required this.wrapped,
    required this.onWrap,
    required this.path,
  });
  final DiffRow row;
  final bool wrapped;
  final VoidCallback onWrap;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<PromptTokens>();
    final isMeta = row.kind == DiffRowKind.meta;
    final background = row.kind == DiffRowKind.addition
        ? tokens?.diffAdd ?? Colors.green.withValues(alpha: .12)
        : row.kind == DiffRowKind.deletion
        ? tokens?.diffDelete ?? Colors.red.withValues(alpha: .12)
        : Colors.transparent;
    final base =
        theme.textTheme.bodySmall?.copyWith(
          fontFamily: promptMonoFamily,
          height: 1.3,
        ) ??
        const TextStyle(fontFamily: promptMonoFamily, height: 1.3);
    final hint = theme.hintColor;
    final spans = isMeta
        ? <InlineSpan>[
            TextSpan(
              text: row.content,
              style: base.copyWith(color: hint),
            ),
          ]
        : highlighterForPath(
            path,
          ).highlight(row.content, base, theme.colorScheme.primary);
    // One gutter, not two: a line belongs to one side of the change, and the
    // second column cost width a phone does not have.
    final number = row.newLine ?? row.oldLine;

    return DecoratedBox(
      key: ValueKey('diff-row-background-${row.id}'),
      decoration: BoxDecoration(color: background),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                number?.toString() ?? '',
                textAlign: TextAlign.right,
                style: base.copyWith(color: hint),
              ),
            ),
          ),
          SizedBox(
            width: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(row.prefix, style: base),
            ),
          ),
          Expanded(child: _content(spans)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _content(List<InlineSpan> spans) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(children: spans),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final overflows = painter.width > constraints.maxWidth;
        painter.dispose();
        final text = Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text.rich(
            TextSpan(children: spans),
            softWrap: wrapped,
            maxLines: wrapped ? null : 1,
            overflow: TextOverflow.clip,
          ),
        );
        // A line that already fits has nothing to wrap, so it offers no action
        // at all rather than a control that does nothing visible.
        if (!overflows && !wrapped) return text;
        return Semantics(
          container: true,
          label: '${row.kind.name} line ${row.newLine ?? row.oldLine ?? ''}',
          hint: wrapped ? 'Tap to unwrap line' : 'Tap to wrap line',
          customSemanticsActions: {
            CustomSemanticsAction(label: wrapped ? 'Unwrap line' : 'Wrap line'):
                onWrap,
          },
          child: InkWell(
            key: ValueKey('diff-row-surface-${row.id}'),
            onTap: onWrap,
            child: wrapped
                ? text
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: text,
                  ),
          ),
        );
      },
    );
  }
}
