import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/ai/chat.dart';
import 'package:fenru/features/ai/course_workspace.dart';
import 'package:fenru/ui/note_editor.dart';
import 'package:fenru/ui/theme.dart';

void main() {
  for (final width in [320.0, 420.0]) {
    testWidgets('reading space and save feedback in a $width chat panel', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-study-ui-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      await tester.runAsync(() async {
        final chat = await w.save('chat', {
          'title': '광합성의 의미',
          'documentId': 'plants',
        });
        await w.save('message', {
          'sessionId': chat.id,
          'role': 'user',
          'body': '광합성을 쉬운 예시로 설명해 줘.',
          'status': 'complete',
        });
        await w.save('message', {
          'sessionId': chat.id,
          'role': 'assistant',
          'status': 'complete',
          'body': '## 빛으로 만드는 에너지\n\n식물은 빛 에너지를 이용해 이산화탄소와 물로부터 당을 만듭니다.\n\n- **핵심:** 빛 에너지가 화학 에너지로 바뀝니다.\n- **확인 질문:** 식물의 질량은 어디에서 올까요?\n\n내 말로 설명한 뒤 원문과 비교해 보세요.',
          'sources': [
            {'documentId': 'plants', 'page': 2, 'title': '식물의 에너지.pdf'},
          ],
        });
      });
      await tester.runAsync(() async {
        final font = File('C:/Windows/Fonts/malgun.ttf');
        if (font.existsSync()) {
          final loader = FontLoader('Malgun Gothic')
            ..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            );
          await loader.load();
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      final capture = GlobalKey();
      final theme = FenruTheme.build(Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Malgun Gothic'),
          ),
          home: RepaintBoundary(
            key: capture,
            child: AIChat(
              workspace: w,
              documentId: 'plants',
              scopeTitle: '식물의 에너지.pdf',
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const ValueKey('chat-messages')),
      );
      expect(viewport.height, greaterThanOrEqualTo(600 * .75));
      expect(
        tester.getRect(find.byKey(const ValueKey('chat-input'))).bottom,
        lessThanOrEqualTo(600),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('dist/qa').create(recursive: true);
        await File('dist/qa/study-chat-${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.ensureVisible(find.text('노트로 저장'));
      await tester.tap(find.text('노트로 저장'));
      for (var i = 0; i < 30 && w.ofKind('note').isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('노트로 저장되었습니다.'), findsOneWidget);
      expect(find.text('노트 열기'), findsOneWidget);
      expect(w.ofKind('note').single.text('documentId'), 'plants');
      expect(
        (w.ofKind('note').single.data['sources'] as List).single['page'],
        2,
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(w.ofKind('note').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    });
  }

  testWidgets('course focus, history and study tools preserve drafts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fenru-study-focus-'),
    ))!;
    final w = Workspace(root, WorkspaceDatabase.memory());
    await tester.runAsync(w.initialize);
    final course = (await tester.runAsync(() async {
      final course = await w.save('course', {'title': '생물학'});
      await w.save('document', {'title': '식물.pdf', 'folder': course.title});
      await w.save('document', {'title': '세포.pdf', 'folder': course.title});
      await w.save('chat', {'title': '이전 복습 대화', 'courseId': course.id});
      return course;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: FenruTheme.build(Brightness.light),
        home: CourseWorkspace(workspace: w, course: course),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      '아직 보내지 않은 질문',
    );
    await tester.tap(find.byTooltip('질문 화면 넓게 보기'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-messages'))).width,
      greaterThan(1200),
    );
    expect(find.text('아직 보내지 않은 질문'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('자료와 나란히 보기'));
    await tester.pumpAndSettle();
    expect(find.text('아직 보내지 않은 질문'), findsOneWidget);
    await tester.tap(find.byTooltip('대화 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 대화'));
    await tester.pumpAndSettle();
    expect(find.text('아직 보내지 않은 질문'), findsNothing);
    await tester.tap(find.byTooltip('학습 질문 도구'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한 문제씩 복습').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      contains('내 답을 기다린 뒤'),
    );
    expect(w.ofKind('message'), isEmpty); // Templates never send automatically.
    await tester.tap(find.byTooltip('대화 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전 대화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전 복습 대화'));
    await tester.pumpAndSettle();
    expect(find.text('아직 보내지 않은 질문'), findsOneWidget);
    final search = find.widgetWithText(TextField, '이 과목 자료 찾기');
    await tester.enterText(search, '식물');
    await tester.pumpAndSettle();
    expect(find.text('식물.pdf'), findsOneWidget);
    expect(find.text('세포.pdf'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await w.close();
      await root.delete(recursive: true);
    });
  });
}
