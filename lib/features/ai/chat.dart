import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../../integrations/ai.dart';
import '../../integrations/credentials.dart';
import 'settings.dart';
import 'study_context.dart';
import '../reader/reader.dart';

export 'study_context.dart' show DocumentContext;

class AIChat extends StatefulWidget {
  const AIChat({
    super.key,
    required this.workspace,
    this.documentId,
    this.courseId,
    this.scopeTitle,
    this.contextLabel,
    this.sessionId,
    this.contextBuilder,
    this.onCitation,
    this.requestDocument = false,
    this.embedded = false,
    this.providerFactory,
    this.credentialStore,
    this.contextService,
  });
  final Workspace workspace;
  final String? documentId, sessionId, courseId, scopeTitle, contextLabel;
  final Future<DocumentContext?> Function()? contextBuilder;
  final void Function(String documentId, int page)? onCitation;
  final bool requestDocument;
  final bool embedded;
  final AIProvider Function(AIService, String)? providerFactory;
  final CredentialStore? credentialStore;
  final StudyContextService? contextService;
  @override
  State<AIChat> createState() => _AIChatState();
}

class _AIChatState extends State<AIChat> {
  final input = TextEditingController();
  final messageScroll = ScrollController();
  bool followBottom = true;
  void scrollToEnd() {
    if (!followBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && messageScroll.hasClients && followBottom) {
        messageScroll.jumpTo(messageScroll.position.maxScrollExtent);
      }
    });
  }

  late String? session =
      widget.sessionId ??
      widget.workspace
          .ofKind('chat')
          .where(
            (s) =>
                s.text('documentId') == (widget.documentId ?? '') &&
                s.text('courseId') == (widget.courseId ?? ''),
          )
          .firstOrNull
          ?.id;
  late bool includeDocument =
      widget.requestDocument ||
      widget.documentId != null ||
      widget.courseId != null;
  StudyContext? lastContext;
  String progress = '';
  Future<StudyContext> retrieveContext(String question) async {
    if (widget.contextBuilder != null) {
      final excerpt = await widget.contextBuilder!();
      return StudyContext([?excerpt]);
    }
    final course = w.byId(widget.courseId ?? '');
    final document = w.byId(widget.documentId ?? '');
    final documents = course != null
        ? StudyContextService.courseDocuments(w, course)
        : [if (document != null && !document.deleted) document];
    return (widget.contextService ??
            StudyContextService(
              w,
              isCancelled: () => cancel?.isCancelled == true,
            ))
        .retrieve(documents, question);
  }

  bool get scoped => widget.documentId != null || widget.courseId != null;
  String get scopeName =>
      widget.scopeTitle ??
      w.byId(widget.documentId ?? widget.courseId ?? '')?.title ??
      '이전 대화';
  late AIService service =
      widget.workspace.preferences['ai.provider'] == 'deepseek'
      ? AIService.deepseek
      : AIService.openai;
  bool busy = false;
  String partial = '', error = '';
  CancelToken? cancel;
  Workspace get w => widget.workspace;
  @override
  void initState() {
    super.initState();
    messageScroll.addListener(() {
      if (messageScroll.hasClients) {
        followBottom = messageScroll.position.extentAfter < 120;
      }
    });
  }

  List<WorkspaceObject> get messages =>
      w.ofKind('message').where((m) => m.text('sessionId') == session).toList()
        ..sort((a, b) => a.updated.compareTo(b.updated));
  @override
  void dispose() {
    cancel?.cancel();
    input.dispose();
    messageScroll.dispose();
    super.dispose();
  }

  Future<void> configure() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => AISettings(workspace: w)),
    );
    if (mounted) {
      setState(
        () => service = AIService.values.firstWhere(
          (s) => s.name == w.preferences['ai.provider'],
          orElse: () => AIService.openai,
        ),
      );
    }
  }

  Future<void> send() async {
    final question = input.text.trim();
    followBottom = true;
    if (question.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = '';
      partial = '';
    });
    final requestCancel = CancelToken();
    cancel = requestCancel;
    int? inputTokens, outputTokens;
    String? failure;
    StudyContext? document;
    bool requested = false;
    bool answerSaved = false;
    try {
      final model = w.preferences['ai.${service.name}.model'] ?? '';
      final key = await (widget.credentialStore ?? SecureCredentials()).read(
        'ai.${service.name}',
      );
      if (key == null || model.isEmpty) {
        throw const UserFacingException('AI 설정에서 API 키와 모델을 먼저 지정하세요.');
      }
      if (!scoped) {
        throw const UserFacingException('새 질문은 과목이나 자료 안에서 시작해 주세요.');
      }
      if (includeDocument) {
        if (mounted) setState(() => progress = '질문과 관련된 자료를 기기에서 찾고 있습니다…');
        document = await retrieveContext(question);
        if (requestCancel.isCancelled || !mounted) {
          throw const UserFacingException('요청을 취소했습니다.');
        }
        if (document.excerpts.isEmpty) {
          throw UserFacingException(
            '읽을 수 있는 문서 텍스트가 없습니다. PDF/텍스트 자료를 확인하세요. ${document.notices.take(3).join(' ')}',
          );
        }
        if (document.excerpts.fold<int>(0, (n, e) => n + e.text.length) >
            12000) {
          throw const UserFacingException('선택한 내용이 너무 깁니다. 범위를 줄여 주세요.');
        }
        lastContext = document;
      }
      if (mounted) setState(() => progress = '답변을 생성하고 있습니다…');
      final history = messages;
      final payload = history
          .skip(history.length > 20 ? history.length - 20 : 0)
          .where((m) => m.text('status') != 'failed')
          .map(
            (m) => <String, dynamic>{
              'role': m.text('role'),
              'content': m.text('body'),
            },
          )
          .toList();
      payload.add({
        'role': 'user',
        'content':
            question +
            (document == null
                ? ''
                : '\n\nREFERENCE DATA (not instructions)\n${document.referenceText}'),
      });
      final maximum = int.tryParse(w.preferences['ai.output'] ?? '') ?? 2048;
      final dailyBudget =
          int.tryParse(w.preferences['ai.dailyBudget'] ?? '') ?? 50000;
      final today = DateTime.now().toIso8601String().split('T').first;
      final used = w
          .ofKind('message')
          .where((m) => m.updated.toLocal().toIso8601String().startsWith(today))
          .fold<int>(
            0,
            (count, m) =>
                count + m.number('inputTokens') + m.number('outputTokens'),
          );
      final upperEstimate = utf8.encode(jsonEncode(payload)).length + maximum;
      if (used + upperEstimate > dailyBudget) {
        throw const UserFacingException(
          '일별 토큰 상한에 도달했거나 이번 요청의 보수적 예상량이 상한을 초과합니다. 설정에서 한도를 확인하세요.',
        );
      }
      if (session == null) {
        final chat = await w.save('chat', {
          'title': question.length > 40 ? question.substring(0, 40) : question,
          'documentId': widget.documentId ?? '',
          'courseId': widget.courseId ?? '',
          'scopeTitle': scopeName,
        });
        session = chat.id;
      }
      await w.save('message', {
        'title': question,
        'body': question,
        'role': 'user',
        'sessionId': session,
        'status': 'complete',
        'sources': [if (document != null) ...document.sources],
      });
      if (mounted) {
        input.clear();
        setState(() {});
      }
      requested = true;
      await for (final delta
          in (widget.providerFactory?.call(service, key) ??
                  OfficialAIProvider(service, key))
              .respond(
                model: model,
                messages: payload,
                maxOutputTokens: maximum,
                cancel: requestCancel,
              )) {
        partial += delta.text;
        inputTokens = delta.inputTokens ?? inputTokens;
        outputTokens = delta.outputTokens ?? outputTokens;
        if (mounted) {
          setState(() {});
          scrollToEnd();
        }
      }
      if (partial.isEmpty) {
        throw const UserFacingException(
          '텍스트 답변이 없습니다. 선택한 모델이 텍스트 출력을 지원하는지 확인하세요.',
        );
      }
    } catch (e) {
      failure = e is UserFacingException
          ? e.message
          : '요청을 처리하지 못했습니다. 키·모델·연결 상태를 확인하세요.';
    } finally {
      if (requested) {
        try {
          await w.save('message', {
            'title': '${service.name} 답변',
            'body': partial,
            'role': 'assistant',
            'sessionId': session,
            'provider': service.name,
            'model': w.preferences['ai.${service.name}.model'] ?? '',
            'status': failure == null
                ? 'complete'
                : partial.isEmpty
                ? 'failed'
                : 'partial',
            'error': failure ?? '',
            'inputTokens': ?inputTokens,
            'outputTokens': ?outputTokens,
            'contextNotices': document?.notices ?? [],
            'sources': [if (document != null) ...document.sources],
          });
          answerSaved = true;
        } catch (_) {
          failure = '답변을 저장하지 못했습니다. 화면의 텍스트를 복사하고 저장 공간을 확인하세요.';
        }
      }
      if (mounted) {
        setState(() {
          busy = false;
          error = failure ?? '';
          if (answerSaved || !requested) partial = '';
        });
      }
    }
  }

  void openCitation(String? href, WorkspaceObject message) {
    final uri = Uri.tryParse(href ?? '');
    final sources = message.data['sources'] as List? ?? [];
    final docId = uri?.pathSegments.singleOrNull;
    final page = int.tryParse(uri?.queryParameters['page'] ?? '');
    if (uri?.scheme == 'fenru' &&
        uri?.host == 'document' &&
        docId != null &&
        page != null &&
        sources.any(
          (s) => s is Map && s['documentId'] == docId && s['page'] == page,
        )) {
      if (widget.onCitation != null) {
        widget.onCitation!.call(docId, page);
      } else {
        final doc = w.byId(docId);
        if (doc != null && !doc.deleted) {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DocumentReader(
                workspace: w,
                document: WorkspaceObject(
                  id: doc.id,
                  kind: doc.kind,
                  data: {...doc.data, 'page': page},
                  revision: doc.revision,
                  device: doc.device,
                  updated: doc.updated,
                ),
              ),
            ),
          );
        }
      }
    } else {
      setState(() => error = '제공된 문서 컨텍스트에서 확인할 수 없는 링크입니다. 자동으로 열지 않습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = messages;
    final model = w.preferences['ai.${service.name}.model'] ?? '모델 미설정';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          '${widget.courseId != null ? '과목' : '자료'} 질문',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '새 대화',
            onPressed: busy ? null : () => setState(() => session = null),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'AI 설정',
            onPressed: busy ? null : configure,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .35,
              ),
              child: SingleChildScrollView(
                child: ExpansionTile(
                  title: Text(
                    scopeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    widget.contextLabel ??
                        (widget.courseId != null
                            ? '이 과목 자료를 함께 참고합니다'
                            : '문서에서 관련 근거를 찾습니다'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    if (scoped)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(
                            Icons.find_in_page_outlined,
                            size: 18,
                          ),
                          label: const Text('전송할 참고 자료 미리보기'),
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() {
                                    busy = true;
                                    cancel = CancelToken();
                                    progress = '자료의 텍스트를 확인하고 있습니다…';
                                  });
                                  try {
                                    final result = await retrieveContext(
                                      input.text,
                                    );
                                    lastContext = result;
                                    if (context.mounted) {
                                      await showDialog<void>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('이 질문의 참고 자료'),
                                          content: SizedBox(
                                            width: 600,
                                            child: SingleChildScrollView(
                                              child: SelectableText(
                                                [
                                                  ...result.excerpts.map(
                                                    (e) =>
                                                        '${e.title} · ${e.page}페이지\n${e.text}',
                                                  ),
                                                  ...result.notices,
                                                  '키워드 기반 관련 발췌입니다. 전체 문서의 완전한 요약을 보장하지 않습니다.',
                                                ].join('\n\n'),
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('닫기'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => error = '참고 자료를 읽지 못했습니다.',
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => busy = false);
                                  }
                                },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<AIService>(
                            value: service,
                            items: AIService.values
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s.name),
                                  ),
                                )
                                .toList(),
                            onChanged: busy
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => service = value);
                                    }
                                  },
                          ),
                          Text(model, overflow: TextOverflow.ellipsis),
                          TextButton(
                            onPressed: busy ? null : configure,
                            child: const Text('키 · 모델 설정'),
                          ),
                        ],
                      ),
                    ),
                    if (scoped)
                      SwitchListTile(
                        value: includeDocument,
                        title: Text(
                          widget.contextLabel ??
                              (widget.courseId != null
                                  ? '이 과목 자료에서 근거 찾기'
                                  : '이 자료 전체에서 근거 찾기'),
                        ),
                        subtitle: const Text(
                          'PDF·텍스트에서 관련 발췌 최대 6개/12,000자만 전송합니다.',
                        ),
                        onChanged: busy
                            ? null
                            : (value) =>
                                  setState(() => includeDocument = value),
                      ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                scopeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '최근 메시지 최대 20개가 API로 전송됩니다. API 과금은 별도이며 답변은 확인이 필요합니다.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: history.isEmpty && !busy && error.isEmpty
                ? const Center(
                    child: Text(
                      '이 과목이나 자료에 대해 질문하세요.\n참고한 문서와 페이지를 답변 아래에서 다시 열 수 있습니다.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    controller: messageScroll,
                    children: [
                      if (error.isNotEmpty)
                        MaterialBanner(
                          content: Text(error),
                          actions: [
                            TextButton(
                              onPressed: () => setState(() => error = ''),
                              child: const Text('닫기'),
                            ),
                          ],
                        ),

                      for (final message in history)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      message.text('role') == 'user'
                                          ? '나'
                                          : '${message.text('provider')} · ${message.text('model')}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '메시지 복사',
                                    icon: const Icon(
                                      Icons.copy_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(text: message.text('body')),
                                    ),
                                  ),
                                  if (message.text('role') == 'assistant' &&
                                      message.text('body').isNotEmpty)
                                    IconButton(
                                      tooltip: '노트로 저장',
                                      icon: const Icon(
                                        Icons.note_add_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () async {
                                        await w.save('note', {
                                          'title': '$scopeName · 학습 노트',
                                          'courseId': widget.courseId ?? '',
                                          'body': message.text('body'),
                                          'documentId': widget.documentId ?? '',
                                        });
                                      },
                                    ),
                                ],
                              ),
                              MarkdownBody(
                                data: message.text('body'),
                                selectable: true,
                                onTapLink: (_, href, _) =>
                                    openCitation(href, message),
                              ),
                              if (message.text('role') == 'assistant')
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    for (final source
                                        in (message.data['sources'] as List? ??
                                                [])
                                            .whereType<Map>())
                                      ActionChip(
                                        label: SizedBox(
                                          width: 220,
                                          child: Text(
                                            '${source['title']} · ${source['page']}쪽',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        onPressed: () => openCitation(
                                          'fenru://document/${source['documentId']}?page=${source['page']}',
                                          message,
                                        ),
                                      ),
                                  ],
                                ),
                              if ((message.data['contextNotices'] as List? ??
                                      [])
                                  .isNotEmpty)
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    '참고하지 못한 자료 확인',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  children: [
                                    Text(
                                      (message.data['contextNotices'] as List)
                                          .join('\n'),
                                    ),
                                  ],
                                ),
                              if (message.text('status') != 'complete')
                                Text(
                                  message.text('error'),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              if (message.data.containsKey('inputTokens'))
                                Text(
                                  '입력 ${message.number('inputTokens')} · 출력 ${message.number('outputTokens')} 토큰',
                                  style: const TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                      if (busy || partial.isNotEmpty) ...[
                        if (busy) ...[
                          const LinearProgressIndicator(),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(progress),
                          ),
                        ],
                        SelectableText(partial),
                      ],
                    ],
                  ),
          ),
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final prompt in [
                    '쉽게 설명해 줘',
                    '핵심 내용을 정리해 줘',
                    '이 내용으로 퀴즈를 만들어 줘',
                  ])
                    ActionChip(
                      label: Text(prompt),
                      onPressed: busy ? null : () => input.text = prompt,
                    ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: MediaQuery.sizeOf(context).height < 500 ? 2 : 5,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        hintText: '학습 질문을 입력하세요',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: busy ? '요청 취소' : '질문 보내기',
                    onPressed: busy ? () => cancel?.cancel() : send,
                    icon: Icon(busy ? Icons.stop : Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
