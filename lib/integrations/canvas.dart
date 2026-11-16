import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:html/parser.dart' as html;

import '../core/models.dart';
import '../core/workspace.dart';
import 'pdf_conversion.dart';
import 'learningx.dart';

abstract interface class LmsProvider {
  Future<List<Json>> courses();
  Future<List<Json>> collection(String path);
}

class CanvasRequestException extends UserFacingException {
  const CanvasRequestException(
    super.message,
    this.statusCode, {
    this.authenticationFailed = false,
  });
  final int? statusCode;
  final bool authenticationFailed;
  bool get restricted =>
      [401, 403, 404].contains(statusCode) && !authenticationFailed;
}

class CanvasImportReport {
  int imported = 0,
      unchanged = 0,
      assignments = 0,
      skipped = 0,
      contentSaved = 0;
  final contents = <String, Json>{};
  final warnings = <String>[];
  String get summary =>
      '파일 $imported개 저장 · 기존 $unchanged개 · 과제 $assignments개 · 공지/본문 $contentSaved개 · 건너뜀 $skipped개';
}

class CanvasSyncSelection {
  CanvasSyncSelection(this.workspace, this.base);
  final Workspace workspace;
  final Uri base;
  String get key => 'canvas.courseIds.${base.host}';
  Set<String> read() {
    if (workspace.preferences.containsKey(key)) {
      try {
        return (jsonDecode(workspace.preferences[key]!) as List)
            .cast<String>()
            .toSet();
      } catch (_) {
        return {};
      }
    }
    return workspace
        .ofKind('course')
        .where((c) => c.text('source').startsWith('${base.origin}/courses/'))
        .map((c) => c.text('externalId'))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> save(Iterable<Json> courses) => workspace.setPreference(
    key,
    jsonEncode(courses.map((c) => '${c['id']}').toList()),
  );
}

class CanvasProvider implements LmsProvider {
  CanvasProvider(String url, this.token, {Dio? client})
    : base = validateUrl(url),
      http =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );
  final Uri base;
  final String token;
  final Dio http;
  bool _authenticated = false;
  LearningXProvider? _learningX;

