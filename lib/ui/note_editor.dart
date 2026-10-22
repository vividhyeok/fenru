import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/models.dart';
import '../core/workspace.dart';
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
  bool dirty = false, preview = false, saving = false;
  String status = '저장됨';
  Future<void> pending = Future.value();
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
          TextButton(onPressed: save, child: Text(status)),
          IconButton(
            tooltip: preview ? '편집' : '미리보기',
            onPressed: () => setState(() => preview = !preview),
            icon: Icon(preview ? Icons.edit_outlined : Icons.preview_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.embedded)
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
                ? Markdown(data: body.text, selectable: true)
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
