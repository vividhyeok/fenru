import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/integrations/canvas.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/ai/study_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('remembered sync courses migrate existing courses and stay isolated by school', () async {
    final root = await Directory.systemTemp.createTemp('fenru-sync-selection-');
    final w = Workspace(root, WorkspaceDatabase.memory());
    await w.initialize();
    try {
      await w.save('course', {
        'title': 'Biology',
        'source': 'https://school.edu/courses/7',
        'externalId': '7',
      });
      final selection = CanvasSyncSelection(w, Uri.parse('https://school.edu'));
      expect(selection.read(), {'7'});
      await selection.save([
        {'id': 7},
        {'id': 9},
      ]);
      expect(CanvasSyncSelection(w, Uri.parse('https://school.edu')).read(), {
        '7',
        '9',
      });
      expect(
        CanvasSyncSelection(w, Uri.parse('https://other.edu')).read(),
        isEmpty,
      );
    } finally {
      await w.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'announcement bodies persist, deduplicate, update and join course evidence',
    () async {
      final root = await Directory.systemTemp.createTemp('fenru-content-');
      final w = Workspace(root, WorkspaceDatabase.memory());
      await w.initialize();
      try {
        final course = await w.save('course', {
          'title': 'Biology',
          'source': 'https://school.edu/courses/1',
        });
        final provider = CanvasProvider('https://school.edu', 'fake');
        CanvasImportReport report(String body) => CanvasImportReport()
          ..contents['topic:4'] = {
            'title': '공지 · 기말시험',
            'body': body,
            'url': 'https://school.edu/courses/1/discussion_topics/4',
            'posted': '2026-11-04',
            'updated': '',
            'contentType': '공지',
          };
        final first = report('시험 범위는 세포 호흡');
        await provider.saveCourseContents(w, course, first);
        expect(first.contentSaved, 1);
        final same = report('시험 범위는 세포 호흡');
        await provider.saveCourseContents(w, course, same);
        expect(same.unchanged, 1);
        expect(w.ofKind('document').length, 2);
        await provider.saveCourseContents(w, course, report('시험 범위는 광합성'));
        final docs = StudyContextService.courseDocuments(w, course);
        expect(docs.length, 1);
        expect(docs.single.text('extension'), '.pdf');
        expect(docs.single.text('sourceUrl'), contains('discussion_topics/4'));
        expect(
          (await StudyContextService(w).pages(docs.single)).single,
          contains('광합성'),
        );
        final source = File('${root.path}/lecture.txt');
        await source.writeAsString('광합성은 빛 에너지를 화학 에너지로 전환한다.');
        await w.importFile(source.path, folder: course.title);
        final context = await StudyContextService(w).retrieve(
          StudyContextService.courseDocuments(w, course),
          '시험 나올 거 짚어 줘',
        );
        expect(context.excerpts.any((e) => e.title.startsWith('공지')), isTrue);
        expect(context.excerpts.any((e) => e.title == 'lecture.txt'), isTrue);
      } finally {
        await w.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('discovers page, module page, discussion reply, announcement and assignment attachments', () async {
    ResponseBody json(Object data) => ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
    final requested = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((r) {
        requested.add(r.uri.host);
        final path = r.uri.path;
        if (path == '/api/v1/courses/1/files') return json([]);
        if (path == '/api/v1/courses/1/modules') {
          return json([
            {'id': 2},
          ]);
        }
        if (path == '/api/v1/courses/1/modules/2/items') {
          return json([
            {'type': 'Page', 'page_url': 'week-1'},
          ]);
        }
        if (path == '/api/v1/courses/1/pages') {
          return json([
            {
              'url': 'intro',
              'title': 'Intro',
              'body': '<a href="/courses/1/files/10/download">A.pdf</a><a href="https://evil.test/files/99">private</a>',
            },
          ]);
        }
        if (path == '/api/v1/courses/1/pages/week-1') {
          return json({
            'title': 'Week 1',
            'body': '<a data-api-endpoint="https://school.edu/api/v1/files/11" href="#">B.docx</a>',
          });
        }
        if (path == '/api/v1/courses/1/discussion_topics') {
          if (r.uri.queryParameters['only_announcements'] == 'true') {
            return json([
              {
                'id': 4,
                'title': 'Notice',
                'message': '<p>기말 시험 범위는 세포 호흡입니다.</p>',
                'posted_at': '2026-11-04T01:00:00Z',
                'attachments': [
                  {'url': '/courses/1/files/13/download', 'filename': 'D.pptx'},
                ],
              },
            ]);
          }
          return json([
            {
              'id': 3,
              'title': 'Board',
              'message': '<a href="/courses/1/files/10">duplicate</a>',
            },
          ]);
        }
        if (path == '/api/v1/courses/1/discussion_topics/3/view') {
          return json({
            'view': [
              {'message': '<a href="/files/12/download">C.hwp</a>'},
            ],
          });
        }
        if (path == '/api/v1/courses/1/assignments') {
          return json([
            {
              'name': 'Task',
              'description': '<a href="/courses/1/files/14/download">E.pdf</a>',
            },
          ]);
        }
        final id = RegExp(r'/api/v1/courses/1/files/(\d+)$')
            .firstMatch(path)
            ?.group(1);
        if (id != null) {
          return json({
            'id': int.parse(id),
            'display_name': 'file_$id.pdf',
            'url': 'https://school.edu/files/$id/download',
          });
        }
        throw StateError('Unexpected request: $path');
      });
    final report = CanvasImportReport();
    final files = await CanvasProvider(
      'https://school.edu',
      'fake',
      client: dio,
    ).discoverFiles('1', report, (_) {});
    expect(files.map((f) => '${f['id']}').toSet(), {
      '10',
      '11',
      '12',
      '13',
      '14',
    });
    expect(
      files.firstWhere((f) => f['id'] == 10)['_locations'],
      contains('게시판 · Board'),
    );
    expect(requested.every((host) => host == 'school.edu'), isTrue);
    expect(report.warnings, isEmpty);
    expect(report.contents['topic:4']!['body'], contains('세포 호흡'));
    expect(report.contents['topic:4']!['contentType'], '공지');
  });
  test('module download rejects a successful HTTP login page', () async {
    final root = await Directory.systemTemp.createTemp('fenru-login-test-');
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (r) => ResponseBody.fromString(
          '<!DOCTYPE html><html>Sign in</html>',
          200,
          headers: {
            'content-type': ['text/html'],
          },
        ),
      );
    try {
      await expectLater(
        CanvasProvider('https://school.edu', 'test', client: dio).downloadFile(
          Uri.parse('https://school.edu/download'),
          '${root.path}/file',
        ),
        throwsA(
          isA<CanvasRequestException>().having(
            (e) => e.restricted,
            'login page rejected',
            isTrue,
          ),
        ),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  for (final fileListStatus in [200, 401]) {
    test(
      'module files survive list status $fileListStatus and restricted items',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'fenru-module-test-',
        );
        final workspace = Workspace(root, WorkspaceDatabase.memory());
        await workspace.initialize();
        final requested = <String>[];
        ResponseBody json(Object body, [int status = 200]) =>
            ResponseBody.fromString(
              jsonEncode(body),
              status,
              headers: {
                'content-type': ['application/json'],
              },
            );
        final dio = Dio()
          ..httpClientAdapter = _Adapter((r) {
            requested.add(r.uri.toString());
            switch (r.uri.path) {
              case '/api/v1/courses':
                return json([
                  {'id': 1, 'name': 'Example course'},
                ]);
              case '/api/v1/courses/1/files':
                return json([], fileListStatus);
              case '/api/v1/courses/1/modules':
                return json([
                  {'id': 10, 'name': 'Week 1'},
                ]);
              case '/api/v1/courses/1/modules/10/items':
                if (r.uri.queryParameters['page'] == '2') {
                  return json([
                    {
                      'type': 'File',
                      'content_id': 22,
                      'title': 'Restricted.pdf',
                    },
                    {
                      'type': 'File',
                      'content_id': 23,
                      'title': 'Posted lecture',
                    },
                  ]);
                }
                return ResponseBody.fromString(
                  jsonEncode([
                    {'type': 'File', 'content_id': 21, 'title': 'Lecture.pdf'},
                    {
                      'type': 'File',
                      'content_id': 21,
                      'title': 'Duplicate.pdf',
                    },
                  ]),
                  200,
                  headers: {
                    'content-type': ['application/json'],
                    'link': [
                      '<https://school.edu/api/v1/courses/1/modules/10/items?page=2>; rel="next"',
                    ],
                  },
                );
              case '/api/v1/courses/1/files/21':
                return json({
                  'id': 21,
                  'filename': 'Lecture.pdf',
                  'display_name': 'Lecture.pdf',
                  'updated_at': 'today',
                  'size': 9,
                  'url': 'https://school.edu/asset',
                });
              case '/api/v1/courses/1/files/22':
              case '/api/v1/courses/1/files/23':
                return json({}, 403);
              case '/courses/1/files/23/download':
                return ResponseBody.fromString(
                  '%PDF-1.7\n',
                  200,
                  headers: {
                    'content-length': ['9'],
                    'content-disposition': [
                      "attachment; filename*=UTF-8''Posted%20lecture.pdf",
                    ],
                  },
                );
              case '/asset':
                return ResponseBody.fromString(
                  'PDF bytes',
                  200,
                  headers: {
                    'content-length': ['9'],
                  },
                );
              case '/courses/1/files/22/download':
                return json({}, 403);
              case '/api/v1/courses/1/assignments':
                return json({}, 403);
              default:
                throw StateError('Unexpected test endpoint');
            }
          });
        try {
          final provider = CanvasProvider(
            'https://school.edu',
            'test',
            client: dio,
          );
          await provider.courses();
          final report = await provider.importCourse(workspace, {
            'id': 1,
            'name': 'Example course',
          }, (_) {});
          expect(report.imported, 2);
          expect(report.skipped, 1);
          expect(
            workspace.ofKind('document').map((d) => d.title),
            containsAll(['Lecture.pdf', 'Posted lecture.pdf']),
          );
          expect(report.warnings.join(), contains('과제'));
          expect(report.warnings.join(), isNot(contains('만료')));
          expect(
            requested.where((uri) => Uri.parse(uri).path == '/asset').length,
            1,
          );
          expect(requested.any((uri) => uri.contains('items?page=2')), isTrue);
        } finally {
          await workspace.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
  test('401 with valid course probe is permission, revoked token remains authentication failure', () async {
    bool revoked = false;
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (r) => ResponseBody.fromString(
          r.uri.path == '/api/v1/courses' && !revoked ? '[]' : '{}',
          r.uri.path == '/api/v1/courses' && !revoked ? 200 : 401,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
    final provider = CanvasProvider('https://school.edu', 'test', client: dio);
    await provider.courses();
    await expectLater(
      provider.collection('/api/v1/courses/1/files'),
      throwsA(
        isA<CanvasRequestException>()
            .having((e) => e.restricted, 'permission error', isTrue)
            .having((e) => e.message, 'message', contains('토큰은 유효')),
      ),
    );
    revoked = true;
    await expectLater(
      provider.collection('/api/v1/courses/1/files'),
      throwsA(
        isA<CanvasRequestException>().having(
          (e) => e.authenticationFailed,
          'revoked token',
          isTrue,
        ),
      ),
    );
  });
  test(
    'download follows HTTPS CDN redirect without leaking Canvas bearer',
    () async {
      final root = await Directory.systemTemp.createTemp('fenru-cdn-test-');
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) {
          requests.add(request);
          if (request.uri.host == 'school.edu') {
            return ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://cdn.example/asset.pdf'],
              },
            );
          }
          return ResponseBody.fromString(
            'PDF bytes',
            200,
            headers: {
              'content-length': ['9'],
            },
          );
        });
      final provider = CanvasProvider(
        'https://school.edu',
        'test-bearer',
        client: dio,
      );
      try {
        await provider.downloadFile(
          Uri.parse('https://school.edu/file/1'),
          '${root.path}/file.bin',
        );
        expect(requests.first.headers['Authorization'], 'Bearer test-bearer');
        expect(requests.last.headers.containsKey('Authorization'), isFalse);
        expect(await File('${root.path}/file.bin').readAsString(), 'PDF bytes');
        expect(requests.length, 2);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('download rejects plaintext redirect destination', () async {
    final root = await Directory.systemTemp.createTemp('fenru-cdn-deny-');
    int count = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        count++;
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['http://unsafe.example/file'],
          },
        );
      });
    try {
      await expectLater(
        CanvasProvider('https://school.edu', 'test', client: dio).downloadFile(
          Uri.parse('https://school.edu/file'),
          '${root.path}/file',
        ),
        throwsException,
      );
      expect(count, 1);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('rejects credential URLs, plaintext and path URLs', () {
    for (final url in [
      'http://school.edu',
      'https://user:token@school.edu',
      'https://school.edu/path',
      'invalid',
    ]) {
      expect(() => CanvasProvider.validateUrl(url), throwsException);
    }
    expect(
      CanvasProvider.validateUrl('https://school.instructure.com').host,
      'school.instructure.com',
    );
  });
  test(
    'paginates and never follows an external next link with credentials',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) {
          requests.add(request);
          return ResponseBody.fromString(
            jsonEncode([
              {'id': requests.length},
            ]),
            200,
            headers: {
              'content-type': ['application/json'],
              if (requests.length == 1)
                'link': [
                  '<https://school.edu/api/v1/courses?page=2>; rel="next"',
                ],
            },
          );
        });
      final client = CanvasProvider(
        'https://school.edu',
        'test-not-a-real-key',
        client: dio,
      );
      expect((await client.courses()).length, 2);
      expect(requests.length, 2);
      expect(requests.every((r) => r.uri.host == 'school.edu'), isTrue);
      dio.httpClientAdapter = _Adapter(
        (request) => ResponseBody.fromString(
          '[]',
          200,
          headers: {
            'content-type': ['application/json'],
            'link': ['<https://evil.example/steal>; rel="next"'],
          },
        ),
      );
      await expectLater(client.courses(), throwsException);
    },
  );
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);
  @override
  void close({bool force = false}) {}
}
