import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';
import '../../core/workspace.dart';

enum MergeOrder { equal, localNewer, remoteNewer, concurrent }

MergeOrder compareClocks(WorkspaceObject local, WorkspaceObject remote) {
  final a = Map<String, dynamic>.from(local.data['_clock'] as Map? ?? {});
  final b = Map<String, dynamic>.from(remote.data['_clock'] as Map? ?? {});
  bool greater = false, less = false;
  for (final key in {...a.keys, ...b.keys}) {
    final av = a[key] as int? ?? 0, bv = b[key] as int? ?? 0;
    greater |= av > bv;
    less |= av < bv;
  }
  if (greater && less) return MergeOrder.concurrent;
  if (greater) return MergeOrder.localNewer;
  if (less) return MergeOrder.remoteNewer;
  return jsonEncode(local.toJson()) == jsonEncode(remote.toJson())
      ? MergeOrder.equal
      : MergeOrder.concurrent;
}

class BackupService {
  const BackupService(this.workspace);
  final Workspace workspace;
  static const maxArchiveSize = 1024 * 1024 * 1024;
  Future<void> exportTo(String destination) async {
    final archive = Archive();
    final metadata = utf8.encode(
      jsonEncode({
        'format': 'fenru',
        'schema': 1,
        'created': DateTime.now().toUtc().toIso8601String(),
        'objects': workspace.objects.map((o) => o.toJson()).toList(),
      }),
    );
    if (metadata.length > 16 * 1024 * 1024) {
      throw const UserFacingException('메타데이터가 백업 한도 16MB를 초과했습니다.');
    }
    int total = metadata.length;
    archive.addFile(ArchiveFile('manifest.json', metadata.length, metadata));
    final paths = <String>{};
    for (final object in workspace.objects.where((o) => o.kind == 'document')) {
      final file = workspace.fileFor(object);
      final name = object.text('file').replaceAll('\\', '/');
      if (await file.exists() && paths.add(name)) {
        total += await file.length();
        if (total > maxArchiveSize) {
          throw const UserFacingException('백업 크기가 1GB를 초과했습니다.');
        }
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
    }
    final temp = File('$destination.part');
    final encoded = ZipEncoder().encode(archive);
    if (encoded.length > maxArchiveSize) {
      throw const UserFacingException('압축 백업이 1GB를 초과했습니다.');
    }
    await temp.writeAsBytes(encoded, flush: true);
    await temp.rename(destination);
  }

  Future<int> restoreFrom(String source) async {
    if (await File(source).length() > maxArchiveSize) {
      throw const UserFacingException('백업 크기는 1GB 이하로 가져올 수 있습니다.');
    }
    final archive = ZipDecoder().decodeBytes(
      await File(source).readAsBytes(),
      verify: true,
    );
    int total = 0;
    for (final entry in archive) {
      total += entry.size;
      if (total > maxArchiveSize ||
          entry.isSymbolicLink ||
          entry.name.contains('\\') ||
          p.posix.isAbsolute(entry.name) ||
          entry.name.split('/').contains('..') ||
          entry.name.contains(':') ||
          !(entry.name == 'manifest.json' ||
              RegExp(r'^files/[a-zA-Z0-9-]+(\.[a-zA-Z0-9]+)?$')
                  .hasMatch(entry.name))) {
        throw const UserFacingException('백업에 안전하지 않은 경로나 과도한 데이터가 있습니다.');
      }
    }
    final manifest = archive.findFile('manifest.json');
    if (manifest == null) throw const UserFacingException('Fenru 백업 파일이 아닙니다.');
    if (manifest.size > 16 * 1024 * 1024) {
      throw const UserFacingException('백업 메타데이터가 허용 크기를 초과했습니다.');
    }
    final json = jsonDecode(utf8.decode(manifest.content)) as Json;
    if (json['format'] != 'fenru' || json['schema'] != 1) {
      throw const UserFacingException('지원하지 않는 백업 버전입니다.');
    }
    final incoming = (json['objects'] as List)
        .map(
          (j) => WorkspaceObject.fromJson(Map<String, dynamic>.from(j as Map)),
        )
        .toList();
    final files = <String, List<int>>{};
    if (incoming.map((o) => o.id).toSet().length != incoming.length) {
      throw const UserFacingException('백업에 중복된 객체 ID가 있습니다.');
    }
    for (final object in incoming.where((o) => o.kind == 'document')) {
      final target = workspace.fileFor(object);
      final entry = archive.findFile(object.text('file').replaceAll('\\', '/'));
      if (entry == null ||
          sha256.convert(entry.content).toString() != object.text('hash')) {
        throw const UserFacingException(
          '문서가 누락되었거나 체크섬이 일치하지 않습니다. 복원을 중단했습니다.',
        );
      }
      if (await target.exists()) {
        if ((await sha256.bind(target.openRead()).first).toString() !=
            object.text('hash')) {
          throw const UserFacingException('기존 파일과 충돌합니다. 별도 작업 공간에서 복원해 주세요.');
        }
      } else {
        files[target.path] = entry.content;
      }
    }
    for (final entry in files.entries) {
      final temp = File('${entry.key}.part');
      await temp.writeAsBytes(entry.value, flush: true);
      await temp.rename(entry.key);
    }
    int conflicts = 0;
    await workspace.db.transaction(() async {
      for (final remote in incoming) {
        final local = workspace.byId(remote.id);
        if (local == null) {
          await workspace.writeObject(remote);
          continue;
        }
        final order = compareClocks(local, remote);
        if (order == MergeOrder.remoteNewer) {
          await workspace.writeObject(remote);
        } else if (order == MergeOrder.concurrent) {
          final conflictId = sha256
              .convert(utf8.encode(jsonEncode(remote.toJson())))
              .toString();
          if (workspace.byId(conflictId) == null) {
            conflicts++;
            await workspace.writeObject(
              WorkspaceObject(
                id: conflictId,
                kind: remote.kind,
                data: {
                  ...remote.data,
                  'title': '${remote.title} (충돌 복사본)',
                  'conflictOf': remote.id,
                  'remoteDeleted': remote.deleted,
                },
                revision: remote.revision,
                device: remote.device,
                updated: remote.updated,
              ),
            );
          }
        }
      }
    });
    await workspace.reload();
    return conflicts;
  }
}
