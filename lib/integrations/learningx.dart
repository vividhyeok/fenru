import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../core/models.dart';

/// LearningX's module API uses its own short-lived token, not a Canvas PAT.
/// Obtain it through Canvas's signed LTI course-navigation launch. Never load
/// lecture-item viewers or submit progress/attendance/quiz endpoints.
class LearningXProvider {
  LearningXProvider(this.base, this.http, this.collection, this.object);
  final Uri base;
  final Dio http;
  final Future<List<Json>> Function(String) collection;
  final Future<Json> Function(String) object;
  final _cookies = <String, String>{};
  final warnings = <String>[];
  String? _token;

  Future<Response<String>> _school(Uri uri, {Json? form}) async {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.origin != base.origin ||
        uri.userInfo.isNotEmpty) {
      throw const UserFacingException('LearningX 인증 경로가 학교 주소와 일치하지 않습니다.');
    }
    final response = await http.requestUri<String>(
      uri,
      data: form,
      options: Options(
        method: form == null ? 'GET' : 'POST',
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 500,
        contentType: form == null ? null : Headers.formUrlEncodedContentType,
        headers: {
          if (_cookies.isNotEmpty)
            'Cookie': _cookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; '),
        },
      ),
    );
    for (final cookie in response.headers['set-cookie'] ?? <String>[]) {
      final pair = cookie.split(';').first;
      final split = pair.indexOf('=');
      if (split > 0) {
        _cookies[pair.substring(0, split).trim()] = pair.substring(split + 1);
      }
    }
    return response;
  }

  Future<void> authenticate(String courseId) async {
    if (_token != null) return;
    final tools = await collection(
      '/api/v1/courses/$courseId/external_tools?include_parents=true&per_page=100',
    );
    final tool = tools.where((t) {
      final uri = Uri.tryParse('${t['url']}');
      return uri?.scheme == 'https' &&
          uri?.host.isNotEmpty == true &&
          uri?.origin == base.origin &&
          uri?.path == '/learningx/lti/modulebuilder';
    }).firstOrNull;
    if (tool == null) {
      throw const UserFacingException('학교 LearningX의 주차별 학습 연결을 찾지 못했습니다.');
    }
    final query = Uri(
      queryParameters: {
        'id': '${tool['id']}',
        'launch_type': 'course_navigation',
      },
    ).query;
    final launch = await object(
      '/api/v1/courses/$courseId/external_tools/sessionless_launch?$query',
    );
    final uri = Uri.tryParse('${launch['url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.origin != base.origin ||
        uri.path != '/courses/$courseId/external_tools/sessionless_launch') {
      throw const UserFacingException('학교 LearningX 인증 응답의 경로가 올바르지 않습니다.');
    }
    final response = await _school(uri);
    if (response.statusCode != 200) {
      throw const UserFacingException('LearningX 연결을 시작하지 못했습니다.');
    }
    final page = html.parse(response.data ?? '');
    final forms = page
        .querySelectorAll('form')
        .where((f) => f.querySelector('input[name="oauth_signature"]') != null);
    if (forms.length != 1) {
      throw const UserFacingException('LearningX 인증 양식을 확인하지 못했습니다.');
    }
    final form = forms.single;
    final action = uri.resolve(form.attributes['action'] ?? '');
    if (action.scheme != 'https' ||
        action.host.isEmpty ||
        action.origin != base.origin ||
        action.path != '/learningx/lti/modulebuilder' ||
        (form.attributes['method'] ?? '').toLowerCase() != 'post') {
      throw const UserFacingException('허용되지 않은 LearningX 인증 양식입니다.');
    }
    final fields = <String, dynamic>{};
    for (final field in form.querySelectorAll('input[type="hidden"]')) {
      final name = field.attributes['name'];
      if (name != null) fields[name] = field.attributes['value'] ?? '';
    }
    final authenticated = await _school(action, form: fields);
    _token = _cookies['xn_api_token'];
    if (authenticated.statusCode != 200 || _token == null || _token!.isEmpty) {
      _token = null;
      throw const UserFacingException(
        '학교 LearningX 인증에 실패했습니다. Canvas 연결은 유지됩니다.',
      );
    }
  }

  Future<List<Json>> files(String courseId) async {
    await authenticate(courseId);
    final response = await http.getUri<dynamic>(
      base.resolve(
        '/learningx/api/v1/courses/$courseId/modules?include_detail=true',
      ),
      options: Options(
        followRedirects: false,
        headers: {'Authorization': 'Bearer $_token'},
      ),
    );
    final dynamic data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (data is! List) {
      throw const UserFacingException('LearningX 주차별 학습 응답을 읽지 못했습니다.');
    }
    final files = <String, Json>{};
    for (final module in data.whereType<Map>()) {
      for (final item
          in (module['module_items'] as List? ?? []).whereType<Map>()) {
        if (item['published'] == false) continue;
        if (item['content_type'] == 'attachment') {
          final id = '${item['content_id']}';
          if (!RegExp(r'^\d+$').hasMatch(id)) continue;
          try {
            files['canvas:$id'] = {
              ...await object('/api/v1/files/$id'),
              '_locations': [
                '주차 학습 · ${module['title'] ?? module['name'] ?? ''}',
              ],
            };
          } on UserFacingException {
            warnings.add('LearningX 첨부자료 한 개의 파일 정보에 접근할 수 없습니다.');
          }
          continue;
        }
        final content = item['content_data'];
        if (content is! Map) continue;
        final detail = content['item_content_data'];
        if (detail is! Map ||
            ![
              'pdf',
              'document',
              'file',
              'ppt',
              'doc',
              'hwp',
              'docx',
              'pptx',
              'hwpx',
            ].contains(detail['content_type'])) {
          continue;
        }
        var view = Uri.tryParse('${detail['view_url'] ?? ''}');
        final contentId = detail['content_id'];
        if ((detail['view_url'] == null || '${detail['view_url']}'.isEmpty) &&
            base.host == 'canvas.jejunu.ac.kr' &&
            contentId is String &&
            RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(contentId)) {
          view = Uri.https('common.jejunu.ac.kr', '/em/$contentId');
        }
        // The current Jeju Commons integration is deliberately exact-origin.
        // Other institutions need their own validated Commons host mapping.
        if (base.host != 'canvas.jejunu.ac.kr' ||
            view?.host != 'common.jejunu.ac.kr' ||
            !['https', 'http'].contains(view?.scheme) ||
            view?.userInfo.isNotEmpty == true) {
          warnings.add('지원하지 않는 LearningX 문서 저장소 주소입니다.');
          continue;
        }
        if (view!.scheme == 'http') view = view.replace(scheme: 'https');
        final slug = view.pathSegments.lastOrNull ?? '';
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(slug)) continue;
        final metadata = view.replace(
          path: '/viewer/ssplayer/uniplayer_support/content.php',
          queryParameters: {'content_id': slug},
          fragment: '',
        );
        try {
          // No Canvas PAT, LearningX token, or school cookies go to Commons.
          final result = await http.getUri<String>(
            metadata,
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: false,
            ),
          );
          final document = XmlDocument.parse(result.data ?? '');
          final download = document
              .findAllElements('content_download_uri')
              .firstOrNull
              ?.innerText
              .trim();
          if (download == null || download.isEmpty) {
            warnings.add('LearningX 문서 한 개에 다운로드 주소가 없습니다.');
            continue;
          }
          var downloadUri = view.resolve(download);
          if (downloadUri.host == view.host && downloadUri.scheme == 'http') {
            downloadUri = downloadUri.replace(scheme: 'https');
          }
          if (downloadUri.scheme != 'https' ||
              downloadUri.host.isEmpty ||
              downloadUri.origin != view.origin ||
              downloadUri.userInfo.isNotEmpty) {
            warnings.add('LearningX 문서의 다운로드 주소가 저장소와 일치하지 않습니다.');
            continue;
          }
          final id = 'learningx:$slug';
          files[id] = {
            'id': id,
            'display_name':
                detail['file_name'] ??
                detail['title'] ??
                item['title'] ??
                '$slug.pdf',
            'updated_at': detail['updated_at'] ?? content['updated_at'],
            'url': downloadUri.toString(),
            '_locations': [
              '주차 학습 · ${module['title'] ?? module['name'] ?? ''}',
            ],
          };
        } on DioException catch (e) {
          if (![401, 403, 404].contains(e.response?.statusCode)) rethrow;
          warnings.add('LearningX 문서 한 개의 저장소에 접근할 수 없습니다.');
        } on XmlParserException {
          warnings.add('LearningX 문서 한 개의 다운로드 정보를 읽지 못했습니다.');
        }
      }
    }
    return files.values.toList();
  }
}
