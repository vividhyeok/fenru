import 'dart:convert';

typedef Json = Map<String, dynamic>;

class WorkspaceObject {
  const WorkspaceObject({
    required this.id,
    required this.kind,
    required this.data,
    required this.revision,
    required this.device,
    required this.updated,
    this.deleted = false,
  });
  final String id, kind, device;
  final Json data;
  final int revision;
  final DateTime updated;
  final bool deleted;
  String get title => data['title'] as String? ?? '';
  String text(String key, [String fallback = '']) =>
      data[key] as String? ?? fallback;
  int number(String key, [int fallback = 0]) =>
      (data[key] as num?)?.toInt() ?? fallback;
  bool flag(String key) => data[key] == true;
  Json toJson() => {
    'id': id,
    'kind': kind,
    'data': data,
    'revision': revision,
    'device': device,
    'updated': updated.toUtc().toIso8601String(),
    'deleted': deleted,
  };
  factory WorkspaceObject.fromJson(Json j) {
    final id = j['id'] as String;
    if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Invalid object ID');
    }
    const kinds = {
      'document',
      'note',
      'annotation',
      'course',
      'task',
      'resource',
      'chat',
      'message',
    };
    if (!kinds.contains(j['kind']) ||
        j['revision'] is! int ||
        (j['revision'] as int) < 1) {
      throw const FormatException('Invalid object kind or revision');
    }
    final data = Map<String, dynamic>.from(j['data'] as Map);
    for (final name in [
      'title',
      'body',
      'tags',
      'folder',
      'file',
      'hash',
      'documentId',
    ]) {
      if (data.containsKey(name) && data[name] is! String) {
        throw const FormatException('Invalid text field');
      }
    }
    final clock = data['_clock'];
    if (clock is! Map ||
        clock.values.any((value) => value is! int || value < 0)) {
      throw const FormatException('Invalid vector clock');
    }
    if (data['page'] != null &&
        (data['page'] is! int || (data['page'] as int) < 1)) {
      throw const FormatException('Invalid page');
    }
    final rectangles = data['rectangles'];
    if (rectangles != null) {
      if (rectangles is! List) {
        throw const FormatException('Invalid rectangles');
      }
      for (final r in rectangles) {
        if (r is! List ||
            r.length != 4 ||
            r.any((v) => v is! num || !v.isFinite) ||
            (r[0] as num) > (r[2] as num) ||
            (r[1] as num) < (r[3] as num)) {
          throw const FormatException('Invalid rectangle coordinates');
        }
      }
    }
    return WorkspaceObject(
      id: id,
      kind: j['kind'] as String,
      data: data,
      revision: j['revision'] as int,
      device: j['device'] as String,
      updated: DateTime.parse(j['updated'] as String),
      deleted: j['deleted'] == true,
    );
  }
  factory WorkspaceObject.fromRow(Map<String, dynamic> r) => WorkspaceObject(
    id: r['id'] as String,
    kind: r['kind'] as String,
    data: jsonDecode(r['payload'] as String) as Json,
    revision: r['revision'] as int,
    device: r['device'] as String,
    updated: DateTime.parse(r['updated'] as String),
    deleted: r['deleted'] == 1,
  );
}

class UserFacingException implements Exception {
  const UserFacingException(this.message);
  final String message;
  @override
  String toString() => message;
}
