import 'dart:convert';
import 'dart:typed_data';

Uint8List samplePdf() {
  const stream =
      'BT /F1 24 Tf 72 720 Td (Fenru learning workspace) Tj '
      '/F1 16 Tf 0 -48 Td (Course notes: Cells and energy) Tj '
      '/F1 13 Tf 0 -38 Td (Key question: How do plants store energy?) Tj '
      '0 -30 Td (Sunlight is converted into chemical energy.) Tj '
      '0 -26 Td (Chlorophyll absorbs light in chloroplasts.) Tj '
      '/F1 16 Tf 0 -50 Td (Active reading) Tj '
      '/F1 13 Tf 0 -34 Td (Read the source. Highlight evidence. Ask a question.) Tj '
      '0 -26 Td (Compare documents and inspect each page citation.) Tj '
      '0 -50 Td (Original synthetic document for integration tests.) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  var pdf = '%PDF-1.4\n';
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = pdf.length;
  pdf += 'xref\n0 6\n0000000000 65535 f \n';
  for (final offset in offsets) {
    pdf += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  pdf += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return Uint8List.fromList(ascii.encode(pdf));
}
