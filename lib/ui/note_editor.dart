import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/workspace.dart';
import '../features/notes/note_pdf.dart';
import '../features/reader/reader.dart';

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.workspace,
    required this.note,
    this.embedded = false,
    this.expanded = false,
    this.onToggleExpanded,
  });
  final Workspace workspace;
  final WorkspaceObject note;
  final bool embedded, expanded;
  final VoidCallback? onToggleExpanded;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> with WidgetsBindingObserver {
  late final title = TextEditingController(text: widget.note.title);
  late final body = TextEditingController(text: widget.note.text('body'));
  Timer? timer;
  late bool preview = body.text.trim().isNotEmpty;
  bool dirty = false, saving = false, exporting = false;
  String status = '저장됨';
  Future<void> pending = Future.value();

  String get displayTitle =>
      title.text.trim().isEmpty ? '제목 없는 노트' : title.text.trim();

  Future<void> makePdf({required bool addToLibrary}) async {
    if (exporting) return;
    setState(() => exporting = true);
    final name = displayTitle;
    final markdown = body.text;
    try {
      await save();
      if (!mounted || dirty || saving) return;
      final bytes = await renderNotePdf(name, markdown);
      if (!mounted) return;
      if (addToLibrary) {
        final temporary = await Directory.systemTemp.createTemp('fenru-note-');
        try {
          final file = await File('${temporary.path}/note.pdf')
              .writeAsBytes(bytes);
          final document = await widget.workspace.importFile(
            file.path,
            displayName: notePdfFileName(name),
          );
          if (mounted) await openSource(document.id);
        } finally {
          await temporary.delete(recursive: true);
        }
      } else {
        final result = await saveNotePdfFile(
          name,
          bytes,
          dialogTitle: '노트를 PDF로 저장',
        );
        if (result != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('PDF를 저장했습니다.')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF를 만들거나 저장하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget readingView() {
    final theme = Theme.of(context);
    final base = MarkdownStyleSheet.fromTheme(theme);
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    displayTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 16),
                  MarkdownBody(
                    data: body.text,
                    styleSheet: base.copyWith(
                      p: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        height: 1.65,
                      ),
                      h1: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      h2: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                      h3: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                      blockSpacing: 14,
                      listIndent: 22,
                      tableCellsPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onTapLink: (_, href, _) {
                      final uri = Uri.tryParse(href ?? '');
                      if (uri != null &&
                          (uri.scheme == 'https' || uri.scheme == 'http')) {
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openSource(String id, [int? page]) async {
    await save();
    if (!mounted || dirty || saving) return;
    final doc = widget.workspace.byId(id);
    if (doc == null || doc.deleted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 자료가 휴지통에 있거나 없습니다.')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentReader(
          workspace: widget.workspace,
          document: page == null
              ? doc
              : WorkspaceObject(
                  id: doc.id,
                  kind: doc.kind,
                  data: {...doc.data, 'page': page},
                  revision: doc.revision,
                  device: doc.device,
                  updated: doc.updated,
                ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && dirty) save();
  }

  void changed() {
    timer?.cancel();
    setState(() {
      dirty = true;
      status = '저장 대기 중';
    });
    timer = Timer(const Duration(milliseconds: 450), save);
  }

  Future<void> save() async {
    timer?.cancel();
    final snapshotTitle = title.text, snapshotBody = body.text;
    if (!dirty) return;
    setState(() {
      saving = true;
      status = '저장 중…';
    });
    final operation = pending.then((_) async {
      await widget.workspace.save('note', {
        ...widget.note.data,
        'title': snapshotTitle,
        'body': snapshotBody,
      }, id: widget.note.id);
    });
    pending = operation.catchError((_) {});
    try {
      await operation;
      if (mounted) {
        setState(() {
          dirty = title.text != snapshotTitle || body.text != snapshotBody;
          saving = false;
          status = dirty ? '저장 대기 중' : '저장됨';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          status = '저장 실패 · 다시 시도';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      await save();
      if (context.mounted && !dirty && !saving) Navigator.pop(context);
    },
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: widget.embedded ? 48 : null,
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          widget.embedded ? '정리 노트' : 'Markdown 노트',
          style: widget.embedded ? const TextStyle(fontSize: 16) : null,
        ),
        actions: [
          if (widget.onToggleExpanded != null)
            IconButton(
              tooltip: widget.expanded ? '자료와 나란히 보기' : '노트 화면 넓게 보기',
              icon: Icon(
                widget.expanded ? Icons.close_fullscreen : Icons.open_in_full,
                size: 18,
              ),
              onPressed: widget.onToggleExpanded,
            ),
          if (!preview || dirty || saving)
            TextButton(onPressed: save, child: Text(status)),
          IconButton(
            tooltip: preview ? '편집' : '읽기',
            onPressed: () {
              FocusScope.of(context).unfocus();
              setState(() => preview = !preview);
              if (preview && dirty) save();
            },
            icon: Icon(preview ? Icons.edit_outlined : Icons.preview_outlined),
          ),
          PopupMenuButton<bool>(
            tooltip: '노트 PDF',
            enabled: !exporting && body.text.trim().isNotEmpty,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onSelected: (value) => makePdf(addToLibrary: value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('PDF로 만들어 필기하기')),
              PopupMenuItem(value: false, child: Text('PDF 파일로 저장')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (exporting) const LinearProgressIndicator(),
          if (!preview)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: title,
                onChanged: (_) => changed(),
                decoration: const InputDecoration(labelText: '제목'),
              ),
            ),
          if (!widget.embedded &&
              (widget.note.text('documentId').isNotEmpty ||
                  (widget.note.data['sources'] as List? ?? []).isNotEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: const Text('연결 자료 · 답변의 출처 열기'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (widget.note.text('documentId').isNotEmpty)
                          ActionChip(
                            label: const Text('연결된 자료 열기'),
                            onPressed: () =>
                                openSource(widget.note.text('documentId')),
                          ),
                        for (final source
                            in (widget.note.data['sources'] as List? ?? [])
                                .whereType<Map>())
                          ActionChip(
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                '${source['title']} · ${source['page']}쪽',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onPressed: () => openSource(
                              source['documentId'].toString(),
                              int.tryParse(source['page'].toString()),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: preview
                ? readingView()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: TextField(
                      controller: body,
                      onChanged: (_) => changed(),
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: '# 학습 노트\n\n배운 내용을 기록하세요. Markdown을 지원합니다.',
                      ),
                      style: const TextStyle(fontSize: 16, height: 1.7),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
