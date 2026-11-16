import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pdfium_dart/pdfium_dart.dart' as native;
import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';

typedef _Export = ({
  String source,
  String destination,
  String password,
  List<int>? selectedPages,
  int? rotatePage,
  List<WorkspaceObject> marks,
});

Future<void> exportAnnotatedPdf({
  required File source,
  required File destination,
  required List<WorkspaceObject> marks,
  String password = '',
  List<int>? selectedPages,
  int? rotatePage,
}) async {
  if (p.equals(p.absolute(source.path), p.absolute(destination.path))) {
    throw ArgumentError('Export destination must differ from the source');
  }
  await pdfrxFlutterInitialize();
  await PdfrxEntryFunctions.instance.compute(_export, (
    source: source.path,
    destination: destination.path,
    password: password,
    selectedPages: selectedPages,
    rotatePage: rotatePage,
    marks: marks,
  ));
}

void _require(int result) {
  if (result == 0) throw const FormatException('PDFium could not save the PDF');
}

void _export(_Export job) => using((arena) {
  final pdf = native.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
  final original = pdf.FPDF_LoadDocument(
    job.source.toNativeUtf8(allocator: arena).cast<Char>(),
    job.password.isEmpty
        ? nullptr
        : job.password.toNativeUtf8(allocator: arena).cast<Char>(),
  );
  if (original == nullptr) {
    throw const UserFacingException('원본 PDF를 열 수 없습니다.');
  }
  var output = original;
  try {
    final count = pdf.FPDF_GetPageCount(original);
    final selected = job.selectedPages;
    if (selected != null &&
        (selected.isEmpty ||
            selected.any((page) => page < 1 || page > count))) {
      throw const UserFacingException('내보낼 페이지가 없습니다.');
    }
    // Export and page assembly must not remove document restrictions.
    if (pdf.FPDF_GetSecurityHandlerRevision(original) >= 0) {
      throw const UserFacingException('암호 또는 보안이 설정된 PDF는 복사본으로 내보낼 수 없습니다.');
    }
    final pageMap = <int, int>{};
    if (selected != null) {
      output = pdf.FPDF_CreateNewDocument();
      if (output == nullptr) throw const FormatException('Cannot create PDF');
      final pageIndex = arena<Int>(selected.length);
      for (final (index, page) in selected.indexed) {
        pageIndex[index] = page - 1;
        pageMap[page] = index;
      }
      _require(
        pdf.FPDF_ImportPagesByIndex(
          output,
          original,
          pageIndex,
          selected.length,
          0,
        ),
      );
    }
    final perPage = <int, List<WorkspaceObject>>{};
    for (final mark in job.marks) {
      final page = mark.number('page');
      if (page < 1 ||
          page > count ||
          (selected != null && !pageMap.containsKey(page))) {
        continue;
      }
      perPage.putIfAbsent(page, () => []).add(mark);
    }
    final targets = {...perPage.keys, ?job.rotatePage};
    for (final page in targets) {
      if (page < 1 ||
          page > count ||
          (selected != null && !pageMap.containsKey(page))) {
        continue;
      }
      final handle = pdf.FPDF_LoadPage(
        output,
        selected == null ? page - 1 : pageMap[page]!,
      );
      if (handle == nullptr) {
        throw const FormatException('Cannot load PDF page');
      }
      try {
        final rotation = pdf.FPDFPage_GetRotation(handle);
        for (final mark in perPage[page] ?? const []) {
          _paintMark(pdf, handle, mark, rotation, arena);
        }
        if (perPage.containsKey(page)) {
          _require(pdf.FPDFPage_GenerateContent(handle));
        }
        if (job.rotatePage == page) {
          pdf.FPDFPage_SetRotation(handle, (rotation + 1) % 4);
        }
      } finally {
        pdf.FPDF_ClosePage(handle);
      }
    }

    final file = File(job.destination).openSync(mode: FileMode.write);
    final callback =
        NativeCallable<
          Int Function(
            Pointer<native.FPDF_FILEWRITE_>,
            Pointer<Void>,
            UnsignedLong,
          )
        >.isolateLocal((
          Pointer<native.FPDF_FILEWRITE_> _,
          Pointer<Void> data,
          int size,
        ) {
          try {
            file.writeFromSync(data.cast<Uint8>().asTypedList(size));
            return 1;
          } catch (_) {
            return 0;
          }
        }, exceptionalReturn: 0);
    try {
      final writer = arena<native.FPDF_FILEWRITE_>();
      writer.ref
        ..version = 1
        ..WriteBlock = callback.nativeFunction;
      _require(pdf.FPDF_SaveAsCopy(output, writer, native.FPDF_NO_INCREMENTAL));
    } finally {
      callback.close();
      file.closeSync();
    }
  } finally {
    if (output != original && output != nullptr) pdf.FPDF_CloseDocument(output);
    pdf.FPDF_CloseDocument(original);
  }
});

