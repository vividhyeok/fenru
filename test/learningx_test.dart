import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/models.dart';
import 'package:fenru/integrations/learningx.dart';

void main() {
  for (final hostile in [false, true]) {
    test(
      'LearningX signed launch, attachments and Commons boundaries hostile=$hostile',
      () async {
        final calls = <RequestOptions>[];
        final dio = Dio()
          ..httpClientAdapter = _Adapter((r) {
            calls.add(r);
            switch (r.uri.path) {
              case '/courses/1/external_tools/sessionless_launch':
                return ResponseBody.fromString(
                  '<html><form method="post" action="${hostile ? 'https://evil.example' : ''}/learningx/lti/modulebuilder"><input type="hidden" name="oauth_signature" value="signed&amp;value"></form></html>',
                  200,
                  headers: {
                    'content-type': ['text/html'],
                  },
                );
              case '/learningx/lti/modulebuilder':
                expect(r.method, 'POST');
                expect((r.data as Map)['oauth_signature'], 'signed&value');
                return ResponseBody.fromString(
                  'LearningX',
                  200,
                  headers: {
                    'set-cookie': [
                      'xn_api_token=short-lived-xn; Path=/; Secure; HttpOnly',
                    ],
                  },
                );
              case '/learningx/api/v1/courses/1/modules':
                expect(r.headers['Authorization'], 'Bearer short-lived-xn');
                return ResponseBody.fromString(
                  jsonEncode([
                    {
                      'module_items': [
                        {
                          'content_type': 'attachment',
                          'content_id': 21,
                          'content_data': null,
                        },
                        {
                          'content_type': 'attendance_item',
                          'content_data': {
                            'item_content_data': {
                              'content_type': 'movie',
                              'view_url':
                                  'https://common.jejunu.ac.kr/em/movie',
                            },
                          },
                        },
                        {
                          'content_type': 'attendance_item',
                          'content_data': {
                            'updated_at': 'today',
                            'item_content_data': {
                              'content_type': 'pdf',
                              'file_name': 'Lecture.pdf',
                              'view_url': 'https://common.jejunu.ac.kr/em/doc1',
                            },
                          },
                        },
                        {
                          'content_type': 'attendance_item',
                          'content_data': {
                            'item_content_data': {
                              'content_type': 'pdf',
                              'view_url': 'https://evil.example/em/evil',
                            },
                          },
                        },
                        {
                          'content_type': 'attendance_item',
                          'content_data': {
                            'item_content_data': {
                              'content_type': 'pdf',
                              'content_id': 'legacy1',
                              'view_url': '',
                            },
                          },
                        },
                      ],
                    },
                  ]),
                  200,
                  headers: {
                    'content-type': ['application/json'],
                  },
                );
              case '/viewer/ssplayer/uniplayer_support/content.php':
                expect(r.uri.host, 'common.jejunu.ac.kr');
                expect(r.headers['Authorization'], isNull);
                expect(r.headers['Cookie'], isNull);
                if (r.uri.queryParameters['content_id'] == 'legacy1') {
                  return ResponseBody.fromString(
                    '<content/>',
                    200,
                    headers: {
                      'content-type': ['text/xml'],
                    },
                  );
                }
                return ResponseBody.fromString(
                  '<content><content_download_uri><![CDATA[/index.php?module=commons&amp;x=1]]></content_download_uri></content>',
                  200,
                  headers: {
                    'content-type': ['text/xml'],
                  },
                );
              default:
                throw StateError('Unexpected network request in test');
            }
          });
        final objectPaths = <String>[];
        final provider = LearningXProvider(
          Uri.parse('https://canvas.jejunu.ac.kr'),
          dio,
          (_) async => [
            {
              'id': 10,
              'url': 'https://canvas.jejunu.ac.kr/learningx/lti/modulebuilder',
            },
          ],
          (path) async {
            objectPaths.add(path);
            if (path.startsWith('/api/v1/files/')) {
              return <String, dynamic>{
                'id': 21,
                'display_name': 'Attachment.pdf',
                'url': 'https://canvas.jejunu.ac.kr/download',
              };
            }
            return <String, dynamic>{
              'url': 'https://canvas.jejunu.ac.kr/courses/1/external_tools/sessionless_launch?verifier=temporary',
            };
          },
        );
        if (hostile) {
          await expectLater(
            provider.files('1'),
            throwsA(isA<UserFacingException>()),
          );
          expect(calls.length, 1);
        } else {
          final files = await provider.files('1');
          expect(
            files.map((f) => f['id']),
            containsAll([21, 'learningx:doc1']),
          );
          expect(files.length, 2);
          expect(
            files.last['url'],
            'https://common.jejunu.ac.kr/index.php?module=commons&amp;x=1',
          );
          expect(provider.warnings.join(), contains('저장소'));
          expect(provider.warnings.join(), contains('다운로드 주소'));
          expect(objectPaths, contains('/api/v1/files/21'));
          expect(calls.where((r) => r.method == 'POST').length, 1);
          expect(
            calls.any(
              (r) =>
                  r.uri.path.contains('items/view') ||
                  r.uri.path.contains('attendance') ||
                  r.uri.host == 'evil.example',
            ),
            isFalse,
          );
        }
      },
    );
  }
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
