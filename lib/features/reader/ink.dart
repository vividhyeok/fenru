import 'package:flutter/material.dart';

/// Page-relative points keep handwriting aligned when the viewer zooms/resizes.
void paintInk(Canvas canvas, Rect rect, Map<String, dynamic> data) {
  final points = (data['points'] as List? ?? [])
      .whereType<List>()
      .where((p) => p.length == 2 && p.every((v) => v is num && v.isFinite))
      .map(
        (p) => Offset(
          rect.left + (p[0] as num).toDouble().clamp(0, 1) * rect.width,
          rect.top + (p[1] as num).toDouble().clamp(0, 1) * rect.height,
        ),
      )
      .toList();
  if (points.isEmpty) return;
  final marker = data['tool'] == 'marker';
  final paint = Paint()
    ..color = Color((data['color'] as num?)?.toInt() ?? 0xff234b80)
        .withValues(alpha: marker ? .3 : 1)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth =
        ((data['width'] as num?)?.toDouble() ?? 2) * rect.width / 600;
  if (points.length == 1) {
    canvas.drawCircle(
      points.first,
      paint.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  if (data['tool'] == 'line') {
    path.lineTo(points.last.dx, points.last.dy);
  } else {
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
  }
  canvas.drawPath(path, paint);
}

class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.tool,
    required this.color,
    required this.width,
    required this.onSave,
  });
  final String tool;
  final int color;
  final double width;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  List<List<double>> points = [];
  bool saving = false;
  Map<String, dynamic> get stroke => {
    'points': points,
    'tool': widget.tool,
    'color': widget.color,
    'width': widget.tool == 'marker' ? widget.width * 5 : widget.width,
  };
  void add(Offset local, Size size) {
    if (saving || size.isEmpty || points.length >= 6000) return;
    final p = [
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    ];
    setState(() => points = [...points, p]);
  }

  Future<void> finish() async {
    if (points.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await widget.onSave(stroke);
    } finally {
      if (mounted) {
        setState(() {
          points = [];
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          if (!saving) {
            points = [];
            add(details.localPosition, box.biggest);
          }
        },
        onPanUpdate: (details) => add(details.localPosition, box.biggest),
        onPanEnd: (_) => finish(),
        onPanCancel: () => setState(() => points = []),
        onTapDown: (details) {
          if (!saving) {
            points = [];
            add(details.localPosition, box.biggest);
          }
        },
        onTapUp: (_) => finish(),
        child: CustomPaint(painter: _LiveInk(stroke), size: Size.infinite),
      ),
    ),
  );
}

class _LiveInk extends CustomPainter {
  _LiveInk(this.stroke);
  final Map<String, dynamic> stroke;
  @override
  void paint(Canvas canvas, Size size) =>
      paintInk(canvas, Offset.zero & size, stroke);
  @override
  bool shouldRepaint(covariant _LiveInk oldDelegate) => true;
}
