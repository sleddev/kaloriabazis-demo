import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand + nutrient colours, shared by light and dark themes.
abstract final class Palette {
  static const ember = Color(0xFFFF5A36); // calories / brand
  static const emberDeep = Color(0xFFE63E1C);
  static const protein = Color(0xFF7C5CFF);
  static const carbs = Color(0xFFFFB020);
  static const fat = Color(0xFF14B8A6);
  static const over = Color(0xFFE5484D);
  static const good = Color(0xFF30A46C);

  static const inkCard = Color(0xFF1E1B18);
  static const inkCard2 = Color(0xFF2B2622);
}

/// Extra colours that differ between light and dark mode.
@immutable
class Surfaces extends ThemeExtension<Surfaces> {
  const Surfaces({
    required this.card,
    required this.muted,
    required this.track,
  });

  final Color card;
  final Color muted;
  final Color track;

  @override
  Surfaces copyWith({Color? card, Color? muted, Color? track}) => Surfaces(
    card: card ?? this.card,
    muted: muted ?? this.muted,
    track: track ?? this.track,
  );

  @override
  Surfaces lerp(Surfaces? other, double t) => other == null
      ? this
      : Surfaces(
          card: Color.lerp(card, other.card, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          track: Color.lerp(track, other.track, t)!,
        );
}

extension ThemeX on BuildContext {
  Surfaces get surfaces => Theme.of(this).extension<Surfaces>()!;
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
}

/// Display face for the big numbers.
TextStyle numberStyle(double size, {Color? color, FontWeight? weight}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w700,
      color: color,
      height: 1.0,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF12100E) : const Color(0xFFF6F2EC);
  final card = dark ? const Color(0xFF1D1A17) : Colors.white;
  final ink = dark ? const Color(0xFFF4EFE8) : const Color(0xFF1E1B18);
  final muted = dark ? const Color(0xFF9C948B) : const Color(0xFF7A7269);

  final scheme = ColorScheme.fromSeed(seedColor: Palette.ember, brightness: b)
      .copyWith(
        primary: Palette.ember,
        onPrimary: Colors.white,
        surface: bg,
        onSurface: ink,
        surfaceContainerLowest: card,
        surfaceContainerLow: card,
        surfaceContainer: dark
            ? const Color(0xFF26221E)
            : const Color(0xFFEFE9E1),
        surfaceContainerHigh: dark
            ? const Color(0xFF2E2924)
            : const Color(0xFFE8E1D8),
        onSurfaceVariant: muted,
        outlineVariant: dark
            ? const Color(0xFF332E29)
            : const Color(0xFFE6DFD5),
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: bg,
  );
  final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
      .apply(bodyColor: ink, displayColor: ink);

  return base.copyWith(
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    extensions: [
      Surfaces(
        card: card,
        muted: muted,
        track: dark ? const Color(0xFF2E2924) : const Color(0xFFEFE8DF),
      ),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: Palette.ember.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? ink : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? Palette.ember : muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF26221E) : const Color(0xFFEFE9E1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: TextStyle(color: muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
      backgroundColor: dark ? const Color(0xFF26221E) : const Color(0xFFEFE9E1),
      selectedColor: ink,
      labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: bg, fontWeight: FontWeight.w700),
      checkmarkColor: bg,
      showCheckmark: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.inkCard,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: Palette.ember,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xFF2B2622) : const Color(0xFFEDE6DC),
      space: 1,
      thickness: 1,
    ),
  );
}
