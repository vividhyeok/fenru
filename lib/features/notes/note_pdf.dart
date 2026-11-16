import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pdf;

Future<Uint8List> renderNotePdf(
  String title,
  String markdown, {
  bool plainText = false,
  String sourceUrl = '',
}) async {
  final regular = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf');
  return compute(_renderNote, (
    title,
    markdown,
    regular,
    bold,
    plainText,
    sourceUrl,
  ));
}

Future<Uint8List> _renderNote(
  (String, String, ByteData, ByteData, bool, String) input,
) => buildNotePdf(
  title: input.$1,
  markdown: input.$2,
  regularFont: input.$3,
  boldFont: input.$4,
  plainText: input.$5,
  sourceUrl: input.$6,
);

Future<Uint8List> buildNotePdf({
  required String title,
  required String markdown,
  required ByteData regularFont,
  required ByteData boldFont,
  bool plainText = false,
  String sourceUrl = '',
}) async {
  final regular = pdf.Font.ttf(regularFont);
  final bold = pdf.Font.ttf(boldFont);
  final document = pdf.Document(title: title);
  final nodes = plainText
      ? [md.Text(markdown)]
      : md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          encodeHtml: false,
        ).parse(markdown);

  pdf.InlineSpan inline(md.Node node) {
    if (node is! md.Element) return pdf.TextSpan(text: node.textContent);
    final href = node.attributes['href'];
    final uri = Uri.tryParse(href ?? '');
    return pdf.TextSpan(
      text: switch (node.tag) {
        'br' => '\n',
        'img' => node.attributes['alt'],
        'input' => node.attributes.containsKey('checked') ? '[x] ' : '[ ] ',
        _ => null,
      },
      children: node.children?.map(inline).toList(),
      annotation:
          href != null && (uri?.scheme == 'https' || uri?.scheme == 'http')
          ? pdf.AnnotationUrl(href)
          : null,
      style: switch (node.tag) {
        'strong' => const pdf.TextStyle(fontWeight: pdf.FontWeight.bold),
        'em' => const pdf.TextStyle(fontStyle: pdf.FontStyle.italic),
        'code' ||
        'blockquote' => const pdf.TextStyle(color: PdfColors.blueGrey700),
        'a' => const pdf.TextStyle(
          color: PdfColors.blue800,
          decoration: pdf.TextDecoration.underline,
        ),
        'del' => const pdf.TextStyle(
          decoration: pdf.TextDecoration.lineThrough,
        ),
        _ => null,
      },
    );
  }

  pdf.Widget paragraph(
    List<pdf.InlineSpan> spans, {
    double size = 11,
    bool heading = false,
  }) => pdf.RichText(
    overflow: pdf.TextOverflow.span,
    text: pdf.TextSpan(
      style: pdf.TextStyle(
        fontSize: size,
        fontWeight: heading ? pdf.FontWeight.bold : pdf.FontWeight.normal,
        color: heading ? PdfColors.blueGrey900 : PdfColors.grey900,
        lineSpacing: 4,
        wordSpacing: 1.4,
      ),
      children: spans,
    ),
  );

  Iterable<pdf.Widget> blocks(md.Node node, {String prefix = ''}) sync* {
    if (node is md.Element) {
      final children = node.children ?? [];
      final level = RegExp(r'^h([1-6])$').firstMatch(node.tag);
      if (level != null) {
        yield pdf.NewPage(freeSpace: 64);
        yield paragraph(
          [inline(node)],
          size: level.group(1) == '1' ? 19 : 15,
          heading: true,
        );
        yield pdf.SizedBox(height: 8);
        return;
      }
      if (node.tag == 'hr') {
        yield pdf.Divider(color: PdfColors.grey400);
        return;
      }
      if (node.tag == 'ul' || node.tag == 'ol') {
        var index = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final item in children) {
          final bullet = node.tag == 'ol' ? '${index++}. ' : '• ';
          if (item is! md.Element) continue;
          final content = item.children ?? [];
          final inlineContent = <md.Node>[];
          var itemPrefix = '$prefix$bullet';
          for (final child in content) {
            if (child is md.Element &&
                ['p', 'ul', 'ol', 'pre', 'blockquote'].contains(child.tag)) {
              if (inlineContent.isNotEmpty) {
                yield paragraph([
                  pdf.TextSpan(text: itemPrefix),
                  ...inlineContent.map(inline),
                ]);
                inlineContent.clear();
                itemPrefix = '    $prefix';
              }
              final nested = child.tag == 'ul' || child.tag == 'ol';
              yield* blocks(child, prefix: nested ? '    $prefix' : itemPrefix);
              itemPrefix = '    $prefix';
            } else {
              inlineContent.add(child);
            }
          }
          if (inlineContent.isNotEmpty) {
            yield paragraph([
              pdf.TextSpan(text: itemPrefix),
              ...inlineContent.map(inline),
            ]);
          }
        }
        yield pdf.SizedBox(height: 8);
        return;
      }
      if (node.tag == 'blockquote') {
        for (final child in children) {
          yield* blocks(child, prefix: '$prefix│ ');
        }
        return;
      }
      if (node.tag == 'table') {
        for (final section in children.whereType<md.Element>()) {
          for (final row in (section.children ?? []).whereType<md.Element>()) {
            final cells = row.children ?? [];
            yield paragraph([
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const pdf.TextSpan(text: '  │  '),
                inline(cells[i]),
              ],
            ], heading: section.tag == 'thead');
          }
        }
        yield pdf.SizedBox(height: 8);
        return;
      }
    }
    yield paragraph([
      if (prefix.isNotEmpty) pdf.TextSpan(text: prefix),
      inline(node),
    ]);
    yield pdf.SizedBox(height: 8);
  }

  document.addPage(
    pdf.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 1000,
      margin: const pdf.EdgeInsets.fromLTRB(52, 52, 52, 42),
      theme: pdf.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      ),
      footer: (context) => pdf.Align(
        alignment: pdf.Alignment.centerRight,
        child: pdf.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pdf.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      build: (_) => [
        paragraph([pdf.TextSpan(text: title)], size: 26, heading: true),
        pdf.Divider(color: PdfColors.grey400, height: 26),
        if (Uri.tryParse(sourceUrl)?.scheme == 'https') ...[
          paragraph([
            pdf.TextSpan(
              text: '학교 원문 열기',
              annotation: pdf.AnnotationUrl(sourceUrl),
              style: const pdf.TextStyle(
                color: PdfColors.blue800,
                decoration: pdf.TextDecoration.underline,
              ),
            ),
          ]),
          pdf.SizedBox(height: 12),
        ],
        for (final node in nodes) ...blocks(node),
      ],
    ),
  );
  return document.save();
}
