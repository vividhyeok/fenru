import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/models.dart';

typedef DriveFile = ({String id, String name, int size});

abstract interface class DriveStore {
  Future<String> accountId();
  Future<List<DriveFile>> list();
  Future<void> download(DriveFile remote, File destination, int limit);
  Future<void> upload(String name, File file);
}

class GoogleDriveStore implements DriveStore {
  GoogleDriveStore(String token)
    : _http = Dio(
        BaseOptions(
          baseUrl: 'https://www.googleapis.com',
          headers: {'authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 45),
          followRedirects: false,
        ),
      );

  static const prefix = 'fenru-sync-v1-';
  final Dio _http;

  @override
  Future<String> accountId() async {
    final result = await _http.get<Json>(
      '/drive/v3/about',
      queryParameters: {'fields': 'user(permissionId)'},
    );
    return (result.data!['user'] as Map)['permissionId'] as String;
  }

  @override
  Future<List<DriveFile>> list() async {
    final entries = <DriveFile>[];
    String? page;
    do {
      final response = await _http.get<Json>(
        '/drive/v3/files',
        queryParameters: {
          'spaces': 'appDataFolder',
          'q': "name contains '$prefix'",
          'fields': 'nextPageToken,files(id,name,size)',
          'pageSize': 1000,
          'pageToken': ?page,
        },
      );
      final result = response.data!;
      for (final file in (result['files'] as List? ?? []).whereType<Map>()) {
        final size = int.tryParse('${file['size']}');
        if (size == null || size < 0) continue;
        entries.add((
          id: file['id'] as String,
          name: file['name'] as String,
          size: size,
        ));
      }
      page = result['nextPageToken'] as String?;
    } while (page != null);
    return entries;
  }

  @override
  Future<void> download(DriveFile remote, File destination, int limit) async {
    if (remote.size > limit) {
      throw const UserFacingException('Drive 파일이 동기화 크기 한도를 초과했습니다.');
    }
    final response = await _http.get<ResponseBody>(
      '/drive/v3/files/${Uri.encodeComponent(remote.id)}',
      queryParameters: {'alt': 'media'},
      options: Options(responseType: ResponseType.stream),
    );
    final sink = destination.openWrite();
    var size = 0;
    try {
      await sink.addStream(
        response.data!.stream.map((chunk) {
          size += chunk.length;
          if (size > limit || size > remote.size) {
            throw const FormatException('Invalid Drive file size');
          }
          return chunk;
        }),
      );
    } finally {
      await sink.close();
    }
    if (size != remote.size) {
      throw const FormatException('Incomplete Drive file');
    }
  }

  @override
  Future<void> upload(String name, File file) async {
    final size = await file.length();
    if (size <= 4 * 1024 * 1024) {
      final boundary = 'fenru_${DateTime.now().microsecondsSinceEpoch}';
      final metadata = jsonEncode({
        'name': name,
        'parents': ['appDataFolder'],
      });
      final body = BytesBuilder(copy: false)
        ..add(
          utf8.encode(
            '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n',
          ),
        )
        ..add(
          utf8.encode(
            '--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n',
          ),
        )
        ..add(await file.readAsBytes())
        ..add(utf8.encode('\r\n--$boundary--\r\n'));
      await _http.post<void>(
        '/upload/drive/v3/files',
        queryParameters: {'uploadType': 'multipart'},
        data: body.takeBytes(),
        options: Options(contentType: 'multipart/related; boundary=$boundary'),
      );
      return;
    }
    final started = await _http.post<void>(
      '/upload/drive/v3/files',
      queryParameters: {'uploadType': 'resumable'},
      data: {
        'name': name,
        'parents': ['appDataFolder'],
      },
      options: Options(
        headers: {
          'x-upload-content-type': 'application/octet-stream',
          'x-upload-content-length': '$size',
        },
      ),
    );
    final url = Uri.tryParse(started.headers.value('location') ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        (url.host != 'www.googleapis.com' &&
            url.host != 'upload.googleapis.com') ||
        url.userInfo.isNotEmpty ||
        url.port != 443) {
      throw const FormatException('Invalid Drive upload URL');
    }
    final source = await file.open();
    try {
      var offset = 0;
      var retries = 0;
      while (offset < size) {
        final remaining = size - offset;
        final bytes = await source.read(
          remaining < 4 * 1024 * 1024 ? remaining : 4 * 1024 * 1024,
        );
        if (bytes.isEmpty) throw const FormatException('Incomplete local file');
        final Response<void> response;
        try {
          response = await _sendChunk(
            url,
            bytes,
            'bytes $offset-${offset + bytes.length - 1}/$size',
          );
        } on DioException catch (error) {
          final status = error.response?.statusCode;
          if (retries >= 2 ||
              (status != null && status < 500 && status != 429)) {
            rethrow;
          }
          retries++;
          await Future<void>.delayed(Duration(seconds: retries));
          final checked = await _sendChunk(url, Uint8List(0), 'bytes */$size');
          if (checked.statusCode != 308) return;
          final next = _receivedBytes(checked);
          if (next < offset || next >= size || next > offset + bytes.length) {
            throw const FormatException('Invalid Drive upload acknowledgement');
          }
          offset = next;
          await source.setPosition(offset);
          continue;
        }
        if (response.statusCode != 308) {
          if (offset + bytes.length != size) {
            throw const FormatException('Early Drive upload completion');
          }
          return;
        }
        final next = _receivedBytes(response);
        if (next <= offset || next >= size || next > offset + bytes.length) {
          throw const FormatException('Invalid Drive upload acknowledgement');
        }
        offset = next;
        retries = 0;
        await source.setPosition(offset);
      }
    } finally {
      await source.close();
    }
  }

  Future<Response<void>> _sendChunk(Uri url, Uint8List bytes, String range) =>
      _http.put<void>(
        url.toString(),
        data: bytes,
        options: Options(
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': bytes.length,
            'content-range': range,
          },
          validateStatus: (code) =>
              code == 308 || (code != null && code >= 200 && code < 300),
        ),
      );

  int _receivedBytes(Response<void> response) {
    final range = RegExp(r'^bytes=0-(\d+)$')
        .firstMatch(response.headers.value('range') ?? '');
    return range == null ? 0 : int.parse(range[1]!) + 1;
  }
}
