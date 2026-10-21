import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/ai/settings.dart';

void main() {
  testWidgets(
    'AI settings exposes an obscured BYOK field and configurable model',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-ai-settings-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      await tester.pumpWidget(MaterialApp(home: AISettings(workspace: w)));
      expect(find.text('새 API 키'), findsOneWidget);
      expect(find.text('연결 확인 · 모델 조회'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.obscureText, isTrue);
      expect(fields.first.enableSuggestions, isFalse);
      expect(fields[1].controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    },
  );
}
