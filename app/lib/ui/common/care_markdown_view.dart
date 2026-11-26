import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'care_widgets.dart';

/// Lightweight, dependency-free Markdown renderer for Care replies and the
/// transparent `SOUL.md` / `MEMORY.md` documents.
///
/// Supports headings (#–###), task checkboxes (`- [ ]` / `- [x]`), bullet /
/// numbered lists, block quotes, fenced code blocks (with one-tap copy),
/// horizontal rules, and inline `**bold**`, `*italic*`, `~~strike~~`,
/// `` `code` ``, and `[text](url)`.
class CareMarkdownView extends StatelessWidget {
  const CareMarkdownView({
    super.key,
    required this.markdown,
    this.baseStyle,
  });

  final String markdown;
  final TextStyle? baseStyle;

  static final _task = RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final _inline = RegExp(
    r'(\*\*[^*]+\*\*|~~[^~]+~~|`[^`]+`|\[[^\]]+\]\([^)]+\)|\*[^*\s][^*]*\*)',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = baseStyle ??
        theme.textTheme.bodyLarge?.copyWith(height: 1.55) ??
        const TextStyle(fontSize: 16, height: 1.55);

    final blocks = <Widget>[];
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        final lang = trimmed.substring(3).trim();
        final code = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          if (code.isNotEmpty) code.write('\n');
          code.write(lines[i]);
          i++;
        }
        i++; // closing fence (or end of streaming text)
        blocks.add(_codeBlock(context, code.toString(), lang, base, scheme));
        continue;
      }

      if (trimmed.isEmpty) {
        if (blocks.isNotEmpty) blocks.add(const SizedBox(height: 6));
      } else if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        blocks.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(),
        ));
      } else if (trimmed.startsWith('#')) {
        final level = trimmed.indexOf(RegExp(r'[^#]'));
        final text = trimmed.substring(level < 0 ? 0 : level).trim();
        final style = switch (level) {
          1 => theme.textTheme.titleLarge,
          2 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        }
            ?.copyWith(fontWeight: FontWeight.w700, height: 1.4);
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 8, bottom: 4),
          child: Text.rich(_spans(text, style ?? base, scheme)),
        ));
      } else if (trimmed.startsWith('>')) {
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 3),
            ),
          ),
          child: Text.rich(_spans(
            trimmed.replaceFirst(RegExp(r'^>\s?'), ''),
            base.copyWith(color: scheme.onSurfaceVariant),
            scheme,
          )),
        ));
      } else if (_task.hasMatch(line)) {
        final m = _task.firstMatch(line)!;
        final checked = m.group(2)!.toLowerCase() == 'x';
        blocks.add(_taskItem(m.group(1)!.length, checked, m.group(3)!, base, scheme));
      } else if (_bullet.hasMatch(line)) {
        final m = _bullet.firstMatch(line)!;
        blocks.add(_listItem(m.group(1)!.length, '•', m.group(2)!, base, scheme));
      } else if (_numbered.hasMatch(line)) {
        final m = _numbered.firstMatch(line)!;
        blocks.add(
          _listItem(m.group(1)!.length, '${m.group(2)}.', m.group(3)!, base, scheme),
        );
      } else {
        blocks.add(Text.rich(_spans(trimmed, base, scheme)));
      }
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  Widget _taskItem(
    int indent,
    bool checked,
    String text,
    TextStyle base,
    ColorScheme scheme,
  ) {
    final textStyle = checked
        ? base.copyWith(
            color: scheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          )
        : base;
    return Padding(
      padding: EdgeInsets.only(left: 2.0 + (indent ~/ 2) * 16, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 8),
            child: Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: checked ? scheme.primary : scheme.outline,
            ),
          ),
          Expanded(child: Text.rich(_spans(text, textStyle, scheme))),
        ],
      ),
    );
  }

  Widget _listItem(
    int indent,
    String marker,
    String text,
    TextStyle base,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: EdgeInsets.only(left: 4.0 + (indent ~/ 2) * 16, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(marker, style: base.copyWith(color: scheme.primary)),
          ),
          Expanded(child: Text.rich(_spans(text, base, scheme))),
        ],
      ),
    );
  }

  Widget _codeBlock(
    BuildContext context,
    String code,
    String lang,
    TextStyle base,
    ColorScheme scheme,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty || code.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(
                children: [
                  Text(
                    lang.isEmpty ? '代码' : lang,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '复制代码',
                    visualDensity: VisualDensity.compact,
                    iconSize: 15,
                    color: scheme.onSurfaceVariant,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) showCareSnack(context, '代码已复制');
                    },
                    icon: const Icon(Icons.content_copy_rounded),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code,
                style: base.copyWith(
                  fontFamily: 'monospace',
                  fontSize: (base.fontSize ?? 16) - 2,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _spans(String text, TextStyle style, ColorScheme scheme) {
    final children = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > last) children.add(TextSpan(text: text.substring(last, m.start)));
      final token = m.group(0)!;
      if (token.startsWith('**')) {
        children.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (token.startsWith('~~')) {
        children.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ));
      } else if (token.startsWith('`')) {
        children.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ));
      } else if (token.startsWith('[')) {
        final closeBracket = token.indexOf('](');
        final label = closeBracket > 1 ? token.substring(1, closeBracket) : token;
        children.add(TextSpan(
          text: label,
          style: TextStyle(
            color: scheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: scheme.primary.withValues(alpha: 0.5),
          ),
        ));
      } else if (token.startsWith('*')) {
        children.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      last = m.end;
    }
    if (last < text.length) children.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: children);
  }
}
