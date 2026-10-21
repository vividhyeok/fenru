import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:fenru/main.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';

import '../test/pdf_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('onboard, import, render PDF, select text and persist bookmark', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('fenru-integration-');
    final w = Workspace(
      root,
      WorkspaceDatabase(File('${root.path}/workspace.sqlite')),
    );
    await w.initialize();
    runApp(
      ProviderScope(
        overrides: [workspaceProvider.overrideWithValue(w)],
        child: FenruApp(workspace: w),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결 없이 먼저 사용하기'));
    await tester.pumpAndSettle();
    final source = File('${root.path}/Fenru-sample.pdf');
    await source.writeAsBytes(samplePdf());
    final doc = await w.importFile(source.path);
    await tester.pumpAndSettle();
    await tester.tap(find.text('라이브러리').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fenru-sample.pdf').first);
    await tester.pumpAndSettle();
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final controller = viewer.controller!;
    for (int i = 0; i < 60 && !controller.isReady; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(controller.isReady, isTrue);
    expect(controller.pageCount, 1);
    final text = await controller.document.pages.first.loadText();
    expect(text!.fullText, contains('Fenru learning workspace'));
    await controller.textSelectionDelegate.selectAllText();
    expect(
      await controller.textSelectionDelegate.getSelectedText(),
      contains('Fenru learning workspace'),
    );
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택 영역 하이라이트'));
    await tester.pumpAndSettle();
    expect(w.ofKind('annotation').single.text('type'), 'highlight');
    await tester.tap(find.byTooltip('책갈피 추가'));
    await tester.pumpAndSettle();
    expect(
      w
          .ofKind('annotation')
          .where((a) => a.text('documentId') == doc.id)
          .length,
      2,
    );
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await w.close();
    final reopened = Workspace(
      root,
      WorkspaceDatabase(File('${root.path}/workspace.sqlite')),
    );
    await reopened.initialize();
    expect(reopened.ofKind('annotation').length, 2);
    expect(
      reopened
          .ofKind('annotation')
          .any(
            (a) =>
                a.text('type') == 'highlight' &&
                (a.data['rectangles'] as List).isNotEmpty,
          ),
      isTrue,
    );
    expect(reopened.ofKind('document').single.id, doc.id);
    await reopened.close();
    await root.delete(recursive: true);
  });
}
