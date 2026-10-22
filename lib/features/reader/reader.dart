import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../../ui/dialogs.dart';
import '../ai/chat.dart';
import '../../ui/note_editor.dart';
import 'ink.dart';
import '../../integrations/pdf_conversion.dart';

class DocumentReader extends StatefulWidget {
  const DocumentReader({
    super.key,
    required this.workspace,
    required this.document,
  });
  final Workspace workspace;
  final WorkspaceObject document;
  @override
  State<DocumentReader> createState() => _DocumentReaderState();
}

class _DocumentReaderState extends State<DocumentReader> {
  WorkspaceObject get document {
    final original =
        widget.workspace.byId(widget.document.id) ?? widget.document;
    final pdf = widget.workspace.byId(original.text('pdfDocumentId'));
    return pdf != null && !pdf.deleted ? pdf : original;
  }

  bool converting = false;
  Future<void> convertDocument() async {
    if (converting) return;
    setState(() => converting = true);
    await safely(() async {
      await PdfConversion(widget.workspace).convert(document);
    });
    if (mounted) setState(() => converting = false);
  }

  final controller = PdfViewerController();
  late int page = document.number('page', 1);
  Timer? pageTimer;
  bool panel = false;
  bool showAI = true, useCurrentPage = false, searchOpen = false;
  bool questionFocus = false;
  String inkTool = 'read';
  double penWidth = 2;
  int penColor = 0xff234b80;
  bool noteMode = false;
  WorkspaceObject? studyNote;
  late int readingTheme =
      (int.tryParse(widget.workspace.preferences['reader.theme'] ?? '') ?? 0)
          .clamp(0, 2);
  late int highlightColor =
      int.tryParse(
        widget.workspace.preferences['reader.highlightColor'] ?? '',
      ) ??
      0xffffd54f;
  double aiWidth = 420;
  List<PdfOutlineNode> outline = [];
  final searchInput = TextEditingController();
  final searchFocus = FocusNode();
  final undoMarks = <List<String>>[];
  final redoMarks = <List<String>>[];
  DocumentContext? pinnedSelection;
  String? error;
  PdfTextSearcher? searcher;
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(refreshMarks);
  }

  void refreshMarks() {
    if (mounted && controller.isReady) controller.invalidate();
  }

  Future<void> highlight(
    PdfTextSelectionDelegate selection,
    String type,
  ) async {
    if (!selection.isCopyAllowed || !selection.hasSelectedText) {
      setState(() => error = '먼저 PDF의 텍스트를 선택하세요. 스캔 문서는 OCR이 필요할 수 있습니다.');
      return;
    }
    await safely(() async {
      final ranges = await selection.getSelectedTextRanges();
      final created = <String>[];
      for (final range in ranges) {
        final rectangles = range.enumerateFragmentBoundingRects().map((
          fragment,
        ) {
          final r = fragment.bounds;
          return [r.left, r.top, r.right, r.bottom];
        }).toList();
        final annotation = await widget.workspace.save('annotation', {
          'title':
              '${type == 'underline' ? '밑줄' : '하이라이트'} · ${range.pageNumber}페이지',
          'body': range.text,
          'documentId': document.id,
          'page': range.pageNumber,
          'type': type,
          'rectangles': rectangles,
          'start': range.start,
          'end': range.end,
          'versionHash': document.text('hash'),
          'color': highlightColor,
        });
        created.add(annotation.id);
      }
      if (created.isNotEmpty) {
        undoMarks.add(created);
        redoMarks.clear();
      }
      if (mounted) setState(() {});
      await selection.clearTextSelection();
    });
  }

  void paintMarks(Canvas canvas, Rect pageRect, PdfPage pdfPage) {
    for (final mark
        in widget.workspace
            .ofKind('annotation')
            .where(
              (m) =>
                  m.text('documentId') == document.id &&
                  m.number('page') == pdfPage.pageNumber,
            )) {
      if (mark.text('type') == 'ink') {
        paintInk(canvas, pageRect, mark.data);
        continue;
      }
      for (final coordinates in mark.data['rectangles'] as List? ?? []) {
        final values = (coordinates as List)
            .map((v) => (v as num).toDouble())
            .toList();
        if (values.length != 4) continue;
        final rect = PdfRect(
          values[0],
          values[1],
          values[2],
          values[3],
        ).toRectInDocument(page: pdfPage, pageRect: pageRect);
        final paint = Paint()
          ..color = Color(mark.number('color', 0xffffd54f))
              .withValues(alpha: .38);
        if (mark.text('type') == 'underline') {
          paint.strokeWidth = 2;
          canvas.drawLine(
            rect.bottomLeft,
            rect.bottomRight,
            paint..color = Color(mark.number('color', 0xffffd54f)),
          );
        } else {
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  Future<void> safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => error = '작업을 저장하지 못했습니다. 저장 공간을 확인하고 다시 시도하세요.');
      }
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(refreshMarks);
    searcher?.removeListener(searchChanged);
    searcher?.dispose();
    searchInput.dispose();
    searchFocus.dispose();
    if (pageTimer?.isActive == true) {
      widget.workspace.recordPage(document, page).catchError((_) {});
    }
    pageTimer?.cancel();
    super.dispose();
  }

  Future<void> addMark(String type) async {
    final body = type == 'bookmark'
        ? '페이지 $page'
        : await askText(context, '페이지 $page 메모', multiline: true);
    if (body == null || body.trim().isEmpty) return;
    await safely(() async {
      await widget.workspace.save('annotation', {
        'title': type == 'bookmark' ? body : '페이지 $page 메모',
        'body': body,
        'documentId': document.id,
        'page': page,
        'type': type,
      });
    });
  }

  Future<void> openStudyNote() async {
    await safely(() async {
      studyNote ??= widget.workspace
          .ofKind('note')
          .where(
            (n) =>
                n.text('documentId') == document.id && n.flag('readerNotebook'),
          )
          .firstOrNull;
      studyNote ??= await widget.workspace.save('note', {
        'title': '${document.title} · 정리 노트',
        'body': '',
        'documentId': document.id,
        'readerNotebook': true,
      });
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).width < 1100) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                NoteEditor(workspace: widget.workspace, note: studyNote!),
          ),
        );
      } else {
        setState(() {
          showAI = true;
          noteMode = true;
        });
      }
    });
  }

  Widget studyPanel() => IndexedStack(
    index: noteMode && studyNote != null ? 1 : 0,
    children: [
      chat(embedded: true),
      if (studyNote != null)
        NoteEditor(
          key: ValueKey(studyNote!.id),
          workspace: widget.workspace,
          note: studyNote!,
          embedded: true,
          expanded: questionFocus,
          onToggleExpanded: () =>
              setState(() => questionFocus = !questionFocus),
        )
      else
        const SizedBox.shrink(),
    ],
  );

  Future<DocumentContext?> documentContext() async {
    if (pinnedSelection != null) return pinnedSelection;
    if (!controller.isReady ||
        !controller.textSelectionDelegate.isCopyAllowed) {
      return null;
    }
    final selected = controller.textSelectionDelegate;
    final ranges = selected.hasSelectedText
        ? await selected.getSelectedTextRanges()
        : <PdfPageTextRange>[];
    if (ranges.map((r) => r.pageNumber).toSet().length > 1) {
      throw const UserFacingException('정확한 출처를 위해 한 페이지 안의 텍스트를 선택해 주세요.');
    }
    final selection = selected.hasSelectedText
        ? await selected.getSelectedText()
        : '';
    final text = selection.isNotEmpty
        ? selection
        : (await controller.document.pages[page - 1].loadText())?.fullText ??
              '';
    return DocumentContext(
      documentId: document.id,
      title: document.title,
      page: ranges.isNotEmpty ? ranges.first.pageNumber : page,
      text: text,
      versionHash: document.text('hash'),
    );
  }

  Widget chat({bool embedded = false}) => AIChat(
    workspace: widget.workspace,
    documentId: document.id,
    scopeTitle: document.title,
    contextLabel: useCurrentPage ? '선택 문장 또는 현재 페이지 포함' : '이 자료 전체에서 근거 찾기',
    contextBuilder: useCurrentPage ? documentContext : null,
    requestDocument: true,
    embedded: embedded,
    currentPageOnly: embedded && document.text('extension') == '.pdf'
        ? useCurrentPage
        : null,
    onContextModeChanged: (value) => setState(() {
      useCurrentPage = value;
      pinnedSelection = null;
    }),
    expanded: questionFocus,
    onToggleExpanded: embedded
        ? () => setState(() => questionFocus = !questionFocus)
        : null,
    onCitation: (id, targetPage) {
      if (id == document.id && controller.isReady) {
        if (!embedded) Navigator.pop(context);
        controller.goToPage(pageNumber: targetPage);
      }
    },
  );

  Widget annotations() => ListenableBuilder(
    listenable: widget.workspace,
    builder: (_, _) {
      final marks = widget.workspace
          .ofKind('annotation')
          .where((o) => o.text('documentId') == document.id)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '책갈피 · 페이지 메모',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: marks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '읽다가 기억할 페이지를 저장하세요.\n책갈피와 메모는 원본 PDF를 변경하지 않습니다.',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: marks.length,
                    itemBuilder: (context, index) {
                      final mark = marks[index];
                      return ListTile(
                        leading: Icon(
                          mark.text('type') == 'bookmark'
                              ? Icons.bookmark_outline
                              : Icons.notes,
                        ),
                        title: Text(mark.title),
                        subtitle: Text(
                          mark.text('body'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          if (controller.isReady) {
                            controller.goToPage(
                              pageNumber: mark.number('page', 1),
                            );
                          }
                        },
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'delete') {
                              await safely(() => widget.workspace.trash(mark));
                            } else {
                              final body = await askText(
                                context,
                                '메모 수정',
                                initial: mark.text('body'),
                                multiline: true,
                              );
                              if (body != null) {
                                await safely(() async {
                                  await widget.workspace.save('annotation', {
                                    ...mark.data,
                                    'body': body,
                                  }, id: mark.id);
                                });
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('수정')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('휴지통으로'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );

  void searchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> askSelection() async {
    try {
      pinnedSelection = null;
      final selected = await documentContext();
      if (!mounted) return;
      setState(() {
        pinnedSelection = selected;
        useCurrentPage = true;
      });
      openQuestions();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is UserFacingException
              ? e.message
              : '선택한 문장을 읽지 못했습니다.',
        );
      }
    }
  }

  Future<void> openQuestions({bool chooseScope = false}) async {
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() => showAI = true);
    } else {
      if (chooseScope && controller.isReady) {
        final mode = await showModalBottomSheet<int>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('질문할 범위')),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('자료 전체에서 근거 찾기'),
                  onTap: () => Navigator.pop(context, 0),
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text('현재 $page 페이지'),
                  onTap: () => Navigator.pop(context, 1),
                ),
                if (controller.textSelectionDelegate.hasSelectedText)
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: const Text('선택한 문장'),
                    onTap: () => Navigator.pop(context, 2),
                  ),
              ],
            ),
          ),
        );
        if (mode == null || !mounted) return;
        pinnedSelection = null;
        useCurrentPage = mode != 0;
        if (mode == 1) {
          await controller.textSelectionDelegate.clearTextSelection();
        }
        if (mode == 2) pinnedSelection = await documentContext();
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => chat()));
    }
  }

  Future<void> undoHighlight({bool redo = false}) async {
    final stack = redo ? redoMarks : undoMarks;
    if (stack.isEmpty) return;
    final ids = stack.last;
    await safely(() async {
      for (final id in ids) {
        final mark = widget.workspace.byId(id);
        if (mark != null) {
          if (redo) {
            await widget.workspace.restore(mark);
          } else {
            await widget.workspace.trash(mark);
          }
        }
      }
      stack.removeLast();
      (redo ? undoMarks : redoMarks).add(ids);
      if (mounted) setState(() {});
    });
  }

  Widget navigation() => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: '페이지'),
            Tab(text: '목차'),
            Tab(text: '주석'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              !controller.isReady
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: controller.pageCount,
                      itemBuilder: (context, index) => InkWell(
                        onTap: () => controller.goToPage(pageNumber: index + 1),
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: page == index + 1
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 180,
                                child: PdfPageView(
                                  document: controller.document,
                                  pageNumber: index + 1,
                                  maximumDpi: 70,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('${index + 1} 페이지'),
                            ],
                          ),
                        ),
                      ),
                    ),
              outline.isEmpty
                  ? const Center(child: Text('이 PDF에 목차가 없습니다.'))
                  : ListView(children: outline.map(outlineTile).toList()),
              annotations(),
            ],
          ),
        ),
      ],
    ),
  );
  Widget outlineTile(PdfOutlineNode node) => node.children.isEmpty
      ? ListTile(
          title: Text(node.title),
          onTap: () => controller.goToDest(node.dest),
        )
      : ExpansionTile(
          title: Text(node.title),
          leading: IconButton(
            tooltip: '목차로 이동',
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: () => controller.goToDest(node.dest),
          ),
          children: node.children.map(outlineTile).toList(),
        );
  void openNavigation() {
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() => panel = !panel);
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: navigation(),
        ),
      );
    }
  }

  Future<void> goToPage() async {
    final value = await askText(context, '이동할 페이지', initial: '$page');
    final target = int.tryParse(value ?? '');
    if (target != null &&
        controller.isReady &&
        target > 0 &&
        target <= controller.pageCount) {
      await controller.goToPage(pageNumber: target);
    }
  }

  Widget tools() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: '읽기 · 필기 도구',
            onSelected: (value) => setState(() => inkTool = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('읽기 · 선택 · 이동')),
              PopupMenuItem(value: 'pen', child: Text('펜 필기')),
              PopupMenuItem(value: 'marker', child: Text('자유 형광펜')),
              PopupMenuItem(value: 'line', child: Text('직선 밑줄')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    inkTool == 'read'
                        ? Icons.pan_tool_outlined
                        : inkTool == 'marker'
                        ? Icons.highlight
                        : inkTool == 'line'
                        ? Icons.format_underlined
                        : Icons.draw_outlined,
                    color: inkTool == 'read'
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    {
                      'read': '읽기',
                      'pen': '펜 필기',
                      'marker': '형광펜',
                      'line': '밑줄',
                    }[inkTool]!,
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          if (inkTool != 'read') ...[
            PopupMenuButton<int>(
              tooltip: '펜 색상',
              icon: Icon(Icons.circle, color: Color(penColor)),
              onSelected: (value) => setState(() => penColor = value),
              itemBuilder: (_) => [
                for (final color in [
                  0xff234b80,
                  0xff212121,
                  0xffe53935,
                  0xffffd54f,
                  0xff81c784,
                ])
                  PopupMenuItem(
                    value: color,
                    child: Icon(Icons.circle, color: Color(color)),
                  ),
              ],
            ),
            PopupMenuButton<double>(
              tooltip: '펜 굵기',
              icon: const Icon(Icons.line_weight),
              onSelected: (value) => setState(() => penWidth = value),
              itemBuilder: (_) => [
                for (final width in [1.0, 2.0, 4.0])
                  PopupMenuItem(
                    value: width,
                    child: Text(
                      '${width.toInt()} · ${width == 1
                          ? '가늘게'
                          : width == 2
                          ? '보통'
                          : '굵게'}',
                    ),
                  ),
              ],
            ),
          ],
          IconButton(
            tooltip: '페이지 · 목차 · 주석',
            onPressed: openNavigation,
            icon: const Icon(Icons.view_sidebar_outlined),
          ),
          IconButton(
            tooltip: '이전 페이지',
            onPressed: controller.isReady && page > 1
                ? () => controller.goToPage(pageNumber: page - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: goToPage,
            child: Text(
              '$page / ${controller.isReady ? controller.pageCount : "…"}',
            ),
          ),
          IconButton(
            tooltip: '다음 페이지',
            onPressed: controller.isReady && page < controller.pageCount
                ? () => controller.goToPage(pageNumber: page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: '축소',
            onPressed: controller.isReady ? () => controller.zoomDown() : null,
            icon: const Icon(Icons.remove),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => SizedBox(
              width: 52,
              child: Text(
                controller.isReady
                    ? '${(controller.currentZoom * 100).round()}%'
                    : '—',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          IconButton(
            tooltip: '확대',
            onPressed: controller.isReady ? () => controller.zoomUp() : null,
            icon: const Icon(Icons.add),
          ),
          TextButton(
            onPressed: controller.isReady
                ? () => controller.goTo(
                    controller.calcMatrixFitWidthForPage(pageNumber: page),
                  )
                : null,
            child: const Text('너비 맞춤'),
          ),
          TextButton(
            onPressed: controller.isReady
                ? () => controller.goTo(
                    controller.calcMatrixForFit(pageNumber: page),
                  )
                : null,
            child: const Text('한 페이지'),
          ),
          IconButton(
            tooltip: 'PDF 본문 검색',
            onPressed: () => setState(() => searchOpen = !searchOpen),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '페이지 메모',
            onPressed: () => addMark('note'),
            icon: const Icon(Icons.note_add_outlined),
          ),
          PopupMenuButton<int>(
            tooltip: '주석 색상',
            icon: Icon(Icons.format_color_fill, color: Color(highlightColor)),
            onSelected: (value) {
              setState(() => highlightColor = value);
              safely(
                () => widget.workspace.setPreference(
                  'reader.highlightColor',
                  '$value',
                ),
              );
            },
            itemBuilder: (_) => [
              for (final entry in {
                0xffffd54f: '노랑',
                0xff81c784: '초록',
                0xff64b5f6: '파랑',
                0xfff48fb1: '분홍',
              }.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: Color(entry.key)),
                      const SizedBox(width: 10),
                      Text(entry.value),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '주석 실행 취소',
            onPressed: undoMarks.isEmpty ? null : () => undoHighlight(),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: '주석 다시 실행',
            onPressed: redoMarks.isEmpty
                ? null
                : () => undoHighlight(redo: true),
            icon: const Icon(Icons.redo),
          ),
          DropdownButton<int>(
            value: readingTheme,
            underline: const SizedBox(),
            onChanged: (value) {
              setState(() => readingTheme = value ?? 0);
              safely(
                () => widget.workspace.setPreference(
                  'reader.theme',
                  '$readingTheme',
                ),
              );
            },
            items: const [
              DropdownMenuItem(value: 0, child: Text('원본')),
              DropdownMenuItem(value: 1, child: Text('따뜻하게')),
              DropdownMenuItem(value: 2, child: Text('야간 읽기')),
            ],
          ),
        ],
      ),
    ),
  );
  Widget filteredPdf(File file, WorkspaceObject doc) {
    final viewer = pdfViewer(file, doc);
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(
        readingTheme == 0
            ? const [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
            : readingTheme == 1
            ? const [
                1,
                0,
                0,
                0,
                0,
                0,
                .97,
                0,
                0,
                0,
                0,
                0,
                .88,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]
            : const [
                -1,
                0,
                0,
                0,
                255,
                0,
                -1,
                0,
                0,
                255,
                0,
                0,
                -1,
                0,
                255,
                0,
                0,
                0,
                1,
                0,
              ],
      ),
      child: viewer,
    );
  }

  Widget pdfViewer(File file, WorkspaceObject doc) => PdfViewer.file(
    file.path,
    controller: controller,
    initialPageNumber: page,
    params: PdfViewerParams(
      panEnabled: inkTool == 'read',
      textSelectionParams: PdfTextSelectionParams(enabled: inkTool == 'read'),
      onViewerReady: (_, _) {
        if (searcher == null) {
          searcher = PdfTextSearcher(controller)..addListener(searchChanged);
          controller.document
              .loadOutline()
              .then((nodes) {
                if (mounted) setState(() => outline = nodes);
              })
              .catchError((Object _) {});
          if (mounted) setState(() {});
        }
      },
      pagePaintCallbacks: [
        paintMarks,
        if (searcher != null) searcher!.pageTextMatchPaintCallback,
      ],
      pageOverlaysBuilder: (_, rect, pdfPage) => [
        if (inkTool != 'read')
          Positioned.fill(
            child: InkSurface(
              key: ValueKey('ink-${pdfPage.pageNumber}-$inkTool'),
              tool: inkTool,
              color: penColor,
              width: penWidth,
              onSave: (stroke) => safely(() async {
                final mark = await widget.workspace.save('annotation', {
                  ...stroke,
                  'title':
                      '${inkTool == 'pen'
                          ? '펜 필기'
                          : inkTool == 'marker'
                          ? '형광펜'
                          : '밑줄'} · ${pdfPage.pageNumber}페이지',
                  'type': 'ink',
                  'documentId': document.id,
                  'page': pdfPage.pageNumber,
                  'versionHash': document.text('hash'),
                });
                undoMarks.add([mark.id]);
                redoMarks.clear();
                controller.invalidate();
                if (mounted) setState(() {});
              }),
            ),
          ),
      ],
      customizeContextMenuItems: (params, items) {
        final selection = params.textSelectionDelegate;
        if (!selection.isCopyAllowed || !selection.hasSelectedText) {
          return;
        }
        items.addAll([
          ContextMenuButtonItem(
            label: '선택 문장 질문',
            onPressed: () {
              params.dismissContextMenu();
              askSelection();
            },
          ),
          ContextMenuButtonItem(
            label: '하이라이트',
            onPressed: () {
              params.dismissContextMenu();
              highlight(selection, 'highlight');
            },
          ),
          ContextMenuButtonItem(
            label: '밑줄',
            onPressed: () {
              params.dismissContextMenu();
              highlight(selection, 'underline');
            },
          ),
        ]);
      },
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      onPageChanged: (value) {
        if (value == null) return;
        setState(() => page = value);
        pageTimer?.cancel();
        pageTimer = Timer(
          const Duration(milliseconds: 400),
          () => safely(() => widget.workspace.recordPage(doc, value)),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final doc = document, file = widget.workspace.fileFor(document);
    final pdf = doc.text('extension') == '.pdf';
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (pdf) {
            setState(() => searchOpen = true);
            searchFocus.requestFocus();
          }
        },
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
          if (controller.isReady) controller.zoomUp();
        },
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
          if (controller.isReady) controller.zoomDown();
        },
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): () {
          if (controller.isReady) {
            controller.goTo(
              controller.calcMatrixFitWidthForPage(pageNumber: page),
            );
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(doc.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: '자료 옆 정리 노트',
                onPressed: openStudyNote,
                icon: const Icon(Icons.edit_note),
              ),
              IconButton(
                tooltip: '책갈피 추가',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: () => addMark('bookmark'),
              ),
              TextButton.icon(
                onPressed: () {
                  if (wide) {
                    setState(() {
                      showAI = noteMode || !showAI;
                      noteMode = false;
                      if (!showAI) questionFocus = false;
                    });
                  } else {
                    openQuestions(chooseScope: true);
                  }
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('자료 질문'),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'external') {
                    await OpenFilex.open(file.path);
                  } else if (value == 'highlight' || value == 'underline') {
                    if (controller.isReady) {
                      await highlight(controller.textSelectionDelegate, value);
                    }
                  } else if (value == 'search') {
                    setState(() => searchOpen = true);
                  } else if (value == 'ai') {
                    openQuestions();
                  }
                },
                itemBuilder: (_) => [
                  if (pdf) ...const [
                    PopupMenuItem(
                      value: 'highlight',
                      child: Text('선택 영역 하이라이트'),
                    ),
                    PopupMenuItem(value: 'underline', child: Text('선택 영역 밑줄')),
                    PopupMenuItem(value: 'search', child: Text('PDF 본문 검색')),
                  ],
                  const PopupMenuItem(value: 'ai', child: Text('이 자료에 질문')),
                  const PopupMenuItem(
                    value: 'external',
                    child: Text('외부 앱으로 열기'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (pdf && !(wide && showAI && questionFocus)) tools(),
              if (pdf && searchOpen && !(wide && showAI && questionFocus))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('pdf-search'),
                          focusNode: searchFocus,
                          controller: searchInput,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '본문에서 찾기 · Enter',
                          ),
                          onSubmitted: (value) =>
                              searcher?.startTextSearch(value),
                        ),
                      ),
                      IconButton(
                        tooltip: '본문 검색 실행',
                        onPressed: () =>
                            searcher?.startTextSearch(searchInput.text),
                        icon: const Icon(Icons.search),
                      ),
                      Text(
                        '${searcher?.currentIndex == null ? 0 : searcher!.currentIndex! + 1}/${searcher?.matches.length ?? 0}',
                      ),
                      IconButton(
                        tooltip: '이전 검색 결과',
                        onPressed: () => searcher?.goToPrevMatch(),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: '다음 검색 결과',
                        onPressed: () => searcher?.goToNextMatch(),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      IconButton(
                        tooltip: '검색 닫기',
                        onPressed: () => setState(() => searchOpen = false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              if (error != null)
                MaterialBanner(
                  content: Text(error!),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => error = null),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              Expanded(
                child: Row(
                  children: [
                    if (pdf && wide && panel && !(showAI && questionFocus)) ...[
                      SizedBox(width: 250, child: navigation()),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      key: const ValueKey('reader-document'),
                      child: Offstage(
                        offstage: wide && showAI && questionFocus,
                        child: OverflowBox(
                          minWidth: wide && showAI && questionFocus
                              ? (MediaQuery.sizeOf(context).width - aiWidth - 8)
                                    .clamp(320, double.infinity)
                              : null,
                          maxWidth: wide && showAI && questionFocus
                              ? (MediaQuery.sizeOf(context).width - aiWidth - 8)
                                    .clamp(320, double.infinity)
                              : null,
                          child: pdf
                              ? filteredPdf(file, doc)
                              : _FilePreview(
                                  file: file,
                                  extension: doc.text('extension'),
                                  conversionError: doc.text('conversionError'),
                                  converting: converting,
                                  onConvert: PdfConversion.supports(doc)
                                      ? convertDocument
                                      : null,
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
                                () => aiWidth = (aiWidth - drag.delta.dx).clamp(
                                  320,
                                  MediaQuery.sizeOf(context).width * .55,
                                ),
                              ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: SizedBox(
                            width: showAI ? 8 : 0,
                            child: const VerticalDivider(width: 1),
                          ),
                        ),
                      ),
                      SizedBox(
                        key: const ValueKey('reader-question-panel'),
                        width: !showAI
                            ? 0
                            : questionFocus
                            ? MediaQuery.sizeOf(context).width - 8
                            : aiWidth.clamp(
                                320,
                                MediaQuery.sizeOf(context).width * .55,
                              ),
                        child: Offstage(
                          offstage: !showAI,
                          child: OverflowBox(
                            minWidth: !showAI ? aiWidth : null,
                            maxWidth: !showAI ? aiWidth : null,
                            child: studyPanel(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: pdf && !(wide && showAI && questionFocus)
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$page 페이지 · ${controller.isReady ? controller.pageCount : "…"}쪽',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '선택 후 우클릭/길게 눌러 주석 · 질문',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({
    required this.file,
    required this.extension,
    this.onConvert,
    this.conversionError = '',
    this.converting = false,
  });
  final VoidCallback? onConvert;
  final String conversionError;
  final bool converting;
  final File file;
  final String extension;
  @override
  Widget build(BuildContext context) {
    if (['.png', '.jpg', '.jpeg', '.webp'].contains(extension)) {
      return InteractiveViewer(
        child: Center(
          child: Image.file(
            file,
            errorBuilder: (_, _, _) => const Text('이미지를 읽을 수 없습니다.'),
          ),
        ),
      );
    }
    if (['.md', '.txt', '.html', '.csv', '.markdown'].contains(extension)) {
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('텍스트를 읽을 수 없습니다. 외부 앱으로 열어 주세요.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return extension == '.md' || extension == '.markdown'
              ? Markdown(data: snapshot.data!, selectable: true)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(snapshot.data!),
                );
        },
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              '파일이 안전하게 보관되었습니다.\n이 형식은 외부 앱에서 열 수 있습니다.',
              textAlign: TextAlign.center,
            ),
            if (onConvert != null) ...[
              const SizedBox(height: 16),
              if (conversionError.isNotEmpty)
                Text(conversionError, textAlign: TextAlign.center),
              FilledButton.icon(
                onPressed: converting ? null : onConvert,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(converting ? 'PDF 변환 중…' : 'PDF로 변환 · 재시도'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final result = await OpenFilex.open(file.path);
                if (result.type != ResultType.done && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('이 파일을 열 수 있는 외부 앱을 설치하세요.')),
                  );
                }
              },
              child: const Text('외부 앱으로 열기'),
            ),
          ],
        ),
      ),
    );
  }
}
