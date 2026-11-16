import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../../ui/dialogs.dart';
import '../ai/chat.dart';
import '../ai/study_context.dart';
import '../../ui/note_editor.dart';
import 'ink.dart';
import 'reading_tools.dart';
import 'reader_toolbar.dart';
import 'reader_settings.dart';
import '../../integrations/pdf_conversion.dart';

class DocumentReader extends StatefulWidget {
  const DocumentReader({
    super.key,
    required this.workspace,
    required this.document,
    this.initialPage,
    this.studyAnchor,
  });
  final Workspace workspace;
  final WorkspaceObject document;
  final int? initialPage;
  final WorkspaceObject? studyAnchor;
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
  late int page = widget.initialPage ?? document.number('page', 1);
  Timer? pageTimer;
  bool panel = false;
  late final savedView = ReaderViewSettings.read(widget.workspace, document.id);
  late bool showAI = savedView.showAI;
  bool useCurrentPage = false, searchOpen = false;
  late String fitMode = savedView.fit;
  bool restoredView = false;
  double? interactionZoom;
  final navigationTouches = <int, Offset>{};
  final activeStylusPointers = <int>{};
  final returnLocations =
      <({Offset center, double zoom, int page, String fit})>[];
  late List<PenPreset> presets = PenPreset.read(widget.workspace);
  bool questionFocus = false;
  late String inkTool =
      widget.workspace.preferences['reader.startTool'] == 'read'
      ? 'read'
      : 'pen';
  bool temporaryEraser = false;
  String lastWritingTool = 'pen';
  bool focusReading = false;
  late final inkWidths = {
    for (final tool in ['pen', 'marker', 'line']) tool: readInkWidth(tool),
  };
  double readInkWidth(String tool) {
    final preferences = widget.workspace.preferences;
    final value = double.tryParse(
      preferences['reader.width.$tool'] ?? preferences['reader.penWidth'] ?? '',
    );
    return value != null && value.isFinite ? value.clamp(.5, 20) : 2;
  }

  String get settingsTool =>
      inkWidths.containsKey(inkTool) ? inkTool : lastWritingTool;
  double get penWidth => inkWidths[settingsTool]!;
  int get activeColor => settingsTool == 'marker' ? highlightColor : penColor;
  static const inkColors = {
    0xff212121: '검정',
    0xff234b80: '남색',
    0xffe53935: '빨강',
    0xffffd54f: '노랑',
    0xff81c784: '초록',
    0xff64b5f6: '하늘색',
  };

  void chooseTool(String tool) {
    setState(() {
      inkTool = tool;
      temporaryEraser = false;
      if (inkWidths.containsKey(tool)) lastWritingTool = tool;
    });
  }

  Future<void> saveWidth(String tool, double width) => safely(
    () => widget.workspace.setPreference('reader.width.$tool', '$width'),
  );

  void chooseWidth(double width) {
    final tool = settingsTool;
    setState(() => inkWidths[tool] = width);
    saveWidth(tool, width);
  }

  Future<void> savePreset(int slot) async {
    await safely(() async {
      await PenPreset(
        '즐겨찾기 ${slot + 1}',
        settingsTool,
        activeColor,
        penWidth,
      ).save(widget.workspace, slot);
      if (mounted) setState(() => presets = PenPreset.read(widget.workspace));
    });
  }

  void choosePreset(PenPreset preset) {
    chooseTool(preset.tool);
    setState(() {
      inkWidths[preset.tool] = preset.width;
      if (preset.tool == 'marker') {
        highlightColor = preset.color;
      } else {
        penColor = preset.color;
      }
    });
    saveWidth(preset.tool, preset.width);
    saveColor(preset.tool, preset.color);
  }

  void chooseColor(int color) {
    final tool = settingsTool;
    setState(() {
      if (tool == 'marker') {
        highlightColor = color;
      } else {
        penColor = color;
      }
    });
    saveColor(tool, color);
  }

