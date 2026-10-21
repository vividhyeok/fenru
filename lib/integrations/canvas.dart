import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/workspace.dart';
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
  int imported = 0, unchanged = 0, assignments = 0, skipped = 0;
  final warnings = <String>[];
  String get summary =>
      '파일 $imported개 저장 · 기존 $unchanged개 · 과제 $assignments개 · 건너뜀 $skipped개';
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
      '/api/v1/courses?enrollment_state=active&per_page=100',
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
    final files = await discoverFiles(courseId, report, progress);
    for (final file in files) {
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
      progress('가져오는 중: $name');
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
        final imported = await workspace.importFile(
          transfer,
          folder: local.title,
          displayName: displayName,
          origin: {'source': sourceKey, 'id': externalId, 'updated': modified},
        );
        if (previous.isNotEmpty) {
          await workspace.save('document', {
            ...imported.data,
            'previousVersion': previous.first.id,
          }, id: imported.id);
        }
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

  Future<List<Json>> discoverFiles(
    String courseId,
    CanvasImportReport report,
    void Function(String) progress,
  ) async {
    final files = <String, Json>{};
    var hasLearningX = false;
    void add(Json file) {
      final id = '${file['id']}';
      if (RegExp(r'^(\d+|learningx:[a-zA-Z0-9_-]+)$').hasMatch(id)) {
        files.putIfAbsent(id, () => file);
      }
    }

    progress('과목 파일 목록을 확인하고 있습니다…');
    try {
      for (final file in await collection(
        '/api/v1/courses/$courseId/files?per_page=100',
      )) {
        add(file);
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
          if (!RegExp(r'^\d+$').hasMatch(id) || files.containsKey(id)) continue;
          try {
            add(await object('/api/v1/courses/$courseId/files/$id'));
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
            });
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
          add(file);
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
    return files.values.toList();
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
