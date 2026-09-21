import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

import '../../../core/ui/ui.dart';

/// Renders the small Markdown subset used in conversation text without
/// interpreting HTML or accepting arbitrary link schemes.
class BasicMarkdownText extends StatelessWidget {
  const BasicMarkdownText({
    required this.text,
    this.style,
    this.onBlockTap,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final ValueChanged<String>? onBlockTap;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          _buildBlock(context, blocks[index]),
          if (index != blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _MarkdownBlock block) {
    final theme = Theme.of(context);
    return switch (block) {
      _HeadingBlock(:final text, :final level) => Semantics(
        header: true,
        child: _selectableText(context, text, _headingStyle(theme, level)),
      ),
      _CodeBlock(:final text, :final language) => Semantics(
        label: 'Code block',
        // The scroll view the code sits in owns a node of its own, which
        // swallowed a bare annotation. Keep the label on a container and let
        // the code keep its own node so it is still readable aloud.
        container: true,
        explicitChildNodes: true,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color:
                theme.extension<PromptTokens>()?.surfaceHighest ??
                theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (language != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
                  child: Text(
                    language,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: promptMonoFamily,
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // Code is not prose: it wraps badly and reads worse. The
              // reference scrolls it sideways instead, so a long line stays on
              // one line.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  text,
                  style: style?.copyWith(
                    fontFamily: promptMonoFamily,
                    fontSize: 14,
                  ),
                  onTap: onBlockTap == null ? null : () => onBlockTap!(text),
                ),
              ),
            ],
          ),
        ),
      ),
      _ListBlock(:final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 6),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: items[index].depth * 16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      items[index].number == null
                          ? _bulletForDepth(items[index].depth)
                          : '${items[index].number}.',
                      style: style,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _selectableText(context, items[index].text, style),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      _TableBlock(:final headers, :final alignments, :final rows) =>
        _MarkdownTable(
          headers: headers,
          alignments: alignments,
          rows: rows,
          style: style,
        ),
      _TextBlock(:final text) => _selectableText(context, text, style),
    };
  }

  Widget _selectableText(
    BuildContext context,
    String text,
    TextStyle? textStyle,
  ) {
    final spans = _inlineSpans(context, text, textStyle);
    final hasLink = spans.any((span) => span is WidgetSpan);
    return SelectableText.rich(
      TextSpan(style: textStyle, children: spans),
      // A block-wide handler wins the gesture arena over embedded links.
      onTap: hasLink || onBlockTap == null ? null : () => onBlockTap!(text),
    );
  }

  TextStyle? _headingStyle(ThemeData theme, int level) {
    final base = switch (level) {
      1 => theme.textTheme.headlineSmall,
      2 => theme.textTheme.titleLarge,
      _ => theme.textTheme.titleMedium,
    };
    return base?.copyWith(color: style?.color);
  }
}

