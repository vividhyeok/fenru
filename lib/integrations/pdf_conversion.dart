import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/workspace.dart';

typedef PdfConvertRunner = Future<void> Function(File source, File output);

class PdfConversion {
  PdfConversion(this.workspace, {this.runner});
  final Workspace workspace;
  final PdfConvertRunner? runner;
  static const extensions = [
    '.doc',
    '.docx',
    '.ppt',
    '.pptx',
    '.hwp',
    '.hwpx',
    '.rtf',
    '.odt',
    '.odp',
  ];
  static bool supports(WorkspaceObject doc) =>
      extensions.contains(doc.text('extension'));

  Future<WorkspaceObject> convert(WorkspaceObject original) async {
    final existing = workspace.byId(original.text('pdfDocumentId'));
    if (existing != null && !existing.deleted) return existing;
    if (!supports(original)) return original;
    final temporary = await Directory.systemTemp.createTemp('fenru-pdf-');
    try {
      final source = await workspace
          .fileFor(original)
          .copy(p.join(temporary.path, 'source${original.text('extension')}'));
      final output = File(p.join(temporary.path, 'source.pdf'));
      await (runner ?? convertOnDevice)(source, output);
      if (!await output.exists() || await output.length() < 5) {
        throw const UserFacingException('변환한 PDF가 없습니다.');
      }
      final signature = await output
          .openRead(0, 5)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      if (String.fromCharCodes(signature) != '%PDF-') {
        throw const UserFacingException('변환 결과가 유효한 PDF가 아닙니다.');
      }
      final pdf = await workspace.importFile(
        output.path,
        displayName: '${p.basenameWithoutExtension(original.title)}.pdf',
        folder: original.text('folder'),
        origin: original.data['origin'] is Map
            ? Map<String, dynamic>.from(original.data['origin'] as Map)
            : null,
      );
      final linked = await workspace.save('document', {
        ...pdf.data,
        'derivedFrom': original.id,
        'tags': original.text('tags'),
      }, id: pdf.id);
      await workspace.save('document', {
        ...original.data,
        'pdfDocumentId': pdf.id,
        'conversionStatus': 'complete',
        'conversionError': '',
      }, id: original.id);
      return linked;
    } catch (e) {
      final message = e is UserFacingException
          ? e.message
          : 'PDF 변환에 실패했습니다. 변환 프로그램 설치·문서 권한을 확인하고 다시 시도하세요.';
      await workspace.save('document', {
        ...original.data,
        'conversionStatus': 'failed',
        'conversionError': message,
      }, id: original.id);
      throw UserFacingException(message);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  static Future<void> convertOnDevice(File source, File output) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw const UserFacingException(
        '이 기기에는 문서 변환 엔진이 없습니다. Windows에서 변환한 PDF를 백업으로 옮기거나 원본 앱에서 PDF로 저장해 가져오세요.',
      );
    }
    final candidates = [
      if (Platform.isWindows) ...[
        r'C:\Program Files\LibreOffice\program\soffice.exe',
        r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
      ] else ...[
        '/usr/bin/libreoffice',
        '/Applications/LibreOffice.app/Contents/MacOS/soffice',
      ],
    ];
    for (final binary in candidates) {
      if (!await File(binary).exists()) continue;
      final profile = Directory(p.join(output.parent.path, 'lo-profile')).uri
          .toString();
      await run(binary, [
        '-env:UserInstallation=$profile',
        '--headless',
        '--convert-to',
        'pdf',
        '--outdir',
        output.parent.path,
        source.path,
      ]);
      if (await output.exists()) return;
    }
    if (!Platform.isWindows) {
      throw const UserFacingException(
        'PDF 자동 변환에는 LibreOffice가 필요합니다. 원본은 보관되어 있습니다.',
      );
    }
    final script = File(p.join(output.parent.path, 'office-to-pdf.ps1'));
    await script.writeAsString(
      await rootBundle.loadString('assets/conversion/office-to-pdf.ps1'),
    );
    await run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      '-Source',
      source.path,
      '-Destination',
      output.path,
    ], processMarker: File('${output.path}.process'));
    if (!await output.exists()) {
      throw const UserFacingException(
        'PDF 변환에 실패했습니다. Word·PowerPoint·한글 또는 LibreOffice 설치를 확인하세요. 열려 있는 Office 문서는 닫은 뒤 재시도하세요. 한글은 파일 접근 허용이 필요할 수 있습니다.',
      );
    }
  }

  static Future<void> run(
    String binary,
    List<String> arguments, {
    File? processMarker,
  }) async {
    final process = await Process.start(binary, arguments, runInShell: false);
    // Drain output without exposing document content or localized COM errors.
    final out = process.stdout.drain<void>();
    final err = process.stderr.drain<void>();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 90));
      await Future.wait([out, err]);
      if (code != 0) {
        throw const UserFacingException(
          'PDF 변환 프로그램이 문서를 처리하지 못했습니다. 프로그램 설치·실행 중인 Office·문서 권한을 확인하세요.',
        );
      }
    } on TimeoutException {
      process.kill();
      if (Platform.isWindows &&
          processMarker != null &&
          await processMarker.exists()) {
        final pid = int.tryParse((await processMarker.readAsString()).trim());
        if (pid != null && pid > 0) {
          await Process.run('taskkill.exe', [
            '/PID',
            '$pid',
            '/T',
            '/F',
          ], runInShell: false);
        }
      }
      throw const UserFacingException(
        'PDF 변환 시간이 초과되었습니다. 변환 프로그램의 파일 접근 확인 창이나 문서 암호를 확인하세요. 원본은 보관되어 있습니다.',
      );
    }
  }
}

/// Import the original first; failed conversions never lose a lecture file.
Future<WorkspaceObject> importStudyFile(
  Workspace workspace,
  String path, {
  String? folder,
  String? displayName,
  Json? origin,
}) async {
  final original = await workspace.importFile(
    path,
    folder: folder,
    displayName: displayName,
    origin: origin,
  );
  if (!PdfConversion.supports(original)) return original;
  try {
    return await PdfConversion(workspace).convert(original);
  } on UserFacingException {
    return workspace.byId(original.id) ?? original;
  }
}
