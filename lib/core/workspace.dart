import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'database.dart';
import 'models.dart';

class Workspace extends ChangeNotifier {
  Workspace(this.root, this.db);
  final Directory root;
  final WorkspaceDatabase db;
  final uuid = const Uuid();
  String device = '';
  List<WorkspaceObject> objects = [];
  Map<String, String> preferences = {};
  String? lastError;

  Future<void> initialize() async {
    await Directory(p.join(root.path, 'files')).create(recursive: true);
    final rows = await db.customSelect('SELECT * FROM preferences').get();
    preferences = {for (final r in rows) r.read<String>('key'): r.read<String>('value')};
    device = preferences['device'] ?? uuid.v4();
    await setPreference('device', device);
    await reload();
  }

  Future<void> reload() async {
    objects = (await db.customSelect('SELECT * FROM objects ORDER BY updated DESC').get())
      .map((r) => WorkspaceObject.fromRow(r.data)).toList();
    notifyListeners();
  }
  List<WorkspaceObject> ofKind(String kind, {bool trash = false}) =>
    objects.where((o) => o.kind == kind && o.deleted == trash).toList();
  WorkspaceObject? byId(String? id) {
    for (final o in objects) { if (o.id == id) return o; }
    return null;
  }
  Future<void> setPreference(String key, String value) async {
    await db.customStatement('INSERT OR REPLACE INTO preferences VALUES (?,?)', [key, value]);
    preferences[key] = value;
    notifyListeners();
  }
  Future<WorkspaceObject> save(String kind, Json data, {String? id, bool deleted = false}) async {
    final previous = byId(id);
    final clock = Map<String, dynamic>.from(previous?.data['_clock'] as Map? ?? {});
    clock[device] = (clock[device] as int? ?? 0) + 1;
    final object = WorkspaceObject(id: id ?? uuid.v4(), kind: kind, data: {...data, '_clock': clock},
      revision: (previous?.revision ?? 0) + 1, device: device,
      updated: DateTime.now().toUtc(), deleted: deleted);
    await db.transaction(() async {
      await writeObject(object);
      await db.customStatement('INSERT OR REPLACE INTO outbox(id,revision) VALUES (?,?)',
        [object.id, object.revision]);
    });
    await reload();
    return object;
  }
  Future<void> writeObject(WorkspaceObject o) async {
    await db.customStatement('INSERT OR REPLACE INTO objects VALUES (?,?,?,?,?,?,?)',
      [o.id, o.kind, jsonEncode(o.data), o.revision, o.device, o.updated.toIso8601String(), o.deleted ? 1 : 0]);
    await db.customStatement('DELETE FROM search_index WHERE id=?', [o.id]);
    if (!o.deleted) {
      await db.customStatement('INSERT INTO search_index(id,title,body) VALUES (?,?,?)',
        [o.id, o.title, '${o.text('body')} ${o.text('tags')} ${o.text('folder')} ${o.text('extracted')}']);
    }
  }
  Future<void> trash(WorkspaceObject o) => save(o.kind, o.data, id: o.id, deleted: true);
  Future<void> restore(WorkspaceObject o) => save(o.kind, o.data, id: o.id);

  File fileFor(WorkspaceObject doc) {
    final relative = doc.text('file');
    final full = p.normalize(p.join(root.path, relative));
    if (relative.isEmpty || !p.isWithin(p.join(root.path, 'files'), full)) {
      throw const UserFacingException('안전하지 않은 파일 경로입니다. 백업을 확인해 주세요.');
    }
    return File(full);
  }

  Future<WorkspaceObject> importFile(String source, {String? folder, Json? origin}) async {
    final file = File(source);
    final size = await file.length();
    final digest = (await sha256.bind(file.openRead()).first).toString();
    for (final existing in ofKind('document')) {
      if (existing.text('hash') == digest && origin == null) return existing;
    }
    final id = uuid.v4();
    final extension = p.extension(source).toLowerCase();
    final relative = p.join('files', '$id$extension');
    final destination = File(p.join(root.path, relative));
    final temporary = File('${destination.path}.part');
    await file.copy(temporary.path);
    if ((await sha256.bind(temporary.openRead()).first).toString() != digest) {
      await temporary.delete();
      throw const UserFacingException('파일 무결성 검사에 실패했습니다. 다시 가져오세요.');
    }
    await temporary.rename(destination.path);
    String extracted = '';
    if (['.txt', '.md', '.markdown', '.html', '.csv'].contains(extension) && size < 10 * 1024 * 1024) {
      extracted = await destination.readAsString().catchError((_) => '');
    }
    return save('document', {'title': p.basename(source), 'originalName': p.basename(source),
      'file': relative, 'hash': digest, 'size': size, 'extension': extension,
      'folder': folder ?? '', 'tags': '', 'page': 1, 'extracted': extracted,
      if (origin != null) 'origin': origin}, id: id);
  }

  Future<List<WorkspaceObject>> search(String query) async {
    if (query.trim().isEmpty) return objects.where((o) => !o.deleted).toList();
    final words = query.trim().split(RegExp(r'\s+'));
    final expression = words.map((w) => '"${w.replaceAll('"', '""')}"*').join(' AND ');
    final rows = await db.customSelect('SELECT id FROM search_index WHERE search_index MATCH ? ORDER BY rank LIMIT 100',
      variables: [Variable.withString(expression)]).get();
    final ids = rows.map((r) => r.read<String>('id')).toSet();
    final lowered = query.toLowerCase();
    return objects.where((o) => !o.deleted && (ids.contains(o.id) ||
      '${o.title} ${o.text('tags')} ${o.text('body')}'.toLowerCase().contains(lowered))).toList();
  }

  Future<void> recordPage(WorkspaceObject doc, int page) async {
    final current = byId(doc.id);
    if (current == null || current.deleted) return;
    await save('document', {...current.data, 'page': page,
      'lastRead': DateTime.now().toUtc().toIso8601String()}, id: doc.id);
  }

  Future<void> close() async { await db.close(); dispose(); }
}
