import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';
import '../../ui/dialogs.dart';

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
  final controller = PdfViewerController();
  late int page = widget.document.number('page', 1);
  Timer? pageTimer;
  bool panel = true;
  String? error;
  late final searcher = PdfTextSearcher(controller);
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
    if (!selection.isCopyAllowed || !selection.hasSelectedText) return;
    await safely(() async {
      final ranges = await selection.getSelectedTextRanges();
      for (final range in ranges) {
        final rectangles = range.enumerateFragmentBoundingRects().map((
          fragment,
        ) {
          final r = fragment.bounds;
          return [r.left, r.top, r.right, r.bottom];
        }).toList();
        await widget.workspace.save('annotation', {
          'title':
              '${type == 'underline' ? '밑줄' : '하이라이트'} · ${range.pageNumber}페이지',
          'body': range.text,
          'documentId': widget.document.id,
          'page': range.pageNumber,
          'type': type,
          'rectangles': rectangles,
          'start': range.start,
          'end': range.end,
          'versionHash': widget.document.text('hash'),
          'color': 0xffffd54f,
        });
      }
      await selection.clearTextSelection();
    });
  }

  void paintMarks(Canvas canvas, Rect pageRect, PdfPage pdfPage) {
    for (final mark
        in widget.workspace
            .ofKind('annotation')
            .where(
              (m) =>
                  m.text('documentId') == widget.document.id &&
                  m.number('page') == pdfPage.pageNumber,
            )) {
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
            paint..color = const Color(0xffb77900),
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
    searcher.dispose();
    if (pageTimer?.isActive == true) {
      widget.workspace.recordPage(widget.document, page).catchError((_) {});
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
        'documentId': widget.document.id,
        'page': page,
        'type': type,
      });
    });
  }

  Widget annotations() => ListenableBuilder(
    listenable: widget.workspace,
    builder: (_, _) {
      final marks = widget.workspace
          .ofKind('annotation')
          .where((o) => o.text('documentId') == widget.document.id)
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
  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final file = widget.workspace.fileFor(doc);
    final pdf = doc.text('extension') == '.pdf';
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (pdf) ...[
            TextButton(
              onPressed: () async {
                final value = await askText(
                  context,
                  '이동할 페이지',
                  initial: '$page',
                );
                final target = int.tryParse(value ?? '');
                if (target != null &&
                    controller.isReady &&
                    target > 0 &&
                    target <= controller.pageCount) {
                  controller.goToPage(pageNumber: target);
                }
              },
              child: Text('$page'),
            ),
            IconButton(
              tooltip: '책갈피 추가',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () => addMark('bookmark'),
            ),
            IconButton(
              tooltip: '페이지 메모',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: () => addMark('note'),
            ),
            IconButton(
              tooltip: '주석 목록',
              icon: const Icon(Icons.view_sidebar_outlined),
              onPressed: () {
                if (wide) {
                  setState(() => panel = !panel);
                } else {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SizedBox(
                      height: MediaQuery.sizeOf(context).height * .7,
                      child: annotations(),
                    ),
                  );
                }
              },
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'external') {
                final result = await OpenFilex.open(file.path);
                if (result.type != ResultType.done && mounted) {
                  setState(() => error = '이 형식을 열 수 있는 외부 앱을 설치하세요.');
                }
              } else if (value == 'search') {
                final text = await askText(context, 'PDF 본문 검색');
                if (text != null && text.isNotEmpty) {
                  searcher.startTextSearch(text);
                }
              } else if (value == 'nextMatch') {
                await searcher.goToNextMatch();
              } else if (controller.isReady) {
                controller.goTo(
                  controller.calcMatrixFitWidthForPage(pageNumber: page),
                );
              }
            },
            itemBuilder: (_) => [
              if (pdf)
                const PopupMenuItem(value: 'search', child: Text('PDF 본문 검색')),
              if (pdf)
                const PopupMenuItem(
                  value: 'nextMatch',
                  child: Text('다음 검색 결과'),
                ),
              if (pdf)
                const PopupMenuItem(value: 'fit', child: Text('너비에 맞추기')),
              const PopupMenuItem(value: 'external', child: Text('외부 앱으로 열기')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
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
                Expanded(
                  child: pdf
                      ? PdfViewer.file(
                          file.path,
                          controller: controller,
                          initialPageNumber: page,
                          params: PdfViewerParams(
                            pagePaintCallbacks: [
                              paintMarks,
                              searcher.pageTextMatchPaintCallback,
                            ],
                            customizeContextMenuItems: (params, items) {
                              final selection = params.textSelectionDelegate;
                              if (!selection.isCopyAllowed ||
                                  !selection.hasSelectedText) {
                                return;
                              }
                              items.addAll([
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
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            onPageChanged: (value) {
                              if (value == null) return;
                              setState(() => page = value);
                              pageTimer?.cancel();
                              pageTimer = Timer(
                                const Duration(milliseconds: 400),
                                () => safely(
                                  () => widget.workspace.recordPage(doc, value),
                                ),
                              );
                            },
                          ),
                        )
                      : _FilePreview(
                          file: file,
                          extension: doc.text('extension'),
                        ),
                ),
                if (pdf && wide && panel) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 290, child: annotations()),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: pdf
          ? SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '이전 페이지',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      if (controller.isReady && page > 1) {
                        controller.goToPage(pageNumber: page - 1);
                      }
                    },
                  ),
                  Text('$page 페이지'),
                  IconButton(
                    tooltip: '다음 페이지',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      if (controller.isReady && page < controller.pageCount) {
                        controller.goToPage(pageNumber: page + 1);
                      }
                    },
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.file, required this.extension});
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