List<InlineSpan> _inlineSpans(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final spans = <InlineSpan>[];
  var index = 0;
  while (index < text.length) {
    if (text.startsWith('`', index)) {
      final end = text.indexOf('`', index + 1);
      if (end != -1) {
        spans.add(
          TextSpan(
            text: text.substring(index + 1, end),
            style: (style ?? const TextStyle()).copyWith(
              fontFamily: promptMonoFamily,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          ),
        );
        index = end + 1;
        continue;
      }
    }
    if (text.startsWith('**', index)) {
      final end = text.indexOf('**', index + 2);
      if (end != -1) {
        spans.add(
          TextSpan(
            text: text.substring(index + 2, end),
            style: (style ?? const TextStyle()).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        index = end + 2;
        continue;
      }
    }
    if (text.startsWith('[', index)) {
      final labelEnd = text.indexOf('](', index + 1);
      if (labelEnd != -1) {
        final urlEnd = text.indexOf(')', labelEnd + 2);
        if (urlEnd != -1) {
          final url = _safeHttpUri(text.substring(labelEnd + 2, urlEnd));
          if (url != null) {
            spans.add(
              _linkSpan(
                context,
                text.substring(index + 1, labelEnd),
                url,
                style,
              ),
            );
            index = urlEnd + 1;
            continue;
          }
        }
      }
    }
    final bareUrl = _bareUrlAt(text, index);
    if (bareUrl != null) {
      spans.add(_linkSpan(context, bareUrl.text, bareUrl.uri, style));
      index += bareUrl.text.length;
      continue;
    }
    final next = _nextMarkup(text, index + 1);
    spans.add(TextSpan(text: text.substring(index, next)));
    index = next;
  }
  return spans;
}

WidgetSpan _linkSpan(
  BuildContext context,
  String label,
  Uri uri,
  TextStyle? style,
) {
  final linkStyle = (style ?? const TextStyle()).copyWith(
    color: Theme.of(context).colorScheme.primary,
    decoration: TextDecoration.underline,
    decorationColor: Theme.of(context).colorScheme.primary,
  );
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Link(
      uri: uri,
      target: LinkTarget.blank,
      builder: (context, followLink) => Semantics(
        link: true,
        label: '$label, link',
        child: InkWell(
          onTap: followLink,
          child: Text(label, style: linkStyle),
        ),
      ),
    ),
  );
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _TextBlock extends _MarkdownBlock {
  const _TextBlock(this.text);

  final String text;
}

class _HeadingBlock extends _MarkdownBlock {
  const _HeadingBlock(this.text, this.level);

  final String text;
  final int level;
}

class _CodeBlock extends _MarkdownBlock {
  const _CodeBlock(this.text, [this.language]);
  final String text;

  /// The fence's info string, when it carried one.
  final String? language;
}

/// One line of a bulleted or numbered list.
class _ListItem {
  const _ListItem({required this.depth, required this.text, this.number});

  /// Nesting level, counted in pairs of leading spaces.
  final int depth;
  final String text;

  /// Position in an ordered list, or null for a bullet.
  final int? number;
}

class _ListBlock extends _MarkdownBlock {
  const _ListBlock(this.items);
  final List<_ListItem> items;
}

class _TableBlock extends _MarkdownBlock {
  const _TableBlock(this.headers, this.alignments, this.rows);

  final List<String> headers;
  final List<_TableAlignment> alignments;
  final List<List<String>> rows;
}

enum _TableAlignment { left, center, right }

class _MarkdownTable extends StatefulWidget {
  const _MarkdownTable({
    required this.headers,
    required this.alignments,
    required this.rows,
    this.style,
  });

  final List<String> headers;
  final List<_TableAlignment> alignments;
  final List<List<String>> rows;
  final TextStyle? style;

  @override
  State<_MarkdownTable> createState() => _MarkdownTableState();
}

class _MarkdownTableState extends State<_MarkdownTable> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widths = List<double>.generate(
      widget.headers.length,
      (column) => 112,
    );
    for (final row in [widget.headers, ...widget.rows]) {
      for (var column = 0; column < row.length; column++) {
        widths[column] = math.min(
          280,
          math.max(widths[column], row[column].length * 8.0 + 24),
        );
      }
    }
    return Semantics(
      label: 'Markdown table',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Table(
                columnWidths: {
                  for (var index = 0; index < widths.length; index++)
                    index: FixedColumnWidth(widths[index]),
                },
                border: TableBorder.all(
                  color: theme.colorScheme.outlineVariant,
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                    ),
                    children: [
                      for (
                        var column = 0;
                        column < widget.headers.length;
                        column++
                      )
                        _tableCell(
                          context,
                          widget.headers[column],
                          column,
                          bold: true,
                        ),
                    ],
                  ),
                  for (final row in widget.rows)
                    TableRow(
                      children: [
                        for (
                          var column = 0;
                          column < widget.headers.length;
                          column++
                        )
                          _tableCell(context, row[column], column),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableCell(
    BuildContext context,
    String text,
    int column, {
    bool bold = false,
  }) {
    final alignment = switch (widget.alignments[column]) {
      _TableAlignment.left => TextAlign.left,
      _TableAlignment.center => TextAlign.center,
      _TableAlignment.right => TextAlign.right,
    };
    final textStyle = (widget.style ?? Theme.of(context).textTheme.bodyLarge)
        ?.copyWith(fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SelectableText.rich(
        TextSpan(
          style: textStyle,
          children: _inlineSpans(context, text, textStyle),
        ),
        textAlign: alignment,
      ),
    );
  }
}

List<_MarkdownBlock> _parseBlocks(String source) {
  final blocks = <_MarkdownBlock>[];
  final lines = source.split('\n');
  final text = <String>[];
  List<String>? code;
  String? language;

  void flushText() {
    // A block that follows a list or a table starts with the blank line that
    // ended it. Drop those, but only whole blank lines: trimming the text
    // itself would eat a trailing space that belongs to the prose.
    var start = 0;
    var end = text.length;
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    final kept = text.sublist(start, end);
    text.clear();
    if (kept.isNotEmpty) blocks.add(_TextBlock(kept.join('\n')));
  }

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    if (line.trimLeft().startsWith('```')) {
      if (code == null) {
        flushText();
        code = <String>[];
        // Only the first word of the info string is the language; the rest is
        // metadata the reference does not print either.
        final info = line.trimLeft().substring(3).trim();
        language = info.isEmpty ? null : info.split(RegExp(r'\s+')).first;
      } else {
        blocks.add(_CodeBlock(code.join('\n'), language));
        code = null;
        language = null;
      }
      continue;
    }
    if (code case final codeLines?) {
      codeLines.add(line);
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    final table = _parseTableAt(lines, lineIndex);
    final list = _parseListAt(lines, lineIndex);
    if (table != null) {
      flushText();
      blocks.add(table.block);
      lineIndex = table.endIndex;
    } else if (list != null) {
      flushText();
      blocks.add(list.block);
      lineIndex = list.endIndex;
    } else if (heading != null) {
      flushText();
      blocks.add(_HeadingBlock(heading.group(2)!, heading.group(1)!.length));
    } else {
      text.add(line);
    }
  }
  if (code != null) {
    text.add('```');
    text.addAll(code);
  }
  flushText();
  return blocks.isEmpty ? const [_TextBlock('')] : blocks;
}

({int endIndex, _TableBlock block})? _parseTableAt(
  List<String> lines,
  int start,
) {
  if (start + 1 >= lines.length) return null;
  final headers = _splitTableRow(lines[start]);
  final separator = _splitTableRow(lines[start + 1]);
  if (headers == null ||
      separator == null ||
      headers.length != separator.length) {
    return null;
  }
  final alignments = <_TableAlignment>[];
  for (final cell in separator) {
    final value = cell.trim();
    if (!RegExp(r'^:?-{3,}:?$').hasMatch(value)) return null;
    alignments.add(
      value.startsWith(':') && value.endsWith(':')
          ? _TableAlignment.center
          : value.startsWith(':')
          ? _TableAlignment.left
          : value.endsWith(':')
          ? _TableAlignment.right
          : _TableAlignment.left,
    );
  }
  final rows = <List<String>>[];
  var end = start + 1;
  while (end + 1 < lines.length) {
    final row = _splitTableRow(lines[end + 1]);
    if (row == null || row.length != headers.length) break;
    rows.add(row);
    end++;
  }
  return (endIndex: end, block: _TableBlock(headers, alignments, rows));
}

List<String>? _splitTableRow(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('|')) return null;
  final withoutLeading = trimmed.startsWith('|')
      ? trimmed.substring(1)
      : trimmed;
  final content = withoutLeading.endsWith('|')
      ? withoutLeading.substring(0, withoutLeading.length - 1)
      : withoutLeading;
  final cells = <String>[];
  final cell = StringBuffer();
  var escaped = false;
  for (var index = 0; index < content.length; index++) {
    final character = content[index];
    if (escaped) {
      cell.write(character);
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(character);
    }
  }
  if (escaped) cell.write('\\');
  cells.add(cell.toString().trim());
  return cells.isEmpty ? null : cells;
}

int _nextMarkup(String text, int start) {
  for (var index = start; index < text.length; index++) {
    if (text[index] == '`' ||
        text[index] == '[' ||
        text.startsWith('**', index) ||
        _startsWithHttpScheme(text, index)) {
      return index;
    }
  }
  return text.length;
}

({String text, Uri uri})? _bareUrlAt(String text, int start) {
  if (!_startsWithHttpScheme(text, start)) {
    return null;
  }
  var end = start;
  while (end < text.length && !RegExp(r'[\s\]\[<>]').hasMatch(text[end])) {
    end++;
  }
  var candidate = text.substring(start, end);
  while (candidate.endsWith('.') ||
      candidate.endsWith(',') ||
      candidate.endsWith(')')) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  final uri = _safeHttpUri(candidate);
  return uri == null ? null : (text: candidate, uri: uri);
}

Uri? _safeHttpUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return null;
  }
  return uri;
}

final _httpSchemePattern = RegExp(r'https?://', caseSensitive: false);

bool _startsWithHttpScheme(String text, int start) =>
    _httpSchemePattern.matchAsPrefix(text, start) != null;

/// The reference cycles three glyphs by depth and stops at the third.
String _bulletForDepth(int depth) =>
    const ['\u2022', '\u25e6', '\u25aa'][depth.clamp(0, 2)];

final _listItemPattern = RegExp(r'^(\s*)(?:([-*+])|(\d{1,9})[.)])\s+(.*)$');

/// Gathers the run of list lines starting at [lineIndex], or null if there is
/// none. A blank line ends the run, as does anything that is not an item.
({int endIndex, _ListBlock block})? _parseListAt(
  List<String> lines,
  int lineIndex,
) {
  final items = <_ListItem>[];
  var index = lineIndex;
  while (index < lines.length) {
    final match = _listItemPattern.firstMatch(lines[index]);
    if (match == null) break;
    final content = match.group(4)!;
    if (content.trim().isEmpty) break;
    final number = match.group(3);
    items.add(
      _ListItem(
        // Two leading spaces make one level, the usual convention; deeper
        // indents round down rather than inventing levels.
        depth: match.group(1)!.length ~/ 2,
        text: content,
        number: number == null ? null : int.parse(number),
      ),
    );
    index++;
  }
  if (items.isEmpty) return null;
  return (endIndex: index - 1, block: _ListBlock(items));
}
