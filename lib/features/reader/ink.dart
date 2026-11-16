import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

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
  if (points.isEmpty || data['tool'] == 'eraser') return;
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
    this.penOnly = false,
    this.stylusButtonEraser = true,
    this.onErasePreview,
    this.onPreviewEnd,
    this.onTemporaryEraser,
  });
  final void Function(Map<String, dynamic>)? onErasePreview;
  final VoidCallback? onPreviewEnd;
  final ValueChanged<bool>? onTemporaryEraser;
  final bool penOnly;
  final bool stylusButtonEraser;
  final String tool;
  final int color;
  final double width;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  List<List<double>> points = [];
  final segments = <Map<String, dynamic>>[];
  int? pointer;
  Offset? lastPosition;
  bool erasing = false;
  bool saving = false;
  bool eraseFor(PointerEvent event) =>
      widget.tool == 'eraser' ||
      event.kind == PointerDeviceKind.invertedStylus ||
      (widget.stylusButtonEraser &&
          event.kind == PointerDeviceKind.stylus &&
          (event.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) !=
              0);

  void updateEraser(bool value) {
    erasing = value;
    widget.onTemporaryEraser?.call(value && widget.tool != 'eraser');
  }

  Map<String, dynamic> get stroke => {
    'points': points,
    'tool': erasing ? 'eraser' : widget.tool,
    'color': widget.color,
    'width': widget.tool == 'marker' ? widget.width * 5 : widget.width,
  };
  void add(Offset local, Size size) {
    if (saving || size.isEmpty || points.length >= 6000) return;
    final p = [
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    ];
    setState(() => points.add(p));
    if (erasing) {
      widget.onErasePreview?.call({
        'tool': 'eraser',
        'points': points.length > 1
            ? [points[points.length - 2], points.last]
            : [points.last],
      });
    }
  }

  Future<void> finish() async {
    if ((points.isEmpty && segments.isEmpty) || saving) return;
    setState(() => saving = true);
    try {
      for (final segment in [...segments, if (points.isNotEmpty) stroke]) {
        await widget.onSave(segment);
      }
    } finally {
      widget.onPreviewEnd?.call();
      if (mounted) {
        setState(() {
          points = [];
          segments.clear();
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => MouseRegion(
      cursor: widget.tool == 'read'
          ? MouseCursor.defer
          : SystemMouseCursors.precise,
      opaque: widget.tool != 'read',
      hitTestBehavior: HitTestBehavior.deferToChild,
      child: RawGestureDetector(
        gestures: widget.tool == 'read'
            ? {}
            : {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(
                      () => EagerGestureRecognizer(
                        supportedDevices: widget.penOnly
                            ? {
                                PointerDeviceKind.stylus,
                                PointerDeviceKind.invertedStylus,
                                PointerDeviceKind.mouse,
                              }
                            : null,
                      ),
                      (recognizer) =>
                          recognizer.supportedDevices = widget.penOnly
                          ? {
                              PointerDeviceKind.stylus,
                              PointerDeviceKind.invertedStylus,
                              PointerDeviceKind.mouse,
                            }
                          : null,
                    ),
              },
        child: Listener(
          behavior: widget.tool == 'read'
              ? HitTestBehavior.translucent
              : HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (saving ||
                pointer != null ||
                (widget.penOnly && event.kind == PointerDeviceKind.touch) ||
                (widget.tool == 'read' &&
                    event.kind != PointerDeviceKind.stylus &&
                    event.kind != PointerDeviceKind.invertedStylus)) {
              return;
            }
            pointer = event.pointer;
            lastPosition = event.localPosition;
            updateEraser(eraseFor(event));
            points = [];
            if (widget.tool != 'read' || erasing) {
              add(event.localPosition, box.biggest);
            }
          },
          onPointerMove: (event) {
            if (event.pointer != pointer) return;
            final position = event.localPosition;
            final moved = position != lastPosition;
            lastPosition = position;
            final nextErase = eraseFor(event);
            if (nextErase != erasing) {
              if (points.isNotEmpty) segments.add(stroke);
              points = [];
              updateEraser(nextErase);
            }
            // Android can report a button change without any pen movement.
            if (!moved || (widget.tool == 'read' && !erasing)) return;
            add(position, box.biggest);
          },
          onPointerUp: (event) {
            if (event.pointer != pointer) return;
            pointer = null;
            lastPosition = null;
            widget.onTemporaryEraser?.call(false);
            finish();
          },
          onPointerCancel: (event) {
            if (event.pointer == pointer) {
              pointer = null;
              lastPosition = null;
              widget.onTemporaryEraser?.call(false);
              widget.onPreviewEnd?.call();
              setState(() {
                points = [];
                segments.clear();
              });
            }
          },
          child: CustomPaint(
            painter: _LiveInk([...segments, stroke]),
            size: Size.infinite,
          ),
        ),
      ),
    ),
  );
}

class _LiveInk extends CustomPainter {
  _LiveInk(this.strokes);
  final List<Map<String, dynamic>> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    for (final segment in strokes.take(strokes.length - 1)) {
      paintInk(canvas, Offset.zero & size, segment);
    }
    final stroke = strokes.last;
    if (stroke['tool'] == 'eraser') {
      final points = stroke['points'] as List;
      if (points.isNotEmpty) {
        final p = points.last as List;
        canvas.drawCircle(
          Offset(
            (p[0] as num).toDouble() * size.width,
            (p[1] as num).toDouble() * size.height,
          ),
          12,
          Paint()
            ..color = const Color(0xff788579)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    } else {
      paintInk(canvas, Offset.zero & size, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveInk oldDelegate) => true;

  @override
  bool hitTest(Offset position) => false;
}

/// Tests line segments in screen coordinates, so fast sweeps cannot skip ink.
bool inkIntersects(
  Map<String, dynamic> ink,
  Map<String, dynamic> eraser,
  Size size,
) {
  List<Offset> decode(Map<String, dynamic> data) =>
      (data['points'] as List? ?? [])
          .whereType<List>()
          .where((p) => p.length == 2 && p.every((v) => v is num && v.isFinite))
          .map(
            (p) => Offset(
              (p[0] as num).toDouble() * size.width,
              (p[1] as num).toDouble() * size.height,
            ),
          )
          .toList();
  var inkPoints = decode(ink);
  final sweep = decode(eraser);
  if (inkPoints.isEmpty || sweep.isEmpty) return false;
  if (ink['tool'] == 'line' && inkPoints.length > 1) {
    inkPoints = [inkPoints.first, inkPoints.last];
  }
  final radius =
      12 + ((ink['width'] as num?)?.toDouble() ?? 2) * size.width / 1200;
  double distance(Offset p, Offset a, Offset b) {
    final d = b - a;
    final t = d.distanceSquared == 0
        ? 0.0
        : (((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared).clamp(
            0.0,
            1.0,
          );
    return (p - (a + d * t)).distance;
  }

  double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
  for (var i = 0; i < inkPoints.length; i++) {
    final a = inkPoints[i], b = inkPoints[i == 0 ? 0 : i - 1];
    for (var j = 0; j < sweep.length; j++) {
      final c = sweep[j], d = sweep[j == 0 ? 0 : j - 1];
      if (distance(a, c, d) <= radius ||
          distance(b, c, d) <= radius ||
          distance(c, a, b) <= radius ||
          distance(d, a, b) <= radius) {
        return true;
      }
      final ab = b - a, cd = d - c;
      final denominator = cross(ab, cd);
      if (denominator != 0) {
        final t = cross(c - a, cd) / denominator,
            u = cross(c - a, ab) / denominator;
        if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return true;
      }
    }
  }
  return false;
}
