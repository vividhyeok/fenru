import 'dart:io';

import 'package:fenru/core/database.dart';
import 'package:fenru/core/models.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/sync/drive_store.dart';
import 'package:fenru/features/sync/drive_sync.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryDrive implements DriveStore {
  final files = <String, List<int>>{};
  bool failNextObject = false;
  final uploaded = <String>[];

  @override
  Future<String> accountId() async => 'account-a';

  @override
  Future<List<DriveFile>> list() async => [
    for (final entry in files.entries)
      (id: entry.key, name: entry.key, size: entry.value.length),
  ];

  @override
  Future<void> download(DriveFile remote, File destination, int limit) async {
    final content = files[remote.id]!;
    if (content.length > limit) throw StateError('File too large');
    await destination.writeAsBytes(content);
  }

  @override
  Future<void> upload(String name, File file) async {
    if (failNextObject && name.contains('-object-')) {
      failNextObject = false;
      throw const SocketException('Offline');
    }
    files[name] = await file.readAsBytes();
    uploaded.add(name);
  }
}

void main() {
  late Directory root;
  late Workspace pc, tablet;
  late MemoryDrive store;
  Future<Workspace> device(String name) async {
    final workspace = Workspace(
      Directory('${root.path}/$name'),
      WorkspaceDatabase.memory(),
    );
    await workspace.initialize();
    return workspace;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fenru-drive-test-');
    pc = await device('pc');
    tablet = await device('tablet');
    store = MemoryDrive();
  });

  tearDown(() async {
    await pc.close();
    await tablet.close();
    await root.delete(recursive: true);
  });

  test(
    'imports attachments once and recovers from interrupted publication',
    () async {
      final source = await File('${root.path}/lecture.pdf')
          .writeAsString('%PDF- fixture');
      final doc = await pc.importFile(source.path);
      final first = DriveSync(pc, store);
      final second = DriveSync(tablet, store);

      store.failNextObject = true;
      await expectLater(
        first.sync('account-a'),
        throwsA(isA<SocketException>()),
      );
      expect(store.files.keys.single, contains('-blob-'));
      expect((await second.sync('account-a')).imported, 0);
      expect((await first.sync('account-a')).uploaded, 1);
      expect((await second.sync('account-a')).imported, 1);
      expect(
        await tablet.fileFor(tablet.byId(doc.id)!).readAsBytes(),
        await source.readAsBytes(),
      );
      expect(
        store.uploaded.where((name) => name.contains('-blob-')),
        hasLength(1),
      );
      expect((await first.sync('account-a')).uploaded, 0);
      expect((await second.sync('account-a')).imported, 0);
    },
  );

  test(
    'merges offline edits and propagates deletes without duplicate conflicts',
    () async {
      final first = DriveSync(pc, store);
      final second = DriveSync(tablet, store);
      final note = await pc.save('note', {'title': 'Note', 'body': 'initial'});
      await first.sync('account-a');
      await second.sync('account-a');
      await pc.save('note', {
        'title': 'Note',
        'body': 'PC offline edit',
      }, id: note.id);
      await tablet.save('note', {
        'title': 'Note',
        'body': 'Tablet offline edit',
      }, id: note.id);
      await first.sync('account-a');
      expect((await second.sync('account-a')).conflicts, 1);
      await first.sync('account-a');
      await second.sync('account-a');
      expect(pc.byId(note.id)!.toJson(), tablet.byId(note.id)!.toJson());
      expect(pc.ofKind('note').map((note) => note.text('body')).toSet(), {
        'PC offline edit',
        'Tablet offline edit',
      });
      expect(tablet.ofKind('note'), hasLength(2));

      await pc.trash(pc.byId(note.id)!);
      await first.sync('account-a');
      await second.sync('account-a');
      expect(tablet.byId(note.id)!.deleted, isTrue);
      expect(tablet.ofKind('note'), hasLength(1));
    },
  );

  test('does not transfer when the active account differs', () async {
    await pc.save('note', {'title': 'Private'});
    await expectLater(
      DriveSync(pc, store).sync('different-account'),
      throwsA(isA<UserFacingException>()),
    );
    expect(store.files, isEmpty);
  });

  test(
    'preserves a concurrent edit in a copy when the original is deleted',
    () async {
      final first = DriveSync(pc, store);
      final second = DriveSync(tablet, store);
      final note = await pc.save('note', {'title': 'Note'});
      await first.sync('account-a');
      await second.sync('account-a');

      await pc.trash(note);
      await tablet.save('note', {'title': 'Edited offline'}, id: note.id);
      await first.sync('account-a');
      await second.sync('account-a');
      await first.sync('account-a');

      final phone = await device('phone');
      try {
        await DriveSync(phone, store).sync('account-a');
        expect(phone.byId(note.id)!.deleted, isTrue);
        expect(phone.ofKind('note').single.title, 'Edited offline (충돌 복사본)');
        expect(phone.ofKind('note').single.id, pc.ofKind('note').single.id);
      } finally {
        await phone.close();
      }
    },
  );
}
