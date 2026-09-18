import 'package:flutter/material.dart';

/// A lazy, read-only text viewer. Content is rendered literally, never as links.
class CodeLineViewer extends StatelessWidget {
  const CodeLineViewer({required this.lines, this.header, super.key});

  final List<String> lines;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final gutterWidth =
        MediaQuery.textScalerOf(
          context,
        ).scale(lines.length.toString().length * 9.0) +
        16;
    final offset = header == null ? 0 : 1;
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: lines.length + offset,
        itemBuilder: (context, index) {
          if (header != null && index == 0) {
            return SelectionContainer.disabled(child: header!);
          }
          final lineIndex = index - offset;
          return Semantics(
            key: ValueKey('code-line-${lineIndex + 1}'),
            container: true,
            label: 'Line ${lineIndex + 1}',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: gutterWidth,
                    child: SelectionContainer.disabled(
                      child: ExcludeSemantics(
                        child: Text(
                          '${lineIndex + 1}',
                          style: style?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final painter = TextPainter(
                          text: TextSpan(text: lines[lineIndex], style: style),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout(maxWidth: constraints.maxWidth);
                        final visibleLines = painter
                            .computeLineMetrics()
                            .length;
                        painter.dispose();
                        return Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: lines[lineIndex]),
                              // Keep source separators when selection joins rows,
                              // without adding another visual row.
                              if (lineIndex < lines.length - 1)
                                const TextSpan(
                                  text: '\n',
                                  style: TextStyle(fontSize: 0, height: 0),
                                ),
                            ],
                          ),
                          style: style,
                          maxLines: visibleLines == 0 ? 1 : visibleLines,
                          overflow: TextOverflow.clip,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
