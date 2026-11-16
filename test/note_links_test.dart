import 'package:fenru/core/models.dart';
import 'package:fenru/features/notes/note_links.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceObject note(
  String id,
  String title, [
  String body = '',
  bool deleted = false,
]) => WorkspaceObject(
  id: id,
  kind: 'note',
  data: {'title': title, 'body': body},
  revision: 1,
  device: 'tests',
  updated: DateTime.utc(2026),
  deleted: deleted,
);

void main() {
  test('stable note links survive renames and ignore code examples', () {
    final original = note('a', '기존 [제목]');
    final renamed = note('a', '변경한 제목');
    final link = noteLinkMarkdown(original);
    final real = note('b', '참고', link);
    final snippet = note('c', '문법 예제', '`$link`\n\n```md\n$link\n```');
    final trash = note('d', '휴지통', link, true);
    final notes = [renamed, real, snippet, trash];
    expect(link, contains('fenru-note://id/a'));
    expect(findNoteBacklinks(renamed, notes).map((item) => item.id), ['b']);
  });

  test('wiki aliases resolve unique titles and skip ambiguous ones', () {
    final destination = note('a', '강의 노트');
    final reference = note('b', '인용', '앞에서 [[강의 노트|수업 내용]]을 읽었다.');
    final candidates = [destination, reference];
    expect(findNoteBacklinks(destination, candidates).map((item) => item.id), [
      'b',
    ]);
    expect(
      findNoteBacklinks(destination, [...candidates, note('c', '강의 노트')]),
      isEmpty,
    );
  });
}
