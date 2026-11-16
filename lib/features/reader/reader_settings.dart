import 'package:flutter/material.dart';

import '../../core/workspace.dart';

class ReaderSettings extends StatelessWidget {
  const ReaderSettings({super.key, required this.workspace});
  final Workspace workspace;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('읽기 · 필기 설정')),
    body: ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('S펜으로 바로 쓰고, 버튼을 누른 동안 지웁니다. 버튼을 놓으면 사용하던 필기 도구로 돌아갑니다.'),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('손가락으로 필기'),
            subtitle: const Text('끄면 손가락은 문서 이동·확대에 사용합니다.'),
            value: workspace.preferences['reader.penOnly'] == 'false',
            onChanged: (value) async {
              try {
                await workspace.setPreference('reader.penOnly', '${!value}');
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('설정을 저장하지 못했습니다.')),
                  );
                }
              }
            },
          ),
          const Divider(height: 32),
          DropdownButtonFormField<int>(
            initialValue:
                (int.tryParse(workspace.preferences['reader.theme'] ?? '') ?? 0)
                    .clamp(0, 2),
            decoration: const InputDecoration(labelText: '읽기 배경'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('원본')),
              DropdownMenuItem(value: 1, child: Text('따뜻하게')),
              DropdownMenuItem(value: 2, child: Text('야간 읽기')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              try {
                await workspace.setPreference('reader.theme', '$value');
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('설정을 저장하지 못했습니다.')),
                  );
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}