void _paintMark(
  native.PDFium pdf,
  native.FPDF_PAGE page,
  WorkspaceObject mark,
  int rotation,
  Arena arena,
) {
  final type = mark.text('type');
  final color = mark.number('color', type == 'ink' ? 0xff234b80 : 0xffffd54f);
  final red = (color >> 16) & 255,
      green = (color >> 8) & 255,
      blue = color & 255;
  void addPath(
    List<(double, double)> points, {
    required double width,
    required int alpha,
  }) {
    final first = points.first;
    final path = pdf.FPDFPageObj_CreateNewPath(first.$1, first.$2);
    if (path == nullptr) throw const FormatException('Cannot create PDF path');
    var attached = false;
    try {
      for (final point in points.skip(1)) {
        _require(pdf.FPDFPath_LineTo(path, point.$1, point.$2));
      }
      if (width > 0) {
        if (points.length == 1) {
          _require(pdf.FPDFPath_LineTo(path, first.$1 + .001, first.$2));
        }
        _require(pdf.FPDFPageObj_SetStrokeColor(path, red, green, blue, alpha));
        _require(pdf.FPDFPageObj_SetStrokeWidth(path, width));
        _require(pdf.FPDFPageObj_SetLineCap(path, native.FPDF_LINECAP_ROUND));
        _require(pdf.FPDFPageObj_SetLineJoin(path, native.FPDF_LINEJOIN_ROUND));
      } else {
        _require(pdf.FPDFPath_Close(path));
        _require(pdf.FPDFPageObj_SetFillColor(path, red, green, blue, alpha));
      }
      _require(
        pdf.FPDFPath_SetDrawMode(
          path,
          width > 0 ? native.FPDF_FILLMODE_NONE : native.FPDF_FILLMODE_WINDING,
          width > 0 ? 1 : 0,
        ),
      );
      _require(pdf.FPDFPage_InsertObject(page, path));
      attached = true;
    } finally {
      if (!attached) pdf.FPDFPageObj_Destroy(path);
    }
  }

  if (type == 'ink') {
    final tool = mark.text('tool');
    if (tool == 'eraser') return;
    final source = _coordinates(mark.data['points'], 2).toList();
    if (source.isEmpty) return;
    final x = arena<Double>(), y = arena<Double>();
    const grid = 100000;
    final points = <(double, double)>[];
    for (final point in tool == 'line' ? [source.first, source.last] : source) {
      _require(
        pdf.FPDF_DeviceToPage(
          page,
          0,
          0,
          grid,
          grid,
          0,
          (point[0].clamp(0, 1) * grid).round(),
          (point[1].clamp(0, 1) * grid).round(),
          x,
          y,
        ),
      );
      points.add((x.value, y.value));
    }
    final width = (mark.data['width'] as num? ?? 2).toDouble().clamp(.1, 100);
    addPath(
      points,
      width: width * pdf.FPDF_GetPageWidthF(page) / 600,
      alpha: tool == 'marker' ? 77 : (color >> 24) & 255,
    );
  } else if (type == 'highlight' || type == 'underline') {
    final box = arena<native.FS_RECTF>();
    _require(pdf.FPDF_GetPageBoundingBox(page, box));
    for (final rect in _coordinates(mark.data['rectangles'], 4)) {
      final left = rect[0] + box.ref.left, right = rect[2] + box.ref.left;
      final top = rect[1] + box.ref.bottom, bottom = rect[3] + box.ref.bottom;
      if (type == 'highlight') {
        addPath(
          [(left, bottom), (right, bottom), (right, top), (left, top)],
          width: 0,
          alpha: 97,
        );
      } else {
        final points = switch (rotation) {
          1 => [(right, bottom), (right, top)],
          2 => [(right, top), (left, top)],
          3 => [(left, top), (left, bottom)],
          _ => [(left, bottom), (right, bottom)],
        };
        addPath(points, width: 2, alpha: 255);
      }
    }
  }
}

Iterable<List<double>> _coordinates(Object? data, int size) sync* {
  if (data is! List) return;
  for (final item in data.whereType<List>()) {
    if (item.length == size && item.every((v) => v is num && v.isFinite)) {
      yield item.cast<num>().map((v) => v.toDouble()).toList();
    }
  }
}
