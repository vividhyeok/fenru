import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/ui/onboarding.dart';

void main() {
  testWidgets(
    'setup keeps typed credentials while scrolling and rejects incomplete AI setup',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-setup-input-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      await tester.pumpWidget(MaterialApp(home: Onboarding(workspace: w)));
      final key = find.widgetWithText(TextField, '새 API 키');
      await tester.ensureVisible(key);
      await tester.enterText(key, 'fixture-key');
      await tester.tap(find.widgetWithText(FilledButton, 'Fenru 시작하기'));
      await tester.pumpAndSettle();
      expect(w.preferences['onboarding'], isNull);
      expect(tester.widget<TextField>(key).controller!.text, 'fixture-key');
      expect(find.text('AI 연결 입력을 확인하세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    },
  );
  testWidgets('onboarding can enter local-only workspace', (tester) async {
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fenru-widget-'),
    ))!;
    final w = Workspace(temp, WorkspaceDatabase.memory());
    await tester.runAsync(w.initialize);
    await tester.pumpWidget(MaterialApp(home: Onboarding(workspace: w)));
    expect(find.text('학교 Canvas HTTPS 주소'), findsOneWidget);
    expect(find.text('새 API 키'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Fenru 시작하기'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Fenru 시작하기'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(w.preferences['onboarding'], 'complete');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await w.close();
      await temp.delete(recursive: true);
    });
  });
}
