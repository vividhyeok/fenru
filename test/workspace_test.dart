import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/core/models.dart';
import 'package:fenru/features/backup/backup_service.dart';

void main() {
  late Directory temp;
  late Workspace w;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fenru-test-');
    w = Workspace(temp, WorkspaceDatabase.memory());
    await w.initialize();
  });
  tearDown(() async {
    await w.close();
    await temp.delete(recursive: true);
  });
  test('Windows workspace lock rejects a second process handle', () async {
    final file = File('${temp.path}/.lock');
    final first = await file.open(mode: FileMode.append);
    final second = await file.open(mode: FileMode.append);
    try {
      await first.lock(FileLock.exclusive);
      await expectLater(
        second.lock(FileLock.exclusive),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await second.close();
      await first.close();
    }
  }, skip: !Platform.isWindows);
  test(
    'remote display names never become filesystem paths or NTFS streams',
    () async {
      final source = File('${temp.path}/transfer.bin');
      await source.writeAsString('content');
      final doc = await w.importFile(
        source.path,
        displayName: 'Week 1: Lecture.pdf:stream',
      );
      expect(doc.title, 'Week 1: Lecture.pdf:stream');
      expect(doc.text('file'), isNot(contains(':')));
      expect(await w.fileFor(doc).exists(), isTrue);
    },
  );
  test('JSON key order does not create a false conflict', () async {
    final note = await w.save('note', {'title': 'same', 'body': 'same'});
    final clone = WorkspaceObject.fromJson({
      ...note.toJson(),
      'data': Map<String, dynamic>.fromEntries(
        note.data.entries.toList().reversed,
      ),
    });
    expect(compareClocks(note, clone), MergeOrder.equal);
  });
  test('concurrent writes keep distinct monotonic revisions', () async {
    final note = await w.save('note', {'title': 'serial', 'body': 'initial'});
    final writes = await Future.wait(
      List.generate(
        8,
        (i) => w.save('note', {'title': 'serial', 'body': '$i'}, id: note.id),
      ),
    );
    expect(writes.map((o) => o.revision).toSet().length, 8);
    expect(w.byId(note.id)!.revision, 9);
    expect(w.byId(note.id)!.data['_clock'][w.device], 9);
  });
  test(
    'note saves, searches and restores from trash without changing ID',
    () async {
      final note = await w.save('note', {
        'title': '선형대수',
        'body': '고유값 eigenvalue',
      });
      expect((await w.search('eigenvalue')).single.id, note.id);
      await w.trash(note);
      expect(w.ofKind('note'), isEmpty);
      expect(await w.search('eigenvalue'), isEmpty);
      await w.restore(w.byId(note.id)!);
      expect(w.ofKind('note').single.id, note.id);
    },
  );
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
  test(
    'backup restores data and preserves concurrent edits idempotently',
    () async {
      final note = await w.save('note', {'title': 'A', 'body': 'initial'});
      final backup = '${temp.path}/backup.zip';
      await BackupService(w).exportTo(backup);
      final otherRoot = await Directory.systemTemp.createTemp('fenru-other-');
      final other = Workspace(otherRoot, WorkspaceDatabase.memory());
      try {
        await other.initialize();
        expect(await BackupService(other).restoreFrom(backup), 0);
        await other.save('note', {
          'title': 'A',
          'body': 'other edit',
        }, id: note.id);
        await w.save('note', {'title': 'A', 'body': 'local edit'}, id: note.id);
        final remoteBackup = '${temp.path}/remote.zip';
        await BackupService(other).exportTo(remoteBackup);
        expect(await BackupService(w).restoreFrom(remoteBackup), 1);
        expect(w.byId(note.id)!.text('body'), 'local edit');
        expect(
          w.ofKind('note').any((n) => n.text('body') == 'other edit'),
          isTrue,
        );
        expect(await BackupService(w).restoreFrom(remoteBackup), 0);
      } finally {
        await other.close();
        await otherRoot.delete(recursive: true);
      }
    },
  );
  test('file database survives close and reopen', () async {
    final file = File('${temp.path}/persistent.sqlite');
    final first = Workspace(temp, WorkspaceDatabase(file));
    await first.initialize();
    final n = await first.save('note', {
      'title': 'persistent',
      'body': 'do not lose',
    });
    await first.close();
    final second = Workspace(temp, WorkspaceDatabase(file));
    await second.initialize();
    expect(second.byId(n.id)!.text('body'), 'do not lose');
    await second.close();
  });
  test('malicious ZIP path is rejected before touching database', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('../escape.txt', 3, [1, 2, 3]));
    final zip = File('${temp.path}/malicious.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(BackupService(w).restoreFrom(zip.path), throwsException);
    expect(w.objects, isEmpty);
  });
  test('backup excludes credentials and preferences', () async {
    await w.setPreference('exampleSecret', 'do-not-export');
    await w.save('note', {'title': 'safe', 'body': 'learning'});
    final path = '${temp.path}/safe.zip';
    await BackupService(w).exportTo(path);
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final manifest = utf8.decode(archive.findFile('manifest.json')!.content);
    expect(manifest, isNot(contains('do-not-export')));
    expect(manifest, isNot(contains('preferences')));
  });
  test(
    'corrupt document hash aborts restore without inserting objects',
    () async {
      final source = File('${temp.path}/source.txt');
      await source.writeAsString('good');
      await w.importFile(source.path);
      final backup = '${temp.path}/good.zip';
      await BackupService(w).exportTo(backup);
      final decoded = ZipDecoder().decodeBytes(
        await File(backup).readAsBytes(),
      );
      final corrupted = Archive();
      for (final entry in decoded) {
        final bytes = entry.name.startsWith('files/')
            ? utf8.encode('bad')
            : entry.content;
        corrupted.addFile(ArchiveFile(entry.name, bytes.length, bytes));
      }
      final bad = '${temp.path}/bad.zip';
      await File(bad).writeAsBytes(ZipEncoder().encode(corrupted));
      final otherRoot = await Directory.systemTemp.createTemp('fenru-corrupt-');
      final other = Workspace(otherRoot, WorkspaceDatabase.memory());
      try {
        await other.initialize();
        await expectLater(
          BackupService(other).restoreFrom(bad),
          throwsException,
        );
        expect(other.objects, isEmpty);
      } finally {
        await other.close();
        await otherRoot.delete(recursive: true);
      }
    },
  );
}
