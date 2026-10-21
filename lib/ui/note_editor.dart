import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../core/models.dart';
import '../core/workspace.dart';

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.workspace, required this.note});
  final Workspace workspace;
  final WorkspaceObject note;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}
class _NoteEditorState extends State<NoteEditor> {
  late final title = TextEditingController(text: widget.note.title);
  late final body = TextEditingController(text: widget.note.text('body'));
  Timer? timer;
  bool dirty = false, preview = false, saving = false;
  String status = '저장됨';
  Future<void> pending = Future.value();
  void changed() {
    timer?.cancel();
    setState(() { dirty = true; status = '저장 대기 중'; });
    timer = Timer(const Duration(milliseconds: 450), save);
  }
  Future<void> save() async {
    timer?.cancel();
    final snapshotTitle = title.text, snapshotBody = body.text;
    if(!dirty) return;
    setState(() { saving = true; status = '저장 중…'; });
    final operation = pending.then((_) async {
      await widget.workspace.save('note', {...widget.note.data,
        'title': snapshotTitle, 'body': snapshotBody}, id: widget.note.id);
    });
    pending = operation.catchError((_) {});
    try {
      await operation;
      if(mounted) setState(() {
        dirty = title.text != snapshotTitle || body.text != snapshotBody;
        saving = false; status = dirty ? '저장 대기 중' : '저장됨';
      });
    } catch (_) { if(mounted) setState(() { saving = false; status = '저장 실패 · 다시 시도'; }); }
  }
  @override
  void dispose() { timer?.cancel(); title.dispose(); body.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving, onPopInvokedWithResult: (didPop, result) async {
      if(didPop) return;
      await save();
      if(mounted && !dirty && !saving) Navigator.pop(context);
    }, child: Scaffold(appBar: AppBar(title: const Text('Markdown 노트'), actions: [
      TextButton(onPressed: save, child: Text(status)),
      IconButton(tooltip: preview ? '편집' : '미리보기', onPressed: () => setState(() => preview = !preview),
        icon: Icon(preview ? Icons.edit_outlined : Icons.preview_outlined)),
    ]), body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: title,
        onChanged: (_) => changed(), decoration: const InputDecoration(labelText: '제목'))),
      if(widget.note.text('documentId').isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.centerLeft, child: Text('연결된 자료: ${widget.workspace.byId(widget.note.text('documentId'))?.title ?? '휴지통의 문서'}'))),
      Expanded(child: preview ? Markdown(data: body.text, selectable: true)
        : Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: TextField(
          controller: body, onChanged: (_) => changed(), expands: true, maxLines: null, minLines: null,
          textAlignVertical: TextAlignVertical.top, decoration: const InputDecoration(
            hintText: '# 학습 노트\n\n배운 내용을 기록하세요. Markdown을 지원합니다.'),
          style: const TextStyle(fontSize: 16, height: 1.7)))),
    ])));
}

