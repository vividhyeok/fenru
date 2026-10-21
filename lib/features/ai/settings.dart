import 'package:flutter/material.dart';

import '../../core/workspace.dart';
import '../../core/models.dart';
import '../../integrations/ai.dart';
import '../../integrations/credentials.dart';

class AISettings extends StatefulWidget {
  const AISettings({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<AISettings> createState() => _AISettingsState();
}

class _AISettingsState extends State<AISettings> {
  AIService service = AIService.openai;
  final keyField = TextEditingController();
  final model = TextEditingController();
  final output = TextEditingController();
  final budget = TextEditingController();
  List<String> models = [];
  bool busy = false;
  String status = '';
  String get prefix => 'ai.${service.name}';
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    model.text = widget.workspace.preferences['$prefix.model'] ?? '';
    output.text = widget.workspace.preferences['ai.output'] ?? '2048';
    budget.text = widget.workspace.preferences['ai.dailyBudget'] ?? '50000';
    keyField.clear();
    models = [];
    status = '';
  }

  Future<void> act(Future<void> Function() action) async {
    setState(() {
      busy = true;
      status = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => status = e is UserFacingException
              ? e.message
              : e is StateError
              ? e.message
              : '보안 저장소 또는 연결 작업에 실패했습니다. 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> check() => act(() async {
    final key = keyField.text.trim().isNotEmpty
        ? keyField.text.trim()
        : await SecureCredentials().read(prefix);
    if (key == null || key.isEmpty) throw StateError('API 키를 입력하세요.');
    final found = await OfficialAIProvider(service, key).models();
    if (mounted) {
      setState(() {
        models = found;
        status = '인증 성공 · ${found.length}개 모델. 텍스트 생성 모델을 선택하세요.';
      });
    }
  });
  Future<void> save() => act(() async {
    final maxOutput = int.tryParse(output.text),
        limit = int.tryParse(budget.text);
    if (model.text.trim().isEmpty ||
        maxOutput == null ||
        maxOutput < 256 ||
        maxOutput > 8192 ||
        limit == null ||
        limit < 1000) {
      throw StateError('모델 ID, 출력 256~8192 토큰, 일별 토큰 상한 1000 이상을 입력하세요.');
    }
    final credentials = SecureCredentials();
    if (keyField.text.trim().isNotEmpty) {
      await credentials.write(prefix, keyField.text.trim());
    }
    if (await credentials.read(prefix) == null) {
      throw StateError('API 키를 입력하세요.');
    }
    await widget.workspace.setPreference('$prefix.model', model.text.trim());
    await widget.workspace.setPreference('ai.provider', service.name);
    await widget.workspace.setPreference('ai.output', '$maxOutput');
    await widget.workspace.setPreference('ai.dailyBudget', '$limit');
    keyField.clear();
    if (mounted) setState(() => status = '저장되었습니다. 키는 기기의 보안 저장소에만 보관합니다.');
  });
  @override
  void dispose() {
    keyField.dispose();
    model.dispose();
    output.dispose();
    budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 연결 및 사용 한도')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'ChatGPT 구독과 API 과금은 별개입니다. 질문과 선택한 문서 내용이 해당 제공자에 전송됩니다.\n모델 목록 조회는 인증 확인이며 텍스트 생성 지원을 보장하지 않습니다.',
        ),
        const SizedBox(height: 20),
        SegmentedButton<AIService>(
          segments: const [
            ButtonSegment(value: AIService.openai, label: Text('OpenAI')),
            ButtonSegment(value: AIService.deepseek, label: Text('DeepSeek')),
          ],
          selected: {service},
          onSelectionChanged: busy
              ? null
              : (values) => setState(() {
                  service = values.first;
                  load();
                }),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: keyField,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '새 API 키',
            hintText: '빈칸이면 저장된 키 유지',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: busy ? null : check,
            child: const Text('연결 확인 · 모델 조회'),
          ),
        ),
        if (models.isNotEmpty)
          DropdownButtonFormField<String>(
            isExpanded: true,
            hint: const Text('조회한 모델 선택'),
            items: models
                .map(
                  (id) => DropdownMenuItem(
                    value: id,
                    child: Text(id, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) model.text = value;
            },
          ),
        const SizedBox(height: 16),
        TextField(
          controller: model,
          decoration: const InputDecoration(labelText: '모델 ID (직접 입력 가능)'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: output,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '요청당 최대 출력 토큰 (256~8192)',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: budget,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '일별 기록 토큰 상한 (금액 예산이 아님)',
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '실제 제공자가 보고한 입력/출력 토큰만 기록합니다. 취소·연결 실패 시 사용량이 누락될 수 있으며, API 청구는 제공자 대시보드가 기준입니다. 금액은 임의로 추정하지 않습니다.',
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(status),
          ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: busy ? null : save,
              child: const Text('저장'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => act(() async {
                      await SecureCredentials().delete(prefix);
                      await widget.workspace.setPreference('$prefix.model', '');
                      if (mounted) {
                        setState(() {
                          model.clear();
                          status = '이 제공자의 키를 삭제했습니다. 대화는 유지됩니다.';
                        });
                      }
                    }),
              child: const Text('연결 해제'),
            ),
          ],
        ),
      ],
    ),
  );
}
