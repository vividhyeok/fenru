import 'dart:convert';

import '../../core/workspace.dart';
import '../../core/models.dart';

class ReaderViewSettings {
  const ReaderViewSettings({
    this.fit = 'custom',
    this.zoom = 1,
    this.x,
    this.y,
    this.panelWidth = 420,
    this.showAI = true,
  });
  final String fit;
  final double zoom, panelWidth;
  final double? x, y;
  final bool showAI;
  static ReaderViewSettings read(Workspace w, String id) {
    try {
      final data = jsonDecode(w.preferences['reader.view.$id'] ?? '{}') as Map;
      double? number(String key) {
        final value = data[key];
        return value is num && value.isFinite ? value.toDouble() : null;
      }

      return ReaderViewSettings(
        fit: ['width', 'page', 'custom'].contains(data['fit'])
            ? data['fit'] as String
            : 'custom',
        zoom: (number('zoom') ?? 1).clamp(.05, 16),
        x: number('x'),
        y: number('y'),
        panelWidth: (number('panelWidth') ?? 420).clamp(320, 1200),
        showAI: data['showAI'] != false,
      );
    } catch (_) {
      return const ReaderViewSettings();
    }
  }

  Future<void> save(Workspace w, String id) async {
    final key = 'reader.view.$id';
    final value = jsonEncode({
      'fit': fit,
      'zoom': zoom,
      'x': x,
      'y': y,
      'panelWidth': panelWidth,
      'showAI': showAI,
    });
    if (w.preferences[key] != value) await w.setPreference(key, value);
  }
}

class PenPreset {
  const PenPreset(this.name, this.tool, this.color, this.width);
  final String name, tool;
  final int color;
  final double width;
  static const defaults = [
    PenPreset('검정 펜', 'pen', 0xff212121, 2),
    PenPreset('빨간 펜', 'pen', 0xffe53935, 2),
    PenPreset('노란 형광펜', 'marker', 0xffffd54f, 2),
  ];
  static List<PenPreset> read(Workspace w) => List.generate(3, (i) {
    try {
      final data = jsonDecode(w.preferences['reader.preset.$i'] ?? '') as Map;
      final color = data['color'], width = data['width'];
      if (!['pen', 'marker', 'line'].contains(data['tool']) ||
          color is! int ||
          color < 0 ||
          color > 0xffffffff ||
          width is! num ||
          !width.isFinite ||
          width < .5 ||
          width > 20) {
        return defaults[i];
      }
      return PenPreset(
        '즐겨찾기 ${i + 1}',
        data['tool'] as String,
        color,
        width.toDouble(),
      );
    } catch (_) {
      return defaults[i];
    }
  });
  Future<void> save(Workspace w, int slot) => w.setPreference(
    'reader.preset.$slot',
    jsonEncode({'tool': tool, 'color': color, 'width': width}),
  );
}

bool isNewSynced(Workspace w, WorkspaceObject document) =>
    document.text('syncedAt').isNotEmpty &&
    w.preferences['sync.seen.${document.id}'] != document.text('syncedAt');
Future<void> markSyncSeen(Workspace w, WorkspaceObject document) async {
  if (isNewSynced(w, document)) {
    await w.setPreference(
      'sync.seen.${document.id}',
      document.text('syncedAt'),
    );
  }
}
