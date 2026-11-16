import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/features/reader/reader_toolbar.dart';

void main() {
  for (final width in [320.0, 600.0, 900.0]) {
    testWidgets('writing toolbar stays one row at $width', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var settings = 0, pages = 0;
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ReaderToolbar(
              tool: 'pen',
              onTool: (tool) => selected = tool,
              onPenSettings: () => settings++,
              onUndo: () {},
              onRedo: () {},
              onPages: () => pages++,
              pageLabel: '3 / 120',
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('writing-toolbar'))).height,
        48,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('reader-page-options'))).right,
        lessThanOrEqualTo(width),
      );
      await tester.tap(find.byTooltip('펜 필기'));
      expect(settings, 1);
      await tester.tap(find.byTooltip('형광펜'));
      expect(selected, 'marker');
      await tester.tap(find.byKey(const ValueKey('reader-page-options')));
      expect(pages, 1);
      expect(find.text('손가락으로 필기'), findsNothing);
      expect(find.text('야간 읽기'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
