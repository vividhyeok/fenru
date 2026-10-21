import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/models.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/ai/chat.dart';
import 'package:fenru/features/ai/study_context.dart';
import 'package:fenru/integrations/ai.dart';
import 'package:fenru/integrations/credentials.dart';
import 'package:fenru/ui/shell.dart';

void main() {
  test('cancelled local retrieval does not read documents', () async {
    final root = await Directory.systemTemp.createTemp('fenru-context-cancel-');
    final w = Workspace(root, WorkspaceDatabase.memory());
    await w.initialize();
    try {
      await expectLater(
        StudyContextService(
          w,
          isCancelled: () => true,
          pageLoader: (_) => throw StateError('must not read'),
        ).pages(await w.save('document', {'title': 'A.pdf'})),
        throwsA(isA<UserFacingException>()),
      );
    } finally {
      await w.close();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'mobile course entry opens a scoped study workspace without a standalone AI destination',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-course-ui-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      late WorkspaceObject course;
      await tester.runAsync(() async {
        course = await w.save('course', {'title': 'Biology'});
        await w.save('document', {
          'title': 'Plants.pdf',
          'folder': course.title,
        });
      });
      await tester.pumpWidget(MaterialApp(home: FenruShell(workspace: w)));
      await tester.pumpAndSettle();
      expect(find.text('AI'), findsNothing);
      await tester.tap(find.text('과목').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(course.title));
      await tester.pumpAndSettle();
      expect(find.text('Plants.pdf'), findsOneWidget);
      await tester.tap(find.text('이 과목 자료에 질문하기'));
      await tester.pumpAndSettle();
      expect(tester.widget<AIChat>(find.byType(AIChat)).courseId, course.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    },
  );
  test('retrieval respects course identity, finds later pages, excludes other courses and deleted documents', () async {
    final root = await Directory.systemTemp.createTemp('fenru-context-');
    final w = Workspace(root, WorkspaceDatabase.memory());
    await w.initialize();
    try {
      final course = await w.save('course', {
        'title': 'Renamed course',
        'source': 'https://school.edu/courses/1',
      });
      final previous = await w.save('document', {
        'title': 'Old Biology.pdf',
        'folder': 'Old title',
        'origin': {'source': course.text('source')},
      });
      final own = await w.save('document', {
        'title': 'Biology.pdf',
        'folder': 'Old title',
        'hash': 'v1',
        'previousVersion': previous.id,
        'origin': {'source': course.text('source')},
      });
      await w.save('document', {
        'title': 'Other.pdf',
        'folder': course.title,
        'origin': {'source': 'https://school.edu/courses/2'},
      });
      final deleted = await w.save('document', {
        'title': 'Deleted.pdf',
        'folder': course.title,
      });
      await w.trash(deleted);
      final docs = StudyContextService.courseDocuments(w, course);
      expect(docs.map((d) => d.id), [own.id]);
      final result = await StudyContextService(
        w,
        pageLoader: (_) async => [
          'Introduction to biology',
          'Plants contain chlorophyll. Photosynthesis converts light to chemical energy.',
        ],
      ).retrieve(docs, 'Explain photosynthesis');
      expect(result.excerpts.first.page, 2);
      expect(result.excerpts.first.versionHash, 'v1');
      expect(
        result.referenceText,
        contains('fenru://document/${own.id}?page=2'),
      );
      final scanned = await StudyContextService(
        w,
        pageLoader: (_) async => [''],
      ).retrieve(docs, 'question');
      expect(scanned.excerpts, isEmpty);
      expect(scanned.notices.single, contains('OCR'));
    } finally {
      await w.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'context has a fixed payload bound and samples more than one document',
    () {
      final candidates = [
        for (var doc = 0; doc < 3; doc++)
          for (var page = 1; page <= 20; page++)
            DocumentContext(
              documentId: 'd$doc',
              title: 'Lecture $doc',
              page: page,
              text: 'x' * 1800,
              versionHash: 'v1',
            ),
      ];
      final result = StudyContextService.rank(candidates, 'summarize');
      expect(result.length, lessThanOrEqualTo(6));
      expect(result.map((e) => e.documentId).toSet().length, 3);
      expect(
        result.fold<int>(0, (n, e) => n + e.text.length),
        lessThanOrEqualTo(12000),
      );
    },
  );
  testWidgets(
    'course chat sends only course evidence, stores scope and exposes sources',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-chat-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      late WorkspaceObject course, own, other;
      await tester.runAsync(() async {
        course = await w.save('course', {
          'title': 'Biology',
          'source': 'school/course1',
        });
        own = await w.save('document', {
          'title': 'Plants.pdf',
          'folder': course.title,
          'origin': {'source': course.text('source')},
        });
        other = await w.save('document', {
          'title': 'Private other course',
          'folder': 'Other',
        });
        await w.setPreference('ai.openai.model', 'test-model');
      });
      final provider = _Provider();
      await tester.pumpWidget(
        MaterialApp(
          home: AIChat(
            workspace: w,
            courseId: course.id,
            scopeTitle: course.title,
            credentialStore: _Credentials(),
            providerFactory: (_, _) => provider,
            contextService: StudyContextService(
              w,
              pageLoader: (doc) async => [
                doc.id == own.id
                    ? 'Photosynthesis needs sunlight.'
                    : 'OTHER COURSE SECRET',
              ],
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Explain photosynthesis',
      );
      await tester.tap(find.byTooltip('질문 보내기'));
      for (var i = 0; i < 30 && w.ofKind('message').length < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        provider.payload.last['content'],
        contains('Photosynthesis needs sunlight'),
      );
      expect(
        provider.payload.last['content'],
        isNot(contains('OTHER COURSE SECRET')),
      );
      expect(w.ofKind('chat').single.text('courseId'), course.id);
      expect(w.ofKind('chat').single.text('documentId'), '');
      expect(
        (w.ofKind('message').last.data['sources'] as List).single['documentId'],
        own.id,
      );
      expect(find.text('Plants.pdf · 1쪽'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: AIChat(
            key: const ValueKey('different-document'),
            workspace: w,
            documentId: other.id,
            scopeTitle: other.title,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Plants use sunlight.'), findsNothing);
      expect(find.text('Plants.pdf · 1쪽'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    },
  );
  for (final width in [390.0, 768.0, 844.0]) {
    testWidgets('scoped chat fits keyboard at width $width', (tester) async {
      tester.view.physicalSize = Size(width, width == 844 ? 390 : 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(
        bottom: width == 844 ? 180 : 300,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-chat-layout-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      await tester.pumpWidget(
        MaterialApp(
          home: AIChat(
            workspace: w,
            documentId: 'doc',
            scopeTitle: 'Long document title for studying',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('질문 보내기'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    });
  }
}

class _Credentials implements CredentialStore {
  @override
  Future<String?> read(String key) async => 'test-not-real';
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

class _Provider implements AIProvider {
  List<Json> payload = [];
  @override
  Future<List<String>> models() async => ['test-model'];
  @override
  Stream<AIDelta> respond({
    required String model,
    required List<Json> messages,
    required int maxOutputTokens,
    required CancelToken cancel,
  }) async* {
    payload = messages;
    yield const AIDelta(
      text: 'Plants use sunlight.',
      inputTokens: 10,
      outputTokens: 5,
      complete: true,
    );
  }
}
