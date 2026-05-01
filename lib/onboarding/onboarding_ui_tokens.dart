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
  static const Color bgBase = Color(0xFF09090B);
  static const Color bgSurface = Color(0xFF161619); // card default
  static const Color bgHover = Color(0xFF1C1C21);
  static const Color bgSelected = Color(0xFF1A1A1F);
  static const Color bgElevated = Color(0xFF161619);

  // Single accent color for premium glow/highlights.
  static const Color accent = Color(0xFF5EF2C7);

  static const Color textPrimary = Color(0xFFEFEFED);
  static const Color textOption = Color(0xFFEFEFED);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF71717A);
  static const Color textDisabled = Color(0xFF52525B);

  static const Color borderDefault = Color(0xFF2A2A2F);
  static const Color borderSubtle = Color(0xFF404047);
  static const Color borderActive = Color.fromRGBO(94, 242, 199, 0.30);

  static const Color ctaBg = Color(0xFFEFEFED);
  static const Color ctaText = Color(0xFF09090B);

  static const Color progressTrack = Color(0xFF222226);
  static const Color progressFill = accent;

  static const Color checkBg = Color(0xFFEFEFED);
  static const Color checkIcon = Color(0xFF09090B);
}

class OnboardingTextStyles {
  static const double _fontScale = 1.06;

  static String get _geistSansFallback =>
      GoogleFonts.dmSans().fontFamily ?? 'DM Sans';
  static String get _geistMonoFallback =>
      GoogleFonts.jetBrainsMono().fontFamily ?? 'JetBrains Mono';

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
    return GoogleFonts.instrumentSerif(
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
