import 'package:flutter/material.dart';

import '../core/workspace.dart';
import '../core/models.dart';
import '../features/ai/settings.dart';
import '../integrations/canvas.dart';
import '../integrations/credentials.dart';
import 'theme.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({
    super.key,
    required this.workspace,
    this.showSetup = false,
  });
  final Workspace workspace;
  final bool showSetup;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final aiKey = GlobalKey<AISettingsState>();
  final url = TextEditingController();
  final token = TextEditingController();
  late bool setup = widget.showSetup;
  bool busy = false;
  String status = '';
  @override
  void initState() {
    super.initState();
    url.text = widget.workspace.preferences['canvasUrl'] ?? '';
  }

  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  Future<bool> connect() async {
    setState(() {
      busy = true;
      status = '';
    });
    try {
      if (token.text.trim().isEmpty) {
        throw const UserFacingException('토큰을 입력하세요.');
      }
      final provider = CanvasProvider(url.text.trim(), token.text.trim());
      await provider.courses();
      await SecureCredentials().write('canvas', token.text.trim());
      await widget.workspace.setPreference('canvasUrl', provider.base.origin);
      if (mounted) {
        token.clear();
        setState(() => status = '학교 연결 완료');
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(
          () => status = e is UserFacingException
              ? e.message
              : '연결하지 못했습니다. 주소와 토큰을 확인하세요.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start() async {
    if (aiKey.currentState?.busy == true) return;
    setState(() => busy = true);
    try {
      if (aiKey.currentState?.needsSave == true &&
          !await aiKey.currentState!.saveForStart()) {
        if (mounted) setState(() => status = 'AI 연결 입력을 확인하세요.');
        return;
      }
      if (token.text.trim().isNotEmpty && !await connect()) return;
      if (!mounted) return;
      await widget.workspace.setPreference('onboarding', 'complete');
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => status = '저장하지 못했습니다. 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get canvasConfigured =>
      (widget.workspace.preferences['canvasUrl'] ?? '').isNotEmpty;

  bool get aiConfigured {
    final preferences = widget.workspace.preferences;
    final provider = preferences['ai.provider'];
    return provider != null &&
        (preferences['ai.$provider.model'] ?? '').isNotEmpty;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(setup ? '연결 설정' : '조작 안내')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(status),
              ),
            FilledButton(
              onPressed: busy
                  ? null
                  : setup
                  ? start
                  : () => setState(() => setup = true),
              child: Text(setup ? 'Fenru 시작하기' : '연결 설정 보기'),
            ),
          ],
        ),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const FenruMark(size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        setup ? '학교와 AI 연결' : 'PDF 읽기와 필기',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!setup) ...[
                  const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('S펜으로 필기'),
                    subtitle: Text('버튼을 누르는 동안 지우기'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.pinch_outlined),
                    title: Text('두 손가락으로 이동·확대'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.pan_tool_outlined),
                    title: Text('왼쪽 펜 아이콘을 눌러 손 모드'),
                    subtitle: Text('한 번 더 누르면 필기로 복귀'),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('설정 → 읽기 · 필기에서 조작을 바꿀 수 있어요.'),
                  ),
                ] else ...[
                  const Text('연결은 선택입니다. PDF 읽기와 필기는 바로 쓸 수 있어요.'),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    initiallyExpanded: !canvasConfigured,
                    maintainState: true,
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('Canvas'),
                    subtitle: Text(canvasConfigured ? '연결 저장됨' : '학교 주소와 토큰'),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      TextField(
                        controller: url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '학교 Canvas HTTPS 주소',
                          hintText: 'https://학교 Canvas 주소',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: token,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Canvas 개인 액세스 토큰',
                          helperText: 'Canvas → 계정 → 설정 → 새 액세스 토큰',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: busy ? null : connect,
                          child: const Text('학교 연결 확인 및 저장'),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    initiallyExpanded: !aiConfigured,
                    maintainState: true,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('AI'),
                    subtitle: Text(
                      aiConfigured ? '연결 저장됨' : '제공자 · API 키 · 모델',
                    ),
                    children: [
                      AISettings(
                        key: aiKey,
                        workspace: widget.workspace,
                        embedded: true,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
