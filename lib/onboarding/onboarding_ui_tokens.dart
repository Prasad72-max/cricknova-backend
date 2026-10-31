import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OnboardingUiTokens {
  static const double maxContentWidth = 390;
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(20, 64, 20, 32);
  static const double topBarHeight = 56;
  static const double progressBarHeight = 3;

  static const Cubic motionEaseInOut = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Cubic motionEaseOut = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Cubic motionEaseIn = Cubic(0.4, 0.0, 1.0, 1.0);
}

class OnboardingColors {
  static const Color bgBase = Color(0xFF16181F);
  static const Color bgSurface = Color(0xFF23262F); // card default: Graphite
  static const Color bgHover = Color(0xFF2B2F3A);
  static const Color bgSelected = Color(0xFF2B2F3A);
  static const Color bgElevated = Color(0xFF2B2F3A);

  // Single accent color for premium glow/highlights: Lime Spark
  static const Color accent = Color(0xFFB6FF2E);

  static const Color textPrimary = Color(0xFFF4F5F7);
  static const Color textOption = Color(0xFFF4F5F7);
  static const Color textSecondary = Color(0xFFA0A5B5);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF4A4F5B);

  static const Color borderDefault = Color(0xFF353A47);
  static const Color borderSubtle = Color(0xFF2E323E);
  static const Color borderActive = Color(0xFFB6FF2E);

  static const Color ctaBg = Color(0xFFB6FF2E);
  static const Color ctaText = Color(0xFF14161C);

  static const Color progressTrack = Color(0xFF2E323E);
  static const Color progressFill = accent;

  static const Color checkBg = Color(0xFFB6FF2E);
  static const Color checkIcon = Color(0xFF14161C);
}

class OnboardingTextStyles {
  static const double _fontScale = 1.06;

  static String get _geistSansFallback =>
      GoogleFonts.poppins().fontFamily ?? 'Poppins';
  static String get _geistMonoFallback =>
      GoogleFonts.poppins().fontFamily ?? 'Poppins';

  static double? _scaled(double? fontSize) =>
      fontSize == null ? null : fontSize * _fontScale;

  static TextStyle serif({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    return GoogleFonts.poppins(
      color: color,
      fontSize: _scaled(fontSize),
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  }

  static TextStyle uiSans({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'GeistSans',
      fontFamilyFallback: <String>[_geistSansFallback],
      color: color,
      fontSize: _scaled(fontSize),
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  }

  static TextStyle uiMono({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: 'GeistMono',
      fontFamilyFallback: <String>[_geistMonoFallback],
      color: color,
      fontSize: _scaled(fontSize),
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
    );
  }
}
