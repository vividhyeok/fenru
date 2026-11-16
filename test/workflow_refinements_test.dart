import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/core/models.dart';
import 'package:fenru/features/ai/study_context.dart';
import 'package:fenru/features/reader/ink.dart';

void main() {
  test(
    'full PDF includes every page; range is sorted and deduplicated',
    () async {
      final root = await Directory.systemTemp.createTemp('fenru-scope-');
      final w = Workspace(root, WorkspaceDatabase.memory());
      await w.initialize();
      try {
        final doc = await w.save('document', {
          'title': 'Lecture',
          'extension': '.pdf',
        });
        final service = StudyContextService(
          w,
          pageLoader: (_) async =>
              List.generate(10, (i) => 'Complete text of page ${i + 1}'),
        );
        final full = await service.readScope(doc, 'full');
        expect(full.excerpts.length, 10);
        expect(full.excerpts.last.text, 'Complete text of page 10');
        final range = await service.readScope(doc, 'range', range: '8, 2-4, 3');
        expect(range.excerpts.map((e) => e.page), [2, 3, 4, 8]);
        expect(
          (await service.readScope(
            doc,
            'current',
            page: 7,
          )).excerpts.single.page,
          7,
        );
        for (final invalid in ['0', '3-2', '1-11', '', 'one']) {
          await expectLater(
            service.readScope(doc, 'range', range: invalid),
            throwsA(isA<UserFacingException>()),
          );
        }
      } finally {
        await w.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('duplicate files stay deduplicated within a folder and can belong to another course', () async {
    final root = await Directory.systemTemp.createTemp('fenru-folders-');
    final w = Workspace(root, WorkspaceDatabase.memory());
    await w.initialize();
    try {
      final source = File('${root.path}/lecture.txt');
      await source.writeAsString('Lecture');
      final first = await w.importFile(source.path, folder: 'A');
      expect((await w.importFile(source.path, folder: 'A')).id, first.id);
      final other = await w.importFile(source.path, folder: 'B');
      expect(other.id, isNot(first.id));
      expect(w.byId(first.id)!.text('folder'), 'A');
    } finally {
      await w.close();
      await root.delete(recursive: true);
    }
  });
  test('eraser catches crossed segments and ignores distant ink', () {
    final ink = {
      'points': [
        [.1, .5],
        [.9, .5],
      ],
      'width': 2,
      'tool': 'line',
    };
    expect(
      inkIntersects(ink, {
        'points': [
          [.5, .1],
          [.5, .9],
        ],
      }, const Size(600, 800)),
      isTrue,
    );
    expect(
      inkIntersects(ink, {
        'points': [
          [.1, .1],
          [.9, .1],
        ],
      }, const Size(600, 800)),
      isFalse,
    );
  });
  testWidgets(
    'pen-only surface passes finger drag to navigation and consumes stylus drag',
    (tester) async {
      var moves = 0, strokes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            onPanUpdate: (_) => moves++,
            child: SizedBox.expand(
              child: InkSurface(
                penOnly: true,
                tool: 'pen',
                color: 0xff234b80,
                width: 2,
                onSave: (_) async {
                  strokes++;
                },
              ),
            ),
          ),
        ),
      );
      final finger = await tester.startGesture(const Offset(100, 100));
      await finger.moveBy(const Offset(0, 70));
      await finger.moveBy(const Offset(0, 70));
      await finger.up();
      await tester.pumpAndSettle();
      expect(moves, greaterThan(0));
      expect(strokes, 0);
      moves = 0;
      final pen = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveBy(const Offset(60, 60));
      await pen.up();
      await tester.pumpAndSettle();
      expect(strokes, 1);
      expect(moves, 0);
    },
  );
  for (final button in [kPrimaryStylusButton, kSecondaryStylusButton]) {
    testWidgets(
      'stylus button $button temporarily erases and resumes pen in the same contact',
      (tester) async {
        final saved = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: InkSurface(
                tool: 'pen',
                color: 0xff234b80,
                width: 2,
                onSave: (data) async {
                  saved.add(data);
                },
              ),
            ),
          ),
        );
        const pointer = 5;
        await tester.sendEventToBinding(
          const PointerDownEvent(
            pointer: pointer,
            position: Offset(100, 100),
            kind: PointerDeviceKind.stylus,
            buttons: kPrimaryButton,
          ),
        );
        await tester.sendEventToBinding(
          PointerMoveEvent(
            pointer: pointer,
            position: const Offset(120, 120),
            kind: PointerDeviceKind.stylus,
            buttons: kPrimaryButton | button,
          ),
        );
        await tester.sendEventToBinding(
          const PointerMoveEvent(
            pointer: pointer,
            position: Offset(140, 140),
            kind: PointerDeviceKind.stylus,
            buttons: kPrimaryButton,
          ),
        );
        await tester.sendEventToBinding(
          const PointerUpEvent(
            pointer: pointer,
            position: Offset(140, 140),
            kind: PointerDeviceKind.stylus,
          ),
        );
        await tester.pumpAndSettle();
        expect(saved.map((s) => s['tool']), ['pen', 'eraser', 'pen']);
      },
    );
  }

  testWidgets(
    'reading keeps touch scrolling and erases only while the pen button is held',
    (tester) async {
      final saved = <Map<String, dynamic>>[];
      final changes = <bool>[];
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              ListView(
                controller: scroll,
                children: const [SizedBox(height: 2000)],
              ),
              InkSurface(
                tool: 'read',
                color: 0xff234b80,
                width: 2,
                onTemporaryEraser: changes.add,
                onSave: (stroke) async => saved.add(stroke),
              ),
            ],
          ),
        ),
      );
      await tester.dragFrom(const Offset(100, 300), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));

      await tester.sendEventToBinding(
        const PointerDownEvent(
          pointer: 50,
          position: Offset(100, 100),
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton | kPrimaryStylusButton,
        ),
      );
      await tester.sendEventToBinding(
        const PointerMoveEvent(
          pointer: 50,
          position: Offset(130, 100),
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton,
        ),
      );
      await tester.sendEventToBinding(
        const PointerUpEvent(
          pointer: 50,
          position: Offset(130, 100),
          kind: PointerDeviceKind.stylus,
        ),
      );
      await tester.pumpAndSettle();
      expect(saved.map((stroke) => stroke['tool']), ['eraser']);
      expect(changes.first, isTrue);
      expect(changes.last, isFalse);
    },
  );
}
