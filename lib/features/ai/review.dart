import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';

const reviewFormat = '''
제공된 자료에 근거해 한국어 연습문제 3개를 만들어 줘.
JSON 배열만 출력해. 각 항목에는 question(문제), choices(보기 배열),
answer(정답 인덱스), explanation(근거를 포함한 해설),
source(사용한 자료의 정확한 fenru://document/... 링크)를 넣어.
concept(핵심 개념), objective(평가하려는 학습 목표)도 넣어.
hint(정답을 드러내지 않는 한 문장 힌트), steps(풀이 단계 문자열 배열),
choiceReasons(보기 순서대로 각 보기가 맞거나 틀린 이유, 서술형이면 빈 배열),
takeaway(시험 전에 기억할 규칙이나 흔한 함정 한 문장)도 함께 작성해.
각 항목은 짧고 서로 중복되지 않게 써. 모든 설명은 같은 출처에서 확인 가능해야 해.
자료의 정의·조건·예외를 먼저 확인하고 서로 다른 목표를 평가해.
객관식은 서로 다른 보기 4개와 0부터 시작하는 정답 인덱스를 사용해.
오답 보기는 실제로 혼동하기 쉬운 개념으로 구성해.
자료로 확인할 수 있는 내용만 출제하고 해설에는 정답의 이유와 흔한 오해를 넣어.
''';

enum ReviewType {
  multipleChoice('객관식', '개념을 구분하는 4지선다 문제를 만들어.'),
  application('응용형', '새 상황이나 조건에 개념을 적용하는 4지선다 문제를 만들어.'),
  shortAnswer(
    '서술형',
    '짧게 설명하거나 계산하는 문제를 만들어. choices는 빈 배열, answer는 -1로 두고 explanation에 모범 답안과 채점 기준을 넣어.',
  ),
  flashcard(
    '암기 카드',
    '핵심 개념을 기억에서 꺼내는 짧은 질문과 답을 만들어. choices는 빈 배열, answer는 -1로 두고 explanation 첫 문장에 짧은 정답을 써.',
  );

  const ReviewType(this.label, this.instruction);
  final String label, instruction;
  bool get written => this == shortAnswer || this == flashcard;
}

class ReviewQuestion {
  const ReviewQuestion(
    this.question,
    this.choices,
    this.answer,
    this.explanation,
    this.source, {
    this.concept = '',
    this.objective = '',
    this.hint = '',
    this.steps = const [],
    this.choiceReasons = const [],
    this.takeaway = '',
  });
  final String question, explanation, source;
  final String concept, objective;
  final String hint, takeaway;
  final List<String> steps, choiceReasons;
  bool get written => choices.isEmpty;
  final List<String> choices;
  final int answer;

  static List<String> _optionalLines(Object? value) => value is List
      ? value
            .whereType<String>()
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList()
      : const [];

  static List<ReviewQuestion> parse(String body) {
    try {
      final cleaned = body
          .trim()
          .replaceFirst(
            RegExp(r'^\x60{3}(?:json)?\s*', caseSensitive: false),
            '',
          )
          .replaceFirst(RegExp(r'\s*\x60{3}$'), '');
      final items = jsonDecode(cleaned);
      if (items is! List || items.isEmpty || items.length > 5) return [];
      return items.map((item) {
        final map = item as Map;
        final question = (map['question'] as String).trim();
        final choices = (map['choices'] as List)
            .map((c) => (c as String).trim())
            .toList();
        final answer = map['answer'] as int;
        final explanation = (map['explanation'] as String).trim();
        final validAnswer = choices.isEmpty
            ? answer == -1
            : choices.length == 4 &&
                  choices.every((c) => c.isNotEmpty) &&
                  choices.toSet().length == 4 &&
                  answer >= 0 &&
                  answer < 4;
        if (question.isEmpty || explanation.isEmpty || !validAnswer) {
          throw const FormatException('Invalid review question');
        }
        final reasons = map['choiceReasons'];
        return ReviewQuestion(
          question,
          choices,
          answer,
          explanation,
          map['source'] as String? ?? '',
          concept: (map['concept'] as String? ?? '').trim(),
          objective: (map['objective'] as String? ?? '').trim(),
          hint: map['hint'] is String ? (map['hint'] as String).trim() : '',
          steps: _optionalLines(map['steps']),
          choiceReasons:
              reasons is List &&
                  reasons.length == choices.length &&
                  reasons.every(
                    (reason) => reason is String && reason.trim().isNotEmpty,
                  )
              ? _optionalLines(reasons)
              : const [],
          takeaway: map['takeaway'] is String
              ? (map['takeaway'] as String).trim()
              : '',
        );
      }).toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.workspace,
    required this.message,
    required this.questions,
    required this.onSource,
    this.wrongOnly = false,
    this.onVariant,
    this.onExplain,
  });
  final Workspace workspace;
  final WorkspaceObject message;
  final List<ReviewQuestion> questions;
  final void Function(String) onSource;
  final bool wrongOnly;
  final ValueChanged<ReviewQuestion>? onVariant;
  final ValueChanged<ReviewQuestion>? onExplain;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool get flashcards =>
      widget.message.text('reviewType') == ReviewType.flashcard.name;
  late Map<String, dynamic> answers = Map<String, dynamic>.from(
    widget.workspace.byId('review-${widget.message.id}')?.data['answers']
            as Map? ??
        {},
  );
  late List<int> order = initialOrder();
  int position = 0;
  int? selection;
  String writtenAnswer = '';
  bool showingSolution = false;
  bool showingHint = false;
  bool saving = false;
  final revealed = <int>{};

