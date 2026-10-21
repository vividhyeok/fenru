import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/backup/backup_service.dart';

void main() {
  late Directory temp;
  late Workspace w;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fenru-test-');
    w = Workspace(temp, WorkspaceDatabase.memory());
    await w.initialize();
  });
  tearDown(() async { await w.close(); await temp.delete(recursive: true); });
  test('note saves, searches and restores from trash without changing ID', () async {
    final note = await w.save('note', {'title': '선형대수', 'body': '고유값 eigenvalue'});
    expect((await w.search('eigenvalue')).single.id, note.id);
    await w.trash(note);
    expect(w.ofKind('note'), isEmpty);
    expect(await w.search('eigenvalue'), isEmpty);
    await w.restore(w.byId(note.id)!);
    expect(w.ofKind('note').single.id, note.id);
  });
  test('import copies bytes, deduplicates and keeps progress', () async {
    final source = File('${temp.path}/original.txt');
    await source.writeAsString('original content');
    final doc = await w.importFile(source.path);
    expect(w.fileFor(doc).path, isNot(source.path));
    expect(await w.fileFor(doc).readAsString(), 'original content');
    expect((await w.importFile(source.path)).id, doc.id);
    await w.recordPage(doc, 7);
    await w.reload();
    expect(w.byId(doc.id)!.number('page'), 7);
    expect(await source.readAsString(), 'original content');
  });
  test('backup restores data and preserves concurrent edits idempotently', () async {
    final note = await w.save('note', {'title': 'A', 'body': 'initial'});
    final backup = '${temp.path}/backup.zip';
    await BackupService(w).exportTo(backup);
    final otherRoot = await Directory.systemTemp.createTemp('fenru-other-');
    final other = Workspace(otherRoot, WorkspaceDatabase.memory());
    try {
      await other.initialize();
      expect(await BackupService(other).restoreFrom(backup), 0);
      await other.save('note', {'title': 'A', 'body': 'other edit'}, id: note.id);
      await w.save('note', {'title': 'A', 'body': 'local edit'}, id: note.id);
      final remoteBackup = '${temp.path}/remote.zip';
      await BackupService(other).exportTo(remoteBackup);
      expect(await BackupService(w).restoreFrom(remoteBackup), 1);
      expect(w.byId(note.id)!.text('body'), 'local edit');
      expect(w.ofKind('note').any((n) => n.text('body') == 'other edit'), isTrue);
      expect(await BackupService(w).restoreFrom(remoteBackup), 0);
    } finally { await other.close(); await otherRoot.delete(recursive: true); }
  });
  test('file database survives close and reopen', () async {
    final file = File('${temp.path}/persistent.sqlite');
    final first = Workspace(temp, WorkspaceDatabase(file));
    await first.initialize();
    final n = await first.save('note', {'title': 'persistent', 'body': 'do not lose'});
    await first.close();
    final second = Workspace(temp, WorkspaceDatabase(file));
    await second.initialize();
    expect(second.byId(n.id)!.text('body'), 'do not lose');
    await second.close();
  });
}
