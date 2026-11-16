import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';
import '../../core/workspace.dart';

File? _pageCache(Workspace workspace, WorkspaceObject document, int page) {
  final hash = document.text('hash');
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) || page < 1) return null;
  return File(p.join(workspace.root.path, 'ocr-v1', hash, '$page.txt'));
}

Future<String?> readRecognizedPage(
  Workspace workspace,
  WorkspaceObject document,
  int page,
) async {
  final file = _pageCache(workspace, document, page);
  if (file == null) return null;
  try {
    if (await file.exists()) return await file.readAsString();
  } on FileSystemException {
    return null;
  }
  return null;
}

Future<String> recognizePdfPage(
  Workspace workspace,
  WorkspaceObject document,
  PdfPage page, {
  required String language,
}) async {
  final cache = _pageCache(workspace, document, page.pageNumber);
  if (cache == null) throw const UserFacingException('문서 체크섬을 확인할 수 없습니다.');
  if (page.document.permissions?.allowsCopying == false) {
    throw const UserFacingException('텍스트 복사가 제한된 PDF입니다.');
  }
  final temporary = await Directory.systemTemp.createTemp('fenru-ocr-');
  try {
    final loaded = await page.ensureLoaded();
    final scale = math.min(3.5, 3200 / math.max(loaded.width, loaded.height));
    final width = math.max(1, (loaded.width * scale).round());
    final height = math.max(1, (loaded.height * scale).round());
    final rendered = await loaded.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xffffffff,
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
    );
    if (rendered == null) {
      throw const UserFacingException('페이지 이미지를 만들 수 없습니다.');
    }
    final source = File(p.join(temporary.path, 'page.png'));
    try {
      final image = await rendered.createImage();
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw const UserFacingException('페이지 이미지를 만들 수 없습니다.');
        await source.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } finally {
      rendered.dispose();
    }
    final text =
        (Platform.isAndroid
                ? await _recognizeOnAndroid(workspace, source, language)
                : await _recognizeOnWindows(source, language))
            .trim();
    await cache.parent.create(recursive: true);
    final staging = File(
      '${cache.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await staging.writeAsString(text, flush: true);
      await staging.rename(cache.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    return text;
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<String> _recognizeOnWindows(File input, String language) async {
  final programFiles = Platform.environment['ProgramFiles'];
  final installed = programFiles == null
      ? null
      : File(p.join(programFiles, 'Tesseract-OCR', 'tesseract.exe'));
  final binary = installed != null && await installed.exists()
      ? installed.path
      : 'tesseract';
  final output = p.join(input.parent.path, 'result');
  final Process process;
  try {
    process = await Process.start(binary, [input.path, output, '-l', language]);
  } on ProcessException {
    throw const UserFacingException('Tesseract를 설치하고 PATH에 추가한 뒤 다시 시도하세요.');
  }
  final drained = Future.wait([
    process.stdout.drain<void>(),
    process.stderr.drain<void>(),
  ]);
  final int result;
  try {
    result = await process.exitCode.timeout(const Duration(minutes: 2));
  } on TimeoutException {
    process.kill();
    await process.exitCode;
    throw const UserFacingException('글자 인식 시간이 초과됐습니다.');
  } finally {
    await drained;
  }
  if (result != 0) {
    throw const UserFacingException(
      '글자를 인식하지 못했습니다. Tesseract 언어 데이터 설치를 확인하세요.',
    );
  }
  return File('$output.txt').readAsString();
}

Future<String> _recognizeOnAndroid(
  Workspace workspace,
  File input,
  String language,
) async {
  const models = {
    'eng': '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2',
    'kor': '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2',
  };
  final root = p.join(workspace.root.path, 'tesseract');
  final data = await Directory(p.join(root, 'tessdata'))
      .create(recursive: true);
  final http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 35),
    ),
  );
  try {
    for (final code in language.split('+')) {
      final expected = models[code];
      if (expected == null) throw ArgumentError.value(language);
      final model = File(p.join(data.path, '$code.traineddata'));
      if (await model.exists() &&
          (await sha256.bind(model.openRead()).first).toString() == expected) {
        continue;
      }
      final staged = File(p.join(input.parent.path, '$code.traineddata'));
      await http.download(
        'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/'
        '65727574dfcd264acbb0c3e07860e4e9e9b22185/$code.traineddata',
        staged.path,
      );
      if ((await sha256.bind(staged.openRead()).first).toString() != expected) {
        throw const UserFacingException('글자 인식 언어 모델을 확인하지 못했습니다.');
      }
      await staged.rename(model.path);
    }
  } on DioException {
    throw const UserFacingException('글자 인식 언어 모델을 내려받지 못했습니다. 연결을 확인하세요.');
  } finally {
    http.close();
  }
  try {
    return await const MethodChannel('fenru/ocr').invokeMethod<String>(
          'recognize',
          {'image': input.path, 'models': root, 'language': language},
        ) ??
        '';
  } on PlatformException catch (error) {
    throw UserFacingException(error.message ?? '글자를 인식하지 못했습니다.');
  }
}
