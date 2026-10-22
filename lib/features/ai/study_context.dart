import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';

class DocumentContext {
  const DocumentContext({
    required this.documentId,
    required this.title,
    required this.page,
    required this.text,
    required this.versionHash,
  });
  final String documentId, title, text, versionHash;
  final int page;
  String get link => 'fenru://document/$documentId?page=$page';
  Json get source => {
    'documentId': documentId,
    'title': title,
    'page': page,
    'versionHash': versionHash,
  };
}

class StudyContext {
  const StudyContext(this.excerpts, {this.notices = const []});
  final List<DocumentContext> excerpts;
  final List<String> notices;
  List<Json> get sources {
    final unique = <String, Json>{};
    for (final excerpt in excerpts) {
      unique['${excerpt.documentId}:${excerpt.page}'] = excerpt.source;
    }
    return unique.values.toList();
  }

  String get referenceText => excerpts
      .map(
        (e) =>
            'Title: ${e.title}\nPage: ${e.page}\nAllowed citation: ${e.link}\n<source>\n${e.text}\n</source>',
      )
      .join('\n\n');
}

/// Local, version-keyed PDF text cache. Only selected excerpts leave the device.
class StudyContextService {
  StudyContextService(this.workspace, {this.pageLoader, this.isCancelled});
  final bool Function()? isCancelled;
  void checkCancellation() {
    if (isCancelled?.call() == true) {
      throw const UserFacingException('자료 검색을 취소했습니다.');
    }
  }

  final Workspace workspace;
  final Future<List<String>> Function(WorkspaceObject)? pageLoader;
  static List<WorkspaceObject> courseDocuments(
    Workspace workspace,
    WorkspaceObject course,
  ) {
    final docs = workspace.ofKind('document').where((doc) {
      final origin = doc.data['origin'];
      if (origin is Map &&
          origin['source'] is String &&
          course.text('source').isNotEmpty) {
        return origin['source'] == course.text('source');
      }
      return doc.text('folder') == course.title;
    }).toList();
    final previous = docs
        .map((d) => d.text('previousVersion'))
        .where((id) => id.isNotEmpty)
        .toSet();
    return docs
        .where(
          (d) =>
              !previous.contains(d.id) &&
              !(workspace.byId(d.text('pdfDocumentId'))?.deleted == false),
        )
        .toList();
  }

