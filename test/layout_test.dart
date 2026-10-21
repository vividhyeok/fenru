import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenru/core/database.dart';
import 'package:fenru/core/workspace.dart';
import 'package:fenru/ui/shell.dart';
import 'package:fenru/ui/theme.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1366, 900),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('shell layout ${size.width} dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final temp = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fenru-layout-'),
        ))!;
        final w = Workspace(temp, WorkspaceDatabase.memory());
        await tester.runAsync(w.initialize);
        final fontPath = File('C:/Windows/Fonts/malgun.ttf');
        if (fontPath.existsSync()) {
          final loader = FontLoader('Malgun Gothic');
          loader.addFont(
            Future.value(ByteData.sublistView(fontPath.readAsBytesSync())),
          );
          await tester.runAsync(loader.load);
        }
        final key = GlobalKey();
        final base = FenruTheme.build(
          dark ? Brightness.dark : Brightness.light,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: 'Malgun Gothic'),
            ),
            home: RepaintBoundary(
              key: key,
              child: FenruShell(workspace: w),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Test-rendered empty-state screenshots; no production fixture data.
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('dist/qa');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/home-${size.width.toInt()}-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await w.close();
          await temp.delete(recursive: true);
        });
      });
    }
  }
}
