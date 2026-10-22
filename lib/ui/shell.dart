import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/workspace.dart';
import '../integrations/pdf_conversion.dart';
import '../features/backup/backup_service.dart';
import '../features/reader/reader.dart';
import '../features/ai/chat.dart';
import '../features/ai/course_workspace.dart';
import '../features/ai/study_context.dart';
import '../features/ai/settings.dart';
import '../integrations/canvas.dart';
import '../integrations/credentials.dart';
import 'dialogs.dart';
import 'note_editor.dart';
import 'theme.dart';

class FenruShell extends StatefulWidget {
  const FenruShell({super.key, required this.workspace});
  final Workspace workspace;
  @override
  State<FenruShell> createState() => _FenruShellState();
}

class _FenruShellState extends State<FenruShell> {
  Workspace get w => widget.workspace;
  int tab = 0;
  bool busy = false, dragging = false, trash = false;
  String query = '', folder = '', status = '', error = '';
  final searchFocus = FocusNode();
  final searchController = TextEditingController();
  final selected = <String>{};
  List<WorkspaceObject>? results;
  static const labels = ['홈', '라이브러리', '과목', '노트', '플래너', '설정'];
  static const icons = [
    Icons.home_outlined,
    Icons.folder_outlined,
    Icons.school_outlined,
    Icons.edit_note,
    Icons.calendar_month_outlined,
    Icons.settings_outlined,
  ];
  @override
  void dispose() {
    searchFocus.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> run(
    Future<void> Function() action, {
    String label = '처리 중…',
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      status = label;
    });
    try {
      await action();
      if (mounted) setState(() => status = '완료 · 모든 변경사항이 기기에 저장되었습니다.');
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is UserFacingException
              ? e.message
              : '작업에 실패했습니다. 저장 공간, 파일 접근 권한과 연결 상태를 확인한 뒤 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importPaths(List<String> paths) => run(() async {
    int count = 0;
    for (final path in paths) {
      await importStudyFile(w, path, folder: folder);
      if (mounted) {
        setState(() => status = '${++count} / ${paths.length}개 파일 가져옴');
      }
    }
    if (mounted) {
      setState(() {
        tab = 1;
        trash = false;
      });
    }
  }, label: '파일을 안전하게 복사하고 있습니다…');
  Future<void> pickFiles() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    await run(() async {
      for (final file in picked) {
        final temporary = await Directory.systemTemp.createTemp(
          'fenru-import-',
        );
        try {
          final target = File(p.join(temporary.path, p.basename(file.name)));
          await file.readAsByteStream().cast<List<int>>().pipe(
            target.openWrite(),
          );
          await importStudyFile(w, target.path, folder: folder);
        } finally {
          await temporary.delete(recursive: true);
        }
      }
      if (mounted) {
        setState(() {
          tab = 1;
          trash = false;
        });
      }
    }, label: '선택한 파일을 가져오고 있습니다…');
  }

  void openObject(WorkspaceObject o) {
    if (o.kind == 'document') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DocumentReader(workspace: w, document: o),
        ),
      );
    } else if (o.kind == 'note') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NoteEditor(workspace: w, note: o),
        ),
      );
    } else if (o.kind == 'message' || o.kind == 'chat') {
      openAI(sessionId: o.kind == 'chat' ? o.id : o.text('sessionId'));
    } else if (o.kind == 'task') {
      setState(() {
        tab = 4;
        query = '';
        results = null;
        searchController.clear();
      });
    } else if (o.kind == 'course') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CourseWorkspace(workspace: w, course: o),
        ),
      );
    } else if (o.kind == 'annotation') {
      final doc = w.byId(o.text('documentId'));
      if (doc != null && !doc.deleted) {
        openObject(
          WorkspaceObject(
            id: doc.id,
            kind: doc.kind,
            data: {...doc.data, 'page': o.number('page', 1)},
            revision: doc.revision,
            device: doc.device,
            updated: doc.updated,
          ),
        );
      }
    }
  }

  void openAI({String? sessionId}) {
    final session = w.byId(sessionId ?? '');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AIChat(
          workspace: w,
          sessionId: sessionId,
          documentId: session?.text('documentId').isNotEmpty == true
              ? session!.text('documentId')
              : null,
          courseId: session?.text('courseId').isNotEmpty == true
              ? session!.text('courseId')
              : null,
          onCitation: (id, page) {
            final doc = w.byId(id);
            if (doc != null && !doc.deleted) {
              openObject(
                WorkspaceObject(
                  id: doc.id,
                  kind: doc.kind,
                  data: {...doc.data, 'page': page},
                  revision: doc.revision,
                  device: doc.device,
                  updated: doc.updated,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> createNote({String? documentId}) async {
    final note = await w.save('note', {
      'title': '제목 없는 노트',
      'body': '',
      'documentId': ?documentId,
    });
    if (mounted) openObject(note);
  }

  Future<void> search(String value) async {
    query = value;
    final found = await w.search(value);
    if (mounted && query == value) {
      setState(() => results = value.isEmpty ? null : found);
    }
  }

  Future<void> editDocument(WorkspaceObject doc) async {
    final title = await askText(context, '자료 이름', initial: doc.title);
    if (title == null || !mounted) return;
    final newFolder = await askText(
      context,
      '폴더 / 과목',
      initial: doc.text('folder'),
    );
    if (newFolder == null || !mounted) return;
    final tags = await askText(
      context,
      '태그 (쉼표로 구분)',
      initial: doc.text('tags'),
    );
    if (tags == null) return;
    await run(() async {
      await w.save('document', {
        ...doc.data,
        'title': title,
        'folder': newFolder,
        'tags': tags,
      }, id: doc.id);
    });
  }

  Future<void> deleteObjects(List<WorkspaceObject> objects) async {
    if (!await confirm(
      context,
      '휴지통으로 이동',
      '${objects.length}개 항목을 휴지통으로 이동합니다. 설정 없이 다시 복구할 수 있습니다.',
    )) {
      return;
    }
    await run(() async {
      for (final o in objects) {
        await w.trash(o);
      }
      selected.clear();
    });
  }

  Widget empty(String title, String body, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.7),
          ),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    ),
  );
  Widget objectList(List<WorkspaceObject> objects) => objects.isEmpty
      ? empty(
          trash ? '휴지통이 비어 있습니다' : '아직 자료가 없습니다',
          trash ? '삭제한 자료는 이곳에서 복구할 수 있습니다.' : 'PDF, 문서, 이미지 등 학습자료를 가져오세요.',
          action: trash
              ? null
              : FilledButton.icon(
                  onPressed: busy ? null : pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('파일 가져오기'),
                ),
        )
      : ListView.separated(
          itemCount: objects.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final o = objects[i], checked = selected.contains(objects[i].id);
            return ListTile(
              selected: checked,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              leading: selected.isNotEmpty
                  ? Checkbox(
                      value: checked,
                      onChanged: (_) => setState(() {
                        checked ? selected.remove(o.id) : selected.add(o.id);
                      }),
                    )
                  : Icon(
                      o.kind == 'note'
                          ? Icons.description_outlined
                          : o.text('extension') == '.pdf'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.insert_drive_file_outlined,
                    ),
              title: Text(
                o.title.isEmpty ? '제목 없음' : o.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                o.kind == 'document'
                    ? '${o.text('folder').isEmpty ? '분류 없음' : o.text('folder')}  ·  ${o.text('conversionStatus') == 'failed'
                          ? 'PDF 변환 확인 필요 · 원본 보관됨'
                          : o.text('pdfDocumentId').isNotEmpty
                          ? 'PDF로 열기 · 원본 보관됨'
                          : o.text('derivedFrom').isNotEmpty
                          ? '원본에서 변환한 PDF'
                          : o.text('tags')}'
                    : o.text('body').replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onLongPress: () => setState(() => selected.add(o.id)),
              onTap: () {
                if (selected.isNotEmpty) {
                  setState(() {
                    checked ? selected.remove(o.id) : selected.add(o.id);
                  });
                } else if (!trash) {
                  openObject(o);
                }
              },
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'select':
                      setState(() => selected.add(o.id));
                    case 'edit':
                      await editDocument(o);
                    case 'ask':
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AIChat(
                            workspace: w,
                            documentId: o.id,
                            scopeTitle: o.title,
                          ),
                        ),
                      );
                    case 'note':
                      await run(() => createNote(documentId: o.id));
                    case 'trash':
                      await deleteObjects([o]);
                    case 'restore':
                      await run(() => w.restore(o));
                  }
                },
                itemBuilder: (_) => trash
                    ? const [PopupMenuItem(value: 'restore', child: Text('복구'))]
                    : [
                        const PopupMenuItem(value: 'select', child: Text('선택')),
                        if (o.kind == 'document') ...[
                          const PopupMenuItem(
                            value: 'ask',
                            child: Text('이 자료에 질문'),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('이름 · 폴더 · 태그 수정'),
                          ),
                          const PopupMenuItem(
                            value: 'note',
                            child: Text('연결된 노트 만들기'),
                          ),
                        ],
                        const PopupMenuItem(
                          value: 'trash',
                          child: Text('휴지통으로 이동'),
                        ),
                      ],
              ),
            );
          },
        );

  Widget home() {
    final recent =
        w
            .ofKind('document')
            .where((o) => o.text('lastRead').isNotEmpty)
            .toList()
          ..sort((a, b) => b.text('lastRead').compareTo(a.text('lastRead')));
    final tasks = w.ofKind('task').where((o) => !o.flag('done')).toList()
      ..sort((a, b) => a.text('due').compareTo(b.text('due')));
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text('오늘도, 한 걸음 더.', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('자료를 읽고 생각을 기록하는 나만의 학습 공간'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : pickFiles,
              icon: const Icon(Icons.add),
              label: const Text('파일 가져오기'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => run(createNote),
              icon: const Icon(Icons.edit_note),
              label: const Text('새 노트'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => tab = 4),
              icon: const Icon(Icons.calendar_today),
              label: const Text('오늘 할 일'),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            Text('보관한 자료  ${w.ofKind('document').length}'),
            Text('학습 노트  ${w.ofKind('note').length}'),
            Text('남은 할 일  ${tasks.length}'),
          ],
        ),
        const SizedBox(height: 30),
        Text('이어서 읽기', style: Theme.of(context).textTheme.titleLarge),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('문서를 열면 마지막으로 읽던 자료가 여기에 표시됩니다.'),
          ),
        for (final doc in recent.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(doc.title),
            subtitle: Text('${doc.number('page', 1)}페이지에서 계속'),
            onTap: () => openObject(doc),
          ),
        const Divider(height: 40),
        Text('다가오는 할 일', style: Theme.of(context).textTheme.titleLarge),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('플래너에서 목표나 일정을 추가해 보세요.'),
          ),
        for (final task in tasks.take(5)) taskTile(task),
        const Divider(height: 40),
        Text('최근 추가한 자료', style: Theme.of(context).textTheme.titleLarge),
        for (final doc in w.ofKind('document').take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(doc.title),
            leading: const Icon(Icons.insert_drive_file_outlined),
            onTap: () => openObject(doc),
          ),
      ],
    );
  }

  Widget library() {
    final docs = trash
        ? w.objects.where((o) => o.deleted).toList()
        : w
              .ofKind('document')
              .where((d) => folder.isEmpty || d.text('folder') == folder)
              .toList();
    final folders =
        w
            .ofKind('document')
            .map((o) => o.text('folder'))
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : pickFiles,
                icon: const Icon(Icons.add),
                label: const Text('파일 가져오기'),
              ),
              FilterChip(
                label: const Text('휴지통'),
                selected: trash,
                onSelected: (value) => setState(() {
                  trash = value;
                  selected.clear();
                }),
              ),
              DropdownButton<String>(
                value: folders.contains(folder) ? folder : '',
                items: [
                  const DropdownMenuItem(value: '', child: Text('모든 폴더')),
                  for (final name in folders)
                    DropdownMenuItem(
                      value: name,
                      child: SizedBox(
                        width: 140,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => folder = value ?? ''),
              ),
              if (selected.isNotEmpty)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => deleteObjects(
                          docs.where((d) => selected.contains(d.id)).toList(),
                        ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('${selected.length}개 삭제'),
                ),
              if (selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(selected.clear),
                  child: const Text('선택 해제'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: objectList(docs)),
      ],
    );
  }

  Future<void> addTask() async {
    final title = await askText(context, '새 학습 일정');
    if (title == null || title.trim().isEmpty || !mounted) return;
    final due = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    await run(() async {
      await w.save('task', {
        'title': title,
        'due': due?.toIso8601String() ?? '',
        'done': false,
      });
    });
  }

  Widget taskTile(WorkspaceObject task) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    value: task.flag('done'),
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(
      task.title,
      style: TextStyle(
        decoration: task.flag('done') ? TextDecoration.lineThrough : null,
      ),
    ),
    subtitle: Text(
      '${task.text('due').split('T').first}  ${task.text('course')}',
    ),
    onChanged: busy
        ? null
        : (done) => run(() async {
            await w.save('task', {...task.data, 'done': done}, id: task.id);
          }),
    secondary: PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'delete') {
          await deleteObjects([task]);
        } else if (task.text('url').startsWith('https://')) {
          await launchUrl(
            Uri.parse(task.text('url')),
            mode: LaunchMode.externalApplication,
          );
        }
      },
      itemBuilder: (_) => [
        if (task.text('url').startsWith('https://'))
          const PopupMenuItem(value: 'source', child: Text('Canvas에서 보기')),
        const PopupMenuItem(value: 'delete', child: Text('휴지통으로 이동')),
      ],
    ),
  );
  Widget planner() {
    final tasks = w.ofKind('task')
      ..sort((a, b) {
        if (a.flag('done') != b.flag('done')) return a.flag('done') ? 1 : -1;
        return a.text('due').compareTo(b.text('due'));
      });
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : addTask,
            icon: const Icon(Icons.add),
            label: const Text('일정 추가'),
          ),
        ),
        const SizedBox(height: 20),
        if (tasks.isEmpty)
          const Text('학습 목표나 시험 일정을 추가하세요. 완료 상태는 자동으로 저장됩니다.'),
        for (final task in tasks) taskTile(task),
      ],
    );
  }

  Future<void> connectCanvas() async {
    final url = await askText(
      context,
      '학교 Canvas 주소',
      initial: w.preferences['canvasUrl'] ?? '',
    );
    if (url == null || !mounted) return;
    final tokenController = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Canvas 개인 액세스 토큰'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Canvas → 계정 → 설정 → 새 액세스 토큰에서 발급하세요. 비밀번호를 입력하지 마세요.'),
            const SizedBox(height: 16),
            TextField(
              controller: tokenController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '액세스 토큰'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, tokenController.text.trim()),
            child: const Text('연결 테스트'),
          ),
        ],
      ),
    );
    tokenController.dispose();
    if (token == null || token.isEmpty) return;
    await run(() async {
      final provider = CanvasProvider(url, token);
      await provider.courses();
      await SecureCredentials().write('canvas', token);
      await w.setPreference('canvasUrl', provider.base.origin);
    }, label: 'Canvas 연결을 확인하고 있습니다…');
  }

  Future<void> syncCanvas() => run(() async {
    final token = await SecureCredentials().read('canvas');
    if (token == null) {
      throw const UserFacingException('설정에서 Canvas를 먼저 연결하세요.');
    }
    final provider = CanvasProvider(w.preferences['canvasUrl'] ?? '', token);
    final courses = await provider.courses();
    if (!mounted) return;
    final courseSelection = <int>{};
    final chosen = await showDialog<List<Json>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('가져올 과목 선택'),
          content: SizedBox(
            width: 500,
            height: 350,
            child: courses.isEmpty
                ? const Text('수강 중인 과목이 없습니다.')
                : ListView.builder(
                    itemCount: courses.length,
                    itemBuilder: (_, i) => CheckboxListTile(
                      value: courseSelection.contains(i),
                      title: Text('${courses[i]['name'] ?? courses[i]['id']}'),
                      onChanged: (value) => update(() {
                        value == true
                            ? courseSelection.add(i)
                            : courseSelection.remove(i);
                      }),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: courseSelection.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      courseSelection.map((i) => courses[i]).toList(),
                    ),
              child: const Text('가져오기'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final summaries = <String>[];
    for (final course in chosen) {
      final report = await provider.importCourse(w, course, (message) {
        if (mounted) setState(() => status = message);
      });
      summaries.add('${course['name'] ?? course['id']}\n${report.summary}');
      summaries.addAll(report.warnings);
      if (report.imported == 0 && report.unchanged == 0) {
        summaries.add(
          '내려받을 문서 파일이 발견되지 않았습니다. 영상·퀴즈·설문은 다운로드하지 않습니다. 아래 경고와 학교 강의실의 원본 문서 다운로드 제공 여부를 확인하세요.',
        );
      }
    }
    await w.setPreference('canvasLastSync', DateTime.now().toIso8601String());
    await w.setPreference('canvasImportSummary', summaries.join('\n\n'));
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Canvas 가져오기 결과'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(summaries.join('\n\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }, label: 'Canvas 과목을 확인하고 있습니다…');
  Widget courses() {
    final items = w.ofKind('course');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '과목 · Canvas 자료',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : syncCanvas,
            icon: const Icon(Icons.sync),
            label: const Text('Canvas 자료 가져오기'),
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const Text('설정에서 학교 Canvas 주소와 토큰을 연결하거나 라이브러리에서 폴더를 지정하세요.'),
        for (final item in items)
          ListTile(
            title: Text(item.title),
            leading: const Icon(Icons.school_outlined),
            subtitle: Text(
              '${StudyContextService.courseDocuments(w, item).length}개 자료',
            ),
            onTap: () => openObject(item),
            trailing: IconButton(
              tooltip: '과목 자료에 질문',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AIChat(
                    workspace: w,
                    courseId: item.id,
                    scopeTitle: item.title,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> exportBackup() async {
    await run(() async {
      final temporary = await Directory.systemTemp.createTemp('fenru-export-');
      try {
        final file = File(p.join(temporary.path, 'backup.zip'));
        await BackupService(w).exportTo(file.path);
        await FilePicker.saveFile(
          dialogTitle: '작업 공간 백업',
          fileName:
              'Fenru-backup-${DateTime.now().toIso8601String().split('T').first}.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
          bytes: await file.readAsBytes(),
          mimeType: 'application/zip',
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    }, label: '백업을 만들고 있습니다…');
  }

  Future<void> restoreBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (file == null || !mounted) return;
    if (!await confirm(
      context,
      '백업 병합',
      '기존 데이터는 유지됩니다. 다른 기기에서 동시에 수정한 항목은 충돌 복사본으로 보존됩니다.',
    )) {
      return;
    }
    await run(() async {
      final temporary = await Directory.systemTemp.createTemp('fenru-restore-');
      int conflicts;
      try {
        final target = File(p.join(temporary.path, 'backup.zip'));
        await file.readAsByteStream().cast<List<int>>().pipe(
          target.openWrite(),
        );
        conflicts = await BackupService(w).restoreFrom(target.path);
      } finally {
        await temporary.delete(recursive: true);
      }
      if (conflicts > 0) {
        throw UserFacingException(
          '복원이 완료되었습니다. 충돌 복사본 $conflicts개를 확인하세요. 기존 내용은 유지되었습니다.',
        );
      }
    }, label: '파일 무결성을 확인하고 백업을 병합하고 있습니다…');
  }

  Future<void> help() async {
    final content = await rootBundle.loadString('assets/help/guide.md');
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Fenru 도움말')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(content, style: const TextStyle(height: 1.7)),
          ),
        ),
      ),
    );
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('나만의 학습 환경', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      const Text('화면', style: TextStyle(fontWeight: FontWeight.w600)),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'system', label: Text('시스템')),
          ButtonSegment(value: 'light', label: Text('라이트')),
          ButtonSegment(value: 'dark', label: Text('다크')),
        ],
        selected: {w.preferences['theme'] ?? 'system'},
        onSelectionChanged: (values) =>
            run(() => w.setPreference('theme', values.first)),
      ),
      const Divider(height: 40),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Canvas LMS'),
        subtitle: Text(w.preferences['canvasUrl'] ?? '연결되지 않음 · 선택 사항'),
        trailing: Wrap(
          children: [
            TextButton(
              onPressed: busy ? null : connectCanvas,
              child: const Text('연결'),
            ),
            if (w.preferences.containsKey('canvasUrl'))
              TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await SecureCredentials().delete('canvas');
                        await w.setPreference('canvasUrl', '');
                      }),
                child: const Text('해제'),
              ),
          ],
        ),
      ),
      if (w.preferences.containsKey('canvasLastSync'))
        Text('마지막 가져오기: ${w.preferences['canvasLastSync']}'),
      if (w.preferences.containsKey('canvasImportSummary'))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SelectableText(w.preferences['canvasImportSummary']!),
        ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.key_outlined),
        title: const Text('AI API 키 · 모델 설정'),
        subtitle: const Text('OpenAI / DeepSeek · 키 입력, 연결 확인, 모델 및 토큰 한도'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => AISettings(workspace: w)),
        ),
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.cloud_outlined),
        title: Text('Google Drive'),
        subtitle: Text('자동 동기화는 개발 중입니다. 기기 간 이동은 ZIP 백업과 병합 복원을 이용하세요.'),
      ),
      const Divider(height: 32),
      Text('데이터와 백업', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      SelectableText(w.root.path),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : exportBackup,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('ZIP 백업'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : restoreBackup,
            icon: const Icon(Icons.restore),
            label: const Text('백업 병합 복원'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        '백업에는 문서·노트·일정·주석이 포함됩니다. 연결 토큰과 API 키는 포함되지 않습니다.\n백업 ZIP은 암호화되지 않습니다. 안전한 위치에 보관하세요.',
      ),
      const Divider(height: 32),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.help_outline),
        title: const Text('도움말 센터'),
        subtitle: const Text('시작하기, Canvas, PDF, 노트, 백업 및 문제 해결'),
        onTap: help,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.school_outlined),
        title: const Text('시작 안내 다시 보기'),
        onTap: () => run(() async {
          await w.setPreference('onboardingStep', '0');
          await w.setPreference('onboarding', '');
        }),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.balance_outlined),
        title: const Text('오픈소스 라이선스'),
        onTap: () =>
            showLicensePage(context: context, applicationName: 'Fenru'),
      ),
      const SizedBox(height: 20),
      const Text(
        'Fenru 0.1.0-alpha.6 · 개발 프리릴리스\n로컬 데이터는 자동 저장됩니다. 별도 계정이나 추적 SDK를 사용하지 않습니다.',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= FenruTheme.tablet;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          if (!busy) pickFiles();
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (!busy) run(createNote);
        },
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const FenruMark(size: 28),
              const SizedBox(width: 10),
              const Text('Fenru'),
              if (wide) ...[
                const SizedBox(width: 28),
                Text(
                  labels[tab],
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: '도움말',
              onPressed: help,
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                focusNode: searchFocus,
                controller: searchController,
                onChanged: search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '자료 · 노트 · 태그 검색  (Ctrl+K)',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색 지우기',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            searchController.clear();
                            search('');
                          },
                        ),
                ),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error.isNotEmpty)
              MaterialBanner(
                content: Text(error),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => error = ''),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 5,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  if (wide) ...[
                    NavigationRail(
                      selectedIndex: tab,
                      onDestinationSelected: (i) => setState(() {
                        tab = i;
                        selected.clear();
                        query = '';
                        results = null;
                        searchController.clear();
                      }),
                      destinations: [
                        for (int i = 0; i < labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(labels[i]),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: DropTarget(
                      onDragEntered: (_) => setState(() => dragging = true),
                      onDragExited: (_) => setState(() => dragging = false),
                      onDragDone: (details) {
                        setState(() => dragging = false);
                        if (!busy) {
                          importPaths(
                            details.files.map((f) => f.path).toList(),
                          );
                        }
                      },
                      child: dragging
                          ? empty('여기에 파일을 놓으세요', '원본을 보존하고 작업 공간에 복사합니다.')
                          : results != null
                          ? (results!.isEmpty
                                ? empty('검색 결과가 없습니다', '다른 검색어를 입력해 보세요.')
                                : objectList(results!))
                          : switch (tab) {
                              0 => home(),
                              1 => library(),
                              2 => courses(),
                              3 => Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FilledButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => run(createNote),
                                        icon: const Icon(Icons.add),
                                        label: const Text('새 노트'),
                                      ),
                                    ),
                                  ),
                                  Expanded(child: objectList(w.ofKind('note'))),
                                ],
                              ),
                              4 => planner(),
                              _ => settings(),
                            },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: [0, 1, 2, 3, 4, 5].indexOf(tab).clamp(0, 5),
                onDestinationSelected: (i) => setState(() {
                  tab = [0, 1, 2, 3, 4, 5][i];
                  selected.clear();
                }),
                destinations: [
                  for (final i in [0, 1, 2, 3, 4, 5])
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: labels[i],
                    ),
                ],
              ),
      ),
    );
  }
}
