import 'package:flutter/material.dart';

import '../core/workspace.dart';
import '../core/models.dart';
import '../features/ai/settings.dart';
import '../integrations/canvas.dart';
import '../integrations/credentials.dart';
import 'theme.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final aiKey = GlobalKey<AISettingsState>();
  final url = TextEditingController();
  final token = TextEditingController();
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
      token.clear();
      if (mounted) setState(() => status = '학교 연결 완료');
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: Navigator.canPop(context)
        ? AppBar(title: const Text('학교 · AI 빠른 연결'))
        : null,
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: busy ? null : start,
          child: const Text('Fenru 시작하기'),
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
                const Row(
                  children: [
                    FenruMark(size: 48),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Fenru 시작하기',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '학교와 AI를 여기서 바로 연결하세요. 입력 후 시작하기를 누르면 함께 저장합니다. 연결 없이 PDF를 읽고 필기할 수도 있습니다.',
                ),
                const SizedBox(height: 20),
                Text(
                  '학교 Canvas 연결 · 선택',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '학교 Canvas HTTPS 주소',
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
                  ),
                ),
                const Text('Canvas → 계정 → 설정에서 발급한 토큰을 입력하세요.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: busy ? null : connect,
                    child: const Text('학교 연결 확인 및 저장'),
                  ),
                ),
                if (status.isNotEmpty) Text(status),
                const Divider(height: 32),
                Text(
                  'AI 연결 · 선택',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                AISettings(
                  key: aiKey,
                  workspace: widget.workspace,
                  embedded: true,
                ),
                const Divider(height: 32),
                const Text(
                  'API 키와 토큰은 기기의 보안 저장소에 보관됩니다. 연결은 나중에도 변경할 수 있습니다.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
