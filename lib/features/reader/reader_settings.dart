import 'package:flutter/material.dart';

import '../../core/workspace.dart';

class ReaderSettings extends StatelessWidget {
  const ReaderSettings({super.key, required this.workspace});
  final Workspace workspace;

  Future<void> save(BuildContext context, String key, String value) async {
    try {
      await workspace.setPreference(key, value);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('설정을 저장하지 못했습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('읽기 · 필기 설정')),
    body: ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: workspace.preferences['reader.startTool'] == 'read'
                ? 'read'
                : 'pen',
            decoration: const InputDecoration(labelText: '문서를 열 때'),
            items: const [
              DropdownMenuItem(value: 'pen', child: Text('펜 모드')),
              DropdownMenuItem(value: 'read', child: Text('손 모드')),
            ],
            onChanged: (value) {
              if (value != null) save(context, 'reader.startTool', value);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue:
                workspace.preferences['reader.touchNavigation'] == 'oneFinger'
                ? 'oneFinger'
                : 'twoFingers',
            decoration: const InputDecoration(
              labelText: '화면 이동',
              helperText: '확대·축소는 두 손가락',
            ),
            items: const [
              DropdownMenuItem(value: 'twoFingers', child: Text('두 손가락')),
              DropdownMenuItem(value: 'oneFinger', child: Text('한 손가락도 허용')),
            ],
            onChanged: (value) {
              if (value != null) save(context, 'reader.touchNavigation', value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('S펜 버튼으로 지우기'),
            subtitle: const Text('누르는 동안만 지우개'),
            value:
                workspace.preferences['reader.stylusButtonEraser'] != 'false',
            onChanged: (value) =>
                save(context, 'reader.stylusButtonEraser', '$value'),
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
            onChanged: (value) {
              if (value != null) save(context, 'reader.theme', '$value');
            },
          ),
        ],
      ),
    ),
  );
}
