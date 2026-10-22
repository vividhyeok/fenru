import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/models.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/features/reader/ink.dart';
import 'package:fenru/features/ai/study_context.dart';
import 'package:fenru/integrations/pdf_conversion.dart';

import 'pdf_fixture.dart';

void main() {
  test('conversion preserves original, links PDF and reuses it', () async {
    final root = await Directory.systemTemp.createTemp('fenru-conversion-');
    final w = Workspace(root, WorkspaceDatabase.memory());
    await w.initialize();
    try {
      final source = File('${root.path}/lecture.docx');
      await source.writeAsString('Original fixture bytes');
      final original = await w.importFile(source.path, folder: 'Biology');
      final course = await w.save('course', {'title': 'Biology'});
      var calls = 0;
      final converter = PdfConversion(
        w,
        runner: (source, output) async {
          calls++;
          await output.writeAsBytes(samplePdf());
        },
      );
      final pdf = await converter.convert(original);
      expect(pdf.text('extension'), '.pdf');
      expect(pdf.text('derivedFrom'), original.id);
      expect(
        await w.fileFor(original).readAsString(),
        'Original fixture bytes',
      );
      expect(StudyContextService.courseDocuments(w, course).single.id, pdf.id);
      expect((await converter.convert(w.byId(original.id)!)).id, pdf.id);
      expect(calls, 1);
      expect(w.ofKind('document').length, 2);
      final context = await StudyContextService(
        w,
        pageLoader: (doc) async {
          expect(doc.id, pdf.id);
          return ['Converted PDF text'];
        },
      ).retrieve([original, pdf], 'Converted');
      expect(context.sources.single['documentId'], pdf.id);
    } finally {
      await w.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'failed conversion retains source and rejects a non-PDF output',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fenru-conversion-fail-',
      );
      final w = Workspace(root, WorkspaceDatabase.memory());
      await w.initialize();
      try {
        final source = File('${root.path}/lecture.hwp');
        await source.writeAsString('original');
        final original = await w.importFile(source.path);
        await expectLater(
          PdfConversion(
            w,
            runner: (_, output) async {
              await output.writeAsString('<html>error</html>');
            },
          ).convert(original),
          throwsA(isA<UserFacingException>()),
        );
        expect(w.ofKind('document').length, 1);
        expect(w.byId(original.id)!.text('conversionStatus'), 'failed');
        expect(await w.fileFor(original).readAsString(), 'original');
      } finally {
        await w.close();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'ink gesture saves relative page coordinates and pen properties',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: InkSurface(
                tool: 'pen',
                color: 0xff234b80,
                width: 2,
                onSave: (data) async {
                  saved = data;
                },
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(InkSurface));
      final gesture = await tester.startGesture(
        rect.topLeft + const Offset(50, 60),
      );
      await gesture.moveBy(const Offset(60, 80));
      await gesture.moveBy(const Offset(40, -10));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved!['tool'], 'pen');
      expect(saved!['width'], 2);
      final points = saved!['points'] as List;
      expect(points.length, greaterThan(1));
      expect((points.last as List)[0], closeTo(.5, .02));
      expect((points.last as List)[1], closeTo(.325, .02));
      expect(tester.takeException(), isNull);
    },
  );
}
