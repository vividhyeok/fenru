import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/workspace.dart';

abstract interface class LmsProvider {
  Future<List<Json>> courses();
  Future<List<Json>> collection(String path);
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
  Future<List<Json>> courses() =>
      collection('/api/v1/courses?enrollment_state=active&per_page=100');
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
          if (e.response?.statusCode != 429 || attempt == 3) throw mapError(e);
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

  Future<void> importCourse(
    Workspace workspace,
    Json course,
    void Function(String) progress,
  ) async {
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
    final files = await collection(
      '/api/v1/courses/$courseId/files?per_page=100',
    );
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
        await http.downloadUri(
          url,
          p.join(tempDir.path, name),
          options: Options(
            headers: url.origin == base.origin
                ? {'Authorization': 'Bearer $token'}
                : {},
            followRedirects: false,
          ),
        );
        final imported = await workspace.importFile(
          p.join(tempDir.path, name),
          folder: local.title,
          origin: {'source': sourceKey, 'id': externalId, 'updated': modified},
        );
        if (previous.isNotEmpty) {
          await workspace.save('document', {
            ...imported.data,
            'previousVersion': previous.first.id,
          }, id: imported.id);
        }
      } on DioException catch (e) {
        throw mapError(e);
      } finally {
        await tempDir.delete(recursive: true);
      }
    }
    final assignments = await collection(
      '/api/v1/courses/$courseId/assignments?per_page=100',
    );
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
    }
  }

  static UserFacingException mapError(DioException e) =>
      UserFacingException(switch (e.response?.statusCode) {
        401 => 'Canvas 토큰이 만료되었거나 올바르지 않습니다. 설정에서 다시 입력하세요.',
        403 => '해당 자료에 접근 권한이 없습니다. 학교 Canvas에서 권한을 확인하세요.',
        404 => 'Canvas 주소 또는 자료를 찾을 수 없습니다.',
        429 => 'Canvas 요청 한도에 도달했습니다. 잠시 뒤 다시 시도하세요.',
        _ => 'Canvas 연결에 실패했습니다. 인터넷 연결과 학교 주소를 확인한 뒤 다시 시도하세요.',
      });
}
