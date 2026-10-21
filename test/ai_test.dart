import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/integrations/ai.dart';

void main() {
  test('Responses SSE survives split UTF8, records usage and disables storage', () async {
    RequestOptions? request;
    const sse =
        'data: {"type":"response.output_text.delta","delta":"설명"}\n\n'
        'data: {"type":"response.completed","response":{"usage":{"input_tokens":12,"output_tokens":3}}}\n\n';
    final bytes = utf8.encode(sse);
    final split = bytes.indexOf(0xec) + 1;
    final client = Dio()
      ..httpClientAdapter = _AIAdapter((options) {
        request = options;
        return ResponseBody(
          Stream.fromIterable([
            Uint8List.fromList(bytes.sublist(0, split)),
            Uint8List.fromList(bytes.sublist(split)),
          ]),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      });
    final provider = OfficialAIProvider(
      AIService.openai,
      'fake-test-secret',
      client: client,
    );
    final events = await provider
        .respond(
          model: 'selected-model',
          messages: [
            {'role': 'user', 'content': 'explain'},
          ],
          maxOutputTokens: 300,
          cancel: CancelToken(),
        )
        .toList();
    expect(events.map((e) => e.text).join(), '설명');
    expect(events.last.inputTokens, 12);
    expect(events.last.outputTokens, 3);
    expect(request!.path, '/responses');
    expect((request!.data as Map)['store'], isFalse);
    expect((request!.data as Map)['model'], 'selected-model');
  });
  test('DeepSeek chat SSE emits text and usage', () async {
    final client = Dio()
      ..httpClientAdapter = _AIAdapter(
        (options) => ResponseBody.fromString(
          'data: {"choices":[{"delta":{"content":"hello"}}]}\n\n'
          'data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2}}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
      );
    final events =
        await OfficialAIProvider(AIService.deepseek, 'test', client: client)
            .respond(
              model: 'chosen',
              messages: [
                {'role': 'user', 'content': 'hi'},
              ],
              maxOutputTokens: 256,
              cancel: CancelToken(),
            )
            .toList();
    expect(events.map((e) => e.text).join(), 'hello');
    expect(
      events.any((e) => e.inputTokens == 4 && e.outputTokens == 2),
      isTrue,
    );
    expect(events.last.complete, isTrue);
  });
  test(
    'provider errors never echo a server-provided secret or response body',
    () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/models'),
        response: Response(
          requestOptions: RequestOptions(path: '/models'),
          statusCode: 401,
          data: {'error': 'fake-sensitive-value'},
        ),
      );
      expect(OfficialAIProvider.explain(error).message, contains('인증'));
      expect(
        OfficialAIProvider.explain(error).message,
        isNot(contains('fake-sensitive-value')),
      );
    },
  );
}

class _AIAdapter implements HttpClientAdapter {
  _AIAdapter(this.handler);
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
