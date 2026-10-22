import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../reader/reader.dart';
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
  String query = '';
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
        final filtered =
            docs
                .where(
                  (d) => d.title.toLowerCase().contains(query.toLowerCase()),
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
                                child: Text('먼저 Canvas에서 이 과목 자료를 가져오세요.'),
                              )
                            : filtered.isEmpty
                            ? const Center(child: Text('검색 결과가 없습니다.'))
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
                                    title: Text(doc.title),
                                    subtitle: Text(
                                      doc.text('extension') == '.pdf'
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
