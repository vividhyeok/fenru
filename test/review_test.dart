import 'dart:convert';

import 'package:fenru/features/ai/review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final question = {
    'question': 'Which is correct?',
    'choices': ['A', 'B', 'C', 'D'],
    'answer': 1,
    'explanation': 'B follows from the source.',
    'source': 'fenru://document/example?page=2',
  };

  test('review parses JSON wrapped in a Markdown code fence', () {
    final fence = String.fromCharCodes([96, 96, 96]);
    final parsed = ReviewQuestion.parse(
      '${fence}json\n${jsonEncode([question])}\n$fence',
    );
    expect(parsed.single.answer, 1);
    expect(parsed.single.source, question['source']);
  });

  test('review rejects out-of-range answers and duplicate choices', () {
    for (final invalid in [
      {...question, 'answer': 4},
      {
        ...question,
        'choices': ['A', 'A', 'C', 'D'],
      },
    ]) {
      expect(ReviewQuestion.parse(jsonEncode([invalid])), isEmpty);
    }
  });

  test('stored help is optional and preserves the order of choice reasons', () {
    final supported = {
      ...question,
      'hint': 'Check the definition.',
      'steps': ['Read the condition.', 'Apply the definition.'],
      'choiceReasons': ['A reason', 'B reason', 'C reason', 'D reason'],
      'takeaway': 'Check the condition first.',
    };
    final parsed = ReviewQuestion.parse(jsonEncode([supported])).single;
    expect(parsed.hint, supported['hint']);
    expect(parsed.steps, supported['steps']);
    expect(parsed.choiceReasons[parsed.answer], 'B reason');
    expect(parsed.takeaway, supported['takeaway']);
    final malformed = ReviewQuestion.parse(
      jsonEncode([
        {
          ...supported,
          'choiceReasons': ['A reason', '', 'C reason', 'D reason'],
        },
      ]),
    ).single;
    expect(malformed.choiceReasons, isEmpty);
    expect(ReviewQuestion.parse(jsonEncode([question])).single.hint, isEmpty);
  });

  test('written questions preserve their concept and learning objective', () {
    final parsed = ReviewQuestion.parse(
      jsonEncode([
        {
          ...question,
          'choices': <String>[],
          'answer': -1,
          'concept': 'Energy',
          'objective': 'Explain conservation',
        },
      ]),
    );
    expect(parsed.single.written, isTrue);
    expect(parsed.single.concept, 'Energy');
    expect(parsed.single.objective, 'Explain conservation');
  });
}
