import 'package:flutter/material.dart';

abstract final class FenruTheme {
  static const navy = Color(0xff28655c);
  static const gap = 16.0;
  static const desktop = 1050.0;
  static const tablet = 700.0;
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: navy, brightness: brightness)
        .copyWith(
          primary: dark ? const Color(0xff9bd3bf) : const Color(0xff28655c),
          surface: dark ? const Color(0xff191d1b) : const Color(0xfffaf9f5),
          surfaceContainerLow: dark
              ? const Color(0xff202622)
              : const Color(0xfff0f0e9),
          surfaceContainerHighest: dark
              ? const Color(0xff303831)
              : const Color(0xffe8ebe3),
          outlineVariant: dark
              ? const Color(0xff424b43)
              : const Color(0xffd8ddd4),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff171c19)
          : const Color(0xfff7f7f2),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xff171c19)
            : const Color(0xfff7f7f2),
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorColor: scheme.primary.withValues(alpha: .12),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        labelType: NavigationRailLabelType.all,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: .12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}

class FenruMark extends StatelessWidget {
  const FenruMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Fenru',
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .13, size.height * .1)
      ..lineTo(size.width * .45, size.height * .42)
      ..lineTo(size.width * .55, size.height * .42)
      ..lineTo(size.width * .87, size.height * .1)
      ..lineTo(size.width * .82, size.height * .68)
      ..lineTo(size.width * .5, size.height * .94)
      ..lineTo(size.width * .18, size.height * .68)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(
      Offset(size.width * .36, size.height * .61),
      size.width * .035,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * .64, size.height * .61),
      size.width * .035,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color;
}