  Future<List<String>> pages(WorkspaceObject document) async {
    checkCancellation();
    if (pageLoader != null) return pageLoader!(document);
    final file = workspace.fileFor(document);
    final extension = document.text('extension');
    if (['.txt', '.md', '.markdown', '.csv'].contains(extension)) {
      if (await file.length() > 10 * 1024 * 1024) {
        throw const UserFacingException('텍스트 자료가 너무 큽니다 (10MB 한도).');
      }
      return [await file.readAsString()];
    }
    if (extension != '.pdf') {
      throw const UserFacingException('현재 PDF와 텍스트 자료만 질문 근거로 읽을 수 있습니다.');
    }
    final hash = document.text('hash');
    final cache = RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)
        ? File('${workspace.root.path}/text-index/$hash.json')
        : null;
    if (cache != null &&
        await cache.exists() &&
        await cache.length() < 24 * 1024 * 1024) {
      try {
        final data = jsonDecode(await cache.readAsString()) as Map;
        if (data['version'] == 1 &&
            data['hash'] == hash &&
            data['pages'] is List) {
          return (data['pages'] as List).cast<String>();
        }
      } catch (_) {
        /* A derived cache can be regenerated from the original. */
      }
    }
    await pdfrxFlutterInitialize();
    final pdf = await PdfDocument.openFile(file.path);
    final result = <String>[];
    try {
      if (pdf.permissions?.allowsCopying == false) {
        throw const UserFacingException('텍스트 복사가 제한된 PDF입니다.');
      }
      if (pdf.pages.length > 2000) {
        throw const UserFacingException('2,000페이지를 넘는 PDF는 분할해서 질문해 주세요.');
      }
      var size = 0;
      for (final page in pdf.pages) {
        checkCancellation();
        final text = (await page.loadText())?.fullText ?? '';
        size += text.length;
        if (size > 10000000) {
          throw const UserFacingException('PDF 텍스트가 너무 큽니다. 자료를 분할해 주세요.');
        }
        result.add(text);
      }
    } finally {
      await pdf.dispose();
    }
    if (cache != null) {
      try {
        await cache.parent.create(recursive: true);
        final temporary = File(
          '${cache.path}.${DateTime.now().microsecondsSinceEpoch}.part',
        );
        try {
          await temporary.writeAsString(
            jsonEncode({'version': 1, 'hash': hash, 'pages': result}),
            flush: true,
          );
          if (!await cache.exists()) await temporary.rename(cache.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      } catch (_) {
        /* Cache failure does not prevent reading the document. */
      }
    }
    return result;
  }

  Future<StudyContext> retrieve(
    List<WorkspaceObject> documents,
    String question,
  ) async {
    final candidates = <DocumentContext>[];
    final notices = <String>[];
    final seen = <String>{};
    for (final entry in documents.where((d) => !d.deleted)) {
      final original = workspace.byId(entry.id) ?? entry;
      final converted = workspace.byId(original.text('pdfDocumentId'));
      final doc = converted != null && !converted.deleted
          ? converted
          : original;
      if (!seen.add(doc.id)) continue;
      checkCancellation();
      try {
        final text = await pages(doc);
        checkCancellation();
        var found = false;
        for (var page = 0; page < text.length; page++) {
          final body = text[page].trim();
          if (body.isEmpty) continue;
          found = true;
          for (var offset = 0; offset < body.length; offset += 1600) {
            candidates.add(
              DocumentContext(
                documentId: doc.id,
                title: doc.title,
                page: page + 1,
                text: body.substring(
                  offset,
                  math.min(offset + 1800, body.length),
                ),
                versionHash: doc.text('hash'),
              ),
            );
          }
        }
        if (!found) {
          notices.add('${doc.title}: 추출 가능한 텍스트가 없습니다. OCR이 필요할 수 있습니다.');
        }
      } catch (e) {
        checkCancellation();
        notices.add(
          '${doc.title}: ${e is UserFacingException ? e.message : '텍스트를 읽지 못했습니다.'}',
        );
      }
    }
    final excerpts = rank(candidates, question);
    return StudyContext(excerpts, notices: notices);
  }

  static List<DocumentContext> rank(
    List<DocumentContext> candidates,
    String question,
  ) {
    final words = RegExp(r'[a-zA-Z0-9가-힣]{2,}')
        .allMatches(question.toLowerCase())
        .map((m) => m.group(0)!)
        .where(
          (s) => ![
            '내용을',
            '내용으로',
            '쉽게',
            '자료',
            '과목',
            '만들어',
            '퀴즈를',
            '설명해줘',
            '해주세요',
            'summary',
            'summarize',
            'explain',
            'please',
            'what',
            'where',
            'why',
            'how',
            'the',
            'and',
            'this',
            'that',
            'are',
            'does',
            'can',
            'could',
            'would',
            '설명해',
            '정리해',
            '내용',
            '이해',
            '알려',
            '핵심',
            '전체',
            '요약해',
            '주세요',
          ].contains(s),
        )
        .toSet();
    final tokens = {...words};
    for (final word in words.where(
      (w) => RegExp(r'[가-힣]').hasMatch(w) && w.length > 2,
    )) {
      for (var i = 0; i < word.length - 1; i++) {
        tokens.add(word.substring(i, i + 2));
      }
    }
    int score(DocumentContext excerpt) {
      final text = excerpt.text.toLowerCase(),
          title = excerpt.title.toLowerCase();
      return tokens.fold(
        0,
        (total, token) =>
            total +
            (text.contains(token) ? 1 : 0) +
            (title.contains(token) ? 2 : 0),
      );
    }

    final ranked = candidates.indexed.toList()
      ..sort((a, b) {
        final diff = score(b.$2) - score(a.$2);
        return diff != 0 ? diff : a.$1.compareTo(b.$1);
      });
    if (ranked.isEmpty) return [];
    if (score(ranked.first.$2) > 0) {
      return ranked
          .where((e) => score(e.$2) > 0)
          .take(6)
          .map((e) => e.$2)
          .toList();
    }
    // With no keyword match, sample across documents/pages rather than silently
    // claiming a whole-course summary from the beginning of the first PDF.
    final grouped = <String, List<DocumentContext>>{};
    for (final item in candidates) {
      grouped.putIfAbsent(item.documentId, () => []).add(item);
    }
    final result = <DocumentContext>[];
    for (var turn = 0; turn < 6 && result.length < 6; turn++) {
      for (final group in grouped.values) {
        if (result.length == 6) break;
        final index = (turn * group.length / 6).floor();
        final chosen = group[index];
        if (!result.contains(chosen)) result.add(chosen);
      }
    }
    return result;
  }
}
