import 'package:markdown/markdown.dart' as md;

import '../../core/models.dart';

class WikiNoteLinkSyntax extends md.InlineSyntax {
  WikiNoteLinkSyntax() : super(r'\[\[([^\[\]\n|]+)(?:\|([^\[\]\n]+))?\]\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final title = match[1]!.trim();
    if (title.isEmpty) return false;
    final link = md.Element.text('a', match[2]?.trim() ?? title);
    link.attributes['href'] = Uri(
      scheme: 'fenru-note',
      host: 'title',
      pathSegments: [title],
    ).toString();
    parser.addNode(link);
    return true;
  }
}

String noteLinkMarkdown(WorkspaceObject note) {
  final label = (note.title.trim().isEmpty ? '제목 없는 노트' : note.title.trim())
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'[\\\[\]]'), (match) => '\\${match[0]}');
  final url = Uri(scheme: 'fenru-note', host: 'id', pathSegments: [note.id]);
  return '[$label]($url)';
}

WorkspaceObject? resolveNoteLink(Uri uri, Iterable<WorkspaceObject> notes) {
  if (uri.scheme != 'fenru-note' || uri.pathSegments.length != 1) return null;
  final value = uri.pathSegments.single;
  final candidates = notes
      .where(
        (note) =>
            !note.deleted &&
            (uri.host == 'id' && note.id == value ||
                uri.host == 'title' &&
                    note.title.trim().toLowerCase() == value.toLowerCase()),
      )
      .take(2)
      .toList();
  return candidates.length == 1 ? candidates.single : null;
}

List<WorkspaceObject> findNoteBacklinks(
  WorkspaceObject target,
  List<WorkspaceObject> notes,
) {
  bool linksToTarget(md.Node node) {
    if (node is! md.Element) return false;
    final href = node.tag == 'a' ? node.attributes['href'] : null;
    final uri = href == null ? null : Uri.tryParse(href);
    return (uri != null && resolveNoteLink(uri, notes)?.id == target.id) ||
        (node.children?.any(linksToTarget) ?? false);
  }

  bool hasLink(WorkspaceObject note) => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    inlineSyntaxes: [WikiNoteLinkSyntax()],
  ).parse(note.text('body')).any(linksToTarget);

  return [
    for (final note in notes)
      if (!note.deleted && note.id != target.id && hasLink(note)) note,
  ];
}
