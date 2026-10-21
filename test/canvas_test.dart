import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/integrations/canvas.dart';

void main() {
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
