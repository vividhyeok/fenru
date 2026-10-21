import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../reader/reader.dart';
import 'chat.dart';
import 'study_context.dart';

class CourseWorkspace extends StatelessWidget {
  const CourseWorkspace({
    super.key,
    required this.workspace,
    required this.course,
  });
  final Workspace workspace;
  final WorkspaceObject course;
  Widget chat({bool embedded = false}) => AIChat(
    key: ValueKey('course-chat-${course.id}'),
    workspace: workspace,
    courseId: course.id,
    scopeTitle: course.title,
    embedded: embedded,
    requestDocument: true,
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
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '과목 자료',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${docs.length}개 자료 · 자료를 열어 읽거나 이 과목 자료에 함께 질문하세요.',
                        ),
                        const SizedBox(height: 16),
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
                        : ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
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
                                  icon: const Icon(Icons.auto_awesome_outlined),
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
            if (MediaQuery.sizeOf(context).width >= 1100) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: 400, child: chat(embedded: true)),
            ],
          ],
        );
      },
    ),
  );
}
