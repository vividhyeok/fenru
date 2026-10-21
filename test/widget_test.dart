import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/ui/onboarding.dart';

void main() {
  testWidgets('onboarding can enter local-only workspace', (tester) async {
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fenru-widget-'),
    ))!;
    final w = Workspace(temp, WorkspaceDatabase.memory());
    await tester.runAsync(w.initialize);
    await tester.pumpWidget(MaterialApp(home: Onboarding(workspace: w)));
    expect(find.text('배움이 이어지는 공간, Fenru'), findsOneWidget);
    await tester.tap(find.text('연결 없이 먼저 사용하기'));
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