  Future<CanvasRequestException> requestError(
    DioException e,
    String operation,
  ) async {
    final code = e.response?.statusCode;
    if (code == 401 && _authenticated) {
      // Canvas also returns 401 for course-level permissions. Recheck an
      // endpoint already known to work before asking the user for another key.
      try {
        final probe = await http.getUri<dynamic>(
          base.resolve('/api/v1/courses?per_page=1'),
          options: Options(
            followRedirects: false,
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        if (probe.data is List) {
          return CanvasRequestException(
            '$operation: 토큰은 유효하지만 이 항목의 접근 권한이 없습니다 (HTTP 401).',
            401,
          );
        }
      } on DioException catch (probe) {
        if (probe.response?.statusCode != 401) {
          return CanvasRequestException(
            '$operation: 접근 여부를 확인하지 못했습니다. 연결 또는 학교 권한을 확인하세요 (HTTP 401).',
            401,
          );
        }
      }
    }
    return CanvasRequestException(
      '$operation: ${mapError(e).message}',
      code,
      authenticationFailed: code == 401,
    );
  }

  Future<Json> object(String path) async {
    final uri = base.resolve(path);
    if (uri.origin != base.origin) {
      throw const UserFacingException('외부 Canvas API 주소는 사용할 수 없습니다.');
    }
    try {
      final response = await http.getUri<dynamic>(
        uri,
        options: Options(
          followRedirects: false,
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      if (response.data is! Map) {
        throw const UserFacingException(
          'Canvas가 JSON 자료 대신 로그인 화면 또는 잘못된 응답을 반환했습니다.',
        );
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw await requestError(e, '자료 정보 조회');
    }
  }

  static Uri validateUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const UserFacingException(
        'Canvas의 HTTPS 기본 주소를 입력하세요. 예: https://school.instructure.com',
      );
    }
    return uri;
  }

  @override
  Future<List<Json>> courses() async {
    final result = await collection(
      '/api/v1/courses?enrollment_state=active&per_page=100&include[]=syllabus_body',
    );
    _authenticated = true;
    return result;
  }

  @override
  Future<List<Json>> collection(String path) async {
    Uri? next = base.resolve(path);
    final seen = <String>{};
    final result = <Json>[];
    while (next != null) {
      if (next.origin != base.origin || !seen.add(next.toString())) {
        throw const UserFacingException('Canvas 페이지 링크가 안전하지 않거나 반복됩니다.');
      }
      Response<dynamic>? response;
      for (int attempt = 0; attempt < 4; attempt++) {
        try {
          response = await http.getUri(
            next,
            options: Options(
              followRedirects: false,
              headers: {'Authorization': 'Bearer $token'},
            ),
          );
          break;
        } on DioException catch (e) {
          if (e.response?.statusCode != 429 || attempt == 3) {
            throw await requestError(e, '목록 조회');
          }
          final seconds =
              int.tryParse(e.response?.headers.value('retry-after') ?? '') ??
              (1 << attempt);
          await Future<void>.delayed(Duration(seconds: seconds.clamp(1, 30)));
        }
      }
      if (response?.data is! List) {
        throw const UserFacingException('Canvas 응답 형식이 올바르지 않습니다.');
      }
      result.addAll(
        (response!.data as List).map(
          (j) => Map<String, dynamic>.from(j as Map),
        ),
      );
      final match = RegExp(r'<([^>]+)>;\s*rel="next"')
          .firstMatch(response.headers.value('link') ?? '');
      next = match == null ? null : base.resolve(match.group(1)!);
    }
    return result;
  }

  Future<String?> downloadFile(Uri initial, String destination) async {
    var current = initial;
    final visited = <String>{};
    for (int hop = 0; hop < 6; hop++) {
      if (current.scheme != 'https' ||
          current.userInfo.isNotEmpty ||
          !visited.add(current.toString())) {
        throw const UserFacingException('안전하지 않거나 반복되는 파일 다운로드 경로입니다.');
      }
      final response = await http.downloadUri(
        current,
        destination,
        options: Options(
          headers: current.origin == base.origin
              ? {'Authorization': 'Bearer $token'}
              : {},
          followRedirects: false,
          validateStatus: (status) =>
              status != null &&
              (status >= 200 && status < 300 ||
                  [301, 302, 303, 307, 308].contains(status)),
        ),
      );
      if ((response.statusCode ?? 0) < 300) {
        if ((response.headers.value('content-type') ?? '').contains(
          'text/html',
        )) {
          final bytes = await File(destination)
              .openRead(0, 512)
              .fold<List<int>>([], (all, part) => all..addAll(part));
          final start = utf8.decode(bytes, allowMalformed: true);
          if (RegExp(
                r'<(?:!doctype\s+html|html)',
                caseSensitive: false,
              ).hasMatch(start) &&
              (response.headers.value('content-disposition') ?? '').isEmpty) {
            throw const CanvasRequestException(
              '파일 대신 로그인/웹 화면이 반환되었습니다. Canvas에서 자료 접근 권한을 확인하세요.',
              403,
            );
          }
        }
        final disposition = response.headers.value('content-disposition') ?? '';
        final encoded = RegExp(
          r"filename\*\s*=\s*UTF-8''([^;]+)",
          caseSensitive: false,
        ).firstMatch(disposition)?.group(1);
        if (encoded != null) {
          try {
            return Uri.decodeComponent(encoded).trim();
          } on FormatException {
            /* Fall back to the plain filename. */
          }
        }
        return RegExp(
              r'filename\s*=\s*"([^"]+)"',
              caseSensitive: false,
            ).firstMatch(disposition)?.group(1) ??
            RegExp(
              r'filename\s*=\s*([^;\s]+)',
              caseSensitive: false,
            ).firstMatch(disposition)?.group(1);
      }
      final location = response.headers.value('location');
      if (location == null) {
        throw const UserFacingException('Canvas 파일의 다음 다운로드 주소가 없습니다.');
      }
      current = current.resolve(location);
    }
    throw const UserFacingException('파일 다운로드 경로가 너무 많이 변경되었습니다. 다시 시도하세요.');
  }

  Future<CanvasImportReport> importCourse(
    Workspace workspace,
    Json course,
    void Function(String) progress,
  ) async {
    final report = CanvasImportReport();
    final courseId = '${course['id']}';
    final sourceKey = '${base.origin}/courses/$courseId';
    final existing = workspace
        .ofKind('course')
        .where((c) => c.text('source') == sourceKey)
        .firstOrNull;
    final local = await workspace.save('course', {
      'title': course['name'] ?? course['course_code'] ?? courseId,
      'source': sourceKey,
      'externalId': courseId,
    }, id: existing?.id);
    if (course['syllabus_body'] is String &&
        (course['syllabus_body'] as String).trim().isNotEmpty) {
      report.contents['syllabus'] = {
        'title': '강의계획 · ${local.title}',
        'body': html.parse(course['syllabus_body'] as String).body?.text ?? '',
        'url': base
            .resolve('/courses/$courseId/assignments/syllabus')
            .toString(),
        'posted': '',
        'updated': '',
        'contentType': '강의계획',
      };
    }
    final files = await discoverFiles(courseId, report, progress);
    progress('발견한 공지와 강의 본문을 저장합니다…');
    await saveCourseContents(workspace, local, report);
    progress('문서 후보 ${files.length}개 · 저장 시작');
    for (final (index, file) in files.indexed) {
      final externalId = '${file['id']}', modified = '${file['updated_at']}';
      final previous = workspace.ofKind('document').where((d) {
        final origin = d.data['origin'];
        return origin is Map &&
            origin['source'] == sourceKey &&
            origin['id'] == externalId;
      }).toList();
      if (previous.any(
        (d) => (d.data['origin'] as Map)['updated'] == modified,
      )) {
        report.unchanged++;
        continue;
      }
      final name = p.basename('${file['display_name'] ?? file['filename']}');
      progress('저장 ${index + 1}/${files.length} · $name');
      final url = Uri.tryParse('${file['url']}');
      if (url == null || url.scheme != 'https') {
        throw const UserFacingException('안전하지 않은 다운로드 주소입니다.');
      }
      final tempDir = await Directory.systemTemp.createTemp('fenru-canvas-');
      try {
        final transfer = p.join(tempDir.path, 'transfer.bin');
        final downloadName = await downloadFile(url, transfer);
        var displayName = name;
        if (file['_moduleFallback'] == true && downloadName != null) {
          displayName = p.basename(downloadName.replaceAll('\\', '/'));
        } else if (p.extension(displayName).isEmpty) {
          if (downloadName != null && p.extension(downloadName).isNotEmpty) {
            displayName = p.basename(downloadName.replaceAll('\\', '/'));
          }
          final header = await File(transfer)
              .openRead(0, 5)
              .fold<List<int>>([], (all, part) => all..addAll(part));
          if (ascii.decode(header, allowInvalid: true) == '%PDF-') {
            displayName = '$displayName.pdf';
          }
        }
        final expectedSize = file['size'];
        if (expectedSize is int &&
            expectedSize >= 0 &&
            await File(transfer).length() != expectedSize) {
          throw const UserFacingException(
            'Canvas 파일 크기가 원본 정보와 다릅니다. 가져오기를 중단했습니다.',
          );
        }
        final imported = await importStudyFile(
          workspace,
          transfer,
          folder: local.title,
          displayName: displayName,
          origin: {
            'source': sourceKey,
            'id': externalId,
            'updated': modified,
            'locations': file['_locations'] ?? [],
          },
        );
        if (imported.text('conversionStatus') == 'failed') {
          report.warnings.add(
            '$displayName: 원본 저장 완료, ${imported.text('conversionError')}',
          );
        }
        await workspace.save('document', {
          ...imported.data,
          'syncedAt': DateTime.now().toUtc().toIso8601String(),
          if (previous.isNotEmpty) 'previousVersion': previous.first.id,
        }, id: imported.id);
        report.imported++;
      } on DioException catch (e) {
        final error = await requestError(e, '파일 다운로드');
        if (!error.restricted) throw error;
        report.skipped++;
        report.warnings.add('$name: ${error.message}');
      } on CanvasRequestException catch (e) {
        if (!e.restricted) rethrow;
        report.skipped++;
        report.warnings.add('$name: ${e.message}');
      } finally {
        await tempDir.delete(recursive: true);
      }
    }
    progress('과목의 과제 일정을 가져옵니다…');
    List<Json> assignments = [];
    try {
      assignments = await collection(
        '/api/v1/courses/$courseId/assignments?per_page=100',
      );
    } on CanvasRequestException catch (e) {
      if (!e.restricted) rethrow;
      report.warnings.add('과제 ${e.message}');
    }
    for (final item in assignments) {
      final key = '$sourceKey/assignments/${item['id']}';
      final old = workspace
          .ofKind('task')
          .where((t) => t.text('source') == key)
          .firstOrNull;
      await workspace.save('task', {
        'title': item['name'] ?? '',
        'course': local.title,
        'due': item['due_at'] ?? '',
        'body': item['description'] ?? '',
        'url': item['html_url'] ?? '',
        'source': key,
        'done': old?.flag('done') ?? false,
      }, id: old?.id);
      report.assignments++;
    }
    return report;
  }

  Future<void> saveCourseContents(
    Workspace workspace,
    WorkspaceObject course,
    CanvasImportReport report,
  ) async {
    for (final entry in report.contents.entries) {
      final item = entry.value;
      final body =
          '${item['title']}\n게시: ${item['posted']}\n수정: ${item['updated']}\n원문: ${item['url']}\n\n${item['body']}';
      final digest = sha256.convert(utf8.encode(body)).toString();
      final externalId = 'content:${entry.key}';
      final previous = workspace.ofKind('document').where((d) {
        final origin = d.data['origin'];
        return d.text('derivedFrom').isEmpty &&
            origin is Map &&
            origin['source'] == course.text('source') &&
            origin['id'] == externalId;
      }).firstOrNull;
      if (previous?.text('hash') == digest) {
        if (previous != null &&
            workspace.byId(previous.text('pdfDocumentId'))?.deleted != false) {
          await convertCourseContent(workspace, previous, report);
        }
        report.unchanged++;
        continue;
      }
      final temporary = await Directory.systemTemp.createTemp('fenru-content-');
      try {
        final file = File(p.join(temporary.path, 'content.txt'));
        await file.writeAsString(body);
        final imported = await workspace.importFile(
          file.path,
          folder: course.title,
          displayName: '${item['title']}.txt',
          origin: {
            'source': course.text('source'),
            'id': externalId,
            'updated': item['updated'],
          },
        );
        final content = await workspace.save('document', {
          ...imported.data,
          'title': item['title'],
          'contentType': item['contentType'],
          'syncedAt': DateTime.now().toUtc().toIso8601String(),
          'courseId': course.id,
          'sourceUrl': item['url'],
          'posted': item['posted'],
          if (previous != null) 'previousVersion': previous.id,
        }, id: imported.id);
        await convertCourseContent(workspace, content, report);
        report.contentSaved++;
      } finally {
        await temporary.delete(recursive: true);
      }
    }
  }

  Future<void> convertCourseContent(
    Workspace workspace,
    WorkspaceObject content,
    CanvasImportReport report,
  ) async {
    try {
      await PdfConversion(workspace).convert(content);
    } on UserFacingException catch (error) {
      report.warnings.add('${content.title}: ${error.message}');
    }
  }

  Future<List<Json>> discoverFiles(
    String courseId,
    CanvasImportReport report,
    void Function(String) progress,
  ) async {
    final files = <String, Json>{};
    final modulePages = <String, Set<String>>{};
    var hasLearningX = false;
    void add(Json file, String location) {
      final id = '${file['id']}';
      if (RegExp(r'^(\d+|learningx:[a-zA-Z0-9_-]+)$').hasMatch(id)) {
        final found = files.putIfAbsent(id, () => file);
        final locations = <String>{
          ...(found['_locations'] as List? ?? []).map((value) => '$value'),
        };
        if (locations.add(location)) {
          found['_locations'] = locations.toList();
          progress(
            '발견 · $location · ${found['display_name'] ?? found['filename'] ?? id}',
          );
        }
      }
    }

    progress('과목 파일 목록을 확인하고 있습니다…');
    try {
      for (final file in await collection(
        '/api/v1/courses/$courseId/files?per_page=100',
      )) {
        add(file, '과목 파일');
      }
    } on CanvasRequestException catch (e) {
      if (!e.restricted) rethrow;
      report.warnings.add('파일 목록 접근 제한: 모듈에 공개된 자료를 확인했습니다.');
    }
    // Many schools hide the Files tab but publish individual files in Modules.
    // Fetch items separately: include[]=items can be truncated by Canvas.
    progress('주차별 모듈에서 공개된 파일을 찾고 있습니다…');
    try {
      final modules = await collection(
        '/api/v1/courses/$courseId/modules?per_page=100',
      );
      for (final module in modules) {
        final moduleId = '${module['id']}';
        if (!RegExp(r'^\d+$').hasMatch(moduleId)) continue;
        final location = '모듈 · ${module['name'] ?? moduleId}';
        progress('탐색 · $location');
        List<Json> items;
        try {
          items = await collection(
            '/api/v1/courses/$courseId/modules/$moduleId/items?per_page=100',
          );
        } on CanvasRequestException catch (e) {
          if (!e.restricted) rethrow;
          report.warnings.add('${module['name'] ?? '모듈'}: 접근할 수 없습니다.');
          continue;
        }
        for (final item in items) {
          if (item['type'] == 'Page' && item['page_url'] is String) {
            modulePages
                .putIfAbsent(item['page_url'] as String, () => <String>{})
                .add(location);
          }
          final external = Uri.tryParse('${item['external_url']}');
          if (item['type'] == 'ExternalTool' &&
              external?.scheme == 'https' &&
              external?.host.isNotEmpty == true &&
              external?.origin == base.origin &&
              external?.path.startsWith('/learningx/') == true) {
            hasLearningX = true;
          }
          if (item['type'] != 'File') continue;
          final id = '${item['content_id']}';
          if (!RegExp(r'^\d+$').hasMatch(id)) continue;
          final known = files[id];
          if (known != null) {
            add(known, location);
            continue;
          }
          try {
            add(await object('/api/v1/courses/$courseId/files/$id'), location);
          } on CanvasRequestException catch (e) {
            if (!e.restricted) rethrow;
            // The course file list/metadata may be hidden while a published
            // module download is still permitted. The server decides access.
            add({
              'id': id,
              'display_name': item['title'] ?? 'file_$id',
              'url': base
                  .resolve('/courses/$courseId/files/$id/download')
                  .toString(),
              '_moduleFallback': true,
            }, location);
          }
        }
      }
    } on CanvasRequestException catch (e) {
      if (!e.restricted) rethrow;
      report.warnings.add('모듈 목록에 접근할 수 없습니다. 공개 파일 목록의 자료만 처리했습니다.');
    }
    if (hasLearningX) {
      progress('학교 LearningX 주차별 문서와 첨부자료를 확인하고 있습니다…');
      try {
        final provider = _learningX ??= LearningXProvider(
          base,
          http,
          collection,
          object,
        );
        provider.warnings.clear();
        for (final file in await provider.files(courseId)) {
          add(file, 'LearningX');
        }
        report.warnings.addAll(provider.warnings);
      } on CanvasRequestException catch (e) {
        if (e.authenticationFailed) rethrow;
        report.warnings.add('LearningX 연결 제한: ${e.message}');
      } on UserFacingException catch (e) {
        report.warnings.add(e.message);
      } on DioException {
        report.warnings.add(
          '학교 LearningX 자료 조회에 실패했습니다. Canvas 토큰 만료와는 별개이며, 잠시 후 다시 시도하세요.',
        );
      }
    }
    await discoverContentAttachments(
      courseId,
      files,
      modulePages,
      report,
      progress,
    );
    return files.values.toList();
  }

  Future<void> discoverContentAttachments(
    String courseId,
    Map<String, Json> files,
    Map<String, Set<String>> modulePages,
    CanvasImportReport report,
    void Function(String) progress,
  ) async {
    progress('페이지 · 게시판 · 공지 · 과제의 첨부자료를 확인하고 있습니다…');
    final attempted = <String>{...files.keys};
    Future<List<Json>> list(String path, String name) async {
      progress('탐색 · $name');
      try {
        return await collection(path);
      } on CanvasRequestException catch (e) {
        if (e.authenticationFailed) rethrow;
        report.warnings.add('$name: 목록에 접근할 수 없어 건너뛰었습니다.');
        return [];
      }
    }

    Future<void> link(String raw, String title, String location) async {
      final parsed = Uri.tryParse(raw);
      if (parsed == null) return;
      final uri = base.resolveUri(parsed);
      if (uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.origin != base.origin ||
          uri.userInfo.isNotEmpty) {
        return;
      }
      final match = RegExp(
        r'(?:^|/)(?:api/v1/)?(?:courses/\d+/)?files/(\d+)(?:/|$)',
      ).firstMatch(uri.path);
      if (match == null) return;
      final id = match.group(1)!;
      if (files.containsKey(id)) {
        final file = files[id]!;
        final places = (file['_locations'] as List? ?? [])
            .map((v) => '$v')
            .toSet();
        if (places.add(location)) {
          file['_locations'] = places.toList();
          progress('발견 · $location · ${file['display_name'] ?? title}');
        }
        return;
      }
      if (!attempted.add(id)) return;
      Json file;
      try {
        file = await object('/api/v1/courses/$courseId/files/$id');
      } on CanvasRequestException catch (e) {
        if (e.authenticationFailed) rethrow;
        file = {
          'id': id,
          'display_name': title.trim().isEmpty ? 'file_$id' : title.trim(),
          'url': base
              .resolve('/courses/$courseId/files/$id/download')
              .toString(),
          '_moduleFallback': true,
        };
      }
      files[id] = {
        ...file,
        '_locations': [location],
      };
      progress('발견 · $location · ${file['display_name'] ?? title}');
    }

    Future<void> content(
      dynamic value,
      String location, [
      String sourceId = '',
      Iterable<String> additionalLocations = const [],
    ]) async {
      if (value is List) {
        for (final item in value) {
          await content(
            item,
            location,
            '$sourceId/${item is Map ? item['id'] ?? '' : ''}',
          );
        }
        return;
      }
      if (value is! Map) return;
      final textParts = <String>[];
      for (final key in ['body', 'message', 'description']) {
        if (value[key] is! String) continue;
        final doc = html.parse(
          (value[key] as String).replaceAll(
            RegExp(
              r'</(?:p|div|li|h[1-6]|tr)>|<br\s*/?>',
              caseSensitive: false,
            ),
            '\n',
          ),
        );
        final plain = doc.body?.text.trim() ?? '';
        if (plain.isNotEmpty) textParts.add(plain);
        for (final element in doc.querySelectorAll(
          '[href], [data-api-endpoint], [src]',
        )) {
          final links = {
            element.attributes['data-api-endpoint'],
            element.attributes['href'],
            element.attributes['src'],
          }.whereType<String>();
          for (final raw in links) {
            await link(raw, element.text, location);
            for (final place in additionalLocations) {
              await link(raw, element.text, place);
            }
          }
        }
      }
      if (textParts.isNotEmpty && sourceId.isNotEmpty) {
        report.contents[sourceId] = {
          'title': location,
          'body': textParts.join('\n\n'),
          'url': value['html_url'] ?? '',
          'posted': value['posted_at'] ?? value['created_at'] ?? '',
          'updated': value['updated_at'] ?? '',
          'contentType': location.split(' · ').first,
        };
      }
      if (value['url'] is String) {
        await link(
          value['url'] as String,
          '${value['display_name'] ?? value['filename'] ?? ''}',
          location,
        );
      }
      for (final key in [
        'attachments',
        'attachment',
        'view',
        'replies',
        'entries',
      ]) {
        if (value[key] != null) {
          if (key == 'attachment' || key == 'attachments') {
            final attachments = value[key];
            for (final attachment
                in (attachments is List ? attachments : [attachments])
                    .whereType<Map>()) {
              final id = '${attachment['id'] ?? attachment['file_id'] ?? ''}';
              if (RegExp(r'^\d+$').hasMatch(id)) {
                await link(
                  '/api/v1/courses/$courseId/files/$id',
                  '${attachment['display_name'] ?? attachment['filename'] ?? ''}',
                  location,
                );
              }
            }
          }
          await content(value[key], location, '$sourceId/$key');
        }
      }
    }

    final pages = await list(
      '/api/v1/courses/$courseId/pages?include[]=body&per_page=100',
      '페이지',
    );
    final seenPages = <String>{};
    Future<void> page(Json item) async {
      final slug = '${item['url'] ?? ''}';
      if (slug.isEmpty || !seenPages.add(slug)) return;
      try {
        final detail = item['body'] is String
            ? item
            : await object(
                '/api/v1/courses/$courseId/pages/${Uri.encodeComponent(slug)}',
              );
        await content(
          detail,
          '페이지 · ${detail['title'] ?? slug}',
          'page:$slug',
          modulePages[slug] ?? const [],
        );
      } on CanvasRequestException catch (e) {
        if (e.authenticationFailed) rethrow;
        report.warnings.add('페이지 $slug: 접근할 수 없습니다.');
      }
    }

    for (final item in pages) {
      await page(item);
    }
    for (final slug in modulePages.keys) {
      await page({'url': slug});
    }
    for (final announcements in [false, true]) {
      final topics = await list(
        '/api/v1/courses/$courseId/discussion_topics?per_page=100${announcements ? '&only_announcements=true' : ''}',
        announcements ? '공지' : '게시판',
      );
      for (final topic in topics) {
        final location =
            '${announcements ? '공지' : '게시판'} · ${topic['title'] ?? ''}';
        await content(topic, location, 'topic:${topic['id']}');
        final id = '${topic['id']}';
        if (!announcements &&
            topic['user_can_see_posts'] != false &&
            RegExp(r'^\d+$').hasMatch(id)) {
          try {
            await content(
              await object(
                '/api/v1/courses/$courseId/discussion_topics/$id/view',
              ),
              location,
              'topic:$id/replies',
            );
          } on CanvasRequestException catch (e) {
            if (e.authenticationFailed) rethrow;
            report.warnings.add('$location: 답글 첨부자료에 접근할 수 없습니다.');
          }
        }
      }
    }
    for (final item in await list(
      '/api/v1/courses/$courseId/assignments?per_page=100',
      '과제 첨부자료',
    )) {
      await content(
        item,
        '과제 · ${item['name'] ?? ''}',
        'assignment:${item['id']}',
      );
    }
  }

  static UserFacingException mapError(DioException e) => UserFacingException(
    switch (e.response?.statusCode) {
      401 => 'Canvas 인증을 확인할 수 없습니다 (HTTP 401). 토큰·주소 또는 학교의 API 접근 정책을 확인하세요.',
      403 => '해당 자료에 접근 권한이 없습니다. 학교 Canvas에서 권한을 확인하세요.',
      404 => 'Canvas 주소 또는 자료를 찾을 수 없습니다.',
      429 => 'Canvas 요청 한도에 도달했습니다. 잠시 뒤 다시 시도하세요.',
      _ => 'Canvas 연결에 실패했습니다. 인터넷 연결과 학교 주소를 확인한 뒤 다시 시도하세요.',
    },
  );
}
