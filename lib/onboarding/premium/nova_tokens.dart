import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NovaTokens {
  static const double maxContentWidth = 420;
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(22, 18, 22, 24);
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(22, 18, 22, 18);

  static const double topBarHeight = 56;
  static const double progressBarHeight = 2;

  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 22;
  static const double rXl = 28;

  static const Duration dFast = Duration(milliseconds: 140);
  static const Duration dMed = Duration(milliseconds: 220);
  static const Duration dSlow = Duration(milliseconds: 520);
  static const Duration dBg = Duration(milliseconds: 2600);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
}

class NovaColors {
  // Graphite base and surfaces
  static const Color bgBase = Color(0xFF16181F);
  static const Color bgSurface = Color(0xFF23262F); // Graphite
  static const Color bgSurface2 = Color(0xFF282C37);
  static const Color bgElevated = Color(0xFF2B2F3A);

  static const Color textPrimary = Color(0xFFF4F5F7);
  static const Color textSecondary = Color(0xFFA0A5B5);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF4A4F5B);

  static const Color border = Color(0xFF353A47);
  static const Color borderSubtle = Color(0xFF2E323E);

  // Lime Spark accent color
  static const Color accent = Color(0xFFB6FF2E);

  static const Color ctaText = Color(0xFF14161C);

  static const Color progressTrack = Color(0xFF2E323E);
  static const Color progressFill = accent;

  static Color accentGlow([double opacity = 0.35]) =>
      accent.withValues(alpha: opacity);
}

class NovaTypography {
  static String get _sansFallback =>
      GoogleFonts.dmSans().fontFamily ?? 'DM Sans';
  static String get _monoFallback =>
      GoogleFonts.jetBrainsMono().fontFamily ?? 'JetBrains Mono';

  static TextStyle display({
    Color? color,
    double size = 34,
    FontWeight weight = FontWeight.w400,
    double height = 1.06,
    double letterSpacing = -0.6,
  }) {
    return GoogleFonts.instrumentSerif(
      color: color ?? NovaColors.textPrimary,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle title({
    Color? color,
    double size = 24,
    FontWeight weight = FontWeight.w600,
    double height = 1.18,
    double letterSpacing = -0.4,
  }) {
    return TextStyle(
      fontFamily: 'GeistSans',
      fontFamilyFallback: <String>[_sansFallback],
      color: color ?? NovaColors.textPrimary,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle body({
    Color? color,
    double size = 15,
    FontWeight weight = FontWeight.w400,
    double height = 1.55,
    double letterSpacing = 0.0,
  }) {
    return TextStyle(
      fontFamily: 'GeistSans',
      fontFamilyFallback: <String>[_sansFallback],
      color: color ?? NovaColors.textSecondary,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle labelMono({
    Color? color,
    double size = 12,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 2.2,
  }) {
    return TextStyle(
      fontFamily: 'GeistMono',
      fontFamilyFallback: <String>[_monoFallback],
      color: color ?? NovaColors.textMuted,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }
}

class NovaMotion {
  static bool reduceMotionOf(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return false;
    return mq.disableAnimations || mq.accessibleNavigation;
  }

  static Duration maybe(Duration d, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : d;
}
