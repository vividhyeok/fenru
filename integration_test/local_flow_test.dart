import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:archive/archive.dart';
import 'package:fenru/main.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/ai/study_context.dart';
import 'package:fenru/features/reader/ink.dart';
import 'package:fenru/ui/note_editor.dart';
import 'package:fenru/integrations/pdf_conversion.dart';
import 'package:fenru/integrations/canvas.dart';

import '../test/pdf_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Canvas body and Android office text become searchable PDFs', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('fenru-convert-test-');
    final w = Workspace(root, WorkspaceDatabase.memory());
    await w.initialize();
    try {
      final course = await w.save('course', {
        'title': 'Course',
        'source': 'https://example.com/courses/1',
      });
      final report = CanvasImportReport()
        ..contents['announcement'] = {
          'title': '공지',
          'body': '시험 범위는 광합성입니다.',
          'url': 'https://example.com/announcement',
          'posted': '',
          'updated': '',
          'contentType': '공지',
        };
      final provider = CanvasProvider('https://example.com', 'fixture');
      await provider.saveCourseContents(w, course, report);
      final notice = StudyContextService.courseDocuments(w, course).single;
      expect(notice.text('extension'), '.pdf');
      expect(
        (await StudyContextService(w).pages(notice)).join(),
        contains('시험 범위는 광합성입니다.'),
      );
      await provider.saveCourseContents(w, course, report);
      expect(w.ofKind('document'), hasLength(2));
      if (Platform.isAndroid) {
        for (final (extension, member) in [
          ('pptx', 'ppt/slides/slide1.xml'),
          ('hwpx', 'Contents/section0.xml'),
          ('docx', 'word/document.xml'),
        ]) {
          final archive = Archive()
            ..addFile(
              ArchiveFile.string(member, '<doc><p><t>한글 강의 본문</t></p></doc>'),
            );
          final original = await File('${root.path}/lecture.$extension')
              .writeAsBytes(ZipEncoder().encode(archive));
          final pdf = await importStudyFile(w, original.path);
          expect(pdf.flag('conversionTextOnly'), isTrue);
          expect(
            (await StudyContextService(w).pages(pdf)).join(),
            contains('한글 강의 본문'),
          );
          expect(
            w.byId(pdf.text('derivedFrom'))?.text('pdfDocumentId'),
            pdf.id,
          );
        }
      }
    } finally {
      await w.close();
      await root.delete(recursive: true);
    }
  });
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
        child: FenruApp(workspace: w),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결 설정 보기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Fenru 시작하기'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Fenru 시작하기'));
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
    await tester.pumpAndSettle();
    final visiblePage = tester
        .getRect(find.byType(InkSurface).first)
        .intersect(tester.getRect(find.byType(PdfViewer)));
    final beforeTouch = controller.value.clone();
    await tester.dragFrom(visiblePage.center, const Offset(0, -55));
    await tester.pumpAndSettle();
    expect(controller.value, beforeTouch);
    expect(w.ofKind('annotation'), isEmpty);

    final left = await tester.startGesture(
      visiblePage.center - const Offset(45, 0),
    );
    final right = await tester.startGesture(
      visiblePage.center + const Offset(45, 0),
    );
    final zoomAtTouch = controller.currentZoom;
    await left.moveBy(const Offset(-30, 0));
    await right.moveBy(const Offset(30, 0));
    expect(controller.currentZoom, greaterThan(zoomAtTouch));
    await left.moveBy(const Offset(25, 0));
    await right.moveBy(const Offset(-25, 0));
    expect(controller.currentZoom, lessThan(zoomAtTouch * 1.4));
    await right.up();
    final afterPinch = controller.value.clone();
    await left.moveBy(const Offset(0, -35));
    await left.up();
    await tester.pumpAndSettle();
    expect(controller.value, afterPinch);
    expect(w.ofKind('annotation'), isEmpty);

    final pen = await tester.startGesture(
      visiblePage.center - const Offset(40, 0),
      kind: ui.PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(40, 20));
    await pen.moveBy(const Offset(40, -30));
    await pen.up();
    await tester.pumpAndSettle();
    for (var i = 0; i < 30 && w.ofKind('annotation').isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(w.ofKind('annotation').single.text('type'), 'ink');
    expect(
      (w.ofKind('annotation').single.data['points'] as List).length,
      greaterThan(1),
    );
    await tester.tap(find.byTooltip('읽기 · 선택 · 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-page-options')));
    await tester.pumpAndSettle();
    final zoomBefore = controller.currentZoom;
    await tester.ensureVisible(find.byTooltip('확대'));
    await tester.tap(find.byTooltip('확대'));
    await tester.pumpAndSettle();
    expect(controller.currentZoom, greaterThan(zoomBefore));
    await tester.ensureVisible(find.text('너비 맞춤'));
    await tester.tap(find.text('너비 맞춤'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('PDF 본문 검색'));
    await tester.tap(find.text('PDF 본문 검색'));
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
    await tester.tap(find.text('나중에 확인').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '남겨둘 질문 (선택)'),
      'What should I check next?',
    );
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(
      w.ofKind('studyAnchor').single.text('body'),
      'What should I check next?',
    );
    expect(w.ofKind('chat'), isEmpty);
    await controller.textSelectionDelegate.selectAllText();
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
    await tester.tap(find.byKey(const ValueKey('reader-page-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('책갈피 추가'));
    await tester.pumpAndSettle();
    expect(
      w
          .ofKind('annotation')
          .where((a) => a.text('documentId') == doc.id)
          .length,
      3,
    );
    await tester.tap(find.byKey(const ValueKey('reader-page-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자료 옆 정리 노트'));
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
    await tester.tap(find.byTooltip('노트 PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF로 만들어 필기하기'));
    for (var i = 0; i < 100 && w.ofKind('document').length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pumpAndSettle();
    final notePdf = w
        .ofKind('document')
        .singleWhere((item) => item.id != doc.id);
    expect(notePdf.text('extension'), '.pdf');
    expect(
      (await StudyContextService(w).pages(notePdf)).join(),
      contains('My study summary'),
    );
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
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
    expect(reopened.byId(doc.id)?.kind, 'document');
    final anchor = reopened.ofKind('studyAnchor').single;
    expect(anchor.text('selection'), contains('Fenru learning workspace'));
    expect(anchor.data['bounds'], hasLength(4));
    await tester.pumpWidget(FenruApp(workspace: reopened));
    await tester.pumpAndSettle();
    expect(find.text('이어서 공부하기'), findsOneWidget);
    await tester.tap(find.textContaining('What should I check next?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('질문 이어가기'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'What should I check next?'),
      findsOneWidget,
    );
    expect(reopened.ofKind('chat'), isEmpty);
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('해결했음'));
    await tester.pumpAndSettle();
    expect(reopened.byId(anchor.id)!.flag('resolved'), isTrue);
    expect(reopened.ofKind('annotation'), hasLength(3));
    await tester.pumpWidget(const SizedBox());
    await reopened.close();
    await root.delete(recursive: true);
  });
}
