import 'package:flutter/material.dart';

import 'reading_tools.dart';

/// One fixed-height writing row; page controls stay separate from pen choices.
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({
    super.key,
    required this.tool,
    required this.onTool,
    required this.onPenSettings,
    required this.onUndo,
    required this.onRedo,
    required this.onPages,
    required this.pageLabel,
    this.onReturn,
    this.temporaryEraser = false,
    this.lastWritingTool = 'pen',
    this.presets = const [],
    this.onPreset,
    this.onSavePreset,
    this.color,
    this.colors = const {},
    this.onColor,
    this.width,
    this.onWidth,
  });
  final String tool, pageLabel, lastWritingTool;
  final ValueChanged<String> onTool;
  final VoidCallback onPenSettings, onPages;
  final VoidCallback? onUndo, onRedo, onReturn;
  final bool temporaryEraser;
  final List<PenPreset> presets;
  final ValueChanged<PenPreset>? onPreset;
  final ValueChanged<int>? onSavePreset;
  final int? color;
  final Map<int, String> colors;
  final ValueChanged<int>? onColor;
  final double? width;
  final ValueChanged<double>? onWidth;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SizedBox(
      key: const ValueKey('writing-toolbar'),
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: tool == 'read' ? '필기로 돌아가기' : '읽기 · 선택 · 이동',
            isSelected: tool == 'read' && !temporaryEraser,
            onPressed: () => onTool(tool == 'read' ? lastWritingTool : 'read'),
            icon: Icon(
              tool == 'read' ? Icons.pan_tool_outlined : Icons.edit_outlined,
            ),
          ),
          const VerticalDivider(width: 1, indent: 10, endIndent: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in <(String, String, IconData)>[
                    ('pen', '펜 필기', Icons.draw_outlined),
                    ('marker', '형광펜', Icons.highlight),
                    ('eraser', '지우개', Icons.auto_fix_normal),
                  ])
                    IconButton(
                      tooltip: item.$2,
                      isSelected: temporaryEraser
                          ? item.$1 == 'eraser'
                          : tool == item.$1,
                      onPressed: () {
                        if (tool == 'eraser' && item.$1 == 'eraser') {
                          onTool(lastWritingTool);
                        } else if (tool == item.$1) {
                          onPenSettings();
                        } else {
                          onTool(item.$1);
                        }
                      },
                      icon: Icon(item.$3),
                    ),
                  IconButton(
                    tooltip: '직선 밑줄',
                    isSelected: tool == 'line' && !temporaryEraser,
                    onPressed: () =>
                        tool == 'line' ? onPenSettings() : onTool('line'),
                    icon: const Icon(Icons.horizontal_rule),
                  ),
                  if (color != null && onColor != null)
                    PopupMenuButton<int>(
                      tooltip: '색상 빠르게 선택',
                      icon: Icon(Icons.circle, size: 20, color: Color(color!)),
                      onSelected: onColor,
                      itemBuilder: (_) => [
                        for (final entry in colors.entries)
                          CheckedPopupMenuItem(
                            value: entry.key,
                            checked: color == entry.key,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 18,
                                  color: Color(entry.key),
                                ),
                                const SizedBox(width: 10),
                                Text(entry.value),
                              ],
                            ),
                          ),
                      ],
                    ),
                  if (width != null && onWidth != null)
                    PopupMenuButton<double>(
                      tooltip: '굵기 빠르게 선택',
                      onSelected: onWidth,
                      itemBuilder: (_) => [
                        for (final option in [1.0, 2.0, 4.0, 8.0])
                          CheckedPopupMenuItem(
                            checked: width == option,
                            value: option,
                            child: Text(
                              '${option.toStringAsFixed(0)} · ${switch (option) {
                                1.0 => '얇게',
                                2.0 => '보통',
                                4.0 => '굵게',
                                _ => '아주 굵게',
                              }}',
                            ),
                          ),
                      ],
                      child: SizedBox(
                        width: 44,
                        height: 48,
                        child: Center(child: Text(width!.toStringAsFixed(1))),
                      ),
                    ),
                  IconButton(
                    tooltip: '주석 실행 취소',
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: '주석 다시 실행',
                    onPressed: onRedo,
                    icon: const Icon(Icons.redo),
                  ),
                  IconButton(
                    tooltip: '펜 색상 · 굵기 · 즐겨찾기',
                    onPressed: onPenSettings,
                    icon: const Icon(Icons.tune),
                  ),
                  for (var i = 0; i < presets.length; i++)
                    InkWell(
                      onTap: onPreset == null
                          ? null
                          : () => onPreset!(presets[i]),
                      onLongPress: onSavePreset == null
                          ? null
                          : () => onSavePreset!(i),
                      child: Tooltip(
                        message: '${presets[i].name} · 길게 눌러 저장',
                        child: SizedBox(
                          width: 40,
                          height: 48,
                          child: Icon(
                            presets[i].tool == 'marker'
                                ? Icons.highlight
                                : presets[i].tool == 'line'
                                ? Icons.horizontal_rule
                                : Icons.draw_outlined,
                            color: Color(presets[i].color),
                          ),
                        ),
                      ),
                    ),
                  if (onReturn != null)
                    IconButton(
                      tooltip: '이전 읽던 위치로 돌아가기',
                      onPressed: onReturn,
                      icon: const Icon(Icons.keyboard_return),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, indent: 10, endIndent: 10),
          TextButton(
            key: const ValueKey('reader-page-options'),
            onPressed: onPages,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pageLabel),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
