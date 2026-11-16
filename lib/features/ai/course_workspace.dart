import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../integrations/pdf_conversion.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../reader/reader.dart';
import '../reader/reading_tools.dart';
import 'chat.dart';
import 'study_context.dart';

class CourseWorkspace extends StatefulWidget {
  const CourseWorkspace({
    super.key,
    required this.workspace,
    required this.course,
  });
  final Workspace workspace;
  final WorkspaceObject course;
  @override
  State<CourseWorkspace> createState() => _CourseWorkspaceState();
}

class _CourseWorkspaceState extends State<CourseWorkspace> {
  Workspace get workspace => widget.workspace;
  WorkspaceObject get course => widget.course;
  bool questionFocus = false, sortByName = false;
  bool importing = false;
  bool newOnly = false;
  String importStatus = '';
  Future<void> addFiles() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final files = await FilePicker.pickFiles();
      for (final file in files) {
        final temporary = await Directory.systemTemp.createTemp(
          'fenru-course-',
        );
        try {
          final target = File(p.join(temporary.path, p.basename(file.name)));
          await file.readAsByteStream().cast<List<int>>().pipe(
            target.openWrite(),
          );
          final doc = await importStudyFile(
            workspace,
            target.path,
            folder: course.title,
          );
          await workspace.save('document', {
            ...doc.data,
            'folder': course.title,
            'courseId': course.id,
          }, id: doc.id);
        } finally {
          await temporary.delete(recursive: true);
        }
      }
      if (mounted) {
        setState(() => importStatus = '${files.length}개 파일을 과목에 추가했습니다.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => importStatus = '파일을 추가하지 못했습니다. 가져온 자료는 보관됩니다. 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  String query = '', contentFilter = '전체';
  double chatWidth = 420;
  Widget chat({bool embedded = false}) => AIChat(
    key: ValueKey('course-chat-${course.id}'),
    workspace: workspace,
    courseId: course.id,
    scopeTitle: course.title,
    embedded: embedded,
    requestDocument: true,
    expanded: questionFocus,
    onToggleExpanded: embedded
        ? () => setState(() => questionFocus = !questionFocus)
        : null,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(course.title, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton.icon(
          onPressed: importing ? null : addFiles,
          icon: const Icon(Icons.upload_file),
          label: Text(importing ? '추가 중…' : '파일 추가'),
        ),
        if (MediaQuery.sizeOf(context).width < 1100)
          TextButton.icon(
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('과목 질문'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => chat()),
            ),
          ),
      ],
    ),
    body: ListenableBuilder(
      listenable: workspace,
      builder: (_, _) {
        final docs = StudyContextService.courseDocuments(workspace, course);
        final unread = docs.where((d) => isNewSynced(workspace, d)).toList();
        final filtered =
            docs
                .where(
                  (d) =>
                      d.title.toLowerCase().contains(query.toLowerCase()) &&
                      (!newOnly || isNewSynced(workspace, d)) &&
                      (contentFilter == '전체' ||
                          (contentFilter == '파일'
                              ? d.text('contentType').isEmpty
                              : d.text('contentType') == contentFilter)),
                )
                .toList()
              ..sort(
                (a, b) => sortByName
                    ? a.title.compareTo(b.title)
                    : b.updated.compareTo(a.updated),
              );
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        return Row(
          children: [
            Expanded(
              child: Offstage(
                offstage: wide && questionFocus,
                child: OverflowBox(
                  minWidth: wide && questionFocus
                      ? (MediaQuery.sizeOf(context).width - chatWidth - 8)
                            .clamp(320, double.infinity)
                      : null,
                  maxWidth: wide && questionFocus
                      ? (MediaQuery.sizeOf(context).width - chatWidth - 8)
                            .clamp(320, double.infinity)
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '과목 자료 ${docs.length}개',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final type in [
                                  '전체',
                                  '파일',
                                  '공지',
                                  '과제',
                                  '페이지',
                                  '게시판',
                                  '강의계획',
                                ])
                                  ChoiceChip(
                                    label: Text(type),
                                    selected: contentFilter == type,
                                    onSelected: (_) =>
                                        setState(() => contentFilter = type),
                                  ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilterChip(
                                  label: Text('새 자료 ${unread.length}개'),
                                  selected: newOnly,
                                  onSelected: (value) =>
                                      setState(() => newOnly = value),
                                ),
                                if (unread.isNotEmpty)
                                  TextButton(
                                    onPressed: () async {
                                      for (final doc in unread) {
                                        await markSyncSeen(workspace, doc);
                                      }
                                    },
                                    child: const Text('모두 확인한 것으로 표시'),
                                  ),
                              ],
                            ),
                            if (importStatus.isNotEmpty) Text(importStatus),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    onChanged: (value) =>
                                        setState(() => query = value),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      prefixIcon: Icon(Icons.search),
                                      hintText: '이 과목 자료 찾기',
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: sortByName
                                      ? '최근 가져온 순으로 정렬'
                                      : '이름순으로 정렬',
                                  onPressed: () =>
                                      setState(() => sortByName = !sortByName),
                                  icon: Icon(
                                    sortByName
                                        ? Icons.sort_by_alpha
                                        : Icons.schedule,
                                  ),
                                ),
                              ],
                            ),
                            if (MediaQuery.sizeOf(context).width < 1100)
                              FilledButton.icon(
                                onPressed: docs.isEmpty
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => chat(),
                                        ),
                                      ),
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('이 과목 자료에 질문하기'),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: docs.isEmpty
                            ? const Center(
                                child: Text('파일 추가로 자료를 넣거나 Canvas에서 가져오세요.'),
                              )
                            : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  newOnly ? '새로 확인할 자료가 없습니다.' : '검색 결과가 없습니다.',
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final doc = filtered[index];
                                  return ListTile(
                                    leading: Icon(
                                      doc.text('extension') == '.pdf'
                                          ? Icons.picture_as_pdf_outlined
                                          : Icons.description_outlined,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(doc.title)),
                                        if (isNewSynced(workspace, doc))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            child: Text(
                                              doc
                                                      .text('previousVersion')
                                                      .isEmpty
                                                  ? '새 자료'
                                                  : '수정됨',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      doc.text('contentType').isNotEmpty
                                          ? '${doc.text('contentType')} · ${doc.text('posted')}'
                                          : doc.text('extension') == '.pdf'
                                          ? '읽기 · 주석 · 자료 질문'
                                          : '자료 열기',
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => DocumentReader(
                                          workspace: workspace,
                                          document: doc,
                                        ),
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: '이 자료에 질문',
                                      icon: const Icon(
                                        Icons.auto_awesome_outlined,
                                      ),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => AIChat(
                                            workspace: workspace,
                                            documentId: doc.id,
                                            scopeTitle: doc.title,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (wide) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: questionFocus
                    ? null
                    : (drag) => setState(
                        () => chatWidth = (chatWidth - drag.delta.dx).clamp(
                          320,
                          MediaQuery.sizeOf(context).width * .6,
                        ),
                      ),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: SizedBox(width: 8, child: VerticalDivider(width: 1)),
                ),
              ),
              SizedBox(
                width: questionFocus
                    ? MediaQuery.sizeOf(context).width - 8
                    : chatWidth.clamp(
                        320,
                        MediaQuery.sizeOf(context).width * .6,
                      ),
                child: chat(embedded: true),
              ),
            ],
          ],
        );
      },
    ),
  );
}
