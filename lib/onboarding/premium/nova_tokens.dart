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
  // Near-black base (avoids pure black for a premium feel).
  static const Color bgBase = Color(0xFF07070A);
  static const Color bgSurface = Color(0xFF101016);
  static const Color bgSurface2 = Color(0xFF14141C);
  static const Color bgElevated = Color(0xFF171722);

  static const Color textPrimary = Color(0xFFEDEDF0);
  static const Color textSecondary = Color(0xFFA6A6B2);
  static const Color textMuted = Color(0xFF777789);
  static const Color textDisabled = Color(0xFF5B5B6A);

  static const Color border = Color(0xFF242430);
  static const Color borderSubtle = Color.fromRGBO(237, 237, 240, 0.08);

  // One accent color for the entire onboarding (premium sports-tech cyan/teal).
  static const Color accent = Color(0xFF5EF2C7);

  static const Color ctaText = Color(0xFF07070A);

  static const Color progressTrack = Color(0xFF20202B);
  static const Color progressFill = accent;

  static Color accentGlow([double opacity = 0.22]) =>
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
