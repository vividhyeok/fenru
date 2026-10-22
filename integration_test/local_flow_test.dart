import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:fenru/main.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/ai/study_context.dart';
import 'package:fenru/features/reader/ink.dart';
import 'package:fenru/ui/note_editor.dart';

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
    final screenshotKey = GlobalKey();
    runApp(
      RepaintBoundary(
        key: screenshotKey,
        child: ProviderScope(
          overrides: [workspaceProvider.overrideWithValue(w)],
          child: FenruApp(workspace: w),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결 없이 먼저 사용하기'));
    await tester.pumpAndSettle();
    final source = File('${root.path}/Fenru-sample.pdf');
    await source.writeAsBytes(samplePdf());
    final doc = await w.importFile(source.path);
    final beforeReader = await StudyContextService(w)
        .retrieve([doc], 'learning workspace');
    expect(beforeReader.excerpts.first.page, 1);
    expect(beforeReader.referenceText, contains('Fenru learning workspace'));
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
    final evidence = await StudyContextService(w)
        .retrieve([doc], 'learning workspace');
    expect(evidence.excerpts.first.documentId, doc.id);
    expect(evidence.excerpts.first.page, 1);
    expect(evidence.referenceText, contains('Fenru learning workspace'));
    await tester.tap(find.byTooltip('읽기 · 필기 도구'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('펜 필기').last);
    await tester.pumpAndSettle();
    final visiblePage = tester
        .getRect(find.byType(InkSurface).first)
        .intersect(tester.getRect(find.byType(PdfViewer)));
    final pen = await tester.startGesture(
      visiblePage.center - const Offset(40, 0),
    );
    await pen.moveBy(const Offset(40, 20));
    await pen.moveBy(const Offset(40, -30));
    await pen.up();
    await tester.pumpAndSettle();
    expect(w.ofKind('annotation').single.text('type'), 'ink');
    expect(
      (w.ofKind('annotation').single.data['points'] as List).length,
      greaterThan(1),
    );
    await tester.tap(find.byTooltip('읽기 · 필기 도구'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('읽기 · 선택 · 이동'));
    await tester.pumpAndSettle();
    final zoomBefore = controller.currentZoom;
    await tester.ensureVisible(find.byTooltip('확대'));
    await tester.tap(find.byTooltip('확대'));
    await tester.pumpAndSettle();
    expect(controller.currentZoom, greaterThan(zoomBefore));
    await tester.ensureVisible(find.text('너비 맞춤'));
    await tester.tap(find.text('너비 맞춤'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('PDF 본문 검색'));
    await tester.tap(find.byTooltip('PDF 본문 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pdf-search')),
      'learning',
    );
    await tester.tap(find.byTooltip('본문 검색 실행'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('1/1'), findsOneWidget);
    await tester.tap(find.byTooltip('검색 닫기'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    if (Platform.isWindows) {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('dist/qa').create(recursive: true);
      await File('dist/qa/reader-native-scoped.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
    await controller.textSelectionDelegate.selectAllText();
    expect(
      await controller.textSelectionDelegate.getSelectedText(),
      contains('Fenru learning workspace'),
    );
    await tester.tap(find.byKey(const ValueKey('reader-document-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택 영역 하이라이트'));
    await tester.pumpAndSettle();
    expect(
      w.ofKind('annotation').where((a) => a.text('type') == 'highlight').length,
      1,
    );
    await tester.ensureVisible(find.byTooltip('주석 실행 취소'));
    await tester.tap(find.byTooltip('주석 실행 취소'));
    await tester.pumpAndSettle();
    expect(w.ofKind('annotation').single.text('type'), 'ink');
    await tester.ensureVisible(find.byTooltip('주석 다시 실행'));
    await tester.tap(find.byTooltip('주석 다시 실행'));
    await tester.pumpAndSettle();
    expect(
      w.ofKind('annotation').where((a) => a.text('type') == 'highlight').length,
      1,
    );
    await tester.tap(find.byTooltip('책갈피 추가'));
    await tester.pumpAndSettle();
    expect(
      w
          .ofKind('annotation')
          .where((a) => a.text('documentId') == doc.id)
          .length,
      3,
    );
    await tester.tap(find.byTooltip('자료 옆 정리 노트'));
    await tester.pumpAndSettle();
    final noteBody = find
        .descendant(
          of: find.byType(NoteEditor),
          matching: find.byType(TextField),
        )
        .last;
    await tester.enterText(
      noteBody,
      'My study summary: light energy becomes chemical energy.',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(w.ofKind('note').single.text('body'), contains('My study summary'));
    // Narrow windows open a note route; wide windows keep it alongside the PDF.
    if (MediaQuery.sizeOf(tester.element(find.byType(NoteEditor))).width <
        1100) {
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await w.close();
    final reopened = Workspace(
      root,
      WorkspaceDatabase(File('${root.path}/workspace.sqlite')),
    );
    await reopened.initialize();
    expect(reopened.ofKind('annotation').length, 3);
    expect(
      reopened.ofKind('note').single.text('body'),
      contains('My study summary'),
    );
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
