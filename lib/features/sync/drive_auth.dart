import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../integrations/credentials.dart';

class DriveAuth {
  DriveAuth(this.credentials);
  final CredentialStore credentials;
  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _channel = MethodChannel('fenru/drive');
  static const _key = 'drive.desktop';
  final _http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<String> token({
    bool interactive = false,
    bool selectAccount = false,
    String? desktopJson,
  }) async {
    if (Platform.isAndroid) {
      final token = await _channel.invokeMethod<String>(
        selectAccount ? 'connect' : 'authorize',
        interactive,
      );
      if (token == null || token.isEmpty) {
        throw const UserFacingException('Google Drive를 다시 연결하세요.');
      }
      return token;
    }
    if (desktopJson != null) return _connectDesktop(desktopJson);
    final saved = await credentials.read(_key);
    if (saved == null) {
      throw const UserFacingException('Windows용 Google OAuth 설정 파일을 선택하세요.');
    }
    final session = jsonDecode(saved) as Json;
    final response = await _exchange({
      'client_id': session['client_id'],
      'client_secret': session['client_secret'],
      'refresh_token': session['refresh_token'],
      'grant_type': 'refresh_token',
    });
    return response['access_token'] as String;
  }

  Future<String> _connectDesktop(String input) async {
    final document = jsonDecode(input);
    final config = document is Map ? document['installed'] : null;
    final clientId = config is Map ? config['client_id'] : null;
    final clientSecret = config is Map ? config['client_secret'] : null;
    if (clientId is! String ||
        !clientId.endsWith('.apps.googleusercontent.com') ||
        clientSecret is! String ||
        clientSecret.isEmpty) {
      throw const UserFacingException(
        'Google Cloud의 데스크톱 OAuth JSON 파일을 선택하세요.',
      );
    }
    final random = Random.secure();
    String nonce() =>
        base64Url.encode(List.generate(48, (_) => random.nextInt(256)));
    final verifier = nonce();
    final state = nonce();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/oauth';
    final result = Completer<String>();
    server.listen((request) async {
      final query = request.uri.queryParameters;
      if (request.uri.path != '/oauth' ||
          query['state'] != state ||
          result.isCompleted) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final code = query['code'];
      request.response.headers.contentType = ContentType.text;
      request.response.write(
        code == null
            ? 'Google Drive connection cancelled.'
            : 'Return to Fenru to finish connecting Google Drive.',
      );
      if (code == null) {
        result.completeError(const UserFacingException('Google 연결이 취소되었습니다.'));
      } else {
        result.complete(code);
      }
      await request.response.close();
    });
    try {
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent select_account',
        'code_challenge': base64Url
            .encode(sha256.convert(ascii.encode(verifier)).bytes)
            .replaceAll('=', ''),
        'code_challenge_method': 'S256',
      });
      final callback = result.future.timeout(const Duration(minutes: 3));
      // Attach an error handler before opening the browser.
      unawaited(callback.then<void>((_) {}, onError: (Object _) {}));
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const UserFacingException('Google 연결 브라우저를 열지 못했습니다.');
      }
      final response = await _exchange({
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': await callback,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      });
      final refresh = response['refresh_token'];
      if (refresh is! String || refresh.isEmpty) {
        throw const UserFacingException('Google이 갱신 권한을 제공하지 않았습니다. 다시 연결하세요.');
      }
      await credentials.write(
        _key,
        jsonEncode({
          'client_id': clientId,
          'client_secret': clientSecret,
          'refresh_token': refresh,
        }),
      );
      return response['access_token'] as String;
    } finally {
      if (!result.isCompleted) result.complete('');
      await server.close(force: true);
    }
  }

  Future<Json> _exchange(Json fields) async {
    try {
      final response = await _http.post<Json>(
        'https://oauth2.googleapis.com/token',
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
        ),
      );
      return response.data!;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 401) {
        throw const UserFacingException('Google 연결을 다시 승인하세요.');
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('disconnect');
    } else {
      await credentials.delete(_key);
    }
  }
}