  List<int> initialOrder() {
    final all = List.generate(widget.questions.length, (i) => i);
    if (widget.wrongOnly) return all.where(wrong).toList();
    final unanswered = all.where((i) => !answers.containsKey('$i')).toList();
    return unanswered.isEmpty ? all : unanswered;
  }

  bool wrong(int index) =>
      answers.containsKey('$index') &&
      (widget.questions[index].written
          ? answers['$index'] != true
          : answers['$index'] != widget.questions[index].answer);

  Future<void> check(int index, Object choice) async {
    setState(() => saving = true);
    final updated = {...answers, '$index': choice};
    try {
      await widget.workspace.save('review', {
        'messageId': widget.message.id,
        'answers': updated,
        'attempts': [
          ...((widget.workspace
                      .byId('review-${widget.message.id}')
                      ?.data['attempts']
                  as List?) ??
              []),
          {
            'questionIndex': index,
            'answer': choice,
            if (widget.questions[index].written && !flashcards)
              'text': writtenAnswer.trim(),
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      }, id: 'review-${widget.message.id}');
      if (mounted) {
        setState(() {
          answers = updated;
          revealed.add(index);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('풀이 기록을 저장하지 못했습니다. 다시 시도하세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mistakes = List.generate(
      widget.questions.length,
      (i) => i,
    ).where(wrong).toList();
    final finished = position >= order.length;
    final index = finished ? 0 : order[position];
    final question = widget.questions[index];
    final checked = revealed.contains(index);
    final sourceAvailable = (widget.message.data['sources'] as List? ?? [])
        .whereType<Map>()
        .any(
          (s) =>
              question.source ==
              'fenru://document/${s['documentId']}?page=${s['page']}',
        );
    return Scaffold(
      appBar: AppBar(title: Text(flashcards ? '암기 카드' : '복습 문제')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            key: ValueKey(position),
            padding: const EdgeInsets.all(24),
            children: finished
                ? [
                    Text(
                      '정답 ${answers.length - mistakes.length} / ${widget.questions.length}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (mistakes.isNotEmpty)
                      FilledButton(
                        onPressed: () => setState(() {
                          order = mistakes;
                          position = 0;
                          selection = null;
                          writtenAnswer = '';
                          showingSolution = false;
                          showingHint = false;
                          revealed.clear();
                        }),
                        child: Text('틀린 문제 ${mistakes.length}개 다시 풀기'),
                      ),
                  ]
                : [
                    LinearProgressIndicator(
                      value: (position + 1) / order.length,
                    ),
                    const SizedBox(height: 16),
                    Text('${position + 1} / ${order.length}'),
                    const SizedBox(height: 8),
                    Text(
                      question.question,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (!checked &&
                        !showingSolution &&
                        question.hint.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => showingHint = !showingHint),
                          icon: const Icon(Icons.lightbulb_outline),
                          label: Text(showingHint ? '힌트 숨기기' : '힌트 보기'),
                        ),
                      ),
                      if (showingHint) Text(question.hint),
                    ],
                    const SizedBox(height: 16),
                    if (question.written && !flashcards)
                      TextFormField(
                        readOnly: showingSolution,
                        minLines: 2,
                        maxLines: 5,
                        onChanged: (value) =>
                            setState(() => writtenAnswer = value),
                        decoration: const InputDecoration(labelText: '내 답안'),
                      ),
                    for (var i = 0; i < question.choices.length; i++)
                      ListTile(
                        leading: Icon(
                          checked && i == question.answer
                              ? Icons.check_circle_outline
                              : i == selection
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(question.choices[i]),
                        selected: i == selection,
                        onTap: checked || saving
                            ? null
                            : () => setState(() => selection = i),
                      ),
                    const SizedBox(height: 16),
                    if (checked || showingSolution) ...[
                      Text(
                        question.written
                            ? flashcards
                                  ? '카드 뒷면'
                                  : '모범 답안과 채점 기준'
                            : selection == question.answer
                            ? '정답'
                            : '오답',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SelectableText(question.explanation),
                      if (question.concept.isNotEmpty)
                        Text('핵심 개념 · ${question.concept}'),
                      if (question.objective.isNotEmpty)
                        Text('학습 목표 · ${question.objective}'),
                      if (question.steps.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('단계별 풀이'),
                          children: [
                            for (final (index, step) in question.steps.indexed)
                              ListTile(
                                dense: true,
                                title: SelectableText('${index + 1}. $step'),
                              ),
                          ],
                        ),
                      if (question.choiceReasons.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('보기별 이유'),
                          children: [
                            for (final (index, reason)
                                in question.choiceReasons.indexed)
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${index + 1}. ${question.choices[index]}',
                                ),
                                subtitle: SelectableText(reason),
                              ),
                          ],
                        ),
                      if (question.takeaway.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('시험 전에 기억할 점'),
                          children: [
                            ListTile(
                              dense: true,
                              title: SelectableText(question.takeaway),
                            ),
                          ],
                        ),
                      if (sourceAvailable)
                        TextButton.icon(
                          onPressed: () => widget.onSource(question.source),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('근거 자료 열기'),
                        ),
                      if (widget.onExplain != null ||
                          (checked && widget.onVariant != null))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: PopupMenuButton<String>(
                            tooltip: '문제 더 알아보기',
                            onSelected: (action) {
                              if (action == 'explain') {
                                widget.onExplain?.call(question);
                              }
                              if (action == 'variant') {
                                widget.onVariant?.call(question);
                              }
                            },
                            itemBuilder: (_) => [
                              if (widget.onExplain != null)
                                const PopupMenuItem(
                                  value: 'explain',
                                  child: Text('추가 해설 요청'),
                                ),
                              if (checked && widget.onVariant != null)
                                const PopupMenuItem(
                                  value: 'variant',
                                  child: Text('비슷한 문제 만들기'),
                                ),
                            ],
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Text('더 알아보기 ▾'),
                            ),
                          ),
                        ),
                    ],
                    if (question.written && showingSolution && !checked)
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => check(index, false),
                            child: const Text('다시 공부할래요'),
                          ),
                          FilledButton(
                            onPressed: saving ? null : () => check(index, true),
                            child: const Text('맞았어요'),
                          ),
                        ],
                      )
                    else
                      FilledButton(
                        onPressed: checked
                            ? () => setState(() {
                                position++;
                                selection = null;
                                writtenAnswer = '';
                                showingSolution = false;
                                showingHint = false;
                              })
                            : question.written
                            ? !flashcards && writtenAnswer.trim().isEmpty
                                  ? null
                                  : () => setState(() => showingSolution = true)
                            : selection == null || saving
                            ? null
                            : () => check(index, selection!),
                        child: Text(
                          checked
                              ? (position + 1 == order.length
                                    ? '결과 보기'
                                    : '다음 문제')
                              : question.written
                              ? flashcards
                                    ? '카드 뒤집기'
                                    : '모범 답안 보기'
                              : '정답 확인',
                        ),
                      ),
                  ],
          ),
        ),
      ),
    );
  }
}
