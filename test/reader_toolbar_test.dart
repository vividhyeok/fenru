import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/features/reader/reader_toolbar.dart';

void main() {
  testWidgets('hand and eraser return to the last writing tool', (
    tester,
  ) async {
    var tool = 'marker';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => Align(
            alignment: Alignment.topLeft,
            child: ReaderToolbar(
              tool: tool,
              lastWritingTool: 'marker',
              onTool: (value) => update(() => tool = value),
              onPenSettings: () {},
              onUndo: null,
              onRedo: null,
              onPages: () {},
              pageLabel: '1 / 2',
            ),
          ),
        ),
      ),
    );
    Finder modeIcon(String tooltip, IconData icon) => find.descendant(
      of: find.byTooltip(tooltip),
      matching: find.byIcon(icon),
    );
    await tester.tap(modeIcon('읽기 · 선택 · 이동', Icons.edit_outlined));
    await tester.pump();
    expect(tool, 'read');
    await tester.tap(modeIcon('필기로 돌아가기', Icons.pan_tool_outlined));
    await tester.pump();
    expect(tool, 'marker');
    await tester.tap(find.byTooltip('지우개'));
    await tester.pump();
    expect(tool, 'eraser');
    await tester.tap(find.byTooltip('지우개'));
    expect(tool, 'marker');
  });

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
