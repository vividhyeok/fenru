import 'package:flutter/material.dart';
import '../core/workspace.dart';
import 'theme.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<Onboarding> createState() => _OnboardingState();
}
class _OnboardingState extends State<Onboarding> {
  late int step = int.tryParse(widget.workspace.preferences['onboardingStep'] ?? '') ?? 0;
  bool saving = false;
  Future<void> go(int value) async {
    setState(() => saving = true);
    try {
      await widget.workspace.setPreference('onboardingStep', '$value');
      if (value == 5) await widget.workspace.setPreference('onboarding', 'complete');
      if (mounted) setState(() { step = value; saving = false; });
    } catch (_) { if (mounted) setState(() => saving = false); }
  }
  static const titles = ['배움이 이어지는 공간, Fenru', '자료는 내 기기에 안전하게', '학교 자료를 한곳에', '문서를 읽고, 생각을 기록하세요', '준비가 끝났습니다'];
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 650), child: SingleChildScrollView(
      padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [FenruMark(size: 48), SizedBox(width: 12), Text('Fenru', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 36),
        LinearProgressIndicator(value: (step + 1) / 5),
        const SizedBox(height: 24),
        Text('${step + 1} / 5', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        Text(titles[step.clamp(0, 4)], style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        Text(switch (step) {
          0 => '강의자료, PDF, 노트와 학습 일정을 한곳에서 관리하세요.\n인터넷이나 API 키 없이도 자료를 읽고 기록할 수 있습니다.',
          1 => '가져온 파일은 앱의 작업 공간에 복사됩니다. 원본 파일은 변경하지 않습니다.\n노트와 읽던 위치는 자동 저장됩니다. ZIP 백업으로 다른 기기로 옮길 수 있습니다.',
          2 => '설정에서 학교 Canvas 주소와 개인 액세스 토큰을 연결할 수 있습니다.\n학교 연결은 선택 사항이며 언제든 나중에 설정할 수 있습니다.',
          3 => 'PDF의 페이지를 이동하고 책갈피와 페이지 메모를 남기세요.\nMarkdown 노트는 자동 저장되며 문서에 연결할 수 있습니다.\nAI 및 Google Drive 연결은 이 개발 버전에서 아직 제공되지 않습니다.',
          _ => '라이브러리의 파일 가져오기로 첫 자료를 추가하세요.\n설정 → 도움말에서 사용법, 백업과 복원을 확인할 수 있습니다.',
        }, style: const TextStyle(fontSize: 17, height: 1.8)),
        if (step == 1) ...[
          const SizedBox(height: 18), SelectableText(widget.workspace.root.path,
            style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 36),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if(step > 0) OutlinedButton(onPressed: saving ? null : () => go(step - 1), child: const Text('이전')),
          FilledButton(onPressed: saving ? null : () => go(step + 1),
            child: Text(step == 4 ? 'Fenru 시작하기' : '다음')),
          if(step == 0) TextButton(onPressed: saving ? null : () => go(5), child: const Text('연결 없이 먼저 사용하기')),
        ]),
      ]))))));
}

