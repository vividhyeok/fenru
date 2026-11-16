import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/reader/reading_tools.dart';
import 'package:fenru/features/ai/chat.dart';
import 'package:fenru/features/ai/course_workspace.dart';
import 'package:fenru/features/ai/study_context.dart';

void main() {
  test(
    'view settings are document-specific and tolerate damaged preferences',
    () async {
      final root = await Directory.systemTemp.createTemp('fenru-reader-view-');
      final w = Workspace(root, WorkspaceDatabase.memory());
      await w.initialize();
      try {
        await const ReaderViewSettings(
          fit: 'width',
          zoom: 2.5,
          x: 100,
          y: 820,
          panelWidth: 500,
          showAI: false,
        ).save(w, 'a');
        final loaded = ReaderViewSettings.read(w, 'a');
        expect(loaded.fit, 'width');
        expect(loaded.zoom, 2.5);
        expect(loaded.x, 100);
        expect(loaded.y, 820);
        expect(loaded.panelWidth, 500);
        expect(loaded.showAI, isFalse);
        expect(ReaderViewSettings.read(w, 'b').showAI, isTrue);
        await w.setPreference('reader.view.a', '{broken');
        expect(ReaderViewSettings.read(w, 'a').zoom, 1);
      } finally {
        await w.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'presets survive reload and invalid entries keep safe defaults',
    () async {
      final root = await Directory.systemTemp.createTemp('fenru-presets-');
      final w = Workspace(root, WorkspaceDatabase.memory());
      await w.initialize();
      try {
        await const PenPreset('custom', 'marker', 0xff00aa00, 4).save(w, 0);
        final loaded = PenPreset.read(w);
        expect(loaded[0].tool, 'marker');
        expect(loaded[0].color, 0xff00aa00);
        expect(loaded[0].width, 4);
        expect(loaded[1].tool, 'pen');
        await w.setPreference(
          'reader.preset.0',
          '{"tool":"erase","color":-1,"width":-1}',
        );
        expect(PenPreset.read(w)[0].color, PenPreset.defaults[0].color);
      } finally {
        await w.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'new sync markers remain read until a different revision arrives',
    () async {
      final root = await Directory.systemTemp.createTemp('fenru-sync-read-');
      final w = Workspace(root, WorkspaceDatabase.memory());
      await w.initialize();
      try {
        final legacy = await w.save('document', {'title': 'legacy'});
        expect(isNewSynced(w, legacy), isFalse);
        final doc = await w.save('document', {
          'title': 'notice',
          'syncedAt': 'revision-one',
        });
        expect(isNewSynced(w, doc), isTrue);
        await markSyncSeen(w, doc);
        expect(isNewSynced(w, doc), isFalse);
        final updated = await w.save('document', {
          ...doc.data,
          'syncedAt': 'revision-two',
        }, id: doc.id);
        expect(isNewSynced(w, updated), isTrue);
      } finally {
        await w.close();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets('new materials filter hides legacy and acknowledged documents', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fenru-new-filter-'),
    ))!;
    final w = Workspace(root, WorkspaceDatabase.memory());
    await tester.runAsync(w.initialize);
    final course = (await tester.runAsync(
      () => w.save('course', {'title': 'Biology'}),
    ))!;
    await tester.runAsync(() async {
      await w.save('document', {'title': 'Old lecture', 'folder': 'Biology'});
      await w.save('document', {
        'title': 'New notice',
        'folder': 'Biology',
        'contentType': '공지',
        'syncedAt': 'revision1',
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CourseWorkspace(workspace: w, course: course),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('새 자료 1개'), findsOneWidget);
    await tester.tap(find.text('새 자료 1개'));
    await tester.pumpAndSettle();
    expect(find.text('Old lecture'), findsNothing);
    expect(find.text('New notice'), findsOneWidget);
    await tester.tap(find.text('모두 확인한 것으로 표시'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(find.text('새 자료 0개'), findsOneWidget);
    expect(find.text('새로 확인할 자료가 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await w.close();
      await root.delete(recursive: true);
    });
  });
  testWidgets(
    'reference scope shows the current page next to input and updates with reader',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fenru-scope-label-'),
      ))!;
      final w = Workspace(root, WorkspaceDatabase.memory());
      await tester.runAsync(w.initialize);
      await tester.runAsync(
        () => w.setPreference('reader.referenceMode', 'current'),
      );
      Widget chat(int page) => MaterialApp(
        home: AIChat(
          workspace: w,
          documentId: 'doc',
          scopeTitle: 'Lecture',
          currentPageNumber: page,
          contextResolver: (_, _) async => const StudyContext([]),
        ),
      );
      await tester.pumpWidget(chat(7));
      await tester.pumpAndSettle();
      expect(find.text('참조: 현재 7쪽'), findsOneWidget);
      await tester.pumpWidget(chat(12));
      await tester.pumpAndSettle();
      expect(find.text('참조: 현재 12쪽'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await w.close();
        await root.delete(recursive: true);
      });
    },
  );
}
