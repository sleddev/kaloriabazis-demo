import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

String fmtKcal(num v) => v.round().toString();

String fmtG(num v) {
  if (v >= 10 || v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(1);
}

/// Animated progress ring with a gradient sweep and a rounded cap.
class CalorieRing extends StatelessWidget {
  const CalorieRing({
    super.key,
    required this.eaten,
    required this.goal,
    this.size = 168,
    this.stroke = 16,
    this.track = const Color(0x22FFFFFF),
    this.child,
  });

  final double eaten;
  final double goal;
  final double size;
  final double stroke;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final frac = goal <= 0 ? 0.0 : eaten / goal;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: frac),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, track),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.stroke, this.track);
  final double frac;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (frac <= 0) return;
    final main = frac.clamp(0.0, 1.0);
    final sweep = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        // Ends on amber again so the round start cap doesn't pick up pink.
        colors: [
          Color(0xFFFFB020),
          Palette.ember,
          Color(0xFFFF2E63),
          Color(0xFFFFB020),
        ],
        stops: [0, 0.5, 0.96, 1],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * main, false, sweep);
    if (frac > 1) {
      // Second lap for the overshoot, in red.
      canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * (frac - 1).clamp(0.0, 1.0),
        false,
        Paint()
          ..color = Palette.over
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke * 0.55,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.frac != frac || old.track != track;
}

/// Thin labelled progress bar for one macro nutrient.
class MacroBar extends StatelessWidget {
  const MacroBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    this.onDark = false,
  });

  final String label;
  final double value;
  final double target;
  final Color color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final frac = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    final fg = onDark ? Colors.white : context.colors.onSurface;
    final sub = onDark ? Colors.white60 : context.surfaces.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: sub,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 7,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: onDark ? Colors.white12 : context.surfaces.track,
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: frac),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: fmtG(value),
                style: TextStyle(color: fg, fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: ' / ${target.round()} g',
                style: TextStyle(color: sub),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 12.5),
        ),
      ],
    );
  }
}

const _avatarColors = [
  Color(0xFFFFE1D6),
  Color(0xFFE6E0FF),
  Color(0xFFFFF0C7),
  Color(0xFFD3F4EE),
  Color(0xFFFFDDE6),
  Color(0xFFDDEBFF),
];

/// Food picture from the site, or a pastel monogram when there is none.
class FoodAvatar extends StatelessWidget {
  const FoodAvatar({
    super.key,
    required this.name,
    this.url,
    this.fallbackUrl,
    this.size = 44,
  });

  final String name;
  final String? url;

  /// Tried when [url] fails (not every food has a large picture).
  final String? fallbackUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    final mono = Center(
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.black.withValues(alpha: 0.55),
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? mono
          : Padding(
              padding: EdgeInsets.all(size * 0.08),
              child: Image.network(
                url!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallbackUrl == null
                    ? mono
                    : Image.network(
                        fallbackUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => mono,
                      ),
                frameBuilder: (_, child, frame, sync) =>
                    sync || frame != null ? child : const SizedBox.shrink(),
              ),
            ),
    );
  }
}

/// Small coloured dot + label, used as a macro legend.
class MacroDot extends StatelessWidget {
  const MacroDot(this.color, this.text, {super.key});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: context.surfaces.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// Inline P / Sz / Zs legend for a [Macros] value.
class MacroLegend extends StatelessWidget {
  const MacroLegend(this.m, {super.key});
  final Macros m;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    children: [
      MacroDot(Palette.protein, 'F ${fmtG(m.protein)}g'),
      MacroDot(Palette.carbs, 'Sz ${fmtG(m.carbs)}g'),
      MacroDot(Palette.fat, 'Zs ${fmtG(m.fat)}g'),
    ],
  );
}

/// Friendly error box with a retry button.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Palette.over.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(Icons.wifi_off_rounded, color: Palette.over),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Újra')),
      ],
    ),
  );
}
