import 'package:flutter/material.dart';

/// Centralized UI color system for CrickX.
/// Strictly based on the Lime Spark (#B6FF2E) and Graphite (#23262F) design combo.
class CrickXColors {
  // ─── Primary UI Duo ───
  /// Lime Spark: vibrant neon lime accent (#B6FF2E)
  static const Color limeSpark = Color(0xFFB6FF2E);

  /// Lime Spark Dark: deeper lime for gradient depth (#96E018)
  static const Color limeSparkDark = Color(0xFF96E018);

  /// Lime Spark Dim: muted lime for secondary gradients and subtle accents (#7BC510)
  static const Color limeSparkDim = Color(0xFF7BC510);

  /// Graphite: deep slate graphite base (#23262F)
  static const Color graphite = Color(0xFF23262F);

  // ─── Graphite Surface Hierarchy ───
  /// Deep background / scaffold background
  static const Color graphiteBg = Color(0xFF16181F);

  /// Standard card, tile, and sheet surface (#23262F)
  static const Color graphiteSurface = Color(0xFF23262F);

  /// Elevated surface for dialogs, modals, and floating cards
  static const Color graphiteElevated = Color(0xFF2B2F3A);

  /// Border and divider color for graphite surfaces
  static const Color graphiteBorder = Color(0xFF353A47);

  /// Subtle border for secondary or nested containers
  static const Color graphiteBorderSubtle = Color(0xFF2E323E);

  /// Input background for text fields and search inputs
  static const Color graphiteInput = Color(0xFF1B1D25);

  // ─── Accent & Interactions ───
  /// Primary accent alias
  static const Color accent = limeSpark;

  /// High-contrast dark text/icon color for rendering on top of Lime Spark backgrounds
  static const Color onLime = Color(0xFF14161C);

  /// Helper for lime glowing shadow / highlight effects
  static Color limeGlow([double opacity = 0.35]) =>
      limeSpark.withValues(alpha: opacity);

  // ─── Typography Neutrals ───
  /// Primary white text on dark graphite surfaces
  static const Color textPrimary = Color(0xFFF4F5F7);

  /// Secondary muted text for subtitles and captions
  static const Color textSecondary = Color(0xFFA0A5B5);

  /// Muted / placeholder text
  static const Color textMuted = Color(0xFF6B7280);

  /// Disabled / inactive text
  static const Color textDisabled = Color(0xFF4A4F5B);

  // ─── Gradients ───
  /// Dynamic Lime Spark gradient for prominent buttons & hero cards
  static const LinearGradient limeGradient = LinearGradient(
    colors: [Color(0xFFD0FF66), Color(0xFFB6FF2E), Color(0xFF8CE600)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Sleek Graphite card gradient
  static const LinearGradient graphiteGradient = LinearGradient(
    colors: [Color(0xFF282C37), Color(0xFF23262F), Color(0xFF1D2028)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
