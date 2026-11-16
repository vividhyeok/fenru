import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/database.dart';
import 'core/models.dart';
import 'core/workspace.dart';
import 'ui/theme.dart';
import 'ui/onboarding.dart';
import 'ui/shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  RandomAccessFile? guard;
  try {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'workspace'));
    await root.create(recursive: true);
    if (Platform.isWindows) {
      guard = await File(p.join(root.path, '.fenru.lock'))
          .open(mode: FileMode.append);
      try {
        await guard.lock(FileLock.exclusive);
      } on FileSystemException {
        await guard.close();
        guard = null;
        throw const UserFacingException(
          '같은 작업 공간의 Fenru가 이미 실행 중입니다. 기존 창을 사용하거나 닫은 뒤 다시 실행하세요.',
        );
      }
    }
    final workspace = Workspace(
      root,
      WorkspaceDatabase(File(p.join(root.path, 'fenru.sqlite'))),
      guard: guard,
    );
    await workspace.initialize();
    runApp(FenruApp(workspace: workspace));
  } catch (error) {
    await guard?.close();
    runApp(
      MaterialApp(
        theme: FenruTheme.build(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                error is UserFacingException ? error.message : 'Fenru를 시작하지 못했습니다.\n저장 공간과 폴더 접근 권한을 확인한 뒤 다시 실행하세요.\n기존 데이터는 삭제되지 않았습니다.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FenruApp extends StatefulWidget {
  const FenruApp({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<FenruApp> createState() => _FenruAppState();
}

class _FenruAppState extends State<FenruApp> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.workspace,
    builder: (_, _) => MaterialApp(
      title: 'Fenru',
      debugShowCheckedModeBanner: false,
      theme: FenruTheme.build(Brightness.light),
      darkTheme: FenruTheme.build(Brightness.dark),
      themeMode: switch (widget.workspace.preferences['theme']) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      locale: Locale(widget.workspace.preferences['language'] ?? 'ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: widget.workspace.preferences['onboarding'] == 'complete'
          ? FenruShell(workspace: widget.workspace)
          : Onboarding(workspace: widget.workspace),
    ),
  );
}