  Future<void> saveColor(String tool, int color) => safely(
    () => widget.workspace.setPreference(
      tool == 'marker' ? 'reader.highlightColor' : 'reader.penColor',
      '$color',
    ),
  );
  late int penColor =
      int.tryParse(widget.workspace.preferences['reader.penColor'] ?? '') ??
      0xff234b80;
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
  late double aiWidth = savedView.panelWidth;
  Timer? viewTimer;
  List<PdfOutlineNode> outline = [];
  final searchInput = TextEditingController();
  final searchFocus = FocusNode();
  final previewErasedIds = <String>{};
  final undoMarks = <List<String>>[];
  final redoMarks = <List<String>>[];
  DocumentContext? pinnedSelection;
  late WorkspaceObject? studyAnchor = widget.studyAnchor;

  Future<void> saveStudyAnchor() => safely(() async {
    final selected = await documentContext(
      usePinned: false,
      selectionOnly: true,
    );
    if (!mounted || selected == null || selected.text.trim().isEmpty) return;
    final ranges = await controller.textSelectionDelegate
        .getSelectedTextRanges();
    final bounds = ranges.firstOrNull?.bounds;
    if (!mounted) return;
    var draft = '';
    final question = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('나중에 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(selected.text, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => draft = value,
              decoration: const InputDecoration(labelText: '남겨둘 질문 (선택)'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, draft.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (!mounted || question == null) return;
    final saved = await widget.workspace.save('studyAnchor', {
      'title': selected.title,
      'documentId': selected.documentId,
      'page': selected.page,
      'versionHash': selected.versionHash,
      'selection': selected.text,
      if (bounds != null)
        'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
      'body': question,
    });
    if (mounted) setState(() => studyAnchor = saved);
  });

  Future<void> resolveStudyAnchor(WorkspaceObject anchor) => safely(() async {
    await widget.workspace.save('studyAnchor', {
      ...anchor.data,
      'resolved': true,
    }, id: anchor.id);
    if (mounted && studyAnchor?.id == anchor.id) {
      setState(() => studyAnchor = null);
    }
  });

  void openSelectionQuestion(
    DocumentContext selection,
    String draft, {
    bool sendNow = false,
    WorkspaceObject? anchor,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AIChat(
          workspace: widget.workspace,
          documentId: selection.documentId,
          scopeTitle: selection.title,
          contextLabel:
              '${selection.page}쪽 · ${anchor == null ? '선택 문장' : '저장된 문장'}',
          contextBuilder: () async => selection,
          sessionId: anchor?.text('sessionId').isNotEmpty == true
              ? anchor!.text('sessionId')
              : null,
          initialQuestion: anchor?.text('sessionId').isNotEmpty == true
              ? null
              : draft,
          sendInitialQuestion: sendNow,
          startNewSession: anchor != null,
          onQuestionSaved: anchor == null
              ? null
              : (session, question) => safely(() async {
                  final current = widget.workspace.byId(anchor.id) ?? anchor;
                  final saved = await widget.workspace.save('studyAnchor', {
                    ...current.data,
                    'sessionId': session,
                    'body': question,
                  }, id: anchor.id);
                  if (mounted && studyAnchor?.id == anchor.id) {
                    setState(() => studyAnchor = saved);
                  }
                }),
        ),
      ),
    );
  }

  Widget studyResume(WorkspaceObject anchor) {
    final sameVersion = anchor.text('versionHash') == document.text('hash');
    final question = anchor.text('body');
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        key: ValueKey(anchor.id),
        initiallyExpanded: widget.studyAnchor?.id == anchor.id,
        title: Text(
          question.isEmpty ? '나중에 확인 · ${anchor.number('page', 1)}쪽' : question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          anchor.text('selection'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(anchor.text('selection')),
          ),
          if (!sameVersion) const Text('자료가 변경되었습니다. 저장한 문장을 원문과 대조하세요.'),
          Wrap(
            spacing: 8,
            children: [
              if (sameVersion)
                TextButton(
                  onPressed: () => openSelectionQuestion(
                    DocumentContext(
                      documentId: document.id,
                      title: document.title,
                      page: anchor.number('page', 1),
                      text: anchor.text('selection'),
                      versionHash: anchor.text('versionHash'),
                    ),
                    question,
                    anchor: anchor,
                  ),
                  child: const Text('질문 이어가기'),
                ),
              TextButton(
                onPressed: () => resolveStudyAnchor(anchor),
                child: const Text('해결했음'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? error;
  PdfTextSearcher? searcher;
  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(refreshMarks);
    markSyncSeen(widget.workspace, document).catchError((_) {});
    if (PdfConversion.canConvertLocally(document) &&
        document.text('conversionStatus') != 'failed') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) convertDocument();
      });
    }
  }

  void rememberJump() {
    if (!controller.isReady) return;
    final location = (
      center: controller.centerPosition,
      zoom: controller.currentZoom,
      page: page,
      fit: fitMode,
    );
    if (returnLocations.isNotEmpty &&
        (returnLocations.last.center - location.center).distance < 1 &&
        (returnLocations.last.zoom - location.zoom).abs() < .001) {
      return;
    }
    setState(() {
      returnLocations.add(location);
      if (returnLocations.length > 30) returnLocations.removeAt(0);
    });
  }

  Future<void> returnToReading() async {
    if (!controller.isReady || returnLocations.isEmpty) return;
    final location = returnLocations.removeLast();
    setState(() => fitMode = location.fit);
    await controller.goTo(
      controller.calcMatrixFor(location.center, zoom: location.zoom),
    );
    rememberView();
  }

  Future<void> changeZoom(bool increase) async {
    fitMode = 'custom';
    if (increase) {
      await controller.zoomUp();
    } else {
      await controller.zoomDown();
    }
    rememberView();
  }

  void rememberView() {
    viewTimer?.cancel();
    viewTimer = Timer(const Duration(milliseconds: 500), persistView);
  }

  void persistView() {
    if (!controller.isReady || !restoredView) return;
    ReaderViewSettings(
      fit: fitMode,
      zoom: controller.currentZoom,
      x: controller.centerPosition.dx,
      y: controller.centerPosition.dy,
      panelWidth: aiWidth,
      showAI: showAI,
    ).save(widget.workspace, document.id).catchError((_) {});
  }

  Future<void> fitPage(String mode) async {
    setState(() => fitMode = mode);
    await controller.goTo(
      mode == 'width'
          ? controller.calcMatrixFitWidthForPage(pageNumber: page)
          : controller.calcMatrixForFit(pageNumber: page),
    );
    rememberView();
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
      if (previewErasedIds.contains(mark.id)) continue;
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
    viewTimer?.cancel();
    persistView();
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

  Future<DocumentContext?> documentContext({
    bool usePinned = true,
    bool selectionOnly = false,
  }) async {
    if (usePinned && pinnedSelection != null) return pinnedSelection;
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
    if (selectionOnly && (ranges.isEmpty || selection.trim().isEmpty)) {
      return null;
    }
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

  Future<StudyContext> resolveContext(String mode, String range) async {
    if (mode == 'selection') {
      if (pinnedSelection == null &&
          (!controller.isReady ||
              !controller.textSelectionDelegate.hasSelectedText)) {
        throw const UserFacingException('먼저 PDF에서 질문할 문장을 선택하세요.');
      }
      final selected = await documentContext();
      return StudyContext([?selected]);
    }
    return StudyContextService(widget.workspace)
        .readScope(document, mode, page: page, range: range);
  }

  Widget chat({bool embedded = false}) => AIChat(
    workspace: widget.workspace,
    contextResolver: document.text('extension') == '.pdf'
        ? resolveContext
        : null,
    documentId: document.id,
    scopeTitle: document.title,
    currentPageNumber: page,
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
        rememberJump();
        if (!embedded) Navigator.pop(context);
        if (embedded && questionFocus) setState(() => questionFocus = false);
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
                            rememberJump();
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
                          itemBuilder: (_) => [
                            if (mark.text('type') != 'ink')
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('수정'),
                              ),
                            const PopupMenuItem(
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
      await widget.workspace.setPreference('reader.referenceMode', 'selection');
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
                  title: const Text('PDF 전문 · 모든 페이지'),
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
        await widget.workspace.setPreference(
          'reader.referenceMode',
          mode == 0
              ? 'full'
              : mode == 1
              ? 'current'
              : 'selection',
        );
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
        final erased = id.startsWith('erase:');
        final mark = widget.workspace.byId(erased ? id.substring(6) : id);
        if (mark != null) {
          if (redo != erased) {
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
                        onTap: () {
                          rememberJump();
                          controller.goToPage(pageNumber: index + 1);
                        },
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
          onTap: () {
            rememberJump();
            controller.goToDest(node.dest);
          },
        )
      : ExpansionTile(
          title: Text(node.title),
          leading: IconButton(
            tooltip: '목차로 이동',
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: () {
              rememberJump();
              controller.goToDest(node.dest);
            },
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
      rememberJump();
      await controller.goToPage(pageNumber: target);
    }
  }

  Future<void> openReaderSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReaderSettings(workspace: widget.workspace),
      ),
    );
    if (mounted) {
      setState(() {
        readingTheme =
            (int.tryParse(widget.workspace.preferences['reader.theme'] ?? '') ??
                    0)
                .clamp(0, 2);
      });
    }
  }

  Future<void> penOptions() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, update) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('펜 설정', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'pen': '펜',
                    'marker': '형광펜',
                    'line': '직선 밑줄',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: settingsTool == entry.key,
                      onSelected: (_) {
                        chooseTool(entry.key);
                        update(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in inkColors.keys)
                    IconButton(
                      tooltip: inkColors[color],
                      isSelected: activeColor == color,
                      onPressed: () {
                        chooseColor(color);
                        update(() {});
                      },
                      icon: Icon(Icons.circle, color: Color(color)),
                      style: IconButton.styleFrom(
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('굵기 ${penWidth.toStringAsFixed(1)}'),
              Slider(
                value: penWidth,
                min: .5,
                max: 20,
                divisions: 39,
                onChanged: (value) {
                  setState(() => inkWidths[settingsTool] = value);
                  update(() {});
                },
                onChangeEnd: (value) => saveWidth(settingsTool, value),
              ),
              const Text('즐겨찾기 · 눌러 사용 / 길게 눌러 현재 펜 저장'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var slot = 0; slot < presets.length; slot++)
                    GestureDetector(
                      onLongPress: () async {
                        await savePreset(slot);
                        if (sheetContext.mounted) update(() {});
                      },
                      child: OutlinedButton.icon(
                        onPressed: () {
                          choosePreset(presets[slot]);
                          update(() {});
                        },
                        icon: Icon(
                          Icons.draw_outlined,
                          color: Color(presets[slot].color),
                        ),
                        label: Text('${slot + 1}'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> pageOptions() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, update) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('페이지 · 보기', style: Theme.of(context).textTheme.titleLarge),
              Row(
                children: [
                  IconButton(
                    tooltip: '이전 페이지',
                    onPressed: controller.isReady && page > 1
                        ? () async {
                            await controller.goToPage(pageNumber: page - 1);
                            if (sheetContext.mounted) update(() {});
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton(
                    onPressed: () async {
                      await goToPage();
                      if (sheetContext.mounted) update(() {});
                    },
                    child: Text(
                      '$page / ${controller.isReady ? controller.pageCount : "…"}',
                    ),
                  ),
                  IconButton(
                    tooltip: '다음 페이지',
                    onPressed: controller.isReady && page < controller.pageCount
                        ? () async {
                            await controller.goToPage(pageNumber: page + 1);
                            if (sheetContext.mounted) update(() {});
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: '축소',
                    onPressed: controller.isReady
                        ? () async {
                            await changeZoom(false);
                            if (sheetContext.mounted) update(() {});
                          }
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    controller.isReady
                        ? '${(controller.currentZoom * 100).round()}%'
                        : '—',
                  ),
                  IconButton(
                    tooltip: '확대',
                    onPressed: controller.isReady
                        ? () async {
                            await changeZoom(true);
                            if (sheetContext.mounted) update(() {});
                          }
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                  TextButton(
                    onPressed: controller.isReady
                        ? () => fitPage('width')
                        : null,
                    child: const Text('너비 맞춤'),
                  ),
                  TextButton(
                    onPressed: controller.isReady
                        ? () => fitPage('page')
                        : null,
                    child: const Text('한 페이지'),
                  ),
                ],
              ),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      openNavigation();
                    },
                    icon: const Icon(Icons.view_sidebar_outlined),
                    label: const Text('페이지 · 목차 · 주석'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      setState(() => searchOpen = true);
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('PDF 본문 검색'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      addMark('bookmark');
                    },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('책갈피 추가'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      addMark('note');
                    },
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('페이지 메모'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      openStudyNote();
                    },
                    icon: const Icon(Icons.edit_note),
                    label: const Text('자료 옆 정리 노트'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      openReaderSettings();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('읽기 · 필기 설정'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget writingToolbar() => ReaderToolbar(
    tool: inkTool,
    lastWritingTool: lastWritingTool,
    onTool: chooseTool,
    temporaryEraser: temporaryEraser,
    color: activeColor,
    colors: inkColors,
    onColor: chooseColor,
    width: penWidth,
    onWidth: chooseWidth,
    presets: presets,
    onPreset: choosePreset,
    onSavePreset: savePreset,
    onPenSettings: penOptions,
    onUndo: undoMarks.isEmpty ? null : () => undoHighlight(),
    onRedo: redoMarks.isEmpty ? null : () => undoHighlight(redo: true),
    onReturn: returnLocations.isEmpty ? null : returnToReading,
    onPages: pageOptions,
    pageLabel: '$page / ${controller.isReady ? controller.pageCount : "…"}',
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
      child: Listener(
        onPointerDown: startNavigationTouch,
        onPointerMove: updateNavigationTouch,
        onPointerUp: endNavigationTouch,
        onPointerCancel: endNavigationTouch,
        child: viewer,
      ),
    );
  }

  void startNavigationTouch(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      activeStylusPointers.add(event.pointer);
    }
    if (event.kind != PointerDeviceKind.touch) return;
    navigationTouches[event.pointer] = event.position;
    final count = navigationTouches.length;
    if ((count == 2 || (count == 1 && oneFingerNavigation)) &&
        controller.isReady) {
      controller.stopInteractiveViewerAnimation();
    }
  }

  bool get oneFingerNavigation =>
      widget.workspace.preferences['reader.touchNavigation'] == 'oneFinger';

  void updateNavigationTouch(PointerMoveEvent event) {
    final previous = navigationTouches[event.pointer];
    if (previous == null) return;
    navigationTouches[event.pointer] = event.position;
    final count = navigationTouches.length;
    if ((count != 2 && !(count == 1 && oneFingerNavigation)) ||
        activeStylusPointers.isNotEmpty ||
        !controller.isReady) {
      return;
    }

    var previousFocus = previous;
    var nextFocus = event.position;
    var scale = 1.0;
    if (count == 2) {
      final other = navigationTouches.entries
          .firstWhere((touch) => touch.key != event.pointer)
          .value;
      final oldDistance = (previous - other).distance;
      if (oldDistance < 1) return;
      previousFocus = (previous + other) / 2;
      nextFocus = (event.position + other) / 2;
      scale = (event.position - other).distance / oldDistance;
    }
    final anchor = controller.globalToDocument(previousFocus);
    final focalPoint = controller.globalToLocal(nextFocus);
    if (anchor == null || focalPoint == null) return;
    final oldZoom = controller.currentZoom;
    final zoom = (oldZoom * scale).clamp(
      controller.minScale,
      controller.maxScale,
    );
    final center =
        anchor + (controller.viewSize.center(Offset.zero) - focalPoint) / zoom;
    controller.value = controller.calcMatrixFor(center, zoom: zoom);
    if ((oldZoom - controller.currentZoom).abs() > .000001) fitMode = 'custom';
    rememberView();
  }

  void endNavigationTouch(PointerEvent event) {
    navigationTouches.remove(event.pointer);
    activeStylusPointers.remove(event.pointer);
  }

  Widget pdfViewer(File file, WorkspaceObject doc) => PdfViewer.file(
    file.path,
    controller: controller,
    initialPageNumber: page,
    params: PdfViewerParams(
      panEnabled: false,
      scaleEnabled: false,
      textSelectionParams: PdfTextSelectionParams(enabled: inkTool == 'read'),
      onInteractionStart: (_) => interactionZoom = controller.currentZoom,
      onInteractionEnd: (_) {
        if (interactionZoom != null &&
            (interactionZoom! - controller.currentZoom).abs() > .001) {
          fitMode = 'custom';
        }
        rememberView();
      },
      onViewSizeChanged: (_, oldSize, _) {
        if (oldSize == null || !restoredView || fitMode == 'custom') return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && controller.isReady) fitPage(fitMode);
        });
      },
      onViewerReady: (_, _) {
        if (!restoredView) {
          restoredView = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted || !controller.isReady) return;
            if (savedView.fit == 'width' || savedView.fit == 'page') {
              await fitPage(savedView.fit);
            } else if (widget.initialPage == null &&
                savedView.x != null &&
                savedView.y != null) {
              await controller.goTo(
                controller.calcMatrixFor(
                  Offset(savedView.x!, savedView.y!),
                  zoom: savedView.zoom,
                ),
                duration: Duration.zero,
              );
            }
            final anchor = studyAnchor;
            final bounds = anchor?.data['bounds'];
            if (mounted &&
                controller.isReady &&
                anchor != null &&
                anchor.text('versionHash') == document.text('hash') &&
                bounds is List &&
                bounds.length == 4 &&
                bounds.every((v) => v is num && v.isFinite)) {
              final target = anchor.number('page', 1);
              if (target >= 1 && target <= controller.pageCount) {
                await controller.goToRectInsidePage(
                  pageNumber: target,
                  rect: PdfRect(
                    (bounds[0] as num).toDouble(),
                    (bounds[1] as num).toDouble(),
                    (bounds[2] as num).toDouble(),
                    (bounds[3] as num).toDouble(),
                  ),
                  duration: Duration.zero,
                );
              }
            }
          });
        }
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
        Positioned.fill(
          child: InkSurface(
            key: ValueKey('ink-${pdfPage.pageNumber}-$inkTool'),
            tool: inkTool,
            penOnly: true,
            stylusButtonEraser:
                widget.workspace.preferences['reader.stylusButtonEraser'] !=
                'false',
            onTemporaryEraser: (value) {
              if (mounted && value != temporaryEraser) {
                setState(() => temporaryEraser = value);
              }
            },
            onErasePreview: (sweep) {
              var changed = false;
              for (final mark
                  in widget.workspace
                      .ofKind('annotation')
                      .where(
                        (m) =>
                            m.text('documentId') == document.id &&
                            m.number('page') == pdfPage.pageNumber &&
                            m.text('type') == 'ink' &&
                            !previewErasedIds.contains(m.id),
                      )) {
                if (inkIntersects(mark.data, sweep, rect.size)) {
                  previewErasedIds.add(mark.id);
                  changed = true;
                }
              }
              if (changed && controller.isReady) controller.invalidate();
            },
            onPreviewEnd: () {
              previewErasedIds.clear();
              if (mounted && controller.isReady) controller.invalidate();
            },
            color: activeColor,
            width: penWidth,
            onSave: (stroke) => safely(() async {
              if (stroke['tool'] == 'eraser') {
                final erased = <String>[];
                for (final mark
                    in widget.workspace
                        .ofKind('annotation')
                        .where(
                          (m) =>
                              m.text('documentId') == document.id &&
                              m.number('page') == pdfPage.pageNumber &&
                              m.text('type') == 'ink',
                        )
                        .toList()) {
                  if (inkIntersects(mark.data, stroke, rect.size)) {
                    await widget.workspace.trash(mark);
                    erased.add('erase:${mark.id}');
                  }
                }
                if (erased.isNotEmpty) {
                  undoMarks.add(erased);
                  redoMarks.clear();
                }
                controller.invalidate();
                if (mounted) setState(() {});
                return;
              }
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
            label: '핵심 설명',
            onPressed: () async {
              params.dismissContextMenu();
              await safely(() async {
                final selected = await documentContext(
                  usePinned: false,
                  selectionOnly: true,
                );
                if (mounted && selected != null) {
                  openSelectionQuestion(
                    selected,
                    '선택한 문장의 핵심을 먼저 짧게 설명하고, 이유와 원문 근거를 알려줘.',
                    sendNow: true,
                  );
                }
              });
            },
          ),
          ContextMenuButtonItem(
            label: '나중에 확인',
            onPressed: () {
              params.dismissContextMenu();
              saveStudyAnchor();
            },
          ),
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
        rememberView();
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
          if (controller.isReady) changeZoom(true);
        },
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
          if (controller.isReady) changeZoom(false);
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
          appBar: focusReading
              ? null
              : AppBar(
                  toolbarHeight: 44,
                  title: Text(doc.title, overflow: TextOverflow.ellipsis),
                  actions: [
                    IconButton(
                      tooltip: '집중해서 필기',
                      onPressed: () => setState(() {
                        focusReading = true;
                        if (inkTool == 'read') inkTool = lastWritingTool;
                        showAI = false;
                        questionFocus = false;
                      }),
                      icon: const Icon(Icons.fullscreen),
                    ),
                    IconButton(
                      tooltip: '자료 질문 열기 · 닫기',
                      onPressed: () {
                        if (wide) {
                          setState(() {
                            showAI = noteMode || !showAI;
                            noteMode = false;
                            if (!showAI) questionFocus = false;
                          });
                          rememberView();
                        } else {
                          openQuestions(chooseScope: true);
                        }
                      },
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                    if (doc.flag('conversionTextOnly'))
                      const Tooltip(
                        message: '본문 추출 PDF · 원본의 그림과 배치는 원본 파일에서 확인하세요.',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.info_outline, size: 18),
                        ),
                      ),
                    PopupMenuButton<String>(
                      key: const ValueKey('reader-document-menu'),
                      tooltip: '자료 메뉴',
                      onSelected: (value) async {
                        if (value == 'external') {
                          final source = widget.workspace.byId(
                            doc.text('derivedFrom'),
                          );
                          await OpenFilex.open(
                            source == null || source.deleted
                                ? file.path
                                : widget.workspace.fileFor(source).path,
                          );
                        } else if (value == 'highlight' ||
                            value == 'underline') {
                          if (controller.isReady) {
                            await highlight(
                              controller.textSelectionDelegate,
                              value,
                            );
                          }
                        } else if (value == 'search') {
                          setState(() => searchOpen = true);
                        } else if (value == 'ai') {
                          openQuestions();
                        } else if (value == 'anchor') {
                          await saveStudyAnchor();
                        }
                      },
                      itemBuilder: (_) => [
                        if (pdf &&
                            controller.isReady &&
                            controller.textSelectionDelegate.hasSelectedText &&
                            controller.textSelectionDelegate.isCopyAllowed)
                          const PopupMenuItem(
                            value: 'anchor',
                            child: Text('나중에 확인'),
                          ),
                        if (pdf) ...const [
                          PopupMenuItem(
                            value: 'highlight',
                            child: Text('선택 영역 하이라이트'),
                          ),
                          PopupMenuItem(
                            value: 'underline',
                            child: Text('선택 영역 밑줄'),
                          ),
                          PopupMenuItem(
                            value: 'search',
                            child: Text('PDF 본문 검색'),
                          ),
                        ],
                        const PopupMenuItem(
                          value: 'ai',
                          child: Text('이 자료에 질문'),
                        ),
                        PopupMenuItem(
                          value: 'external',
                          child: Text(
                            doc.text('derivedFrom').isEmpty
                                ? '외부 앱으로 열기'
                                : '원본을 외부 앱으로 열기',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          body: SafeArea(
            top: focusReading,
            child: Column(
              children: [
                if (!focusReading && studyAnchor != null)
                  studyResume(studyAnchor!),
                if (pdf &&
                    !focusReading &&
                    searchOpen &&
                    !(wide && showAI && questionFocus))
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
                          onPressed: () {
                            rememberJump();
                            searcher?.goToPrevMatch();
                          },
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          tooltip: '다음 검색 결과',
                          onPressed: () {
                            rememberJump();
                            searcher?.goToNextMatch();
                          },
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
                      if (pdf &&
                          !focusReading &&
                          wide &&
                          panel &&
                          !(showAI && questionFocus)) ...[
                        SizedBox(width: 250, child: navigation()),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        key: const ValueKey('reader-document'),
                        child: Offstage(
                          offstage: wide && showAI && questionFocus,
                          child: OverflowBox(
                            minWidth: wide && showAI && questionFocus
                                ? (MediaQuery.sizeOf(context).width -
                                          aiWidth -
                                          8)
                                      .clamp(320, double.infinity)
                                : null,
                            maxWidth: wide && showAI && questionFocus
                                ? (MediaQuery.sizeOf(context).width -
                                          aiWidth -
                                          8)
                                      .clamp(320, double.infinity)
                                : null,
                            child: pdf
                                ? Column(
                                    children: [
                                      if (!focusReading) writingToolbar(),
                                      Expanded(child: filteredPdf(file, doc)),
                                    ],
                                  )
                                : _FilePreview(
                                    file: file,
                                    extension: doc.text('extension'),
                                    conversionError: doc.text(
                                      'conversionError',
                                    ),
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
                          onHorizontalDragEnd: (_) => rememberView(),
                          onHorizontalDragUpdate: questionFocus
                              ? null
                              : (drag) => setState(
                                  () =>
                                      aiWidth = (aiWidth - drag.delta.dx).clamp(
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
          ),
          floatingActionButton: focusReading
              ? FloatingActionButton.small(
                  tooltip: '도구 다시 보기',
                  onPressed: () => setState(() => focusReading = false),
                  child: const Icon(Icons.fullscreen_exit),
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
    if (PdfConversion.textExtensions.contains(extension)) {
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('텍스트를 읽을 수 없습니다. 외부 앱으로 열어 주세요.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final preview = extension == '.md' || extension == '.markdown'
              ? Markdown(data: snapshot.data!, selectable: true)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(snapshot.data!),
                );
          return Column(
            children: [
              if (onConvert != null)
                TextButton.icon(
                  onPressed: converting ? null : onConvert,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(converting ? 'PDF 변환 중…' : 'PDF로 변환'),
                ),
              if (conversionError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(conversionError),
                ),
              Expanded(child: preview),
            ],
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
