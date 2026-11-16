import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../backup/backup_service.dart';
import 'drive_store.dart';

class DriveSync {
  const DriveSync(this.workspace, this.store);
  final Workspace workspace;
  final DriveStore store;
  static const _prefix = GoogleDriveStore.prefix;
  static const _maxObjectSize = 16 * 1024 * 1024;
  static const _maxBlobSize = 1024 * 1024 * 1024;
  static final _objectName = RegExp(
    r'^fenru-sync-v1-object-[a-f0-9]{64}\.json$',
  );
  static final _sha = RegExp(r'^[a-f0-9]{64}$');

  Future<({int imported, int uploaded, int conflicts})> sync(
    String account,
  ) async {
    if (account.isEmpty || await store.accountId() != account) {
      throw const UserFacingException('연결된 Google 계정이 달라졌습니다. 설정에서 다시 연결하세요.');
    }
    final files = {for (final file in await store.list()) file.name: file};
    final applied = {
      for (final row
          in await workspace.db
              .customSelect(
                'SELECT name FROM drive_applied WHERE account=?',
                variables: [Variable(account)],
              )
              .get())
        row.read<String>('name'),
    };
    final temporary = await Directory.systemTemp.createTemp('fenru-drive-');
    final staging = File('${temporary.path}/object.json');
    var imported = 0, uploaded = 0, conflicts = 0;
    try {
      final incoming =
          files.values
              .where(
                (file) =>
                    _objectName.hasMatch(file.name) &&
                    !applied.contains(file.name),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      for (final entry in incoming) {
        await store.download(entry, staging, _maxObjectSize);
        final bytes = await staging.readAsBytes();
        if (entry.name != _nameFor(bytes)) {
          throw const FormatException('Drive object checksum mismatch');
        }
        final remote = WorkspaceObject.fromJson(
          jsonDecode(utf8.decode(bytes)) as Json,
        );
        if (remote.kind == 'document') await _receiveBlob(remote, files);
        final merged = await workspace.serializeWrite(() async {
          var changed = false, conflict = false;
          await workspace.db.transaction(() async {
            final local = workspace.byId(remote.id);
            if (local == null) {
              changed = true;
              await workspace.writeObject(remote);
            } else {
              final order = compareClocks(local, remote);
              if (order == MergeOrder.remoteNewer) {
                changed = true;
                await workspace.writeObject(remote);
              } else if (order == MergeOrder.concurrent) {
                (changed, conflict) = await _mergeConcurrent(local, remote);
              }
            }
            await _markApplied(account, entry.name);
          });
          if (changed || conflict) await workspace.reload();
          return (changed, conflict);
        });
        if (merged.$1) imported++;
        if (merged.$2) conflicts++;
      }

      final snapshot = List<WorkspaceObject>.of(workspace.objects);
      final published = files.keys.toSet();
      for (final object in snapshot) {
        final bytes = utf8.encode(canonicalObjectJson(object));
        final name = _nameFor(bytes);
        if (published.contains(name)) continue;
        if (bytes.length > _maxObjectSize) {
          throw const UserFacingException('동기화할 항목이 16MB를 초과했습니다.');
        }
        if (object.kind == 'document') {
          final blob = _blobName(object);
          if (!published.contains(blob)) {
            final source = workspace.fileFor(object);
            if (await source.length() > _maxBlobSize ||
                await _fileHash(source) != object.text('hash')) {
              throw const UserFacingException('동기화할 문서의 크기 또는 체크섬을 확인하세요.');
            }
            await store.upload(blob, source);
            published.add(blob);
          }
        }
        await staging.writeAsBytes(bytes);
        await store.upload(name, staging);
        await _markApplied(account, name);
        published.add(name);
        uploaded++;
      }
      return (imported: imported, uploaded: uploaded, conflicts: conflicts);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<void> _markApplied(String account, String name) =>
      workspace.db.customStatement(
        'INSERT OR IGNORE INTO drive_applied(account,name) VALUES (?,?)',
        [account, name],
      );

  static String _nameFor(List<int> bytes) =>
      '${_prefix}object-${sha256.convert(bytes)}.json';

  static String _blobName(WorkspaceObject object) {
    final digest = object.text('hash');
    if (!_sha.hasMatch(digest)) {
      throw const FormatException('Invalid document checksum');
    }
    return '${_prefix}blob-$digest';
  }

  static Future<String> _fileHash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _receiveBlob(
    WorkspaceObject object,
    Map<String, DriveFile> files,
  ) async {
    final name = _blobName(object);
    final target = workspace.fileFor(object);
    final digest = object.text('hash');
    if (await target.exists()) {
      if (await _fileHash(target) != digest) {
        throw const UserFacingException('로컬 문서가 Drive 문서와 충돌합니다.');
      }
      return;
    }
    final remote = files[name];
    if (remote == null) {
      throw const FormatException('Drive document blob unavailable');
    }
    final temporary = await target.parent.createTemp('fenru-sync-');
    try {
      final staged = File('${temporary.path}/document');
      await store.download(remote, staged, _maxBlobSize);
      if (await _fileHash(staged) != digest) {
        throw const FormatException('Drive blob checksum mismatch');
      }
      if (await target.exists()) {
        if (await _fileHash(target) != digest) {
          throw const FormatException('Local document collision');
        }
      } else {
        await staged.rename(target.path);
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<(bool, bool)> _mergeConcurrent(
    WorkspaceObject local,
    WorkspaceObject remote,
  ) async {
    final localVersion = _version(local);
    final remoteVersion = _version(remote);
    final remoteWins = local.deleted == remote.deleted
        ? remoteVersion.compareTo(localVersion) > 0
        : remote.deleted;
    final winner = remoteWins ? remote : local;
    final loser = remoteWins ? local : remote;
    final clock = Map<String, int>.from(winner.data['_clock'] as Map);
    for (final entry in (loser.data['_clock'] as Map).entries) {
      final device = entry.key as String;
      final revision = entry.value as int;
      if (revision > (clock[device] ?? 0)) clock[device] = revision;
    }

    var conflict = false;
    if (!loser.deleted && remoteVersion != localVersion) {
      final id = sha256
          .convert(utf8.encode('drive-conflict:${_version(loser)}'))
          .toString();
      if (workspace.byId(id) == null) {
        await workspace.writeObject(
          WorkspaceObject(
            id: id,
            kind: loser.kind,
            data: {
              ...loser.data,
              'title': '${loser.title} (충돌 복사본)',
              'conflictOf': loser.id,
            },
            revision: loser.revision,
            device: loser.device,
            updated: loser.updated,
          ),
        );
        conflict = true;
      }
    }
    final merged = WorkspaceObject(
      id: winner.id,
      kind: winner.kind,
      data: {...winner.data, '_clock': clock},
      revision: winner.revision,
      device: winner.device,
      updated: winner.updated,
      deleted: winner.deleted,
    );
    final changed = canonicalObjectJson(local) != canonicalObjectJson(merged);
    if (changed) await workspace.writeObject(merged);
    return (changed, conflict);
  }

  static String _version(WorkspaceObject object) {
    final data = {...object.data}..remove('_clock');
    final version = WorkspaceObject(
      id: object.id,
      kind: object.kind,
      data: data,
      revision: object.revision,
      device: object.device,
      updated: object.updated,
      deleted: object.deleted,
    );
    return '${object.updated.toUtc().toIso8601String()}:${canonicalObjectJson(version)}';
  }
}
