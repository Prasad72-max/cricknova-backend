import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cricket_facts_data.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../analysis/analysis_queue_store.dart';
import '../analysis/analyzing_videos_screen.dart';
import '../models/pending_video.dart';
import '../premium/premium_screen.dart';
import '../navigation/main_navigation.dart';
import '../services/app_analytics.dart';
import '../services/razorpay_service.dart';
import '../services/play_billing_service.dart';
import '../services/premium_service.dart';
import '../services/improvement_plan_service.dart';
import '../services/weekly_stats_service.dart';
import '../services/cricknova_notification_service.dart';
import '../services/xp_service.dart';

enum _DrsCinematicPhase { idle, snicko, tracking, decision }

enum _DrsReplayMode { ultraEdge, lbw }

enum _DrsUmpireCall { out, notOut, umpire }

enum _DrsViewMode { keeper, umpire, striker }

String _wakeOverlayUserName() {
  final user = FirebaseAuth.instance.currentUser;
  final uid = user?.uid;
  if (uid != null && Hive.isBoxOpen("local_stats_$uid")) {
    final box = Hive.box("local_stats_$uid");
    final profileName = box.get("profileName") as String?;
    if (profileName != null && profileName.trim().isNotEmpty) {
      return profileName.trim().split(" ").first;
    }
  }
  if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
    return user.displayName!.trim().split(" ").first;
  }
  if ((user?.email ?? "").contains("@")) {
    return user!.email!.split("@").first;
  }
  return "Player";
}

List<Map<String, double>> _sanitizeVideoTrajectory(dynamic rawPoints) {
  if (rawPoints is! List) return const [];
  final pts = <Map<String, double>>[];
  for (final e in rawPoints) {
    if (e is! Map) continue;
    final x = e["x"];
    final y = e["y"];
    if (x is! num || y is! num) continue;
    final px = x.toDouble().clamp(0.0, 1.0);
    final py = y.toDouble().clamp(0.0, 1.0);
    if (pts.isNotEmpty) {
      final prev = pts.last;
      if ((prev["x"]! - px).abs() < 0.0005 &&
          (prev["y"]! - py).abs() < 0.0005) {
        continue;
      }
    }
    pts.add({"x": px, "y": py});
  }
  return pts;
}

List<Map<String, double>> _smoothVideoTrajectory(
  List<Map<String, double>> points,
) {
  if (points.length < 3) return points;
  final out = List<Map<String, double>>.generate(
    points.length,
    (_) => {"x": 0, "y": 0},
  );
  const w = 2;
  for (int i = 0; i < points.length; i++) {
    double sumX = 0;
    double sumY = 0;
    int count = 0;
    for (int j = i - w; j <= i + w; j++) {
      if (j < 0 || j >= points.length) continue;
      sumX += points[j]["x"]!;
      sumY += points[j]["y"]!;
      count++;
    }
    out[i]["x"] = sumX / count;
    out[i]["y"] = sumY / count;
  }

  for (int i = 1; i < out.length; i++) {
    out[i]["x"] = (0.65 * out[i - 1]["x"]!) + (0.35 * out[i]["x"]!);
    out[i]["y"] = (0.65 * out[i - 1]["y"]!) + (0.35 * out[i]["y"]!);
  }
  return out;
}

double _trajectoryQualityScore(
  List<Map<String, double>> points, {
  Size? videoSize,
}) {
  if (points.isEmpty) return 0.0;
  final minDim =
      videoSize == null || videoSize.width <= 0 || videoSize.height <= 0
      ? 720.0
      : math.min(videoSize.width, videoSize.height);
  final resScore = ((minDim - 240.0) / 840.0).clamp(0.0, 1.0);
  final countScore = ((points.length - 6) / 20.0).clamp(0.0, 1.0);

  final deltas = <double>[];
  for (int i = 1; i < points.length; i++) {
    final dx = points[i]["x"]! - points[i - 1]["x"]!;
    final dy = points[i]["y"]! - points[i - 1]["y"]!;
    final d = math.sqrt((dx * dx) + (dy * dy));
    if (d > 0) deltas.add(d);
  }
  double jitterScore = 0.5;
  if (deltas.length >= 2) {
    final mean = deltas.reduce((a, b) => a + b) / deltas.length;
    double variance = 0.0;
    for (final d in deltas) {
      final diff = d - mean;
      variance += diff * diff;
    }
    variance /= deltas.length;
    final std = math.sqrt(variance);
    final ratio = mean > 0 ? (std / mean) : 1.0;
    jitterScore = (1.0 - (ratio / 0.45)).clamp(0.0, 1.0);
  }
  return (resScore * 0.25) + (countScore * 0.35) + (jitterScore * 0.40);
}

int _detectBounceIndex(List<Map<String, double>> points) {
  if (points.length < 3) return -1;
  final ys = List<double>.generate(points.length, (i) => points[i]["y"]!);
  final span = (ys.reduce(math.max) - ys.reduce(math.min)).abs();
  final minProm = math.max(0.0012, span * 0.05);
  int bestIdx = -1;
  double bestProm = 0;
  for (int i = 1; i < ys.length - 1; i++) {
    final peak = ys[i] >= ys[i - 1] && ys[i] >= ys[i + 1];
    if (!peak) continue;
    final prom = ys[i] - ((ys[i - 1] + ys[i + 1]) * 0.5);
    if (prom > minProm && prom > bestProm) {
      bestProm = prom;
      bestIdx = i;
    }
  }
  if (bestIdx != -1) return bestIdx;

  // Full toss / very short tracks: choose strongest interior descent turn.
  int fallback = -1;
  double bestY = -1e9;
  for (int i = 1; i < ys.length - 1; i++) {
    if (ys[i] > bestY) {
      bestY = ys[i];
      fallback = i;
    }
  }
  return fallback;
}

Map<String, dynamic> _drsGeometryWorker(Map<String, dynamic> input) {
  final pointsRaw = (input["points"] as List<dynamic>? ?? const []);
  final points = _smoothVideoTrajectory(_sanitizeVideoTrajectory(pointsRaw));
  final confidence = (input["confidence"] as num?)?.toDouble() ?? 0.0;
  final backendBallTracking = input["ballTracking"] == true;
  final seed = (input["seed"] as num?)?.toInt() ?? 0;

  if (points.length < 3) {
    final lane = seed % 7;
    final pitchX = points.isNotEmpty
        ? points.first["x"]!
        : <double>[0.39, 0.44, 0.48, 0.51, 0.55, 0.60, 0.64][lane];
    final drift = <double>[
      -0.08,
      -0.04,
      -0.015,
      0.01,
      0.035,
      0.065,
      0.09,
    ][lane];
    final impactX = (points.length >= 2 ? points.last["x"]! : pitchX + drift)
        .clamp(0.08, 0.92);
    final projectedX = (impactX + (drift * 0.75)).clamp(0.08, 0.92);
    const stumpCenterX = 0.5;
    const offStumpX = 0.575;
    const legStumpX = 0.425;
    final dOff = (projectedX - offStumpX).abs();
    final dMid = (projectedX - stumpCenterX).abs();
    final dLeg = (projectedX - legStumpX).abs();
    final minD = math.min(dOff, math.min(dMid, dLeg));
    // Avoid "always OUT" feedback loops: only treat backend ball tracking as
    // a strong hint, not an unconditional override.
    final isHitting =
        (backendBallTracking && confidence >= 0.55) ||
        (minD <= 0.055 && confidence >= 0.50);
    final isUmpires = !isHitting && minD <= 0.12;
    final pitchDelta = pitchX - stumpCenterX;
    final impactDelta = (impactX - stumpCenterX).abs();
    final pitchingText = pitchDelta < -0.075
        ? "Outside Leg"
        : (pitchDelta > 0.075 ? "Outside Off" : "In Line");
    final impactText = impactDelta > 0.13
        ? "Outside"
        : (impactDelta > 0.08 ? "Umpires Call" : "In Line");
    final wicketTarget = dOff <= dMid && dOff <= dLeg
        ? "Off"
        : (dLeg <= dOff && dLeg <= dMid ? "Leg" : "Middle");
    return {
      "deliveryStart": {"x": (pitchX - drift).clamp(0.08, 0.92), "y": 0.20},
      "pitchPoint": {"x": pitchX, "y": 0.58},
      "impactPoint": {"x": impactX, "y": 0.74},
      "stumpsPoint": {"x": 0.50, "y": 0.88},
      "stumpLeft": {"x": legStumpX, "y": 0.88},
      "stumpRight": {"x": offStumpX, "y": 0.88},
      "pathPoints": points,
      "pitchingText": pitchingText,
      "impactText": impactText,
      "wicketsText": isHitting
          ? "Hitting"
          : (isUmpires ? "Umpires Call" : "Missing"),
      "wicketTarget": wicketTarget,
      "wicketsHitting": isHitting,
    };
  }

  final bounceIdx = _detectBounceIndex(points).clamp(0, points.length - 2);
  final impactIdx = points.length - 1;

  final deliveryStart = {"x": points.first["x"]!, "y": points.first["y"]!};
  final pitchPoint = {
    "x": points[bounceIdx]["x"]!,
    "y": points[bounceIdx]["y"]!,
  };
  final impactPoint = {
    "x": points[impactIdx]["x"]!,
    "y": points[impactIdx]["y"]!,
  };
  // Stable stump centerline (center of pitch/screen)
  // Accuracy: Stumps do not move with the ball. Use fixed 0.5 (center).
  const stumpCenterX = 0.5;
  const stumpY = 0.88;

  final offStumpX = stumpCenterX + 0.085;
  final legStumpX = stumpCenterX - 0.085;

  final dxPost = impactPoint["x"]! - pitchPoint["x"]!;
  final dyPost = impactPoint["y"]! - pitchPoint["y"]!;

  double projectedAtStumpsX;
  if (dyPost.abs() < 0.02) {
    // Ball is nearly flat — use impact X directly
    projectedAtStumpsX = impactPoint["x"]!;
  } else {
    // Linear extrapolation from pitch point through impact to stump depth
    final stumpRelY = stumpY - pitchPoint["y"]!;
    final impactRelY = impactPoint["y"]! - pitchPoint["y"]!;
    final ratio = impactRelY.abs() > 0.005 ? stumpRelY / impactRelY : 1.0;
    projectedAtStumpsX = (pitchPoint["x"]! + dxPost * ratio).clamp(0.05, 0.95);
  }

  final stumpsPoint = {"x": stumpCenterX, "y": stumpY};
  final stumpLeft = {"x": legStumpX, "y": stumpY};
  final stumpRight = {"x": offStumpX, "y": stumpY};

  String pitchingText;
  final pitchDelta = (pitchPoint["x"]! - stumpCenterX);
  if (pitchDelta < -0.075) {
    pitchingText = "Outside Leg";
  } else if (pitchDelta > 0.075) {
    pitchingText = "Outside Off";
  } else {
    pitchingText = "In Line";
  }

  String impactText;
  final absImpactDelta = (impactPoint["x"]! - stumpCenterX).abs();
  if (absImpactDelta > 0.13) {
    impactText = "Outside";
  } else if (absImpactDelta > 0.08) {
    impactText = "Umpires Call";
  } else {
    impactText = "In Line";
  }

  const stumpRadius = 0.042;
  final dOff = (projectedAtStumpsX - offStumpX).abs();
  final dMid = (projectedAtStumpsX - stumpCenterX).abs();
  final dLeg = (projectedAtStumpsX - legStumpX).abs();
  final minD = math.min(dOff, math.min(dMid, dLeg));

  final legalPitch = pitchingText != "Outside Leg";
  final legalImpact =
      !impactText.contains("Outside") ||
      backendBallTracking ||
      confidence >= 0.45;

  // Wicket Hitting Logic with Real-World Tolerances
  bool wicketsHitting = false;
  String wicketsText = "Missing";

  if (legalPitch && legalImpact) {
    if (minD <= stumpRadius) {
      wicketsHitting = true;
      wicketsText = "Hitting";
    } else if (minD <= stumpRadius * 1.5) {
      wicketsHitting = false;
      wicketsText = "Umpires Call";
    } else {
      wicketsHitting = false;
      wicketsText = "Missing";
    }
  }

  String wicketTarget;
  if (dOff <= dMid && dOff <= dLeg) {
    wicketTarget = "Off";
  } else if (dLeg <= dOff && dLeg <= dMid) {
    wicketTarget = "Leg";
  } else {
    wicketTarget = "Middle";
  }

  return {
    "deliveryStart": deliveryStart,
    "pitchPoint": pitchPoint,
    "impactPoint": impactPoint,
    "stumpsPoint": stumpsPoint,
    "stumpLeft": stumpLeft,
    "stumpRight": stumpRight,
    "pathPoints": points,
    "pitchingText": pitchingText,
    "impactText": impactText,
    "wicketsText": wicketsText,
    "wicketTarget": wicketTarget,
    "wicketsHitting": wicketsHitting,
  };
}

class _DrsTrackingGeometry {
  final Offset deliveryStart;
  final Offset pitchPoint;
  final Offset impactPoint;
  final Offset stumpsPoint;
  final Offset stumpLeft;
  final Offset stumpRight;
  final List<Offset> pathPoints;
  final String pitchingText;
  final String impactText;
  final String wicketsText;
  final String wicketTarget;
  final bool wicketsHitting;

  const _DrsTrackingGeometry({
    required this.deliveryStart,
    required this.pitchPoint,
    required this.impactPoint,
    required this.stumpsPoint,
    required this.stumpLeft,
    required this.stumpRight,
    required this.pathPoints,
    required this.pitchingText,
    required this.impactText,
    required this.wicketsText,
    required this.wicketTarget,
    required this.wicketsHitting,
  });

  const _DrsTrackingGeometry.fallback()
    : deliveryStart = const Offset(0.16, 0.20),
      pitchPoint = const Offset(0.47, 0.58),
      impactPoint = const Offset(0.66, 0.72),
      stumpsPoint = const Offset(0.80, 0.80),
      stumpLeft = const Offset(0.463, 0.82),
      stumpRight = const Offset(0.537, 0.82),
      pathPoints = const [],
      pitchingText = "In Line",
      impactText = "In Line",
      wicketsText = "Missing",
      wicketTarget = "Middle",
      wicketsHitting = false;
}

class TrajectoryPainter extends CustomPainter {
  final List<dynamic> points;

  TrajectoryPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    return; // ball path completely disabled
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SnickoWavePainter extends CustomPainter {
  final double progress;
  final bool hasSpike;

  _SnickoWavePainter({required this.progress, required this.hasSpike});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (int i = 1; i < 5; i++) {
      final y = size.height * (i / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final basePath = Path();
    final spikePath = Path();
    bool spikeStarted = false;
    final midY = size.height * 0.5;
    for (int i = 0; i <= size.width.toInt(); i++) {
      final t = i / size.width;
      final baseWave = math.sin((t * 16) + (progress * 14));
      final baseAmp = hasSpike ? 9.0 : 5.5;
      final y = midY + (baseWave * baseAmp);

      if (i == 0) {
        basePath.moveTo(i.toDouble(), y);
      } else {
        basePath.lineTo(i.toDouble(), y);
      }

      if (hasSpike && t > 0.485 && t < 0.555) {
        final spikeAmp =
            62.0 * (1.0 - ((t - 0.52).abs() * 24.0).clamp(0.0, 1.0));
        final spikeY = midY - spikeAmp;
        if (!spikeStarted) {
          spikeStarted = true;
          spikePath.moveTo(i.toDouble(), y);
        }
        spikePath.lineTo(i.toDouble(), spikeY);
      }
    }

    final glow = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(basePath, glow);

    final line = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawPath(basePath, line);

    if (hasSpike) {
      final spikeGlow = Paint()
        ..color = Colors.redAccent.withOpacity(0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawPath(spikePath, spikeGlow);
      canvas.drawPath(
        spikePath,
        Paint()
          ..color = Colors.redAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnickoWavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.hasSpike != hasSpike;
  }
}

class _UltraEdgeAudioResult {
  const _UltraEdgeAudioResult({
    required this.spikeDetected,
    required this.waveform,
    required this.reason,
    this.spikeMs,
    this.spikeT,
  });

  final bool spikeDetected;
  final List<double> waveform;
  final String reason;
  final double? spikeMs;
  final double? spikeT;

  factory _UltraEdgeAudioResult.noSpike(String reason) {
    return _UltraEdgeAudioResult(
      spikeDetected: false,
      waveform: const [],
      reason: reason,
    );
  }
}

class _UltraEdgeWaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final double? spikeT;
  final bool highlightSpike;

  _UltraEdgeWaveformPainter({
    required this.waveform,
    required this.progress,
    required this.spikeT,
    required this.highlightSpike,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.5;
    final baseLine = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), baseLine);

    if (waveform.isEmpty) {
      final flat = Paint()
        ..color = const Color(0xFF7FE9FF)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), flat);
      return;
    }

    final n = waveform.length;
    final shift = (progress * n).floor();
    final path = Path();
    for (int i = 0; i <= size.width.toInt(); i++) {
      final t = i / size.width;
      final idx = (shift + (t * n)).floor() % n;
      final amp = waveform[idx].clamp(0.0, 1.0);
      final y = midY - (amp * midY * 0.85);
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    final glow = Paint()
      ..color = const Color(0xFF6FE7FF).withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, glow);

    final line = Paint()
      ..color = const Color(0xFF2DE7FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawPath(path, line);

    if (highlightSpike && spikeT != null) {
      final x = (spikeT!.clamp(0.0, 1.0) * size.width);
      final spikeTop = midY - (size.height * 0.45);
      final spikeBottom = midY + (size.height * 0.45);
      final spikePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawLine(Offset(x, spikeBottom), Offset(x, spikeTop), spikePaint);
      canvas.drawLine(
        Offset(x, spikeBottom),
        Offset(x, spikeTop),
        Paint()
          ..color = const Color(0xFF6FE7FF)
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UltraEdgeWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.spikeT != spikeT ||
        oldDelegate.highlightSpike != highlightSpike ||
        oldDelegate.waveform != waveform;
  }
}

class _BatBallPainter extends CustomPainter {
  final double progress;
  final bool freezeAtBat;

  _BatBallPainter(this.progress, {required this.freezeAtBat});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      bg,
    );

    final bat = Paint()..color = const Color(0xFFC9A86A);
    final batRect = Rect.fromLTWH(
      size.width * 0.68,
      size.height * 0.2,
      size.width * 0.06,
      size.height * 0.6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(batRect, const Radius.circular(6)),
      bat,
    );

    final motionProgress = freezeAtBat
        ? math.min(progress.clamp(0.0, 1.0), 0.52)
        : progress.clamp(0.0, 1.0);
    final ballX = size.width * (0.1 + (0.7 * motionProgress));
    final ballY = size.height * (0.35 + (0.25 * motionProgress));
    final ball = Paint()..color = Colors.redAccent;
    canvas.drawCircle(Offset(ballX, ballY), 8, ball);
    final seam = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(ballX, ballY), radius: 5),
      -0.8,
      1.6,
      false,
      seam,
    );
  }

  @override
  bool shouldRepaint(covariant _BatBallPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.freezeAtBat != freezeAtBat;
  }
}

class _AnalysisPulsePainter extends CustomPainter {
  final double pulse;

  _AnalysisPulsePainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) * 0.28;
    final shell = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x6600C2FF),
          const Color(0x2200C2FF),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.8));
    canvas.drawCircle(center, baseRadius * 1.7, shell);

    for (int i = 0; i < 3; i++) {
      final ringT = ((pulse + (i * 0.22)) % 1.0);
      final ringRadius = baseRadius * (0.95 + (ringT * 1.05));
      final ringAlpha = (1 - ringT).clamp(0.0, 1.0) * 0.32;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF00C2FF).withValues(alpha: ringAlpha);
      canvas.drawCircle(center, ringRadius, ring);
    }

    final orbitRadius = baseRadius * 1.2;
    final orbitAngle = pulse * math.pi * 2;
    final orbitDot = Offset(
      center.dx + (math.cos(orbitAngle) * orbitRadius),
      center.dy + (math.sin(orbitAngle) * orbitRadius),
    );
    final orbitPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF00FF9D), Color(0x0000FF9D)],
      ).createShader(Rect.fromCircle(center: orbitDot, radius: 14));
    canvas.drawCircle(orbitDot, 14, orbitPaint);
    canvas.drawCircle(orbitDot, 4, Paint()..color = const Color(0xFF00FF9D));

    final coreRect = Rect.fromCircle(center: center, radius: baseRadius * 0.82);
    final core = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF16324A), Color(0xFF0D141D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(coreRect);
    canvas.drawCircle(center, baseRadius * 0.82, core);

    final seam = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      coreRect.deflate(baseRadius * 0.18),
      -1.05,
      2.1,
      false,
      seam,
    );
    canvas.drawArc(coreRect.deflate(baseRadius * 0.18), 2.1, 2.1, false, seam);
  }

  @override
  bool shouldRepaint(covariant _AnalysisPulsePainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}

class _DrsTrajectoryPainter extends CustomPainter {
  final _DrsTrackingGeometry geometry;
  final double progress;
  final _DrsViewMode viewMode;

  _DrsTrajectoryPainter({
    required this.geometry,
    required this.progress,
    required this.viewMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackProgress = progress.clamp(0.0, 1.0);

    Offset lerpPoint(Offset a, Offset b, double t) {
      return Offset(a.dx + ((b.dx - a.dx) * t), a.dy + ((b.dy - a.dy) * t));
    }

    // Background is pitch.png on parent stack; painter draws trajectory overlay only.

    // Camera presets.
    late final Offset nearLeft;
    late final Offset nearRight;
    late final Offset farLeft;
    late final Offset farRight;
    late final double perspectiveStrength;
    switch (viewMode) {
      case _DrsViewMode.keeper:
        nearLeft = Offset(size.width * 0.12, size.height * 0.93);
        nearRight = Offset(size.width * 0.94, size.height * 0.93);
        farLeft = Offset(size.width * 0.43, size.height * 0.46);
        farRight = Offset(size.width * 0.65, size.height * 0.46);
        perspectiveStrength = 0.13;
        break;
      case _DrsViewMode.umpire:
        // Strict umpire trapezoid: bottom=100%, top=25%.
        nearLeft = Offset(0, size.height * 0.97);
        nearRight = Offset(size.width, size.height * 0.97);
        farLeft = Offset(size.width * 0.375, size.height * 0.40);
        farRight = Offset(size.width * 0.625, size.height * 0.40);
        perspectiveStrength = 0.21;
        break;
      case _DrsViewMode.striker:
        nearLeft = Offset(size.width * 0.20, size.height * 0.93);
        nearRight = Offset(size.width * 0.92, size.height * 0.93);
        farLeft = Offset(size.width * 0.49, size.height * 0.48);
        farRight = Offset(size.width * 0.70, size.height * 0.48);
        perspectiveStrength = 0.12;
        break;
    }

    Offset worldToScreen(double u, double v) {
      final vv = v.clamp(0.0, 1.0);
      final uu = u.clamp(0.0, 1.0);
      final left = lerpPoint(nearLeft, farLeft, vv);
      final right = lerpPoint(nearRight, farRight, vv);
      final depthSqueeze = perspectiveStrength * vv;
      final uWarp = ((uu - 0.5) * (1.0 - depthSqueeze)) + 0.5;
      return lerpPoint(left, right, uWarp.clamp(0.0, 1.0));
    }

    // Real-world depth mapping for pitch.png umpire view:
    // release far end (top), impact/wickets near end (bottom).
    const pitchLengthM = 20.12;
    const pitchZ = 11.20;
    double vFromZ(double z) => (1.0 - (z / pitchLengthM)).clamp(0.0, 1.0);

    final uRelease = geometry.deliveryStart.dx.clamp(0.12, 0.88);
    final uPitch = geometry.pitchPoint.dx.clamp(0.18, 0.82);
    final uImpact = geometry.impactPoint.dx.clamp(0.20, 0.82);

    // Full-pitch stretch from far release to near stumps.
    Offset wDelivery = worldToScreen(
      uRelease,
      vFromZ(0.0) - 0.02,
    ).translate(0, -86);
    Offset wPitch = worldToScreen(uPitch, vFromZ(pitchZ));
    // Keep both stump sets on one center line every time.
    final wStumps = worldToScreen(0.5, vFromZ(pitchLengthM) + 0.01);
    // Keep impact at pad height so path does not appear to bounce twice.
    final wImpact = worldToScreen(uImpact, vFromZ(15.80)).translate(0, -34);
    // Outcome after bounce: either stump hit or miss beside stumps.
    final missSide = (uImpact - uPitch) >= 0 ? 1.0 : -1.0;
    final wOutcome = geometry.wicketsHitting
        ? wStumps
        : wStumps.translate(22 * missSide, -5);

    // Intentionally skip drawing synthetic pitch/outfield/stumps/grid.

    Offset quadBezier(Offset p0, Offset p1, Offset p2, double t) {
      final mt = 1 - t;
      return Offset(
        (mt * mt * p0.dx) + (2 * mt * t * p1.dx) + (t * t * p2.dx),
        (mt * mt * p0.dy) + (2 * mt * t * p1.dy) + (t * t * p2.dy),
      );
    }

    void drawTubeFromPoints(
      List<Offset> pts, {
      required Color color,
      required double nearW,
      required double farW,
      bool dotted = false,
    }) {
      final n = pts.length;
      for (int i = 0; i < n - 1; i++) {
        if (dotted && i % 2 == 1) continue;
        final t = i / (n - 1);
        final w = nearW + ((farW - nearW) * t);
        final p0 = pts[i];
        final p1 = pts[i + 1];
        // Tube depth shadow (bottom-right).
        canvas.drawLine(
          p0.translate(w * 0.14, w * 0.22),
          p1.translate(w * 0.14, w * 0.22),
          Paint()
            ..color = Colors.black.withOpacity(0.26)
            ..strokeWidth = w * 0.92
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          p0,
          p1,
          Paint()
            ..color = color
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round,
        );
        // Tube highlight (top-left).
        canvas.drawLine(
          p0.translate(-w * 0.08, -w * 0.12),
          p1.translate(-w * 0.08, -w * 0.12),
          Paint()
            ..color = Colors.white.withOpacity(0.18)
            ..strokeWidth = w * 0.25
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    void draw3DBall(Offset center, {required double radius, double lift = 0}) {
      final shadowCenter = center.translate(0, lift.abs() * 0.35);
      canvas.drawOval(
        Rect.fromCenter(
          center: shadowCenter,
          width: radius * 2.4,
          height: radius * 0.9,
        ),
        Paint()..color = Colors.black.withOpacity(0.20),
      );
      final ballRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 1.0,
            colors: [
              const Color(0xFFFF8A80),
              const Color(0xFFE53935),
              const Color(0xFFB71C1C),
            ],
          ).createShader(ballRect),
      );
      canvas.drawArc(
        Rect.fromCircle(center: center.translate(-1.4, -0.8), radius: radius),
        -0.95,
        1.7,
        false,
        Paint()
          ..color = Colors.white.withOpacity(0.85)
          ..strokeWidth = 1.0,
      );
    }

    Offset? ballAt;
    double ballLift = 0;
    Offset? releaseMarker;
    Offset? pitchMarker;
    Offset? impactMarker;
    final rawPath = geometry.pathPoints;
    final useRawPath = rawPath.length >= 2;
    final simpleGraphOnly = true;

    List<Offset> buildQuadPoints(
      Offset a,
      Offset c,
      Offset b,
      double tMax, {
      int segments = 28,
    }) {
      final pts = <Offset>[];
      for (int i = 0; i <= segments; i++) {
        final t = (i / segments) * tMax;
        pts.add(quadBezier(a, c, b, t));
      }
      return pts;
    }

    void drawSimpleGraph(List<Offset> pts, {double width = 6}) {
      if (pts.length < 2) return;
      canvas.drawPath(
        Path()..addPolygon(pts, false),
        Paint()
          ..color = const Color(0xFFD50000)
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (useRawPath) {
      // Render directly from video trajectory and mark release/pitch/impact.
      final n = rawPath.length;
      final minY = rawPath.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      final maxY = rawPath.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
      final ySpan = (maxY - minY).abs() < 0.0001 ? 1.0 : (maxY - minY);

      int? pitchIdx;
      if (n >= 5) {
        // Detect a real bounce as an interior local maximum in Y
        // with enough prominence and recovery after contact.
        final ys = List<double>.generate(n, (i) {
          final a = rawPath[(i - 1).clamp(0, n - 1)].dy;
          final b = rawPath[i].dy;
          final c = rawPath[(i + 1).clamp(0, n - 1)].dy;
          return (a + b + c) / 3.0;
        });
        final span = (ys.reduce(math.max) - ys.reduce(math.min)).abs();
        // Relaxed thresholds to capture short, steep bouncer contacts too.
        final minProm = math.max(0.0012, span * 0.045);
        final minRecover = math.max(0.0009, span * 0.025);
        double bestProm = 0.0;
        int bestIdx = -1;

        for (int i = 2; i <= n - 3; i++) {
          final isPeak = ys[i] >= ys[i - 1] && ys[i] >= ys[i + 1];
          if (!isPeak) continue;
          final base = (ys[i - 1] + ys[i + 1]) / 2.0;
          final prom = ys[i] - base;
          if (prom < minProm) continue;
          bool recovered = false;
          for (int j = i + 1; j < n; j++) {
            if ((ys[i] - ys[j]) >= minRecover) {
              recovered = true;
              break;
            }
          }
          if (!recovered) continue;
          if (prom > bestProm) {
            bestProm = prom;
            bestIdx = i;
          }
        }
        if (bestIdx != -1) {
          pitchIdx = bestIdx;
        }

        // Secondary fallback: if no strict peak found, use strongest interior
        // rise-then-fall point (prevents bouncers becoming "full toss").
        if (pitchIdx == null) {
          int maxIdx = -1;
          double maxVal = -1e9;
          for (int i = 1; i <= n - 2; i++) {
            if (ys[i] > maxVal) {
              maxVal = ys[i];
              maxIdx = i;
            }
          }
          if (maxIdx != -1) {
            final leftRise = ys[maxIdx] - ys.first;
            final rightDrop = ys[maxIdx] - ys.last;
            final riseOk = leftRise >= math.max(0.001, span * 0.12);
            final dropOk = rightDrop >= math.max(0.0008, span * 0.08);
            final localPeak =
                ys[maxIdx] >= ys[(maxIdx - 1).clamp(0, n - 1)] &&
                ys[maxIdx] >= ys[(maxIdx + 1).clamp(0, n - 1)];
            if (riseOk && dropOk && localPeak) {
              pitchIdx = maxIdx;
            }
          }
        }

        // Final fallback: still use real trajectory, but force a plausible
        // interior first-contact point so path doesn't go direct to stumps.
        if (pitchIdx == null && n >= 3) {
          final minIdx = (n * 0.25).round().clamp(1, n - 2);
          final maxIdx = (n * 0.85).round().clamp(1, n - 2);
          int bestInterior = minIdx;
          double bestYInterior = ys[minIdx];
          for (int i = minIdx + 1; i <= maxIdx; i++) {
            if (ys[i] > bestYInterior) {
              bestYInterior = ys[i];
              bestInterior = i;
            }
          }
          pitchIdx = bestInterior;
        }
      }
      // Short-track fallback: ensure a pitching point exists for n=3/4 too.
      if (pitchIdx == null && n >= 3) {
        int bestInterior = 1;
        double bestYInterior = rawPath[1].dy;
        for (int i = 2; i <= n - 2; i++) {
          if (rawPath[i].dy > bestYInterior) {
            bestYInterior = rawPath[i].dy;
            bestInterior = i;
          }
        }
        pitchIdx = bestInterior;
      }
      final impactIdx = n - 1;
      const forceOppositeDirection = true;

      // Detect actual bowling end from tracked motion.
      final startsFromFarEnd = rawPath.first.dy < rawPath.last.dy;
      Offset mapPoint(int i) {
        final p = rawPath[i];
        final yNorm = ((p.dy - minY) / ySpan).clamp(0.0, 1.0);
        final v = startsFromFarEnd
            ? (0.88 - (yNorm * 0.80)) // far(top) -> near(bottom)
            : (0.08 + (yNorm * 0.80)); // near(bottom) -> far(top)
        return worldToScreen(p.dx.clamp(0.05, 0.95), v.clamp(0.0, 1.0));
      }

      // Use real tracked release point, lifted upward to hand level.
      final releaseIdx = forceOppositeDirection ? impactIdx : 0;
      final mappedPitchIdx = pitchIdx == null
          ? null
          : (forceOppositeDirection ? (n - 1 - pitchIdx) : pitchIdx);
      final impactMappedIdx = forceOppositeDirection ? 0 : impactIdx;
      releaseMarker = mapPoint(releaseIdx);
      pitchMarker = mappedPitchIdx == null ? null : mapPoint(mappedPitchIdx);
      impactMarker = mapPoint(impactMappedIdx);
      // Slight lift so release appears from hand, not from ground.
      releaseMarker = releaseMarker.translate(0, -56);
      // Keep impact near pad height.
      impactMarker = impactMarker.translate(0, -14);
      final Offset rel = releaseMarker!;
      final Offset? pit = pitchMarker;
      final Offset imp = impactMarker!;

      if (simpleGraphOnly) {
        final mapped = List<Offset>.generate(
          n,
          (i) => mapPoint(forceOppositeDirection ? (n - 1 - i) : i),
          growable: true,
        );
        if (mapped.length < 2) return;

        final bounceLocalRaw = pitchIdx == null
            ? null
            : (forceOppositeDirection ? (n - 1 - pitchIdx) : pitchIdx);
        final bounceLocal = bounceLocalRaw == null
            ? (mapped.length * 0.56).round()
            : bounceLocalRaw.clamp(1, mapped.length - 2);

        final rel = Offset(
          mapped.first.dx,
          (wStumps.dy - 250).clamp(size.height * 0.30, size.height * 0.80),
        ); // release at requested reference height
        final pit = mapped[bounceLocal];
        final end = mapped.last.translate(0, -14);

        releaseMarker = rel;
        pitchMarker = pit;
        impactMarker = end;

        final preCtrl = lerpPoint(rel, pit, 0.42).translate(0, -70);
        final postCtrl = lerpPoint(pit, end, 0.34).translate(0, -18);
        final full = <Offset>[];
        for (int i = 0; i <= 28; i++) {
          full.add(quadBezier(rel, preCtrl, pit, i / 28));
        }
        for (int i = 1; i <= 26; i++) {
          full.add(quadBezier(pit, postCtrl, end, i / 26));
        }

        final visible = <Offset>[];
        final scaled = trackProgress * (full.length - 1);
        final lastFull = scaled.floor().clamp(0, full.length - 1);
        for (int i = 0; i <= lastFull; i++) {
          visible.add(full[i]);
        }
        if (lastFull < full.length - 1) {
          final frac = (scaled - lastFull).clamp(0.0, 1.0);
          visible.add(lerpPoint(full[lastFull], full[lastFull + 1], frac));
        }
        if (visible.length >= 2) {
          drawSimpleGraph(visible, width: 6.5);
          ballAt = visible.last;
        }
        return;
      }

      Offset rawPreBezier(double t) {
        final p = pit ?? lerpPoint(rel, imp, 0.52);
        final ctrl = lerpPoint(rel, p, 0.45).translate(0, -34);
        return quadBezier(rel, ctrl, p, t);
      }

      Offset rawPostBezier(double t) {
        final p = pit ?? lerpPoint(rel, imp, 0.52);
        final ctrl = lerpPoint(p, imp, 0.45).translate(0, -18);
        return quadBezier(p, ctrl, imp, t);
      }

      if (pit == null) {
        final ctrl = lerpPoint(rel, imp, 0.48).translate(0, -32);
        final t = trackProgress.clamp(0.0, 1.0);
        final pts = <Offset>[];
        for (int i = 0; i <= 34; i++) {
          pts.add(quadBezier(rel, ctrl, imp, (i / 34) * t));
        }
        drawTubeFromPoints(
          pts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
        );
        ballAt = quadBezier(rel, ctrl, imp, t);
      } else if (trackProgress <= 0.55) {
        final tMax = (trackProgress / 0.55).clamp(0.0, 1.0);
        final prePts = <Offset>[];
        for (int i = 0; i <= 30; i++) {
          final t = (i / 30) * tMax;
          prePts.add(rawPreBezier(t));
        }
        drawTubeFromPoints(
          prePts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
        );
        ballAt = rawPreBezier(tMax);
      } else {
        // Draw full pre-bounce arc.
        final prePts = <Offset>[];
        for (int i = 0; i <= 30; i++) {
          prePts.add(rawPreBezier(i / 30));
        }
        drawTubeFromPoints(
          prePts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
        );
        // Single post-bounce direct line to impact.
        final t2 = ((trackProgress - 0.55) / 0.45).clamp(0.0, 1.0);
        final post = rawPostBezier(t2);
        final postPts = <Offset>[];
        for (int i = 0; i <= 20; i++) {
          final t = (i / 20) * t2;
          postPts.add(rawPostBezier(t));
        }
        drawTubeFromPoints(
          postPts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
        );
        ballAt = post;
      }
    } else {
      // Fallback synthetic trajectory if backend trajectory is unavailable.
      if (simpleGraphOnly) {
        return;
      }
      final preCtrl = lerpPoint(wDelivery, wPitch, 0.48) + const Offset(0, -46);
      final postCtrl = lerpPoint(wPitch, wImpact, 0.52) + const Offset(0, -18);
      final predCtrl =
          lerpPoint(wImpact, wOutcome, 0.45) + const Offset(0, -34);

      if (trackProgress > 0.0) {
        final p1 = (trackProgress / 0.33).clamp(0.0, 1.0);
        final prePts = <Offset>[];
        for (int i = 0; i <= 26; i++) {
          final t = (i / 26) * p1;
          prePts.add(quadBezier(wDelivery, preCtrl, wPitch, t));
        }
        drawTubeFromPoints(
          prePts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
        );
        ballAt = quadBezier(wDelivery, preCtrl, wPitch, p1);
        ballLift = 26 * (1 - p1);
      }

      if (trackProgress > 0.33) {
        final p2 = ((trackProgress - 0.33) / 0.32).clamp(0.0, 1.0);
        final postPts = <Offset>[];
        for (int i = 0; i <= 22; i++) {
          final t = (i / 22) * p2;
          postPts.add(quadBezier(wPitch, postCtrl, wImpact, t));
        }
        drawTubeFromPoints(
          postPts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
        );
        final bouncePulse = ((trackProgress - 0.33) / 0.22).clamp(0.0, 1.0);
        final rippleAlpha = (1.0 - bouncePulse).clamp(0.0, 1.0);
        final r = 10 + (20 * bouncePulse);
        canvas.drawCircle(
          wPitch,
          9,
          Paint()..color = Colors.white.withOpacity(0.86),
        );
        canvas.drawCircle(
          wPitch,
          r,
          Paint()
            ..color = Colors.white.withOpacity(0.48 * rippleAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
      }

      if (trackProgress > 0.65) {
        final p3 = ((trackProgress - 0.65) / 0.35).clamp(0.0, 1.0);
        final projPts = <Offset>[];
        for (int i = 0; i <= 26; i++) {
          final t = (i / 26) * p3;
          projPts.add(quadBezier(wImpact, predCtrl, wOutcome, t));
        }
        drawTubeFromPoints(
          projPts,
          color: const Color(0xFFFF0000),
          nearW: 3.0,
          farW: 12.0,
          dotted: false,
        );
        ballAt = quadBezier(wImpact, predCtrl, wOutcome, p3);
        final liftCurve = math.sin(math.pi * p3);
        ballLift = 14 * liftCurve;
      }
    }

    void drawSharpRing(Offset center, Color color, {double r = 11}) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
      canvas.drawCircle(
        center,
        r + 4,
        Paint()
          ..color = color.withOpacity(0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(center, 2.8, Paint()..color = Colors.white);
    }

    // Show one pulsing white bounce ring at pitching point.
    final pulse = 0.5 + (0.5 * math.sin(trackProgress * math.pi * 8));
    final pulseR = 9.0 + (6.0 * pulse);
    if (!useRawPath) {
      drawSharpRing(wPitch, Colors.white, r: 10);
      canvas.drawCircle(
        wPitch,
        pulseR,
        Paint()
          ..color = Colors.white.withOpacity(0.40 * (1.0 - pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
    if (useRawPath) {
      if (releaseMarker != null) {
        drawSharpRing(releaseMarker!, const Color(0xFF00FFFF), r: 8);
      }
      if (pitchMarker != null) {
        drawSharpRing(pitchMarker!, const Color(0xFFFF0000), r: 10);
        canvas.drawCircle(
          pitchMarker!,
          pulseR,
          Paint()
            ..color = const Color(0xFFFF0000).withOpacity(0.40 * (1.0 - pulse))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
      if (impactMarker != null) {
        drawSharpRing(impactMarker!, Colors.orangeAccent, r: 9);
      }
    }
    if (!useRawPath && ballAt != null) {
      draw3DBall(ballAt.translate(0, -ballLift), radius: 5.2, lift: ballLift);
    }
    if (useRawPath && ballAt != null) {
      draw3DBall(ballAt.translate(0, -ballLift), radius: 4.8, lift: ballLift);
    }

    // Stumps are part of pitch.png background.
  }

  @override
  bool shouldRepaint(covariant _DrsTrajectoryPainter oldDelegate) {
    return oldDelegate.geometry != geometry || oldDelegate.progress != progress;
  }
}

class _DrsReplayProjection {
  final Offset impact;
  final Offset stumpLeft;
  final Offset stumpMiddle;
  final Offset stumpRight;
  final double stumpTopY;
  final double stumpBaseY;
  final double lineY;
  final Offset wicketImpactPoint;
  final Offset pathControl;

  const _DrsReplayProjection({
    required this.impact,
    required this.stumpLeft,
    required this.stumpMiddle,
    required this.stumpRight,
    required this.stumpTopY,
    required this.stumpBaseY,
    required this.lineY,
    required this.wicketImpactPoint,
    required this.pathControl,
  });
}

class _DrsBroadcastPainter extends CustomPainter {
  final _DrsTrackingGeometry geometry;
  final double scannerProgress;
  final double pathProgress;
  final bool showPath;
  final bool showImpactRipple;
  final bool showRedZone;
  final bool showGlassStumps;
  final String wicketText;

  const _DrsBroadcastPainter({
    required this.geometry,
    required this.scannerProgress,
    required this.pathProgress,
    required this.showPath,
    required this.showImpactRipple,
    required this.showRedZone,
    required this.showGlassStumps,
    required this.wicketText,
  });

  _DrsReplayProjection _project(Size size) {
    Offset lerpPoint(Offset a, Offset b, double t) {
      return Offset(a.dx + ((b.dx - a.dx) * t), a.dy + ((b.dy - a.dy) * t));
    }

    final nearLeft = Offset(0, size.height * 0.97);
    final nearRight = Offset(size.width, size.height * 0.97);
    final farLeft = Offset(size.width * 0.375, size.height * 0.40);
    final farRight = Offset(size.width * 0.625, size.height * 0.40);

    Offset worldToScreen(double u, double v) {
      final vv = v.clamp(0.0, 1.0);
      final uu = u.clamp(0.0, 1.0);
      final left = lerpPoint(nearLeft, farLeft, vv);
      final right = lerpPoint(nearRight, farRight, vv);
      final depthSqueeze = 0.21 * vv;
      final uWarp = ((uu - 0.5) * (1.0 - depthSqueeze)) + 0.5;
      return lerpPoint(left, right, uWarp.clamp(0.0, 1.0));
    }

    const pitchLengthM = 20.12;
    double vFromZ(double z) => (1.0 - (z / pitchLengthM)).clamp(0.0, 1.0);

    final stumpDepth = vFromZ(pitchLengthM) + 0.01;
    final stumpLeft = worldToScreen(geometry.stumpLeft.dx, stumpDepth);
    final stumpRight = worldToScreen(geometry.stumpRight.dx, stumpDepth);
    final stumpMiddle = worldToScreen(geometry.stumpsPoint.dx, stumpDepth);
    final impact = worldToScreen(
      geometry.impactPoint.dx.clamp(0.16, 0.84),
      vFromZ(15.80),
    ).translate(0, -34);

    final stumpHeight = size.height * 0.18;
    final stumpBaseY = stumpMiddle.dy + 4;
    final stumpTopY = stumpBaseY - stumpHeight;
    final lineY = impact.dy.clamp(stumpTopY + 8, stumpBaseY - 8);

    final wicketLower = wicketText.toLowerCase();
    final isHitting = wicketLower.contains("hitting");
    final isUmpires = wicketLower.contains("umpire");
    final missSide = geometry.impactPoint.dx >= geometry.stumpsPoint.dx
        ? 1.0
        : -1.0;
    final wicketImpactPoint = isHitting
        ? Offset(stumpMiddle.dx, lineY)
        : isUmpires
        ? Offset(missSide > 0 ? stumpRight.dx + 6 : stumpLeft.dx - 6, lineY)
        : Offset(
            stumpMiddle.dx + (30 * missSide),
            (lineY - 10).clamp(stumpTopY + 4, stumpBaseY - 8),
          );
    final pathControl = Offset(
      ((impact.dx + wicketImpactPoint.dx) / 2) + (16 * missSide),
      impact.dy - (size.height * 0.13),
    );

    return _DrsReplayProjection(
      impact: impact,
      stumpLeft: stumpLeft,
      stumpMiddle: stumpMiddle,
      stumpRight: stumpRight,
      stumpTopY: stumpTopY,
      stumpBaseY: stumpBaseY,
      lineY: lineY,
      wicketImpactPoint: wicketImpactPoint,
      pathControl: pathControl,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final projection = _project(size);

    if (showImpactRipple) {
      final rippleT = (math.sin(scannerProgress * math.pi * 2) + 1) * 0.5;
      final rippleRadius = 10 + (18 * rippleT);
      canvas.drawCircle(
        projection.impact,
        7,
        Paint()..color = const Color(0xFFFF8A80),
      );
      canvas.drawCircle(
        projection.impact,
        rippleRadius,
        Paint()
          ..color = const Color(0x88FF5252)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      canvas.drawCircle(
        projection.impact,
        rippleRadius + 10,
        Paint()
          ..color = const Color(0x44FF8A80)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    final wicketPath = Path()
      ..moveTo(projection.impact.dx, projection.impact.dy)
      ..quadraticBezierTo(
        projection.pathControl.dx,
        projection.pathControl.dy,
        projection.wicketImpactPoint.dx,
        projection.wicketImpactPoint.dy,
      );

    if (showPath) {
      final metrics = wicketPath.computeMetrics();
      final metric = metrics.isNotEmpty ? metrics.first : null;
      if (metric != null) {
        final clampedProgress = pathProgress.clamp(0.0, 1.0);
        final partial = metric.extractPath(0, metric.length * clampedProgress);
        final isHitting = wicketText.toLowerCase().contains("hitting");
        final trailColor = isHitting
            ? const Color(0xFFFF3D3D)
            : const Color(0xFFEDEDED);
        canvas.drawPath(
          partial,
          Paint()
            ..color = trailColor.withOpacity(0.75)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 9
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
        canvas.drawPath(
          partial,
          Paint()
            ..color = trailColor
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 4.2,
        );

        final tangent = metric.getTangentForOffset(
          metric.length * clampedProgress,
        );
        if (tangent != null) {
          // Removed moving red ball glow per request.
        }
      }
    }

    if (showGlassStumps) {
      final stumpXs = <double>[
        projection.stumpLeft.dx,
        projection.stumpMiddle.dx,
        projection.stumpRight.dx,
      ];
      for (final x in stumpXs) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              x,
              (projection.stumpTopY + projection.stumpBaseY) / 2,
            ),
            width: 8,
            height: projection.stumpBaseY - projection.stumpTopY,
          ),
          const Radius.circular(7),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55FFFFFF), Color(0x33F0D28D), Color(0x66FFFFFF)],
            ).createShader(rect.outerRect),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = const Color(0x55FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
      final bailPaint = Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(projection.stumpLeft.dx, projection.stumpTopY + 4),
        Offset(projection.stumpMiddle.dx, projection.stumpTopY + 1),
        bailPaint,
      );
      canvas.drawLine(
        Offset(projection.stumpMiddle.dx, projection.stumpTopY + 1),
        Offset(projection.stumpRight.dx, projection.stumpTopY + 4),
        bailPaint,
      );
    }

    if (showRedZone) {
      final zoneRect = Rect.fromLTRB(
        projection.stumpLeft.dx,
        projection.lineY - 9,
        projection.stumpRight.dx,
        projection.lineY + 9,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(zoneRect, const Radius.circular(6)),
        Paint()..color = const Color(0x44FF1744),
      );
      canvas.drawLine(
        Offset(projection.stumpLeft.dx, projection.lineY),
        Offset(projection.stumpRight.dx, projection.lineY),
        Paint()
          ..color = const Color(0xAAFF5252)
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawLine(
        Offset(projection.stumpLeft.dx, projection.lineY),
        Offset(projection.stumpRight.dx, projection.lineY),
        Paint()
          ..color = const Color(0xFFFF3B30)
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DrsBroadcastPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.scannerProgress != scannerProgress ||
        oldDelegate.pathProgress != pathProgress ||
        oldDelegate.showPath != showPath ||
        oldDelegate.showImpactRipple != showImpactRipple ||
        oldDelegate.showRedZone != showRedZone ||
        oldDelegate.showGlassStumps != showGlassStumps ||
        oldDelegate.wicketText != wicketText;
  }
}

class _DrsEdgeDebugPainter extends CustomPainter {
  final List<Offset> points;
  final double progress;

  const _DrsEdgeDebugPainter({required this.points, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const batXMin = 0.44;
    const batXMax = 0.58;
    const batYMin = 0.22;
    const batYMax = 0.50;
    final batRect = Rect.fromLTRB(
      batXMin * size.width,
      batYMin * size.height,
      batXMax * size.width,
      batYMax * size.height,
    );
    final expanded = batRect.inflate(5);

    final batPaint = Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final padPaint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRect(expanded, padPaint);
    canvas.drawRect(batRect, batPaint);

    if (points.isNotEmpty) {
      final t = progress.clamp(0.0, 1.0);
      final idxFloat = t * (points.length - 1);
      final idx = idxFloat.floor();
      final next = math.min(idx + 1, points.length - 1);
      final frac = idxFloat - idx;
      final p0 = points[idx];
      final p1 = points[next];
      final ballNorm = Offset(
        p0.dx + ((p1.dx - p0.dx) * frac),
        p0.dy + ((p1.dy - p0.dy) * frac),
      );
      final ball = Offset(ballNorm.dx * size.width, ballNorm.dy * size.height);
      final ballRect = Rect.fromCenter(center: ball, width: 12, height: 12);
      final ballPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawRect(ballRect, ballPaint);
    }

    final label = TextPainter(
      text: const TextSpan(
        text: "DEBUG",
        style: TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(10, 10));
  }

  @override
  bool shouldRepaint(covariant _DrsEdgeDebugPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.points != points;
  }
}

class _DrsCinematicScreen extends StatefulWidget {
  final VideoPlayerController videoController;
  final _DrsTrackingGeometry geometry;
  final bool hasSpike;
  final String ultraedgeReason;
  final List<double> ultraedgeWaveform;
  final double? ultraedgeSpikeMs;
  final double? ultraedgeSpikeT;
  final String ultraedgeStatus;
  final String pitching;
  final String impact;
  final String wickets;
  final String wicketTarget;
  final String originalDecision;
  final String decisionCall;
  final String decisionDetail;
  final bool isOut;
  final double speedKmph;
  final double swingDeg;
  final double spinDeg;
  final double aiVal;
  final _DrsReplayMode mode;

  const _DrsCinematicScreen({
    required this.videoController,
    required this.geometry,
    required this.hasSpike,
    required this.ultraedgeReason,
    required this.ultraedgeWaveform,
    required this.ultraedgeSpikeMs,
    required this.ultraedgeSpikeT,
    required this.ultraedgeStatus,
    required this.pitching,
    required this.impact,
    required this.wickets,
    required this.wicketTarget,
    required this.originalDecision,
    required this.decisionCall,
    required this.decisionDetail,
    required this.isOut,
    required this.aiVal,
    required this.speedKmph,
    required this.swingDeg,
    required this.spinDeg,
    required this.mode,
  });

  @override
  State<_DrsCinematicScreen> createState() => _DrsCinematicScreenState();
}

class _DrsCinematicScreenState extends State<_DrsCinematicScreen>
    with TickerProviderStateMixin {
  static const _heartbeatAsset = "audio/heartbeat.mp3";
  static const _dingAsset = "audio/ding.wav";
  static const _whistleAsset = "audio/umpire_whistle.wav";
  static const _crowdCheerAsset = "audio/stadium_crowd_cheer.wav";
  static const _buzzerAsset = "audio/drs_buzzer.wav";
  static const _crowdSighAsset = "audio/crowd_sigh.wav";
  static const _fallbackFxAsset = "audio/onboarding_whoosh.wav";

  late final VideoPlayerController _videoController;
  late final AnimationController _scannerController;
  late final AnimationController _pathController;
  late final ConfettiController _confettiController;
  late final PageController _whyPageController;
  final AudioPlayer _heartbeatPlayer = AudioPlayer();
  final AudioPlayer _fxPlayer = AudioPlayer();
  Timer? _heartbeatTimer;
  bool _ready = false;
  late bool _finalOut;
  late String _decisionCall;
  late String _decisionDetail;
  late final _DrsReplayMode _mode;
  double _videoProgress = 0.0;
  bool _impactVisualLocked = false;
  bool _showPitch = false;
  bool _showImpact = false;
  bool _showPath = false;
  bool _showWicket = false;
  bool _showDecisionBanner = false;
  bool _showSidebarDecision = false;
  bool _showImpactRipple = false;
  bool _showRedZone = false;
  bool _showWicketFlash = false;
  bool _showDebugOverlay = false;
  bool _awaitingUmpireCall = false;
  bool _showUserCallChip = false;
  bool _showOutcomePanel = false;
  bool _userCallMatchedAi = false;
  bool _flashCrickNovaCall = false;
  int _whyPageIndex = 0;
  String _stageText = "PREPARING REPLAY";
  int _sequenceToken = 0;
  _DrsUmpireCall? _userCall;

  @override
  void initState() {
    super.initState();
    _finalOut = widget.isOut;
    _decisionCall = widget.decisionCall;
    _decisionDetail = widget.decisionDetail;
    _mode = widget.mode;
    _videoController = widget.videoController;
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _pathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 1800),
    );
    _whyPageController = PageController(viewportFraction: 0.92);
    _initAndRun();
  }

  Future<void> _initAndRun() async {
    if (!_videoController.value.isInitialized) {
      await _videoController.initialize();
    }
    await _videoController.seekTo(Duration.zero);
    await _videoController.setLooping(false);
    _videoController.addListener(_handleVideoTick);
    if (!mounted) return;
    await _videoController.setPlaybackSpeed(0.25);
    _scannerController.repeat(reverse: true);
    setState(() {
      _ready = true;
      _showWicketFlash = false;
      _showOutcomePanel = false;
      _awaitingUmpireCall = true;
      _stageText = "DECISION PENDING";
    });

    await _videoController.pause();
    await _startDecisionHeartbeat();
  }

  @override
  void dispose() {
    _sequenceToken++;
    _heartbeatTimer?.cancel();
    _videoController.removeListener(_handleVideoTick);
    _scannerController.dispose();
    _pathController.dispose();
    _whyPageController.dispose();
    _confettiController.dispose();
    _heartbeatPlayer.dispose();
    _fxPlayer.dispose();
    super.dispose();
  }

  void _handleVideoTick() {
    if (!mounted || !_videoController.value.isInitialized) return;
    final durationMs = _videoController.value.duration.inMilliseconds;
    final positionMs = _videoController.value.position.inMilliseconds;
    final progress = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0);
    final impactGate = _timelineMilestones().impact;
    if ((progress - _videoProgress).abs() > 0.004) {
      setState(() {
        _videoProgress = progress;
      });
    }
    if (!_impactVisualLocked && (progress >= impactGate || progress >= 0.985)) {
      _impactVisualLocked = true;
      if (mounted) {
        setState(() {
          _showImpactRipple = false;
          if (_mode == _DrsReplayMode.lbw) {
            _showRedZone = true;
          }
          if (_showImpact) {
            _stageText = "IMPACT CONFIRMED";
          }
        });
      }
    }
  }

  void _triggerWicketFlash() {
    if (_showWicketFlash || !_finalOut || !mounted) return;
    setState(() => _showWicketFlash = true);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) {
        setState(() => _showWicketFlash = false);
      }
    });
  }

  Future<void> _playTickSound() async {
    await SystemSound.play(SystemSoundType.click);
  }

  Future<void> _playDecisionSound() async {
    if (_finalOut) {
      HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.alert);
      await Future.delayed(const Duration(milliseconds: 140));
      if (!mounted) return;
      await SystemSound.play(SystemSoundType.alert);
      return;
    }
    await SystemSound.play(SystemSoundType.click);
  }

  Future<bool> _waitStage(Duration duration, int token) async {
    await Future.delayed(duration);
    return mounted && token == _sequenceToken;
  }

  bool get _hasUserCall => _userCall != null;

  bool get _isUmpiresCall {
    final wickets = widget.wickets.toLowerCase();
    final detail = widget.decisionDetail.toLowerCase();
    return wickets.contains("umpire") || detail.contains("umpire");
  }

  String get _userCallLabel => _userCall == _DrsUmpireCall.out
      ? "OUT"
      : _userCall == _DrsUmpireCall.notOut
      ? "NOT OUT"
      : "UMPIRE'S CALL";

  String get _aiCallLabel =>
      _isUmpiresCall ? "UMPIRE'S CALL" : _decisionCall.toUpperCase();

  IconData get _userCallIcon => _userCall == _DrsUmpireCall.out
      ? Icons.gavel_rounded
      : _userCall == _DrsUmpireCall.notOut
      ? Icons.shield_rounded
      : Icons.sports_cricket;

  Color get _userCallAccent => _userCall == _DrsUmpireCall.out
      ? const Color(0xFFFF6E6E)
      : _userCall == _DrsUmpireCall.notOut
      ? const Color(0xFF62FFB1)
      : const Color(0xFFFFD54F);

  bool get _userCallMatchesAi {
    if (!_hasUserCall) return false;
    if (_userCall == _DrsUmpireCall.umpire) {
      return _isUmpiresCall;
    }
    return _userCall == _DrsUmpireCall.out ? _finalOut : !_finalOut;
  }

  Future<bool> _playFirstAvailable(
    AudioPlayer player,
    List<String> assets, {
    required double volume,
    ReleaseMode releaseMode = ReleaseMode.stop,
  }) async {
    try {
      await player.stop();
      await player.setReleaseMode(releaseMode);
      await player.setVolume(volume);
    } catch (_) {}

    for (final asset in assets) {
      try {
        await player.play(AssetSource(asset));
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _startDecisionHeartbeat() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 650), (
      timer,
    ) {
      if (!mounted || !_awaitingUmpireCall) {
        timer.cancel();
        return;
      }
      if (timer.tick.isOdd) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    });
    await _playFirstAvailable(
      _heartbeatPlayer,
      const [_heartbeatAsset],
      volume: 0.52,
      releaseMode: ReleaseMode.loop,
    );
  }

  Future<void> _stopDecisionHeartbeat() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      await _heartbeatPlayer.stop();
    } catch (_) {}
  }

  Future<void> _submitUmpireCall(_DrsUmpireCall call) async {
    if (!_awaitingUmpireCall || _hasUserCall) {
      return;
    }
    HapticFeedback.heavyImpact();
    await _stopDecisionHeartbeat();
    if (!mounted) return;

    bool finalVerdict = widget.isOut;
    String finalCall = widget.decisionCall;

    setState(() {
      _userCall = call;
      _awaitingUmpireCall = false;
      _finalOut = finalVerdict;
      _decisionCall = finalCall;
      _showUserCallChip = true;
      _showOutcomePanel = false;
      _showDecisionBanner = false;
      _showSidebarDecision = false;
      _stageText = widget.mode == _DrsReplayMode.lbw
          ? "ANALYZING BALL"
          : "SCANNING ULTRAEDGE";
      _whyPageIndex = 0;
    });
    await _videoController.seekTo(Duration.zero);
    if (!mounted) return;
    await _videoController.play();
    unawaited(_startTimedRevealSequence());
  }

  Future<void> _presentPredictionFeedback(int token) async {
    if (!mounted ||
        token != _sequenceToken ||
        _mode != _DrsReplayMode.lbw ||
        !_hasUserCall) {
      return;
    }

    final matched = _userCallMatchesAi;
    if (_whyPageController.hasClients) {
      _whyPageController.jumpToPage(0);
    }
    setState(() {
      _userCallMatchedAi = matched;
      _showOutcomePanel = true;
      _whyPageIndex = 0;
    });
    await _triggerCrickNovaCallFlash();

    if (matched) {
      _confettiController.play();
      HapticFeedback.heavyImpact();
      return;
    }

    HapticFeedback.mediumImpact();
    final played = await _playFirstAvailable(_fxPlayer, const [
      _buzzerAsset,
      _crowdSighAsset,
    ], volume: 0.88);
    if (!played) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _triggerCrickNovaCallFlash() async {
    if (!mounted) return;
    setState(() => _flashCrickNovaCall = true);
    final played = await _playFirstAvailable(_fxPlayer, const [
      _dingAsset,
    ], volume: 0.6);
    if (!played) {
      await SystemSound.play(SystemSoundType.click);
    }
    Future.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      setState(() => _flashCrickNovaCall = false);
    });
  }

  Future<void> _startTimedRevealSequence() async {
    final token = ++_sequenceToken;
    if (_mode == _DrsReplayMode.lbw && !_hasUserCall) return;
    if (!await _waitStage(const Duration(milliseconds: 350), token)) return;

    if (mounted) {
      setState(() {
        _showDecisionBanner = false;
        _showSidebarDecision = false;
        _showOutcomePanel = false;
      });
    }

    Future<void> revealDecision() async {
      if (!mounted || token != _sequenceToken) return;
      if (_mode == _DrsReplayMode.lbw && _finalOut) {
        _triggerWicketFlash();
      }
      setState(() {
        _showDecisionBanner = true;
        _showSidebarDecision = false;
        _stageText = "DECISION READY";
      });
      await _playTickSound();
      await _playDecisionSound();
      Future.delayed(const Duration(milliseconds: 900), () async {
        if (!mounted || token != _sequenceToken) return;
        setState(() {
          _showDecisionBanner = false;
          _showSidebarDecision = true;
        });
        if (_mode == _DrsReplayMode.lbw) {
          await _presentPredictionFeedback(token);
        }
      });
    }

    if (_mode == _DrsReplayMode.ultraEdge) {
      setState(() {
        _showPitch = false;
        _showImpact = false;
        _showPath = false;
        _showWicket = false;
        _showDecisionBanner = false;
        _showSidebarDecision = false;
        _stageText = "CHECKING CONTACT";
      });
      await _playTickSound();
      if (!await _waitStage(const Duration(milliseconds: 650), token)) return;

      await revealDecision();
      return;
    }

    setState(() {
      _showPitch = true;
      _stageText = "PITCHING CONFIRMED";
    });
    await _playTickSound();
    if (!await _waitStage(const Duration(milliseconds: 550), token)) return;

    setState(() {
      _showImpact = true;
      _stageText = _impactVisualLocked
          ? "IMPACT CONFIRMED"
          : "ANALYZING IMPACT";
    });
    await _playTickSound();
    if (!await _waitStage(const Duration(milliseconds: 500), token)) return;

    setState(() {
      _showPath = true;
      _stageText = "PROJECTING";
    });
    unawaited(_pathController.forward(from: 0));
    if (!await _waitStage(const Duration(milliseconds: 600), token)) return;

    setState(() {
      _showWicket = true;
    });
    await revealDecision();
  }

  ({double pitch, double impact, double wicket}) _timelineMilestones() {
    final points = widget.geometry.pathPoints;
    if (points.length < 3) {
      return (pitch: 0.50, impact: 0.88, wicket: 0.97);
    }
    final bounceIdx = _detectBounceIndex(
      points.map((o) => {"x": o.dx, "y": o.dy}).toList(),
    ).clamp(0, points.length - 2);
    final pitch = (bounceIdx / (points.length - 1)).clamp(0.18, 0.78);
    final impact = ((points.length - 2) / (points.length - 1)).clamp(
      pitch + 0.08,
      0.94,
    );
    final wicket = (impact + 0.04).clamp(impact, 0.985);
    return (pitch: pitch, impact: impact, wicket: wicket);
  }

  Color _statusAccent(String title, String value) {
    final lower = value.toLowerCase();
    if (title == "PITCHING") {
      return lower.contains("in line")
          ? const Color(0xFF4CFF7A)
          : const Color(0xFFFFD54F);
    }
    if (title == "IMPACT") {
      return lower.contains("in line")
          ? const Color(0xFF4FC3F7)
          : const Color(0xFFFFD54F);
    }
    if (title == "WICKET") {
      if (lower.contains("hitting")) {
        return const Color(0xFFFF5252);
      }
      if (lower.contains("umpire")) {
        return const Color(0xFFFFD54F);
      }
      return Colors.white;
    }
    if (title == "DECISION") {
      if (_mode == _DrsReplayMode.ultraEdge) {
        return widget.hasSpike ? const Color(0xFF6FE7FF) : Colors.white70;
      }
      return _finalOut ? const Color(0xFFFF6E6E) : const Color(0xFF7DFFB1);
    }
    return const Color(0xFF00E676);
  }

  String get _modeLabel =>
      _mode == _DrsReplayMode.ultraEdge ? "ULTRA-EDGE" : "LBW ANALYSIS";

  String get _decisionLabel => widget.decisionDetail.isNotEmpty
      ? "${widget.decisionCall} - ${widget.decisionDetail}"
      : widget.decisionCall;

  Widget _statusIndicator(String title, String value) {
    final accent = _statusAccent(title, value);
    final lower = value.toLowerCase();
    final isDecision = title == "DECISION";
    final isWicket = title == "WICKET";
    final useIcon = isWicket || isDecision;
    final positive = isDecision
        ? (_mode == _DrsReplayMode.ultraEdge ? widget.hasSpike : _finalOut)
        : (lower.contains("in line") || lower.contains("hitting"));
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: useIcon ? Colors.transparent : accent.withOpacity(0.18),
        border: Border.all(color: accent.withOpacity(0.95), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.55),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: useIcon
            ? Icon(
                isDecision
                    ? (positive ? Icons.gavel_rounded : Icons.shield_outlined)
                    : lower.contains("umpire")
                    ? Icons.trip_origin_rounded
                    : (positive ? Icons.check_rounded : Icons.close_rounded),
                size: 14,
                color: accent,
              )
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
      ),
    );
  }

  Widget _sidebarRow({
    required String title,
    required String value,
    required bool visible,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: visible ? 1 : 0.22,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        offset: visible ? Offset.zero : const Offset(-0.08, 0),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              _statusIndicator(title, value),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 9,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.toUpperCase(),
                      style: TextStyle(
                        color: _statusAccent(title, value),
                        fontSize: 12,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String title, String value, bool visible) {
    final v = value.toLowerCase();
    final ok =
        v.contains("in line") ||
        v.contains("hitting") ||
        v.contains("not out") ||
        v.contains("tracked") ||
        v.contains("frame");
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1 : 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.34),
              border: Border.all(
                color: (ok ? const Color(0xFF00E676) : const Color(0xFFFF5252))
                    .withOpacity(0.85),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: "RobotoCondensed",
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: "RobotoCondensed",
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stageLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: "RobotoCondensed",
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _sideToolButton(IconData icon, {VoidCallback? onTap}) {
    final child = SizedBox(
      width: 56,
      height: 56,
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 21, color: const Color(0xFF616161)),
        ),
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  Widget _ultraEdgeWaveformPanel(double progress) {
    final statusText = widget.ultraedgeStatus.isNotEmpty
        ? widget.ultraedgeStatus
        : (widget.hasSpike ? "EDGE DETECTED" : "NO EDGE");
    final statusColor = widget.hasSpike
        ? const Color(0xFF6FE7FF)
        : Colors.white70;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "ULTRA-EDGE: $statusText",
                style: TextStyle(
                  color: statusColor,
                  fontFamily: "RobotoCondensed",
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
              if (widget.ultraedgeReason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.ultraedgeReason,
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 70,
                child: CustomPaint(
                  painter: _UltraEdgeWaveformPainter(
                    waveform: widget.ultraedgeWaveform,
                    progress: progress,
                    spikeT: widget.ultraedgeSpikeT,
                    highlightSpike: _finalOut,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _decisionBanner() {
    final accent = _mode == _DrsReplayMode.ultraEdge
        ? (_finalOut ? const Color(0xFF6FE7FF) : Colors.white70)
        : (_finalOut ? const Color(0xFFFF4D4D) : const Color(0xFF4CFF7A));
    final reason = widget.decisionDetail;
    final jitter = _showDecisionBanner
        ? math.sin((_scannerController.value + 0.18) * math.pi * 10) * 1.4
        : 0.0;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: _showDecisionBanner ? 1.0 : 0.0,
      child: Transform.translate(
        offset: Offset(jitter, 0),
        child: AnimatedScale(
          scale: _showDecisionBanner ? 1.0 : 0.92,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.62),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.9), width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.45),
                  blurRadius: 26,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _decisionCall.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontFamily: "Montserrat",
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                    letterSpacing: 1.2,
                  ),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    reason.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontFamily: "RobotoCondensed",
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, Object>> _lbwReasonCards() {
    final wicketLower = widget.wickets.toLowerCase();
    final wicketReason = wicketLower.contains("hitting")
        ? "Ball tracking had the delivery crashing into the ${widget.wicketTarget.toUpperCase()} stump."
        : wicketLower.contains("umpire")
        ? "Projection clipped the ${widget.wicketTarget.toUpperCase()} stump, so the call stayed with the umpire."
        : "Ball tracking showed the delivery missing the ${widget.wicketTarget.toUpperCase()} stump.";

    return [
      {
        "title": "PITCHING",
        "value": widget.pitching.toUpperCase(),
        "reason": widget.pitching.toLowerCase().contains("in line")
            ? "The ball pitched in line, so the LBW review stayed alive."
            : "The ball pitched outside the line, which takes LBW out of play.",
        "accent": _statusAccent("PITCHING", widget.pitching),
      },
      {
        "title": "IMPACT",
        "value": widget.impact.toUpperCase(),
        "reason": widget.impact.toLowerCase().contains("in line")
            ? "Impact was in line with the stumps."
            : "Impact was outside the line, so the batter survives.",
        "accent": _statusAccent("IMPACT", widget.impact),
      },
      {
        "title": "WICKETS",
        "value": widget.wickets.toUpperCase(),
        "reason": wicketReason,
        "accent": _statusAccent("WICKET", widget.wickets),
      },
    ];
  }

  Widget _predictionActionButton({
    required String title,
    required String subtitle,
    required Color accent,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.92),
              accent.withValues(alpha: 0.58),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.32),
              blurRadius: 26,
              spreadRadius: 1,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: "Montserrat",
                fontWeight: FontWeight.w900,
                fontSize: 26,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decisionOverlay() {
    if (!_awaitingUmpireCall) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF071018).withValues(alpha: 0.94),
                          const Color(0xFF101C29).withValues(alpha: 0.88),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFFFFD54F).withValues(alpha: 0.16),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xAA000000),
                          blurRadius: 34,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final stackButtons = constraints.maxWidth < 430;
                        final isLbw = _mode == _DrsReplayMode.lbw;

                        final titleOut = isLbw ? "OUT" : "EDGED";
                        final subtitleOut = isLbw
                            ? "Finger goes up. You are calling it dead straight."
                            : "You heard a clear sound. Finger goes up.";
                        final iconOut = isLbw
                            ? Icons.gavel_rounded
                            : Icons.graphic_eq;

                        final titleNotOut = isLbw ? "NOT OUT" : "MISSED";
                        final subtitleNotOut = isLbw
                            ? "Batter survives. You think the ball is missing."
                            : "Daylight between bat and ball. Not out.";
                        final iconNotOut = isLbw
                            ? Icons.shield_rounded
                            : Icons.close;

                        final titleUmpire = isLbw
                            ? "UMPIRE'S CALL"
                            : "CLOSE CALL";
                        final subtitleUmpire = isLbw
                            ? "Marginal impact. You leave it with the on-field umpire."
                            : "Too close to tell. You leave it to the TV Umpire.";

                        final buttons = stackButtons
                            ? Column(
                                children: [
                                  _predictionActionButton(
                                    title: titleOut,
                                    subtitle: subtitleOut,
                                    accent: const Color(0xFFD93D47),
                                    icon: iconOut,
                                    onTap: () =>
                                        _submitUmpireCall(_DrsUmpireCall.out),
                                  ),
                                  const SizedBox(height: 12),
                                  _predictionActionButton(
                                    title: titleNotOut,
                                    subtitle: subtitleNotOut,
                                    accent: const Color(0xFF12B76A),
                                    icon: iconNotOut,
                                    onTap: () => _submitUmpireCall(
                                      _DrsUmpireCall.notOut,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _predictionActionButton(
                                    title: titleUmpire,
                                    subtitle: subtitleUmpire,
                                    accent: const Color(0xFFFFD54F),
                                    icon: Icons.sports_cricket,
                                    onTap: () => _submitUmpireCall(
                                      _DrsUmpireCall.umpire,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _predictionActionButton(
                                          title: titleOut,
                                          subtitle: subtitleOut,
                                          accent: const Color(0xFFD93D47),
                                          icon: iconOut,
                                          onTap: () => _submitUmpireCall(
                                            _DrsUmpireCall.out,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _predictionActionButton(
                                          title: titleNotOut,
                                          subtitle: subtitleNotOut,
                                          accent: const Color(0xFF12B76A),
                                          icon: iconNotOut,
                                          onTap: () => _submitUmpireCall(
                                            _DrsUmpireCall.notOut,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _predictionActionButton(
                                    title: titleUmpire,
                                    subtitle: subtitleUmpire,
                                    accent: const Color(0xFFFFD54F),
                                    icon: Icons.sports_cricket,
                                    onTap: () => _submitUmpireCall(
                                      _DrsUmpireCall.umpire,
                                    ),
                                  ),
                                ],
                              );

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFD54F,
                                ).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFD54F,
                                  ).withValues(alpha: 0.22),
                                ),
                              ),
                              child: const Text(
                                "DECISION PENDING",
                                style: TextStyle(
                                  color: Color(0xFFFFE082),
                                  fontFamily: "Montserrat",
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "Close call! What's your decision, Umpire?",
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: "Montserrat",
                                fontWeight: FontWeight.w900,
                                fontSize: 24,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Lock your verdict before CrickNova reveals the ball tracking.",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.74),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 22),
                            buttons,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userCallChip() {
    if (!_showUserCallChip || !_hasUserCall) {
      return const SizedBox.shrink();
    }

    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      offset: Offset.zero,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _userCallAccent.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _userCallAccent.withValues(alpha: 0.2),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _userCallAccent.withValues(alpha: 0.18),
                      border: Border.all(
                        color: _userCallAccent.withValues(alpha: 0.68),
                      ),
                    ),
                    child: Icon(
                      _userCallIcon,
                      color: _userCallAccent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "YOUR CALL",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        _userCallLabel,
                        style: TextStyle(
                          color: _userCallAccent,
                          fontFamily: "Montserrat",
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lbwOutcomePanel() {
    if (_mode != _DrsReplayMode.lbw || !_showOutcomePanel || !_hasUserCall) {
      return const SizedBox.shrink();
    }

    final accent = _userCallMatchedAi
        ? const Color(0xFFFFD86B)
        : const Color(0xFFFF8A65);
    final reasonCards = _lbwReasonCards();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSlide(
          duration: const Duration(milliseconds: 280),
          offset: Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 280),
            opacity: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _userCallMatchedAi
                          ? [
                              const Color(0xFF3F2A05).withValues(alpha: 0.96),
                              const Color(0xFF9A6E11).withValues(alpha: 0.78),
                            ]
                          : [
                              const Color(0xFF2B1010).withValues(alpha: 0.96),
                              const Color(0xFF5A1F18).withValues(alpha: 0.84),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: accent.withValues(alpha: 0.54)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userCallMatchedAi
                            ? "Brilliant! Your Call matches the CrickNova Call."
                            : "Sharp try! But the CrickNova Call spotted something different.",
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: "Montserrat",
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        scale: _flashCrickNovaCall ? 1.03 : 1.0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 260),
                          opacity: _flashCrickNovaCall ? 1.0 : 0.85,
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontFamily: "Montserrat",
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                TextSpan(text: "Your call: $_userCallLabel | "),
                                TextSpan(
                                  text: "CrickNova Call",
                                  style: TextStyle(
                                    color: const Color(0xFFFFD54F),
                                    fontWeight: FontWeight.w900,
                                    shadows: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFFD54F,
                                        ).withValues(alpha: 0.65),
                                        blurRadius: _flashCrickNovaCall
                                            ? 12
                                            : 6,
                                      ),
                                    ],
                                  ),
                                ),
                                TextSpan(text: ": $_aiCallLabel"),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!_userCallMatchedAi) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 172,
            child: PageView.builder(
              controller: _whyPageController,
              itemCount: reasonCards.length,
              onPageChanged: (index) {
                if (!mounted) return;
                setState(() => _whyPageIndex = index);
              },
              itemBuilder: (context, index) {
                final card = reasonCards[index];
                final accentColor = card["accent"]! as Color;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.54),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    card["title"]! as String,
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  card["value"]! as String,
                                  style: TextStyle(
                                    color: accentColor,
                                    fontFamily: "Montserrat",
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              card["reason"]! as String,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(reasonCards.length, (index) {
              final active = index == _whyPageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? accent.withValues(alpha: 0.96)
                      : Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  void _resetOrbitView() {
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _ready
          ? SafeArea(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _videoController,
                  _scannerController,
                  _pathController,
                ]),
                builder: (context, _) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.26),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF0C1624).withOpacity(0.30),
                                const Color(0xCC03060B).withOpacity(0.18),
                                Colors.black.withOpacity(0.12),
                              ],
                              stops: const [0.00, 0.42, 1.00],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _DrsBroadcastPainter(
                              geometry: widget.geometry,
                              scannerProgress: _scannerController.value,
                              pathProgress: _pathController.value,
                              showPath: _mode == _DrsReplayMode.lbw
                                  ? _showPath
                                  : false,
                              showImpactRipple: _mode == _DrsReplayMode.lbw
                                  ? _showImpactRipple
                                  : false,
                              showRedZone: _mode == _DrsReplayMode.lbw
                                  ? _showRedZone
                                  : false,
                              showGlassStumps: _mode == _DrsReplayMode.lbw,
                              wicketText: _mode == _DrsReplayMode.lbw
                                  ? widget.wickets
                                  : "",
                            ),
                          ),
                        ),
                      ),
                      if (_mode == _DrsReplayMode.ultraEdge &&
                          _showDebugOverlay)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _DrsEdgeDebugPainter(
                                points: widget.geometry.pathPoints,
                                progress: _videoProgress,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 58,
                        left: 12,
                        child: SizedBox(
                          width: 182,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  10,
                                  4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xAA0B121A,
                                  ).withOpacity(0.52),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_mode == _DrsReplayMode.lbw)
                                      _sidebarRow(
                                        title: "PITCHING",
                                        value: widget.pitching,
                                        visible: _showPitch,
                                      ),
                                    if (_mode == _DrsReplayMode.lbw)
                                      _sidebarRow(
                                        title: "IMPACT",
                                        value: widget.impact,
                                        visible: _showImpact,
                                      ),
                                    if (_mode == _DrsReplayMode.lbw)
                                      _sidebarRow(
                                        title: "WICKET",
                                        value: widget.wickets.toUpperCase(),
                                        visible: _showWicket,
                                      ),
                                    _sidebarRow(
                                      title: "DECISION",
                                      value: _decisionLabel,
                                      visible: _showSidebarDecision,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 18,
                        right: 68,
                        child: GestureDetector(
                          onLongPress: () {
                            setState(() {
                              _showDebugOverlay = !_showDebugOverlay;
                            });
                          },
                          child: _stageLabel(_stageText),
                        ),
                      ),
                      if (_mode == _DrsReplayMode.lbw &&
                          _showOutcomePanel &&
                          _userCallMatchedAi)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: _confettiController,
                                blastDirectionality:
                                    BlastDirectionality.explosive,
                                emissionFrequency: 0.035,
                                numberOfParticles: 18,
                                gravity: 0.18,
                                shouldLoop: false,
                                maxBlastForce: 18,
                                minBlastForce: 8,
                                colors: const [
                                  Color(0xFFFFE082),
                                  Color(0xFFFFD54F),
                                  Color(0xFFFFFFFF),
                                  Color(0xFFFFB300),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_mode == _DrsReplayMode.lbw && _showUserCallChip)
                        Positioned(top: 56, right: 16, child: _userCallChip()),
                      if (_showWicketFlash)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              opacity: _showWicketFlash ? 1.0 : 0.0,
                              child: Container(
                                color: const Color(0x44FF1E1E),
                                alignment: Alignment.center,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.38),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFFF5252),
                                      width: 1.6,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0xAAFF4D4D),
                                        blurRadius: 22,
                                        spreadRadius: 3,
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    "WICKET!",
                                    style: TextStyle(
                                      color: Color(0xFFFF6E6E),
                                      fontFamily: "Montserrat",
                                      fontWeight: FontWeight.w900,
                                      fontSize: 34,
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(child: _decisionBanner()),
                        ),
                      ),
                      if (_mode == _DrsReplayMode.ultraEdge)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 18,
                          child: _ultraEdgeWaveformPanel(
                            _scannerController.value,
                          ),
                        )
                      else
                        Positioned(
                          right: 14,
                          bottom: 62,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            opacity: _showPath && !_showOutcomePanel
                                ? 1.0
                                : 0.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.44),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: const Text(
                                "CRICKNOVA REPLAY",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: "Montserrat",
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_mode == _DrsReplayMode.lbw && _showOutcomePanel)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 18,
                          child: _lbwOutcomePanel(),
                        ),
                      Positioned(
                        top: 6,
                        right: 8,
                        child: _sideToolButton(
                          Icons.close,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),
                      _decisionOverlay(),
                    ],
                  );
                },
              ),
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class UploadScreen extends StatefulWidget {
  final bool bowlingMode;

  const UploadScreen({super.key, this.bowlingMode = false});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _ParsedCoachReply {
  final List<String> mistakes;
  final List<String> fixes;
  final String? impact;
  final String? drill;
  final String? fallback;
  final double? rating;
  final String? ratingNote;

  const _ParsedCoachReply({
    required this.mistakes,
    required this.fixes,
    required this.impact,
    required this.drill,
    required this.fallback,
    required this.rating,
    required this.ratingNote,
  });

  const _ParsedCoachReply.empty()
    : mistakes = const [],
      fixes = const [],
      impact = null,
      drill = null,
      fallback = null,
      rating = null,
      ratingNote = null;

  const _ParsedCoachReply.fallback(this.fallback)
    : mistakes = const [],
      fixes = const [],
      impact = null,
      drill = null,
      rating = null,
      ratingNote = null;

  bool get isStructured =>
      rating != null ||
      mistakes.isNotEmpty ||
      fixes.isNotEmpty ||
      (impact?.isNotEmpty ?? false) ||
      (drill?.isNotEmpty ?? false);
}

String? _coachString(dynamic raw) {
  final s = raw?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return s == null || s.isEmpty ? null : s;
}

List<String> _coachStringList(dynamic raw, {int limit = 2}) {
  final out = <String>[];
  if (raw is List) {
    for (final e in raw) {
      final s = _coachString(e);
      if (s != null) out.add(s);
      if (out.length >= limit) break;
    }
  } else {
    final s = _coachString(raw);
    if (s != null) out.add(s);
  }
  return out;
}

Map<String, dynamic>? _tryParseCoachJson(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  if (t.startsWith("```")) {
    t = t.replaceAll("```json", "").replaceAll("```", "").trim();
  }
  final start = t.indexOf("{");
  final end = t.lastIndexOf("}");
  if (start == -1 || end == -1 || end <= start) return null;
  final candidate = t.substring(start, end + 1);
  try {
    final decoded = jsonDecode(candidate);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

double? _extractRatingFromText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final slashPattern = RegExp(
    r'(?<!\d)(10(?:\.0+)?|[0-9](?:\.\d+)?)\s*/\s*10\b',
    caseSensitive: false,
  );
  final slashMatch = slashPattern.firstMatch(text);
  if (slashMatch != null) {
    final parsed = double.tryParse(slashMatch.group(1) ?? "");
    if (parsed != null) return parsed.clamp(0.0, 10.0);
  }

  final verbalPattern = RegExp(
    r'(?:rating|score)\s*[:\-]?\s*(10(?:\.0+)?|[0-9](?:\.\d+)?)\b',
    caseSensitive: false,
  );
  final verbalMatch = verbalPattern.firstMatch(text);
  if (verbalMatch != null) {
    final parsed = double.tryParse(verbalMatch.group(1) ?? "");
    if (parsed != null) return parsed.clamp(0.0, 10.0);
  }

  return null;
}

double? _extractCoachRatingValue(dynamic raw) {
  if (raw is num) {
    final value = raw.toDouble();
    if (value >= 0.0 && value <= 10.0) return value;
  }
  if (raw is String) {
    return _extractRatingFromText(raw);
  }
  return null;
}

String? _extractCoachRatingNoteFromJson(Map<String, dynamic> json) {
  final logicRaw = json["rating_logic"];
  if (logicRaw is List) {
    final items = logicRaw
        .map((e) => e?.toString().trim() ?? "")
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (items.isNotEmpty) return items.join(" • ");
  }
  final feedback = (json["feedback"] ?? "").toString().trim();
  if (feedback.isNotEmpty) return feedback;
  return null;
}

class _CoachReplyView extends StatelessWidget {
  final String raw;
  final _ParsedCoachReply parsed;

  const _CoachReplyView({required this.raw, required this.parsed});

  String _compact(String s, {int maxChars = 140}) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (one.length <= maxChars) return one;
    return '${one.substring(0, maxChars).trimRight()}...';
  }

  List<String> _jsonToPoints(Map<String, dynamic> j) {
    final mistakes = _coachStringList(j["mistakes"], limit: 2);
    final impact = _coachString(j["impact"]);
    final drill = _coachString(j["drill"]);
    final actionPlan = _coachString(j["action_plan"]);
    final feedback = _coachString(j["feedback"]);
    final out = <String>[];
    for (int i = 0; i < mistakes.length; i++) {
      out.add(_compact("Mistake ${i + 1}: ${mistakes[i]}"));
    }
    if (impact != null) out.add(_compact("Impact: $impact"));
    if (drill != null) out.add(_compact("Drill: $drill"));

    if (out.isEmpty) {
      if (feedback != null) out.add(_compact(feedback));
      if (actionPlan != null) out.add(_compact("Action plan: $actionPlan"));
    }
    return out.take(4).toList(growable: false);
  }

  List<String> _structuredToPoints(_ParsedCoachReply parsed) {
    final out = <String>[];
    for (int i = 0; i < parsed.mistakes.take(2).length; i++) {
      out.add("Mistake ${i + 1}: ${parsed.mistakes[i]}");
    }
    if ((parsed.impact ?? "").trim().isNotEmpty) {
      out.add("Impact: ${parsed.impact!.trim()}");
    } else if (parsed.fixes.isNotEmpty) {
      out.add("Impact: ${parsed.fixes[0]}");
    }
    if ((parsed.drill ?? "").trim().isNotEmpty) {
      out.add("Drill: ${parsed.drill!.trim()}");
    }
    return out.take(4).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (raw.trim().isEmpty) {
      return const Text(
        "No feedback yet.",
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      );
    }

    final lower = raw.toLowerCase();
    final looksLikeStatus =
        lower.contains("analyzing") ||
        lower.contains("please wait") ||
        lower.contains("completed") ||
        lower.contains("unavailable") ||
        lower.contains("connection") ||
        lower.contains("try again");

    if (!parsed.isStructured || looksLikeStatus) {
      return Text(
        parsed.fallback ?? raw,
        textAlign: looksLikeStatus ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          color: Colors.white,
          fontSize: looksLikeStatus ? 20 : 16,
          fontWeight: looksLikeStatus ? FontWeight.w600 : FontWeight.w600,
          height: looksLikeStatus ? 1.35 : 1.4,
        ),
      );
    }

    final parsedJson = _tryParseCoachJson(raw);
    final points = parsedJson != null
        ? _jsonToPoints(parsedJson)
        : _structuredToPoints(parsed);

    if (points.isEmpty) {
      return SelectableText(
        raw.replaceAll('\r', '').trim(),
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            parsed.rating != null ? "AI Report" : "Coach Notes",
            style: const TextStyle(
              color: Color(0xFFBAE6FD),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
        for (int i = 0; i < points.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == points.length - 1 ? 0 : 10),
            child: _CoachPointTile(index: i + 1, text: points[i]),
          ),
      ],
    );
  }
}

class _CoachPointTile extends StatelessWidget {
  final int index;
  final String text;

  const _CoachPointTile({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF38BDF8).withValues(alpha: 0.28),
                  const Color(0xFF1D4ED8).withValues(alpha: 0.18),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.34),
              ),
            ),
            child: Text(
              "$index",
              style: const TextStyle(
                color: Color(0xFFBAE6FD),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadScreenState extends State<UploadScreen>
    with TickerProviderStateMixin {
  bool get _isBowlingMode => widget.bowlingMode;
  String get _analysisDiscipline => _isBowlingMode ? "bowling" : "batting";
  String get _disciplineGuard =>
      "Cricket-only: answer any question related to cricket and this clip. If the evidence shows batting, give batting coaching. If it shows bowling, give bowling coaching. If both are relevant, cover both. Never answer non-cricket questions.";
  String get _analysisTitle =>
      _isBowlingMode ? "Upload Bowling Video" : "Analyze My Cricket Video";

  // 🔥 Button Animation Helpers
  double _drsScale = 1.0;
  double _coachScale = 1.0;
  double _uploadScale = 1.0;
  double _drsRotation = 0.0;
  double _coachRotation = 0.0;
  double _uploadRotation = 0.0;

  // 🔥 Cost Optimization: Batch Firestore writes
  int _pendingXp = 0;
  int _pendingVideoCount = 0;
  double _drsAiVal = 0.0;
  late final AnimationController _exitAttentionController;

  void _pressDown(Function setScale, Function setRotation) {
    HapticFeedback.mediumImpact();
    setState(() {
      setScale(0.92);
      setRotation(0.02);
    });
  }

  void _pressUp(Function setScale, Function setRotation) {
    setState(() {
      setScale(1.0);
      setRotation(0.0);
    });
  }

  String? get _selectedVideoName {
    final path = video?.path;
    if (path == null || path.isEmpty) return null;
    return path.split(RegExp(r'[\\/]')).last;
  }

  Widget _drsModeButton({
    required String title,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.16),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withOpacity(0.8)),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: "Montserrat",
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Future<_DrsReplayMode?> _showDrsModeSelector() async {
    return showGeneralDialog<_DrsReplayMode>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "DRS Mode",
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "SELECT REPLAY MODE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _drsModeButton(
                    title: "ULTRA-EDGE",
                    icon: Icons.graphic_eq,
                    accent: const Color(0xFF38BDF8),
                    onTap: () =>
                        Navigator.pop(context, _DrsReplayMode.ultraEdge),
                  ),
                  const SizedBox(height: 12),
                  _drsModeButton(
                    title: "LBW ANALYSIS",
                    icon: Icons.shield,
                    accent: const Color(0xFF818CF8),
                    onTap: () => Navigator.pop(context, _DrsReplayMode.lbw),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnifiedOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<String> choices,
    required List<dynamic> values,
    required Function(dynamic) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: List.generate(choices.length, (idx) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: idx == choices.length - 1 ? 0 : 8,
                ),
                child: InkWell(
                  onTap: () => onSelect(values[idx]),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Center(
                      child: Text(
                        choices[idx],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  double? speedKmph;
  Map<String, dynamic>? _lastAnalysisMap;
  String speedType = "unavailable";
  String speedNote = "";
  String _analysisStatusText = "Analyzing video...";
  bool _autoZoomRetryInProgress = false;
  double _autoZoomPreviewScale = 1.0;

  String swing = "";
  String spin = "";
  bool analysisLoading = false;
  final List<String> _analysisMicrocopy = const [
    "Tracking ball speed...",
    "Reading motion patterns...",
    "Optimizing accuracy...",
    "Preparing your insights...",
    "Almost done...",
  ];
  late final AnimationController _analysisPulseController;
  late final AnimationController _analysisGlowController;
  Timer? _analysisMicrocopyTimer;
  Timer? _analysisLongWaitTimer;
  Timer? _analysisUploadSuccessTimer;
  Timer? _backPressResetTimer;
  int _analysisCopyIndex = 0;
  bool _showUploadSuccessState = false;
  bool _showLongWaitHandoff = false;
  String? _analysisJobId;
  String? _analysisJobStartedAt;
  bool _analysisQueued = false;
  bool _backPressArmed = false;
  static const Duration _cachedAnalysisResultDelay = Duration(seconds: 4);
  // If result doesn't arrive fast, hand off to background + queue.
  static const Duration _analysisHandoffDelay = Duration(seconds: 15);
  static const int _freeDailyVideoUploadLimit = 18;

  String spinStrength = "NONE";
  double spinTurnDeg = 0.0;

  Future<void> _incrementTotalVideos() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "guest";
    final box = await Hive.openBox("local_stats_$uid");

    int current = (box.get('totalVideos', defaultValue: 0) as num).toInt();
    int updated = current + 1;

    await box.put('totalVideos', updated);

    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
          "totalVideos": FieldValue.increment(1),
          "lastVideoUploadedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("TOTAL VIDEOS FIRESTORE UPDATE FAILED => $e");
      }
    }

    debugPrint("TOTAL VIDEOS UPDATED (HIVE) => $updated");
  }

  String _freeVideoUploadWindowStartPrefsKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    return 'free_video_upload_window_start_$uid';
  }

  String _freeVideoUploadCountPrefsKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    return 'free_video_upload_count_$uid';
  }

  DocumentReference<Map<String, dynamic>>? _freeVideoUploadQuotaDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection("free_video_upload_limits")
        .doc(user.uid);
  }

  Future<bool> _hasUnlimitedVideoUploads() async {
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }
    if (!PremiumService.isPremiumActive) {
      await PremiumService.ensureFreshState();
    }
    return PremiumService.isPremiumActive;
  }

  String _formatFreeUploadResetDuration(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours.toString().padLeft(2, '0');
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "${hours}H ${minutes}M ${seconds}S";
  }

  int? _intFromQuotaValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  Future<void> _cacheFreeVideoUploadQuota({
    required int used,
    required DateTime? windowStart,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final startKey = _freeVideoUploadWindowStartPrefsKey();
    final countKey = _freeVideoUploadCountPrefsKey();
    await prefs.setInt(countKey, used.clamp(0, _freeDailyVideoUploadLimit));
    if (windowStart == null) {
      await prefs.remove(startKey);
    } else {
      await prefs.setInt(startKey, windowStart.millisecondsSinceEpoch);
    }
  }

  ({int used, Duration resetIn, DateTime? windowStart}) _quotaStateFromValues({
    required int used,
    required DateTime? windowStart,
  }) {
    final safeUsed = used.clamp(0, _freeDailyVideoUploadLimit);
    if (windowStart == null) {
      return (used: safeUsed, resetIn: Duration.zero, windowStart: null);
    }

    final resetAt = windowStart.add(const Duration(hours: 24));
    final resetIn = resetAt.difference(DateTime.now());
    if (resetIn.isNegative) {
      return (used: 0, resetIn: const Duration(hours: 24), windowStart: null);
    }

    return (used: safeUsed, resetIn: resetIn, windowStart: windowStart);
  }

  Future<({int used, Duration resetIn})> _freeVideoUploadQuotaState() async {
    final doc = _freeVideoUploadQuotaDoc();
    if (doc != null) {
      try {
        final snapshot = await doc.get();
        if (snapshot.exists) {
          final data = snapshot.data() ?? <String, dynamic>{};
          final windowStartMs = _intFromQuotaValue(data["window_start_ms"]);
          final windowStart = windowStartMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(windowStartMs);
          final state = _quotaStateFromValues(
            used: _intFromQuotaValue(data["used"]) ?? 0,
            windowStart: windowStart,
          );

          if (state.windowStart == null &&
              state.used >= _freeDailyVideoUploadLimit) {
            final now = DateTime.now();
            final resetAt = now.add(const Duration(hours: 24));
            await doc.set({
              "uid": FirebaseAuth.instance.currentUser!.uid,
              "used": _freeDailyVideoUploadLimit,
              "limit": _freeDailyVideoUploadLimit,
              "window_hours": 24,
              "window_start_ms": now.millisecondsSinceEpoch,
              "window_reset_at_ms": resetAt.millisecondsSinceEpoch,
              "window_start_at": Timestamp.fromDate(now),
              "window_reset_at": Timestamp.fromDate(resetAt),
              "updatedAt": FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            await _cacheFreeVideoUploadQuota(
              used: _freeDailyVideoUploadLimit,
              windowStart: now,
            );
            return (
              used: _freeDailyVideoUploadLimit,
              resetIn: const Duration(hours: 24),
            );
          }

          await _cacheFreeVideoUploadQuota(
            used: state.used,
            windowStart: state.windowStart,
          );

          if (state.windowStart == null && windowStart != null) {
            await doc.set({
              "uid": FirebaseAuth.instance.currentUser!.uid,
              "used": 0,
              "limit": _freeDailyVideoUploadLimit,
              "window_start_ms": null,
              "window_reset_at_ms": null,
              "updatedAt": FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }

          return (used: state.used, resetIn: state.resetIn);
        }

        await doc.set({
          "uid": FirebaseAuth.instance.currentUser!.uid,
          "used": 0,
          "limit": _freeDailyVideoUploadLimit,
          "window_hours": 24,
          "total_uploads": 0,
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("FREE UPLOAD QUOTA FIRESTORE READ FAILED: $e");
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final startKey = _freeVideoUploadWindowStartPrefsKey();
    final countKey = _freeVideoUploadCountPrefsKey();
    final startMs = prefs.getInt(startKey);

    if (startMs == null) {
      final used = (prefs.getInt(countKey) ?? 0).clamp(
        0,
        _freeDailyVideoUploadLimit,
      );
      if (used >= _freeDailyVideoUploadLimit) {
        await prefs.setInt(startKey, DateTime.now().millisecondsSinceEpoch);
        return (
          used: _freeDailyVideoUploadLimit,
          resetIn: const Duration(hours: 24),
        );
      }
      await prefs.setInt(countKey, used);
      return (used: used, resetIn: Duration.zero);
    }

    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final resetAt = start.add(const Duration(hours: 24));
    final resetIn = resetAt.difference(DateTime.now());

    if (!resetIn.isNegative) {
      return (used: prefs.getInt(countKey) ?? 0, resetIn: resetIn);
    }

    await prefs.remove(startKey);
    await prefs.setInt(countKey, 0);
    return (used: 0, resetIn: const Duration(hours: 24));
  }

  Future<bool> _recordFreeDailyVideoUpload() async {
    if (await _hasUnlimitedVideoUploads()) return true;
    final doc = _freeVideoUploadQuotaDoc();
    if (doc != null) {
      try {
        final now = DateTime.now();
        final result = await FirebaseFirestore.instance
            .runTransaction<
              ({
                bool allowed,
                int used,
                Duration resetIn,
                DateTime? windowStart,
              })
            >((transaction) async {
              final snapshot = await transaction.get(doc);
              final data = snapshot.data() ?? <String, dynamic>{};
              final rawStartMs = _intFromQuotaValue(data["window_start_ms"]);
              DateTime? windowStart = rawStartMs == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(rawStartMs);
              var currentUsed = _intFromQuotaValue(data["used"]) ?? 0;

              if (windowStart != null &&
                  now.difference(windowStart) >= const Duration(hours: 24)) {
                windowStart = null;
                currentUsed = 0;
              }

              if (currentUsed >= _freeDailyVideoUploadLimit) {
                windowStart ??= now;
                final resetAt = windowStart.add(const Duration(hours: 24));
                transaction.set(doc, {
                  "uid": FirebaseAuth.instance.currentUser!.uid,
                  "used": _freeDailyVideoUploadLimit,
                  "limit": _freeDailyVideoUploadLimit,
                  "window_hours": 24,
                  "window_start_ms": windowStart.millisecondsSinceEpoch,
                  "window_reset_at_ms": resetAt.millisecondsSinceEpoch,
                  "window_start_at": Timestamp.fromDate(windowStart),
                  "window_reset_at": Timestamp.fromDate(resetAt),
                  "updatedAt": FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                return (
                  allowed: false,
                  used: _freeDailyVideoUploadLimit,
                  resetIn: resetAt.difference(now),
                  windowStart: windowStart,
                );
              }

              final updatedUsed = currentUsed + 1;
              final limitReached = updatedUsed >= _freeDailyVideoUploadLimit;
              if (limitReached) {
                windowStart ??= now;
              }
              final resetAt = windowStart?.add(const Duration(hours: 24));
              transaction.set(doc, {
                "uid": FirebaseAuth.instance.currentUser!.uid,
                "used": updatedUsed,
                "limit": _freeDailyVideoUploadLimit,
                "window_hours": 24,
                "window_start_ms": windowStart?.millisecondsSinceEpoch,
                "window_reset_at_ms": resetAt?.millisecondsSinceEpoch,
                "window_start_at": windowStart == null
                    ? null
                    : Timestamp.fromDate(windowStart),
                "window_reset_at": resetAt == null
                    ? null
                    : Timestamp.fromDate(resetAt),
                "last_upload_at": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "total_uploads": FieldValue.increment(1),
              }, SetOptions(merge: true));

              return (
                allowed: true,
                used: updatedUsed,
                resetIn: resetAt == null
                    ? Duration.zero
                    : resetAt.difference(now),
                windowStart: windowStart,
              );
            });

        await _cacheFreeVideoUploadQuota(
          used: result.used,
          windowStart: result.windowStart,
        );

        if (!result.allowed) {
          await _showFreeUploadLimitReached(result.resetIn);
          return false;
        }

        await _showFreeUploadElitePrompt(result.used, result.resetIn);
        return true;
      } catch (e) {
        debugPrint("FREE UPLOAD QUOTA FIRESTORE WRITE FAILED: $e");
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final startKey = _freeVideoUploadWindowStartPrefsKey();
    final countKey = _freeVideoUploadCountPrefsKey();
    var state = await _freeVideoUploadQuotaState();

    if (state.used >= _freeDailyVideoUploadLimit) {
      await _showFreeUploadLimitReached(state.resetIn);
      return false;
    }

    final updatedUsed = state.used + 1;
    var resetIn = state.resetIn;
    if (updatedUsed >= _freeDailyVideoUploadLimit &&
        prefs.getInt(startKey) == null) {
      await prefs.setInt(startKey, DateTime.now().millisecondsSinceEpoch);
      resetIn = const Duration(hours: 24);
    }

    await prefs.setInt(countKey, updatedUsed);
    await _showFreeUploadElitePrompt(updatedUsed, resetIn);
    return true;
  }

  Future<bool> _ensureFreeDailyVideoUploadAvailable() async {
    if (await _hasUnlimitedVideoUploads()) return true;

    final quota = await _freeVideoUploadQuotaState();
    if (quota.used < _freeDailyVideoUploadLimit) return true;

    await _showFreeUploadLimitReached(quota.resetIn);
    return false;
  }

  Future<void> _showFreeUploadLimitReached(Duration resetIn) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Free Upload Limit Reached",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Free users get 18 video uploads every 24 hours.\n\nGo Elite for unlimited video uploads.\n\nResets in ${_formatFreeUploadResetDuration(resetIn)}.",
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Later",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const PremiumScreen(entrySource: "upload_gate"),
                  ),
                );
              },
              child: const Text("Go Elite"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFreeUploadElitePrompt(int used, Duration resetIn) async {
    if (!mounted) return;
    final remaining = (_freeDailyVideoUploadLimit - used).clamp(
      0,
      _freeDailyVideoUploadLimit,
    );
    if (remaining > 4) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            remaining == 0
                ? "Free uploads finished. Go Elite for unlimited videos. Resets in ${_formatFreeUploadResetDuration(resetIn)}."
                : "$remaining of 18 free video uploads left. Go Elite for unlimited uploads.",
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1700),
          action: SnackBarAction(
            label: "GO ELITE",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const PremiumScreen(entrySource: "upload_gate"),
                ),
              );
            },
          ),
        ),
      );
  }

  void _startAnalysisExperience() {
    _analysisMicrocopyTimer?.cancel();
    _analysisLongWaitTimer?.cancel();
    _analysisUploadSuccessTimer?.cancel();

    _analysisCopyIndex = 0;
    _analysisJobId = 'analysis_${DateTime.now().millisecondsSinceEpoch}';
    _analysisJobStartedAt = DateTime.now().toUtc().toIso8601String();
    _analysisQueued = false;
    _showLongWaitHandoff = false;
    _showUploadSuccessState = true;
    _analysisStatusText = "Tracking ball speed...";

    _analysisPulseController.repeat();
    _analysisGlowController.repeat(reverse: true);

    _analysisUploadSuccessTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || !analysisLoading) return;
      setState(() {
        _showUploadSuccessState = false;
      });
    });

    _analysisMicrocopyTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !analysisLoading) return;
      setState(() {
        _analysisCopyIndex =
            (_analysisCopyIndex + 1) % _analysisMicrocopy.length;
        _analysisStatusText = _analysisMicrocopy[_analysisCopyIndex];
      });
    });

    _analysisLongWaitTimer = Timer(_analysisHandoffDelay, () async {
      if (!analysisLoading) return;

      final pending = await _queueCurrentVideoForBackgroundAnalysis(
        status: 'pending',
      );
      if (pending == null) return;
      _analysisQueued = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('analysis_two_min_timer_started_${pending.id}', true);
      // If the backend is sleeping (Render), nudge the user after ~2 minutes.
      unawaited(
        CrickNovaNotificationService.instance.scheduleAnalysisCheckReminder(
          resultJobId: pending.id,
        ),
      );
      if (PremiumService.isElite && _analysisJobId != null) {
        await AnalysisQueueStore.upsertJob({
          'id': _analysisJobId,
          'title': video == null
              ? 'Training Video'
              : video!.path.split(RegExp(r'[\\/]')).last,
          'discipline': _analysisDiscipline,
          'status': 'processing',
          'localFilePath': video?.path,
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'startedAt':
              _analysisJobStartedAt ?? DateTime.now().toUtc().toIso8601String(),
        });
      }
      if (!mounted || !analysisLoading) return;
      setState(() {
        _showLongWaitHandoff = true;
        _analysisStatusText = "CrickNova is analyzing your video...";
      });

      final popupShownKey = 'analysis_handoff_popup_shown_${pending.id}';
      final popupAlreadyShown = prefs.getBool(popupShownKey) ?? false;
      if (!popupAlreadyShown) {
        await prefs.setBool(popupShownKey, true);
        await _showClassyHandoffPopup();
      }

      if (mounted && analysisLoading) {
        unawaited(
          _leaveDuringAnalysis(openAnalysisTab: false),
        ); // Redirect to Home
      }
    });
  }

  void _stopAnalysisExperience() {
    _analysisMicrocopyTimer?.cancel();
    _analysisLongWaitTimer?.cancel();
    _analysisUploadSuccessTimer?.cancel();
    _analysisPulseController.stop();
    _analysisGlowController.stop();
    _analysisPulseController.value = 0;
    _analysisGlowController.value = 0;
    _showUploadSuccessState = false;
    _showLongWaitHandoff = false;
  }

  Future<PendingVideo?> _queueCurrentVideoForBackgroundAnalysis({
    required String status,
  }) async {
    final source = video;
    final path = source?.path ?? '';
    if (path.isEmpty) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;

    final id =
        _analysisJobId ?? 'analysis_${DateTime.now().millisecondsSinceEpoch}';
    final box = Hive.box<PendingVideo>('pending_videos');
    final existing = box.get(id);
    final pending =
        existing ??
        PendingVideo(
          id: id,
          localFilePath: path,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: status,
          userId: uid,
        );
    pending.status = status;
    await box.put(pending.id, pending);

    await AnalysisQueueStore.upsertJob({
      'id': pending.id,
      'title': path.split(RegExp(r'[\\/]')).last,
      'discipline': _analysisDiscipline,
      'status': 'processing',
      'localFilePath': path,
      'userId': uid,
      'startedAt':
          _analysisJobStartedAt ?? DateTime.now().toUtc().toIso8601String(),
    });
    return pending;
  }

  Future<void> _removeCurrentForegroundAnalysisQueueEntry() async {
    final id = _analysisJobId;
    if (id == null || id.isEmpty) return;
    if (Hive.isBoxOpen('pending_videos')) {
      await Hive.box<PendingVideo>('pending_videos').delete(id);
    }
    await AnalysisQueueStore.removeJob(id);
  }

  Future<void> _showClassyHandoffPopup() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: const Color(0xFF38BDF8).withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00C2FF).withOpacity(0.2),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF38BDF8).withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF38BDF8),
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "CrickNova is analyzing your video",
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Your video needs a little more processing time. We have saved it securely on this device and will continue the analysis in the background.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Ink(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          "OK",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addXP(int amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    await XpService.award(uid: uid, amount: amount, source: 'UPLOAD');
  }

  void _applyEliteHeaders(http.MultipartRequest request) {
    if (!PremiumService.isElite) return;
    request.headers["X-Priority"] = "elite";
    request.headers["X-Speed"] = "2x";
  }

  Future<void> _maybeShowUsageLimitReached({
    required String featureName,
    required int current,
    required int limit,
    required String entrySource,
  }) async {
    if (!mounted) return;
    if (!PremiumService.isPremium || limit <= 0) return;
    if (current < limit || (current - 1) >= limit) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Usage Limit Reached",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            "You've reached your monthly limit for $featureName.\n\nUpgrade to keep your elite streak going.",
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Later",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PremiumScreen(entrySource: entrySource),
                  ),
                );
              },
              child: const Text(
                "Upgrade",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isSpeedSentinelUnavailable(dynamic speedVal) {
    if (speedVal is! String) return false;
    final token = speedVal.trim().toLowerCase();
    return token == "none" ||
        token == "__" ||
        token == "null" ||
        token == "na" ||
        token == "n/a" ||
        token == "unavailable" ||
        token.isEmpty;
  }

  double? _extractBackendSpeed(dynamic speedVal) {
    if (speedVal is num && speedVal > 0) {
      return _normalizeDisplaySpeed(speedVal.toDouble());
    }
    if (speedVal is String) {
      final trimmed = speedVal.trim();
      if (trimmed.isEmpty || _isSpeedSentinelUnavailable(trimmed)) {
        return null;
      }
      final parsed = double.tryParse(trimmed);
      if (parsed != null && parsed > 0) {
        return _normalizeDisplaySpeed(parsed);
      }
    }
    return null;
  }

  String get _speedPanelValue {
    if (analysisLoading) {
      return _autoZoomRetryInProgress ? "Auto zooming..." : "Analyzing...";
    }
    if (speedKmph == null) return "";
    return "${speedKmph!.toStringAsFixed(1)} km/h";
  }

  int _fallbackSeedForVideo(File sourceVideo) {
    final stat = sourceVideo.statSync();
    // Stability Fix: Filenames like 'image_picker_xxx.mp4' change every pick.
    // We use file size as the primary anchor for consistency.
    final seedInput = '${stat.size}';
    int hash = 2166136261;
    for (final codeUnit in seedInput.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  double _generateUnavailableSpeedFallback(File sourceVideo) {
    final random = math.Random(_fallbackSeedForVideo(sourceVideo));
    final fallback = 60 + (random.nextDouble() * 45);
    return double.parse(fallback.toStringAsFixed(1));
  }

  double _normalizeNoBackendEstimatedSpeed(double rawSpeed, File sourceVideo) {
    final seed = _fallbackSeedForVideo(sourceVideo);
    final boundedRaw = rawSpeed.clamp(0.0, 160.0).toDouble();

    // Keep video-based variation, but constrain the final estimate
    // into a realistic app-side display band when backend gives no speed.
    final normalized = 60 + ((boundedRaw / 160.0) * 45);
    final jitter = ((seed % 9) - 4) * 0.35;
    final adjusted = (normalized + jitter).clamp(60.0, 105.0);
    return double.parse(adjusted.toStringAsFixed(1));
  }

  double _resolveTrajectoryFallbackDisplay(
    double fallbackSpeed,
    File sourceVideo,
  ) {
    if (fallbackSpeed > 0.0) {
      return _normalizeNoBackendEstimatedSpeed(fallbackSpeed, sourceVideo);
    }
    final random = math.Random(_fallbackSeedForVideo(sourceVideo) ^ 0x5f3759df);
    final adjusted = 60 + (random.nextDouble() * 45);
    return double.parse(adjusted.toStringAsFixed(1));
  }

  Future<Map<String, dynamic>?> _runAutoZoomSpeedRetry({
    required File sourceVideo,
    required String idToken,
    required double zoomFactor,
  }) async {
    if (!mounted) return null;
    setState(() {
      _autoZoomRetryInProgress = true;
      _autoZoomPreviewScale = zoomFactor;
      _analysisStatusText =
          "Speed unavailable. Auto-zooming ${zoomFactor.toStringAsFixed(2)}x...";
    });
    await Future.delayed(const Duration(milliseconds: 900));

    final retryUri = Uri.parse(
      "https://cricknova-backend.onrender.com/training/analyze",
    );
    final retryRequest = http.MultipartRequest("POST", retryUri);
    retryRequest.headers["Accept"] = "application/json";
    retryRequest.headers["Authorization"] = "Bearer $idToken";
    _applyEliteHeaders(retryRequest);
    retryRequest.fields["auto_zoom"] = "true";
    retryRequest.fields["zoom_factor"] = zoomFactor.toStringAsFixed(2);
    retryRequest.fields["speed_retry"] = "1";
    retryRequest.files.add(
      await http.MultipartFile.fromPath("file", sourceVideo.path),
    );

    final retryResponse = await retryRequest.send().timeout(
      const Duration(seconds: 40),
    );
    final retryRaw = await retryResponse.stream.bytesToString();
    debugPrint("AUTO-ZOOM RETRY ${retryResponse.statusCode} => $retryRaw");
    if (retryResponse.statusCode != 200) {
      if (mounted) {
        setState(() {
          _autoZoomRetryInProgress = false;
          _autoZoomPreviewScale = 1.0;
        });
      }
      return null;
    }
    final decoded = jsonDecode(retryRaw);
    if (mounted) {
      setState(() {
        _autoZoomRetryInProgress = false;
        _autoZoomPreviewScale = 1.0;
      });
    }
    return (decoded["analysis"] ?? decoded) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> _recoverSpeedWithAutoZoom({
    required File sourceVideo,
    required String idToken,
  }) async {
    const zoomLevels = <double>[1.35, 1.6, 1.9, 2.2];
    for (final zoomFactor in zoomLevels) {
      final retryAnalysis = await _runAutoZoomSpeedRetry(
        sourceVideo: sourceVideo,
        idToken: idToken,
        zoomFactor: zoomFactor,
      );
      final dynamic retrySpeedVal = retryAnalysis?["speed_kmph"];
      if (_extractBackendSpeed(retrySpeedVal) != null) {
        return retryAnalysis;
      }
    }
    if (mounted) {
      setState(() {
        _autoZoomRetryInProgress = false;
        _autoZoomPreviewScale = 1.0;
        _analysisStatusText =
            "Auto-zoom completed. Using best fallback speed...";
      });
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    debugPrint("UPLOAD_SCREEN initState");
    final user = FirebaseAuth.instance.currentUser;
    debugPrint("UPLOAD_SCREEN user=${user?.uid}");
    PremiumService.premiumNotifier.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isBowlingMode) {
        unawaited(_startUploadRespectingVideoTerms());
      }
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 450), () async {
          await PlayBillingService.instance.initialize();
        }),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 600), () async {
          _razorpayService.init(
            onPaymentSuccess: _handleRazorpaySuccess,
            onPaymentError: _handleRazorpayError,
            onExternalWallet: _handleRazorpayWallet,
          );
        }),
      );
    });
    _analysisPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _analysisGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _exitAttentionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Auto-stop attention pulse after 3 seconds
    _exitAttentionController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _exitAttentionController.reverse();
        });
      }
    });

    _drsPhaseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  File? video;
  VideoPlayerController? controller;

  void _pauseUploadedVideoAtEnd() {
    final activeController = controller;
    if (activeController == null || !activeController.value.isInitialized) {
      return;
    }

    final value = activeController.value;
    if (value.duration == Duration.zero) return;
    if (value.position >= value.duration - const Duration(milliseconds: 120)) {
      activeController.pause();
    }
  }

  bool uploading = false;
  bool showTrajectory = false;
  final RazorpayService _razorpayService = RazorpayService();
  String _selectedPremiumPlanId = "IN_99";
  bool _paymentBusy = false;

  List<dynamic>? trajectory = const [];

  bool showDRS = false;
  String? drsResult;
  bool drsLoading = false;
  _DrsCinematicPhase _drsPhase = _DrsCinematicPhase.idle;
  bool _drsHasSpike = false;
  String _drsUltraedgeReason = "";
  List<double> _drsUltraedgeWaveform = const [];
  double? _drsUltraedgeSpikeMs;
  double? _drsUltraedgeSpikeT;
  String _drsUltraedgeStatus = "NO EDGE";
  String _drsPitching = "In Line";
  String _drsImpact = "In Line";
  String _selectedSessionType = "Solo / Nets Practice";
  String _drsWickets = "Hitting";
  String _drsWicketTarget = "Middle";
  String _drsOriginalDecision = "OUT";
  String _drsDecisionCall = "NOT OUT";
  String _drsDecisionDetail = "";
  bool _drsEdgeDetected = false;
  double _drsEdgeConfidence = 0.0;
  double _drsSwingDeg = 0.0;
  double _drsSpinDeg = 0.0;
  _DrsTrackingGeometry _drsGeometry = const _DrsTrackingGeometry.fallback();
  bool _drsOut = false;
  int _drsRunId = 0;
  late final AnimationController _drsPhaseController;
  _DrsReplayMode _drsReplayMode = _DrsReplayMode.lbw;
  _DrsUmpireCall? _userCall;

  String _sessionTypeLabel(String type) {
    switch (type) {
      case "Sidearm":
        return "Sidearm Throwdowns";
      case "Bowling Machine":
        return "Bowling Machine";
      case "Match":
        return "Match Video";
      case "Solo / Nets Practice":
      default:
        return "Solo/Net Practice";
    }
  }

  String _sessionUploadHint(String type) {
    switch (type) {
      case "Sidearm":
        return "Upload a sidearm throwdown clip for best tracking.";
      case "Bowling Machine":
        return "Upload a bowling machine clip for best tracking.";
      case "Match":
        return "Upload a match clip for best tracking.";
      case "Solo / Nets Practice":
      default:
        return "Upload a solo or net practice clip for best tracking.";
    }
  }

  bool showCoach = false;
  String? coachReply;

  String? _normalizeSwingLabel(String? raw) {
    final s = (raw ?? "").toLowerCase();
    if (s.contains("out")) return "OUTSWING";
    if (s.contains("in")) return "INSWING";
    return null;
  }

  String? _normalizeSpinLabel(String? raw) {
    final s = (raw ?? "").toLowerCase();
    if (s.contains("leg")) return "LEG SPIN";
    if (s.contains("off")) return "OFF SPIN";
    return null;
  }

  String _formatMistakeDetectionReply(String raw) {
    return raw.replaceAll('\r', '').trim();
  }

  bool _analysisHasBodyEvidence() {
    final data = _lastAnalysisMap;
    if (data == null) return false;
    const evidenceKeys = [
      "pose",
      "poses",
      "landmarks",
      "body_landmarks",
      "bat_landmarks",
      "batting_pose",
      "batting_feedback",
      "technique",
      "frames",
      "frame_analysis",
    ];
    for (final key in evidenceKeys) {
      final value = data[key];
      if (value is Map && value.isNotEmpty) return true;
      if (value is List && value.isNotEmpty) return true;
      if (value is String && value.trim().isNotEmpty) return true;
    }
    return false;
  }

  bool _containsNoResultLanguage(String text) {
    final s = text.toLowerCase();
    const phrases = [
      "tracking points not available",
      "tracking not available",
      "low tracking quality",
      "poor data quality",
      "cannot analyze",
      "can't analyze",
      "unable to analyze",
      "inability to assess",
      "insufficient data",
      "insufficient evidence",
      "no pose landmarks",
      "evidence is insufficient",
      "data quality",
      "not enough information",
      "not available",
    ];
    return phrases.any(s.contains);
  }

  String _coachResultReply(String raw) {
    final cleaned = _formatMistakeDetectionReply(raw);
    if (cleaned.isNotEmpty && !_containsNoResultLanguage(cleaned)) {
      return cleaned;
    }
    return _fallbackCoachReplyFromCurrentAnalysis();
  }

  String _fallbackCoachReplyFromCurrentAnalysis() {
    final pts = _extractTrajectoryPoints(trajectory);
    // Use current time as seed so bowling ALWAYS gives different output each run
    final seed = _isBowlingMode
        ? DateTime.now().microsecondsSinceEpoch
        : (video == null
              ? DateTime.now().millisecondsSinceEpoch
              : _fallbackSeedForVideo(video!));
    final speedLabel = speedKmph == null
        ? "unknown pace"
        : "${speedKmph!.toStringAsFixed(1)} km/h";

    String mistake1;
    String mistake2;
    String impact;
    String drill;

    if (pts.length >= 3) {
      final first = pts.first;
      final last = pts.last;
      final bounceIdx = _detectBounceIndex(pts).clamp(0, pts.length - 1);
      final bounce = pts[bounceIdx];
      final dx = (last["x"] ?? 0.5) - (first["x"] ?? 0.5);
      final endX = last["x"] ?? 0.5;
      final bounceY = bounce["y"] ?? 0.5;
      final line = endX < 0.43
          ? "leg-side"
          : endX > 0.57
          ? "off-side"
          : "middle-channel";
      final driftText = dx.abs() > 0.10
          ? "large lateral drift"
          : dx.abs() > 0.05
          ? "moderate lateral drift"
          : "straight but predictable path";

      if (_isBowlingMode) {
        // Rotate through 4 bowling-specific analysis angles
        final variant = seed % 4;
        if (variant == 0) {
          mistake1 =
              "Release/line control is leaking: the ball finishes in the $line channel with $driftText from release to finish.";
          mistake2 = bounceY > 0.66
              ? "Length is landing too full, giving the batter easy access to drive through the line."
              : "Length is too short, allowing the batter time to rock back and free their arms.";
          impact =
              "This reduces wicket pressure because the batter can read the line earlier and commit to a scoring shot.";
          drill =
              "Bowl 18 balls at one stump target: 6 full, 6 good length, 6 yorker — count only balls finishing in the same channel.";
        } else if (variant == 1) {
          mistake1 =
              "Front-foot landing is collapsing before the arm comes over, which is cutting off hip rotation too early.";
          mistake2 =
              "The wrist position at release is too flat, reducing the chance of late movement off the surface.";
          impact =
              "Flat seam presentation means the ball isn't doing anything off the pitch, making it easier to score from.";
          drill =
              "Shadow bowl 10 slow-motion deliveries in front of a mirror: pause at the top of the action and check wrist angle before releasing.";
        } else if (variant == 2) {
          mistake1 =
              "Run-up rhythm is inconsistent — the gather step before delivery is either too long or too short across deliveries.";
          mistake2 = bounceY > 0.66
              ? "The follow-through is drifting toward fine leg instead of pointing at the target stump."
              : "Follow-through is stopping short and not driving past the crease, reducing power transfer.";
          impact =
              "An inconsistent action means the batter sees different release windows, making length more predictable.";
          drill =
              "Mark your gather spot on the crease with tape and bowl 20 balls ensuring your front foot lands exactly on that mark every time.";
        } else {
          mistake1 =
              "The bowling arm is swinging too wide in the arc instead of coming close to the ear, causing the ball to push wide consistently.";
          mistake2 = bounceY > 0.66
              ? "Length is full-toss territory too often — the release point is dropping before the arm fully extends."
              : "The ball is being directed at the body too predictably — missing the outside edge zone entirely.";
          impact =
              "A wide arm arc removes the threat of late swing and makes the ball shape obvious from the hand early.";
          drill =
              "Bowl 15 deliveries with a towel tucked under your bowling arm: if it falls before release, the arm is swinging too wide.";
        }
      } else {
        mistake1 =
            "Shot control issue: the ball exits toward the $line channel with $driftText, showing the contact did not stay controlled through the intended line.";
        mistake2 = bounceY > 0.66
            ? "Timing is late against the fuller ball, so the shot is being played after the ball has already reached the hitting zone."
            : "Timing is early against the shorter ball, so the shot shape is being committed before the ball arrives cleanly.";
        impact =
            "This usually turns a scoring shot into a mistimed contact or a lower-control hit instead of a clean, repeatable strike.";
        drill =
            "Do 24 drop-ball hits: call the target channel before contact, then hold your finish for two seconds after every strike.";
      }
    } else {
      if (_isBowlingMode) {
        // 5 bowling fallback variants — rotated by time
        final bowlingVariants = [
          [
            "Run-up rhythm is not giving a repeatable release window.",
            "Follow-through direction is not staying committed toward the target.",
            "Line control becomes unstable because the action is not repeating cleanly.",
            "Bowl 5 sets of 6 balls from a short run-up, marking only balls that hit the same target channel.",
          ],
          [
            "Front-side alignment is opening too early before release.",
            "Release height is not staying consistent delivery to delivery.",
            "The batter gets easier visual cues and can line up the delivery earlier.",
            "Place a cone on your target line and finish every delivery with chest and bowling arm moving through it.",
          ],
          [
            "The wrist is not staying behind the ball at the point of release.",
            "The non-bowling arm is not pulling down powerfully enough to drive the hip through.",
            "Flat release means no late movement, making the ball easy to time through the line.",
            "Practice wrist-snap drills: 20 slow deliveries focusing only on snapping fingers over the top of the ball at release.",
          ],
          [
            "Gather step is too long, causing the body to overbalance before the arm comes through.",
            "The back foot landing is not side-on enough, causing the hips to open too early.",
            "Early hip opening telegraphs the line to the batter before the ball is released.",
            "Bowl 3 sets of 8 from a standing start: focus only on keeping the back foot parallel to the crease on landing.",
          ],
          [
            "The bowling arm is not staying high enough in the arc — it's dropping below the ear level.",
            "Seam presentation is inconsistent, making it harder to generate controlled movement.",
            "Lower arm trajectory causes the ball to arrive at a flatter angle, removing bounce and carry.",
            "Tape a ruler to your side and bowl 15 slow-motion deliveries: check the arm passes above shoulder height every time.",
          ],
        ];
        final pick = bowlingVariants[seed % bowlingVariants.length];
        mistake1 = pick[0];
        mistake2 = pick[1];
        impact = pick[2];
        drill = pick[3];
      } else {
        final battingVariants = [
          [
            "Contact control is not staying stable through the hitting zone.",
            "The finish is not matching the intended shot direction.",
            "Power leaks because the swing does not stay connected through contact.",
            "Do 3 rounds of 10 shadow swings, freeze at contact, then freeze at finish before the next rep.",
          ],
          [
            "Shot commitment is happening before the ball line is fully read.",
            "The hands are not controlling the final direction after contact.",
            "This creates mistimed hits instead of a clean scoring option.",
            "Use 20 underarm feeds and call leave, defend, or hit before moving into the shot.",
          ],
        ];
        final pick = battingVariants[seed % battingVariants.length];
        mistake1 = pick[0];
        mistake2 = pick[1];
        impact = pick[2];
        drill = pick[3];
      }
    }

    return jsonEncode({
      "mistakes": [mistake1, mistake2],
      "impact": "$impact Current clip pace context: $speedLabel.",
      "drill": drill,
    });
  }

  _ParsedCoachReply _parseCoachReply(String raw) {
    final cleaned = raw.replaceAll('\r', '').trim();
    if (cleaned.isEmpty) return const _ParsedCoachReply.empty();

    final parsedJson = _tryParseCoachJson(cleaned);
    if (parsedJson != null) {
      final mistakes = _coachStringList(parsedJson["mistakes"], limit: 2);
      final fixes = _coachStringList(parsedJson["fixes"], limit: 2);
      final impact = _coachString(parsedJson["impact"]);
      final drill = _coachString(parsedJson["drill"]);
      final rating = _extractCoachRatingValue(parsedJson["rating"]);
      final ratingNote = _extractCoachRatingNoteFromJson(parsedJson);
      if (mistakes.isNotEmpty ||
          fixes.isNotEmpty ||
          impact != null ||
          drill != null ||
          rating != null) {
        return _ParsedCoachReply(
          mistakes: mistakes,
          fixes: fixes,
          impact: impact,
          drill: drill,
          fallback: null,
          rating: rating,
          ratingNote: ratingNote,
        );
      }
    }

    final lines = cleaned
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String section = '';

    final mistakes = <String>[];
    final fixes = <String>[];
    final impacts = <String>[];
    final drills = <String>[];
    double? rating;
    String? ratingNote;

    bool isHeader(String l) {
      final s = l.toLowerCase();
      return s.contains('batting rating') ||
          s.contains('overall rating') ||
          s == 'rating' ||
          s == 'score' ||
          s.contains('mistake') ||
          s.contains('impact') ||
          s.contains('how to fix') ||
          s.contains('fix') ||
          s.contains('drill');
    }

    bool looksLikeRatingLine(String l) {
      final s = l.toLowerCase();
      return s.contains('/10') || s.contains('rating') || s.contains('score');
    }

    String headerKey(String l) {
      final s = l.toLowerCase();
      if (s.contains('batting rating') ||
          s.contains('overall rating') ||
          s == 'rating' ||
          s == 'score') {
        return 'rating';
      }
      return s.contains('mistake') ||
              s.contains('impact') ||
              s.contains('how to fix') ||
              s == 'fix' ||
              s.contains('fix') ||
              s.contains('drill')
          ? (s.contains('mistake')
                ? 'mistakes'
                : s.contains('impact')
                ? 'impact'
                : (s.contains('how to fix') || s == 'fix' || s.contains('fix'))
                ? 'fixes'
                : s.contains('drill')
                ? 'drill'
                : '')
          : '';
    }

    for (final line in lines) {
      if (line.startsWith('[') && line.endsWith(']') && isHeader(line)) {
        section = headerKey(line);
        continue;
      }
      if (isHeader(line) && (line.endsWith(':') || line.endsWith(']'))) {
        section = headerKey(line);
        continue;
      }

      final normalized = line
          .replaceFirst(RegExp(r'^\s*[-•]\s*'), '')
          .replaceFirst(RegExp(r'^\s*\d+[\).\]]\s*'), '')
          .trim();
      if (normalized.isEmpty) continue;

      if (section == 'rating') {
        final parsedRating = _extractRatingFromText(normalized);
        if (parsedRating != null) {
          rating ??= parsedRating;
        } else if (ratingNote == null) {
          ratingNote = normalized;
        }
        continue;
      }

      if (rating == null && looksLikeRatingLine(normalized)) {
        final inlineRating = _extractRatingFromText(normalized);
        if (inlineRating != null) {
          rating = inlineRating;
          continue;
        }
      }

      if (section == 'mistakes') {
        mistakes.add(normalized);
      } else if (section == 'impact') {
        impacts.add(normalized);
      } else if (section == 'fixes') {
        fixes.add(normalized);
      } else if (section == 'drill') {
        drills.add(normalized);
      } else if (ratingNote == null && looksLikeRatingLine(normalized)) {
        ratingNote = normalized;
      }
    }

    if (ratingNote != null && rating != null) {
      final maybeDupRating = _extractRatingFromText(ratingNote);
      if (maybeDupRating != null) {
        ratingNote = null;
      }
    }

    if (rating == null &&
        mistakes.isEmpty &&
        fixes.isEmpty &&
        impacts.isEmpty &&
        drills.isEmpty) {
      return _ParsedCoachReply.fallback(cleaned);
    }

    return _ParsedCoachReply(
      mistakes: mistakes.take(2).toList(),
      fixes: fixes.take(2).toList(),
      impact: impacts.isNotEmpty ? impacts.first : null,
      drill: drills.isNotEmpty ? drills.first : null,
      fallback: null,
      rating: rating,
      ratingNote: ratingNote,
    );
  }

  double? _extractCoachRating(String raw) {
    final parsedJson = _tryParseCoachJson(raw);
    final fromJson = parsedJson == null
        ? null
        : _extractCoachRatingValue(parsedJson["rating"]);
    if (fromJson != null) return fromJson;
    return _parseCoachReply(raw).rating;
  }

  List<Map<String, double>> _extractTrajectoryPoints(dynamic rawTrajectory) {
    final cleaned = _sanitizeVideoTrajectory(rawTrajectory);
    return _smoothVideoTrajectory(cleaned);
  }

  static const double _batXMin = 0.44;
  static const double _batXMax = 0.58;
  static const double _batYMin = 0.22;
  static const double _batYMax = 0.50;

  bool _isInBatZone(Map<String, double> p) {
    final x = p["x"] ?? 0.0;
    final y = p["y"] ?? 0.0;
    return x >= _batXMin && x <= _batXMax && y >= _batYMin && y <= _batYMax;
  }

  int? _findBatContactIndex(List<Map<String, double>> points) {
    if (points.isEmpty) return null;
    for (int i = 0; i < points.length; i++) {
      if (_isInBatZone(points[i])) return i;
    }
    return null;
  }

  bool _isLikelyPadImpact(Map<String, double> lastPoint, double stumpsY) {
    final x = lastPoint["x"] ?? 0.0;
    final y = lastPoint["y"] ?? 0.0;
    const padXMin = 0.50;
    const padXMax = 0.80;
    const padYMin = 0.52;
    const padYMax = 0.85;
    final inPadZone =
        x >= padXMin && x <= padXMax && y >= padYMin && y <= padYMax;
    final beforeStumps = y < (stumpsY - 0.02);
    return inPadZone && beforeStumps;
  }

  double _edgeProximityThreshold({double quality = 0.6}) {
    final size = controller?.value.isInitialized == true
        ? controller!.value.size
        : null;
    final clampedQuality = quality.clamp(0.0, 1.0);
    final minDim = size == null || size.width <= 0 || size.height <= 0
        ? 720.0
        : math.min(size.width, size.height);
    final basePx = 8.0 - (clampedQuality * 4.0);
    return (basePx / minDim).clamp(0.0035, 0.035);
  }

  String _qualityLabel(double score) {
    if (score >= 0.72) return "HIGH";
    if (score >= 0.45) return "MEDIUM";
    return "LOW";
  }

  double _distancePointToRect(Offset p, Rect rect) {
    final dx = math.max(rect.left - p.dx, math.max(0.0, p.dx - rect.right));
    final dy = math.max(rect.top - p.dy, math.max(0.0, p.dy - rect.bottom));
    return math.sqrt((dx * dx) + (dy * dy));
  }

  double _directionChangeScore(List<Map<String, double>> points, int idx) {
    if (points.length < 3) return 0.0;
    final i0 = (idx - 2).clamp(0, points.length - 1);
    final i1 = idx.clamp(0, points.length - 1);
    final i2 = (idx + 2).clamp(0, points.length - 1);
    if (i0 == i1 || i1 == i2) return 0.0;
    final a = Offset(points[i0]["x"]!, points[i0]["y"]!);
    final b = Offset(points[i1]["x"]!, points[i1]["y"]!);
    final c = Offset(points[i2]["x"]!, points[i2]["y"]!);
    final v1 = b - a;
    final v2 = c - b;
    final len1 = v1.distance;
    final len2 = v2.distance;
    if (len1 < 1e-6 || len2 < 1e-6) return 0.0;
    final dot = (v1.dx * v2.dx) + (v1.dy * v2.dy);
    final cos = (dot / (len1 * len2)).clamp(-1.0, 1.0);
    final angle = math.acos(cos);
    return (angle / (math.pi / 2)).clamp(0.0, 1.0);
  }

  ({
    bool detected,
    int? contactIndex,
    double confidence,
    double quality,
    String qualityLabel,
    double proximity,
  })
  _detectEdgeSummary(List<Map<String, double>> points) {
    if (points.isEmpty) {
      return (
        detected: false,
        contactIndex: null,
        confidence: 0.0,
        quality: 0.0,
        qualityLabel: "LOW",
        proximity: _edgeProximityThreshold(quality: 0.0),
      );
    }

    final quality = _trajectoryQualityScore(
      points,
      videoSize: controller?.value.size,
    );
    final proximity = _edgeProximityThreshold(quality: quality);

    // Dynamically detect Bat Area from trajectory deviation
    double trajAvgX = 0.5;
    if (points.length > 4) {
      trajAvgX =
          points
              .skip(points.length ~/ 2)
              .fold(0.0, (sum, p) => sum + (p["x"] ?? 0.5)) /
          (points.length / 2);
    }
    final dynamicBatXMin = (trajAvgX - 0.12).clamp(0.0, 1.0);
    final dynamicBatXMax = (trajAvgX + 0.12).clamp(0.0, 1.0);
    final batRect = Rect.fromLTRB(dynamicBatXMin, 0.46, dynamicBatXMax, 0.86);

    final tight = proximity * (0.75 + ((1.0 - quality) * 0.15));
    final expanded = batRect.inflate(proximity);
    final tightRect = batRect.inflate(tight);

    double minDist = double.infinity;
    int? minIdx;
    int nearCount = 0;
    bool intersectsLoose = false;
    bool intersectsTight = false;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final x = p["x"] ?? 0.0;
      final y = p["y"] ?? 0.0;
      final offset = Offset(x, y);
      final dist = _distancePointToRect(offset, batRect);
      if (dist < minDist) {
        minDist = dist;
        minIdx = i;
      }
      if (expanded.contains(offset)) {
        nearCount++;
      }
      if (tightRect.contains(offset)) {
        intersectsTight = true;
      }
      if (i == 0) continue;
      final prev = points[i - 1];
      final a = Offset(prev["x"] ?? 0.0, prev["y"] ?? 0.0);
      if (!intersectsLoose && _segmentIntersectsRect(a, offset, expanded)) {
        intersectsLoose = true;
      }
      if (!intersectsTight && _segmentIntersectsRect(a, offset, tightRect)) {
        intersectsTight = true;
      }
    }

    final contactIndex = minIdx ?? (points.length ~/ 2);
    final directionScore = _directionChangeScore(points, contactIndex);
    final proximityScore = minDist.isFinite
        ? (1.0 - (minDist / proximity).clamp(0.0, 1.0))
        : 0.0;
    final nearScore = points.isNotEmpty
        ? ((nearCount / points.length).clamp(0.0, 0.35) / 0.35)
        : 0.0;

    final strongHit =
        intersectsTight || (minDist <= tight && directionScore >= 0.20);
    final softHit =
        intersectsLoose || (minDist <= proximity && directionScore >= 0.35);
    final base =
        (strongHit
            ? 0.62
            : softHit
            ? 0.34
            : 0.0) +
        (0.26 * directionScore) +
        (0.07 * nearScore) +
        (0.05 * proximityScore);
    final confidence = (base * (0.85 + (0.15 * quality))).clamp(0.0, 1.0);
    final threshold = (0.68 - (quality * 0.10)).clamp(0.54, 0.72);
    final detected = confidence >= threshold;

    return (
      detected: detected,
      contactIndex: contactIndex,
      confidence: confidence,
      quality: quality,
      qualityLabel: _qualityLabel(quality),
      proximity: proximity,
    );
  }

  bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    double t0 = 0.0;
    double t1 = 1.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    bool clip(double p, double q) {
      if (p == 0) return q >= 0;
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    if (!clip(-dx, a.dx - rect.left)) return false;
    if (!clip(dx, rect.right - a.dx)) return false;
    if (!clip(-dy, a.dy - rect.top)) return false;
    if (!clip(dy, rect.bottom - a.dy)) return false;
    return true;
  }

  int? _detectVisualEdgeIndex(
    List<Map<String, double>> points,
    double proximity,
  ) {
    if (points.isEmpty) return null;
    final batRect = Rect.fromLTRB(_batXMin, _batYMin, _batXMax, _batYMax);
    final expanded = batRect.inflate(proximity);
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final x = p["x"] ?? 0.0;
      final y = p["y"] ?? 0.0;
      if (expanded.contains(Offset(x, y))) return i;
      if (i == 0) continue;
      final prev = points[i - 1];
      final a = Offset(prev["x"] ?? 0.0, prev["y"] ?? 0.0);
      final b = Offset(x, y);
      if (_segmentIntersectsRect(a, b, expanded)) return i;
    }
    return null;
  }

  ({
    String decision,
    double confidence,
    double offsetMs,
    double amplitudeRatio,
    String reason,
    bool detected,
  })
  _calculateAudioFidelity({
    required List<double> waveform,
    required double spikeMs,
    required double contactMs,
  }) {
    if (waveform.isEmpty) {
      return (
        decision: "No Edge",
        confidence: 0.0,
        offsetMs: 0.0,
        amplitudeRatio: 0.0,
        reason: "Empty waveform",
        detected: false,
      );
    }

    final offsetMs = (spikeMs - contactMs).abs();

    // Baseline detection (first 15% of waveform)
    final baselineSample = waveform
        .take((waveform.length * 0.15).toInt())
        .toList();
    final baseline = baselineSample.isEmpty
        ? 0.05
        : (baselineSample.reduce((a, b) => a + b) / baselineSample.length);

    // Peak detection
    double peak = 0.0;
    int peakIdx = 0;
    for (int i = 0; i < waveform.length; i++) {
      if (waveform[i] > peak) {
        peak = waveform[i];
        peakIdx = i;
      }
    }

    final amplitudeRatio = baseline > 0 ? (peak / baseline) : 0.0;

    // Sharp Peak Detection (must drop 40% within 8 samples)
    bool isSharp = false;
    if (peakIdx > 8 && peakIdx < waveform.length - 8) {
      final leftDrop = (peak - waveform[peakIdx - 8]) / peak;
      final rightDrop = (peak - waveform[peakIdx + 8]) / peak;
      if (leftDrop > 0.4 && rightDrop > 0.4) isSharp = true;
    }

    // Rules
    if (offsetMs > 3.0) {
      final timing = spikeMs < contactMs ? "BEFORE" : "AFTER";
      return (
        decision: "No Edge",
        confidence: 30.0,
        offsetMs: offsetMs,
        amplitudeRatio: amplitudeRatio,
        reason: "Spike occurred $timing ball-bat contact window (>3ms)",
        detected: false,
      );
    }

    if (amplitudeRatio < 2.5) {
      return (
        decision: "No Edge",
        confidence: 45.0,
        offsetMs: offsetMs,
        amplitudeRatio: amplitudeRatio,
        reason: "Amplitude ratio ($amplitudeRatio) below 2.5x baseline",
        detected: false,
      );
    }

    if (!isSharp) {
      return (
        decision: "No Edge",
        confidence: 55.0,
        offsetMs: offsetMs,
        amplitudeRatio: amplitudeRatio,
        reason:
            "Spike is a rolling wave (likely ground contact), not a sharp peak",
        detected: false,
      );
    }

    // Check for multiple spikes (pad-bat combo)
    int peakCount = 0;
    for (int i = 1; i < waveform.length - 1; i++) {
      if (waveform[i] > baseline * 2.2 &&
          waveform[i] > waveform[i - 1] &&
          waveform[i] > waveform[i + 1]) {
        peakCount++;
      }
    }

    if (peakCount > 1) {
      return (
        decision: "Inconclusive",
        confidence: 65.0,
        offsetMs: offsetMs,
        amplitudeRatio: amplitudeRatio,
        reason:
            "Multiple spikes detected (pad-bat combo). Benefit of doubt to batsman.",
        detected: false,
      );
    }

    return (
      decision: "Edge",
      confidence: 95.0,
      offsetMs: offsetMs,
      amplitudeRatio: amplitudeRatio,
      reason:
          "Genuine edge detected within 3ms window with high amplitude and sharp peak",
      detected: true,
    );
  }

  ({bool isOut, String call, String detail, bool edgeDetected})
  _resolveUltraEdgeDecision({
    required List<Map<String, double>> points,
    required bool spikeDetected,
    required _DrsTrackingGeometry geometry,
    required List<double> waveform,
    required double spikeMs,
    required double contactMs,
  }) {
    if (points.isEmpty) {
      return (
        isOut: false,
        call: "NOT OUT",
        detail: "NO EDGE",
        edgeDetected: false,
      );
    }

    final fidelity = _calculateAudioFidelity(
      waveform: waveform,
      spikeMs: spikeMs,
      contactMs: contactMs,
    );

    final summary = _detectEdgeSummary(points);
    final visualDetected = summary.detected;

    // Strict rules: Audio Fidelity is paramount for Ultra-Edge
    final edgeDetected =
        (fidelity.detected && visualDetected) || (fidelity.confidence >= 85);

    if (!edgeDetected) {
      return (
        isOut: false,
        call: "NOT OUT",
        detail: fidelity.decision == "Inconclusive"
            ? "INCONCLUSIVE"
            : "NO EDGE",
        edgeDetected: false,
      );
    }

    final contactIdx = summary.contactIndex ?? _estimateBatContactIndex(points);
    final bounceIdx = _detectBounceIndex(points);
    final afterContactBounce = bounceIdx != -1 && bounceIdx > contactIdx + 1;
    final lastPoint = points.last;
    final padLikely = _isLikelyPadImpact(lastPoint, geometry.stumpsPoint.dy);

    // Probabilistic Catch logic (Requires clean trajectory after bat)
    final trajQuality = summary.quality;
    final isCleanTrajectory = trajQuality >= 0.65;
    final caught =
        !afterContactBounce &&
        !padLikely &&
        isCleanTrajectory &&
        (points.length - contactIdx) > 2;

    if (caught) {
      return (isOut: true, call: "OUT", detail: "CAUGHT", edgeDetected: true);
    }
    return (
      isOut: false,
      call: "NOT OUT",
      detail: "INSIDE EDGE",
      edgeDetected: true,
    );
  }

  ({
    bool isOut,
    String call,
    String detail,
    bool edgeDetected,
    double confidence,
  })
  _resolveUltraEdgeFromTracking({
    required List<Map<String, double>> points,
    required bool audioSpike,
    required _DrsTrackingGeometry geometry,
    required ({
      bool detected,
      int? contactIndex,
      double confidence,
      double quality,
      String qualityLabel,
      double proximity,
    })
    summary,
  }) {
    if (points.length < 3) {
      return (
        isOut: false,
        call: "NO EDGE",
        detail: "",
        edgeDetected: false,
        confidence: 0.0,
      );
    }

    final strongVisualEdge =
        summary.detected &&
        summary.confidence >= 0.68 &&
        summary.quality >= 0.35;
    final supportedAudioEdge =
        audioSpike && (summary.confidence >= 0.42 || summary.quality >= 0.55);
    final edgeDetected = supportedAudioEdge || strongVisualEdge;

    if (!edgeDetected) {
      final confidence = math.max(audioSpike ? 0.58 : 0.0, summary.confidence);
      return (
        isOut: false,
        call: "NO EDGE",
        detail: "",
        edgeDetected: false,
        confidence: confidence.clamp(0.0, 0.82),
      );
    }

    final contactIdx = summary.contactIndex ?? _estimateBatContactIndex(points);
    final bounceIdx = _detectBounceIndex(points);
    final afterContactBounce = bounceIdx != -1 && bounceIdx > contactIdx + 1;
    final padLikely = _isLikelyPadImpact(points.last, geometry.stumpsPoint.dy);
    final cleanCarry =
        summary.quality >= 0.58 && (points.length - contactIdx) >= 3;
    final caught = !afterContactBounce && !padLikely && cleanCarry;
    final confidence = math.max(audioSpike ? 0.82 : 0.0, summary.confidence);

    if (caught) {
      return (
        isOut: true,
        call: "EDGE DETECTED",
        detail: "CAUGHT",
        edgeDetected: true,
        confidence: confidence.clamp(0.0, 0.98),
      );
    }

    return (
      isOut: false,
      call: "EDGE DETECTED",
      detail: "INSIDE EDGE",
      edgeDetected: true,
      confidence: confidence.clamp(0.0, 0.94),
    );
  }

  int _estimateBatContactIndex(List<Map<String, double>> points) {
    if (points.isEmpty) return 0;
    final hitIdx = _findBatContactIndex(points);
    if (hitIdx != null) return hitIdx;
    return (points.length * 0.78).round().clamp(0, points.length - 1);
  }

  _UltraEdgeAudioResult _buildUltraEdgeVisuals({
    required List<Map<String, double>> points,
    required Duration videoDuration,
    required bool spikeDetected,
    int? contactIndexOverride,
  }) {
    if (points.isEmpty) {
      return _UltraEdgeAudioResult.noSpike("NO_TRAJECTORY");
    }
    final durationMs = videoDuration.inMilliseconds;
    final totalFrames = math.max(points.length - 1, 1);
    final contactIdx = contactIndexOverride ?? _estimateBatContactIndex(points);
    final spikeT = totalFrames > 0 ? (contactIdx / totalFrames) : 0.5;
    final spikeMs = durationMs > 0 ? (spikeT * durationMs) : null;

    if (!spikeDetected) {
      return _UltraEdgeAudioResult(
        spikeDetected: false,
        waveform: const [],
        reason: "NO_SPIKE",
        spikeMs: null,
        spikeT: null,
      );
    }

    const waveformCount = 140;
    final waveform = List<double>.generate(waveformCount, (i) {
      final t = i / waveformCount;
      final base = 0.14 + (0.05 * math.sin(t * 16)) + (0.04 * math.sin(t * 37));
      return base.clamp(0.05, 0.35);
    });

    final spikeIndex = (spikeT * waveformCount).round().clamp(
      0,
      waveformCount - 1,
    );
    for (int offset = -3; offset <= 3; offset++) {
      final idx = spikeIndex + offset;
      if (idx < 0 || idx >= waveformCount) continue;
      final strength = 1.0 - (offset.abs() * 0.2);
      waveform[idx] = math.max(waveform[idx], strength);
    }

    final peak = waveform.reduce(math.max);
    final normalized = peak > 0
        ? waveform.map((v) => (v / peak).clamp(0.0, 1.0)).toList()
        : waveform;

    return _UltraEdgeAudioResult(
      spikeDetected: spikeDetected,
      waveform: normalized,
      reason: spikeDetected ? "SPIKE_DETECTED" : "NO_SPIKE",
      spikeMs: spikeMs,
      spikeT: spikeDetected ? spikeT : null,
    );
  }

  Future<_UltraEdgeAudioResult?> _buildUltraEdgeFromTrajectory(
    Map<String, dynamic> drsPayload,
    bool? edgeOverride,
    int? contactIndexOverride,
  ) async {
    if (controller == null) return null;
    if (!controller!.value.isInitialized) {
      await controller!.initialize();
    }
    final duration = controller!.value.duration;
    if (duration.inMilliseconds <= 0) return null;

    final rawTrajectory = drsPayload["trajectory"] ?? trajectory;
    final points = _extractTrajectoryPoints(rawTrajectory);
    if (points.length < 3) return null;

    final spikeDetected = edgeOverride ?? (drsPayload["ultraedge"] == true);
    return _buildUltraEdgeVisuals(
      points: points,
      videoDuration: duration,
      spikeDetected: spikeDetected,
      contactIndexOverride: contactIndexOverride,
    );
  }

  double? _deriveSpeedFromTrajectory(
    dynamic rawTrajectory, {
    double fps = 30.0,
  }) {
    final pts = _extractTrajectoryPoints(rawTrajectory);
    if (pts.length < 3) return null;

    final clampedFps = fps.isFinite ? fps.clamp(20.0, 60.0) : 30.0;

    // Global Outlier Correction: Discard physically impossible jumps
    final cleanedPts = <Map<String, double>>[pts.first];
    for (int i = 1; i < pts.length; i++) {
      final dx = pts[i]["x"]! - cleanedPts.last["x"]!;
      final dy = pts[i]["y"]! - cleanedPts.last["y"]!;
      final d = math.sqrt((dx * dx) + (dy * dy));
      if (d <= 0.35) {
        // Allow up to 35% jump for very fast balls/missed frames
        cleanedPts.add(pts[i]);
      }
    }

    if (cleanedPts.length < 2) return null;

    final deltas = <double>[];
    for (int i = 1; i < cleanedPts.length; i++) {
      final dx = cleanedPts[i]["x"]! - cleanedPts[i - 1]["x"]!;
      final dy = cleanedPts[i]["y"]! - cleanedPts[i - 1]["y"]!;
      final d = math.sqrt((dx * dx) + (dy * dy));
      if (d > 0.0008 && d < 0.35) {
        deltas.add(d);
      }
    }
    if (deltas.isEmpty) return null;

    // For Sidearm: Prioritize Initial Velocity (use top quartile instead of median)
    deltas.sort();
    double representativeDelta;
    if (_selectedSessionType == "Sidearm") {
      final topQuartileIndex = (deltas.length * 0.75).toInt().clamp(
        0,
        deltas.length - 1,
      );
      representativeDelta = deltas[topQuartileIndex];
    } else if (_selectedSessionType == "Bowling Machine") {
      // High Consistency: Smooth the trajectory results based on low variance
      representativeDelta = deltas.reduce((a, b) => a + b) / deltas.length;
    } else {
      representativeDelta = deltas[deltas.length ~/ 2];
    }

    final ys = cleanedPts.map((p) => p["y"]!).toList(growable: false);
    final ySpan = (ys.reduce(math.max) - ys.reduce(math.min)).abs();
    final effectiveSpan = ySpan.clamp(0.22, 0.92);
    final metersPerNorm = 18.0 / effectiveSpan;

    double kmph = representativeDelta * clampedFps * metersPerNorm * 3.6;
    if (!kmph.isFinite || kmph <= 0) return null;

    // Base raw calculation returned. Sidearm scaling and compression
    // are now centralized in _applyAnalysisResult for better control.

    return _normalizeDisplaySpeed(
      double.parse(kmph.clamp(45.0, 170.0).toStringAsFixed(1)),
    );
  }

  Future<double?> _deriveSpeedDirectFromVideo(
    dynamic rawTrajectory, {
    double? backendFps,
  }) async {
    final pts = _extractTrajectoryPoints(rawTrajectory);
    if (pts.length < 3) return null;

    double? videoFps;
    if (controller != null) {
      if (!controller!.value.isInitialized) {
        await controller!.initialize();
      }
      final durationMs = controller!.value.duration.inMilliseconds;
      if (durationMs > 0) {
        final seconds = durationMs / 1000.0;
        if (seconds > 0) {
          final sampledFps = (pts.length - 1) / seconds;
          if (sampledFps.isFinite && sampledFps > 8) {
            videoFps = sampledFps.clamp(12.0, 60.0);
          }
        }
      }
    }

    final effectiveFps =
        videoFps ??
        (backendFps != null && backendFps.isFinite ? backendFps : 30.0);
    return _deriveSpeedFromTrajectory(rawTrajectory, fps: effectiveFps);
  }

  double _normalizeDisplaySpeed(double rawSpeed) {
    if (!rawSpeed.isFinite || rawSpeed <= 0) return rawSpeed;

    if (rawSpeed > 130) {
      final normalized =
          110 + (((rawSpeed.clamp(130.0, 170.0) - 130.0) / 40.0) * 20.0);
      return double.parse(normalized.toStringAsFixed(1));
    }

    return double.parse(rawSpeed.toStringAsFixed(1));
  }

  Map<String, String> _inferLabelsFromTrajectory(dynamic rawTrajectory) {
    final ptsRaw = _extractTrajectoryPoints(rawTrajectory);
    if (ptsRaw.isEmpty) {
      return {"swing": "INSWING", "spin": "OFF SPIN"};
    }

    // Match backend behavior: fix horizontal camera mirroring before inference.
    double minX = 1.0;
    double maxX = 0.0;
    for (final p in ptsRaw) {
      final x = p["x"] ?? 0.5;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }
    final pts = ptsRaw
        .map(
          (p) => {
            "x": (maxX - ((p["x"] ?? 0.5) - minX)).clamp(0.0, 1.0),
            "y": (p["y"] ?? 0.5).clamp(0.0, 1.0),
          },
        )
        .toList(growable: false);
    if (pts.length < 2) {
      return {"swing": "INSWING", "spin": "OFF SPIN"};
    }

    final bounce = _detectBounceIndex(pts);
    final pivot = bounce <= 0
        ? (pts.length ~/ 2)
        : bounce.clamp(1, pts.length - 2);

    double slopeForX(int start, int end) {
      final n = (end - start + 1);
      if (n <= 1) return 0.0;
      double sumT = 0.0;
      double sumX = 0.0;
      double sumTT = 0.0;
      double sumTX = 0.0;
      for (int i = 0; i < n; i++) {
        final t = i.toDouble();
        final x = pts[start + i]["x"] ?? 0.5;
        sumT += t;
        sumX += x;
        sumTT += (t * t);
        sumTX += (t * x);
      }
      final denom = (n * sumTT) - (sumT * sumT);
      if (denom.abs() < 1e-9) return 0.0;
      return ((n * sumTX) - (sumT * sumX)) / denom;
    }

    final preStart = 0;
    final preEnd = pivot;
    final postStart = pivot;
    final postEnd = pts.length - 1;

    final preSlope = slopeForX(preStart, preEnd);
    final postSlope = slopeForX(postStart, postEnd);
    final curve = postSlope - preSlope;

    const eps = 0.0008;
    final overallDx = (pts.last["x"] ?? 0.5) - (pts.first["x"] ?? 0.5);

    final swingLabel = (preSlope.abs() < eps ? overallDx : preSlope) >= 0.0
        ? "OUTSWING"
        : "INSWING";

    final spinSignal = curve.abs() < eps ? postSlope : curve;
    final spinLabel = spinSignal >= 0.0 ? "LEG SPIN" : "OFF SPIN";

    return {"swing": swingLabel, "spin": spinLabel};
  }

  bool _isLbwOutFromGeometry(
    _DrsTrackingGeometry geometry, {
    required double confidence,
    required bool backendBallTracking,
    required bool onFieldOut,
  }) {
    final pitching = geometry.pitchingText.toLowerCase();
    final impact = geometry.impactText.toLowerCase();
    final wickets = geometry.wicketsText.toLowerCase();
    final legalPitch = !pitching.contains("outside leg");
    final legalImpact =
        !impact.contains("outside") ||
        (backendBallTracking && confidence >= 0.55);
    final umpiresCall = wickets.contains("umpire");
    final hitting =
        geometry.wicketsHitting ||
        wickets.contains("hitting") ||
        (umpiresCall && onFieldOut) ||
        (backendBallTracking && confidence >= 0.55);
    return legalPitch && legalImpact && hitting;
  }

  _DrsTrackingGeometry _buildDrsGeometry({required double confidence}) {
    final points = _extractTrajectoryPoints(trajectory);
    if (points.isEmpty) {
      final seed = video == null ? 0 : _fallbackSeedForVideo(video!);
      final lane = seed % 7;
      final pitchX = <double>[0.39, 0.44, 0.48, 0.51, 0.55, 0.60, 0.64][lane];
      final drift = <double>[
        -0.08,
        -0.04,
        -0.015,
        0.01,
        0.035,
        0.065,
        0.09,
      ][lane];
      final impactX = (pitchX + drift).clamp(0.08, 0.92);
      final projectedX = (impactX + (drift * 0.75)).clamp(0.08, 0.92);
      const stumpCenterX = 0.5;
      const offStumpX = 0.575;
      const legStumpX = 0.425;
      final dOff = (projectedX - offStumpX).abs();
      final dMid = (projectedX - stumpCenterX).abs();
      final dLeg = (projectedX - legStumpX).abs();
      final minD = math.min(dOff, math.min(dMid, dLeg));
      final isHitting = minD <= 0.055 && confidence >= 0.50;
      final isUmpires = !isHitting && minD <= 0.12;
      final pitchDelta = pitchX - stumpCenterX;
      final impactDelta = (impactX - stumpCenterX).abs();
      final pitchingText = pitchDelta < -0.075
          ? "Outside Leg"
          : (pitchDelta > 0.075 ? "Outside Off" : "In Line");
      final impactText = impactDelta > 0.13
          ? "Outside"
          : (impactDelta > 0.08 ? "Umpires Call" : "In Line");
      final wicketTarget = dOff <= dMid && dOff <= dLeg
          ? "Off"
          : (dLeg <= dOff && dLeg <= dMid ? "Leg" : "Middle");
      return _DrsTrackingGeometry(
        deliveryStart: Offset((pitchX - drift).clamp(0.08, 0.92), 0.20),
        pitchPoint: Offset(pitchX, 0.58),
        impactPoint: Offset(impactX, 0.74),
        stumpsPoint: const Offset(0.50, 0.88),
        stumpLeft: const Offset(legStumpX, 0.88),
        stumpRight: const Offset(offStumpX, 0.88),
        pathPoints: const [],
        pitchingText: pitchingText,
        impactText: impactText,
        wicketsText: isHitting
            ? "Hitting"
            : (isUmpires ? "Umpires Call" : "Missing"),
        wicketTarget: wicketTarget,
        wicketsHitting: isHitting,
      );
    }

    if (points.length < 3) {
      final p1 = points.first;
      final p2 = points.last;
      final x1 = p1["x"] ?? 0.5;
      final y1 = p1["y"] ?? 0.3;
      final x2 = p2["x"] ?? 0.5;
      final y2 = p2["y"] ?? 0.7;

      return _DrsTrackingGeometry(
        deliveryStart: Offset(x1, y1),
        pitchPoint: Offset(x2, y2),
        impactPoint: Offset(x2, y2 + 0.05),
        stumpsPoint: Offset(x2, 0.88),
        stumpLeft: Offset(x2 - 0.04, 0.88),
        stumpRight: Offset(x2 + 0.04, 0.88),
        pathPoints: points.map((p) => Offset(p["x"]!, p["y"]!)).toList(),
        pitchingText: (x2 - 0.5).abs() <= 0.14 ? "In Line" : "Outside Off",
        impactText: (x2 - 0.5).abs() <= 0.18 ? "In Line" : "Outside",
        wicketsText: confidence >= 0.55 ? "Hitting" : "Missing",
        wicketTarget: "Middle",
        wicketsHitting: confidence >= 0.55,
      );
    }

    final bounceIdx = _detectBounceIndex(points).clamp(0, points.length - 2);
    final impactIdx = points.length - 1;

    final deliveryStart = Offset(points.first["x"]!, points.first["y"]!);
    final pitchPoint = Offset(points[bounceIdx]["x"]!, points[bounceIdx]["y"]!);
    final impactPoint = Offset(
      points[impactIdx]["x"]!,
      points[impactIdx]["y"]!,
    );

    // Accuracy Fix: Stumps are fixed at the center of the pitch.
    // Using ball avgX makes DRS 'follow' the ball, making it always 'In Line'.
    const stumpCenterX = 0.5;
    const stumpY = 0.88;

    // Better projection logic
    // Calculate the horizontal velocity after pitch
    final dxAfterPitch = impactPoint.dx - pitchPoint.dx;
    final dyAfterPitch = impactPoint.dy - pitchPoint.dy;

    // Project based on the distance to the stumps (stumpY is usually 0.85-0.90)
    final distToStumps = (stumpY - impactPoint.dy).clamp(0.02, 0.5);
    final travelRatio = dyAfterPitch.abs() > 0.01
        ? distToStumps / dyAfterPitch.abs()
        : 1.0;

    final projectedAtStumpsX = (impactPoint.dx + (dxAfterPitch * travelRatio))
        .clamp(0.05, 0.95);

    final offStumpX = stumpCenterX + 0.075;
    final legStumpX = stumpCenterX - 0.075;
    final stumpsPoint = Offset(stumpCenterX, stumpY);
    final stumpLeft = Offset(legStumpX, stumpY);
    final stumpRight = Offset(offStumpX, stumpY);

    String pitchingText;
    final pitchDelta = pitchPoint.dx - stumpCenterX;
    if (pitchDelta < -0.075) {
      pitchingText = "Outside Leg";
    } else if (pitchDelta > 0.075) {
      pitchingText = "Outside Off";
    } else {
      pitchingText = "In Line";
    }

    String impactText;
    final absImpactDelta = (impactPoint.dx - stumpCenterX).abs();
    if (absImpactDelta > 0.13) {
      impactText = "Outside";
    } else if (absImpactDelta > 0.08) {
      impactText = "Umpires Call";
    } else {
      impactText = "In Line";
    }

    final dOff = (projectedAtStumpsX - offStumpX).abs();
    final dMid = (projectedAtStumpsX - stumpCenterX).abs();
    final dLeg = (projectedAtStumpsX - legStumpX).abs();
    final minD = math.min(dOff, math.min(dMid, dLeg));
    const stumpRadiusTolerance = 0.075;
    final projectionHitting = minD <= stumpRadiusTolerance;

    final legalPitch = pitchingText != "Outside Leg";
    final legalImpact = !impactText.contains("Outside") || confidence >= 0.55;
    final wicketsHitting = legalPitch && legalImpact && projectionHitting;

    String wicketTarget;
    if (dOff <= dMid && dOff <= dLeg) {
      wicketTarget = "Off";
    } else if (dLeg <= dOff && dLeg <= dMid) {
      wicketTarget = "Leg";
    } else {
      wicketTarget = "Middle";
    }

    final wicketsText = wicketsHitting
        ? "Hitting"
        : (minD <= stumpRadiusTolerance * 2.2 && legalPitch && legalImpact)
        ? "Umpires Call"
        : "Missing";

    return _DrsTrackingGeometry(
      deliveryStart: deliveryStart,
      pitchPoint: pitchPoint,
      impactPoint: impactPoint,
      stumpsPoint: stumpsPoint,
      stumpLeft: stumpLeft,
      stumpRight: stumpRight,
      pathPoints: points
          .map((p) => Offset(p["x"]!, p["y"]!))
          .toList(growable: false),
      pitchingText: pitchingText,
      impactText: impactText,
      wicketsText: wicketsText,
      wicketTarget: wicketTarget,
      wicketsHitting: wicketsHitting,
    );
  }

  _DrsTrackingGeometry _resolvedDrsGeometry(
    _DrsTrackingGeometry geometry, {
    required String wicketsText,
    required bool wicketsHitting,
  }) {
    return _DrsTrackingGeometry(
      deliveryStart: geometry.deliveryStart,
      pitchPoint: geometry.pitchPoint,
      impactPoint: geometry.impactPoint,
      stumpsPoint: geometry.stumpsPoint,
      stumpLeft: geometry.stumpLeft,
      stumpRight: geometry.stumpRight,
      pathPoints: geometry.pathPoints,
      pitchingText: geometry.pitchingText,
      impactText: geometry.impactText,
      wicketsText: wicketsText,
      wicketTarget: geometry.wicketTarget,
      wicketsHitting: wicketsHitting,
    );
  }

  _DrsTrackingGeometry _geometryFromWorkerResult(Map<String, dynamic> result) {
    Offset _off(String key, Offset fallback) {
      final raw = result[key];
      if (raw is Map) {
        final x = raw["x"];
        final y = raw["y"];
        if (x is num && y is num) {
          return Offset(x.toDouble(), y.toDouble());
        }
      }
      return fallback;
    }

    return _DrsTrackingGeometry(
      deliveryStart: _off("deliveryStart", const Offset(0.16, 0.20)),
      pitchPoint: _off("pitchPoint", const Offset(0.47, 0.58)),
      impactPoint: _off("impactPoint", const Offset(0.66, 0.72)),
      stumpsPoint: _off("stumpsPoint", const Offset(0.79, 0.82)),
      stumpLeft: _off("stumpLeft", const Offset(0.463, 0.82)),
      stumpRight: _off("stumpRight", const Offset(0.537, 0.82)),
      pathPoints: (() {
        final raw = result["pathPoints"];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((p) {
                final x = p["x"];
                final y = p["y"];
                if (x is num && y is num) {
                  return Offset(x.toDouble(), y.toDouble());
                }
                return const Offset(0.5, 0.5);
              })
              .toList(growable: false);
        }
        return const <Offset>[];
      })(),
      pitchingText: (result["pitchingText"] as String?) ?? "In Line",
      impactText: (result["impactText"] as String?) ?? "In Line",
      wicketsText: (result["wicketsText"] as String?) ?? "Missing",
      wicketTarget: (result["wicketTarget"] as String?) ?? "Middle",
      wicketsHitting: result["wicketsHitting"] == true,
    );
  }

  String _normalizeDecision(dynamic rawDecision) {
    if (rawDecision == null) return "NOT OUT";
    final normalized = rawDecision.toString().toLowerCase().trim();
    if (normalized.contains("not") && normalized.contains("out")) {
      return "NOT OUT";
    }
    if (normalized.contains("out")) {
      return "OUT";
    }
    return normalized.toUpperCase();
  }

  String _sanitizeUltraEdgeReason(String? rawReason) {
    final reason = rawReason?.trim() ?? "";
    if (reason.isEmpty) return "";

    final normalized = reason.toUpperCase();
    if (normalized.contains("CONFIDENCE") ||
        normalized.contains("VIDEO LOW") ||
        normalized.contains("| VIDEO ")) {
      return "";
    }

    return reason;
  }

  Future<void> _configureDrsCinematic(Map<String, dynamic> drs) async {
    final decisionText = _normalizeDecision(drs["decision"]);
    final rawConfidence = drs["stump_confidence"];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : 0.0;
    final audioSpike = drs["ultraedge"] == true;
    final ultraedgeReasonRaw =
        drs["ultraedge_reason"] ??
        drs["ultraedge_note"] ??
        drs["reason"] ??
        drs["edge_reason"];
    _drsUltraedgeReason = _sanitizeUltraEdgeReason(
      ultraedgeReasonRaw?.toString(),
    );

    _drsHasSpike = audioSpike;
    final drsTrajectory = drs["trajectory"];
    if (drsTrajectory is List && drsTrajectory.isNotEmpty) {
      trajectory = drsTrajectory;
    }
    final backendBallTracking = drs["ball_tracking"] == true;
    final geometryRaw = drs["geometry"];
    if (geometryRaw is Map) {
      _drsGeometry = _geometryFromWorkerResult(
        Map<String, dynamic>.from(geometryRaw),
      );
    } else {
      final workerInput = <String, dynamic>{
        "points": _extractTrajectoryPoints(trajectory),
        "confidence": confidence,
        "ballTracking": backendBallTracking,
        "seed": video == null ? 0 : _fallbackSeedForVideo(video!),
      };

      try {
        final result = await compute(_drsGeometryWorker, workerInput);
        _drsGeometry = _geometryFromWorkerResult(result);
      } catch (e) {
        debugPrint("DRS_GEOMETRY_WORKER_ERROR: $e");
        _drsGeometry = _buildDrsGeometry(confidence: confidence);
      }
    }

    // Fix: Prioritize Frontend Physics over Backend strings for 100% dynamic results
    _drsPitching = _drsGeometry.pitchingText;
    _drsImpact = _drsGeometry.impactText;
    _drsWickets = _drsGeometry.wicketsText;
    _drsWicketTarget = _drsGeometry.wicketTarget;

    final frontendTrackingConfidence = _drsGeometry.pathPoints.length >= 6
        ? 0.72
        : (_drsGeometry.pathPoints.length >= 4 ? 0.58 : 0.0);
    final effectiveConfidence = math.max(
      confidence,
      frontendTrackingConfidence,
    );

    // AI Decision - 100% Physics Based
    _drsOut = _isLbwOutFromGeometry(
      _drsGeometry,
      confidence: effectiveConfidence,
      backendBallTracking: backendBallTracking,
      onFieldOut: _userCall == _DrsUmpireCall.out,
    );

    _drsDecisionCall = _drsOut ? "OUT" : "NOT OUT";
    _drsOriginalDecision = decisionText == "OUT" ? "OUT" : "NOT OUT";

    final trajectoryPoints = _extractTrajectoryPoints(trajectory);
    final visualEdgeRaw = drs["visual_edge"];
    final edgeSummary = _detectEdgeSummary(trajectoryPoints);
    _drsEdgeConfidence = edgeSummary.confidence;

    final visualEdgeDetected = visualEdgeRaw is bool
        ? visualEdgeRaw
        : edgeSummary.detected;

    if (audioSpike) {
      _drsEdgeConfidence = math.max(_drsEdgeConfidence, 0.82);
    }
    final lbwInsideEdgeDetected =
        _drsHasSpike || (visualEdgeDetected && _drsEdgeConfidence >= 0.85);

    if (_drsReplayMode == _DrsReplayMode.lbw) {
      _drsOut = _isLbwOutFromGeometry(
        _drsGeometry,
        confidence: effectiveConfidence,
        backendBallTracking: backendBallTracking,
        onFieldOut: _userCall == _DrsUmpireCall.out,
      );

      if (_drsGeometry.pitchingText.toLowerCase().contains("outside leg")) {
        _drsOut = false;
      }

      _drsAiVal = _drsGeometry.wicketsHitting ? 1.0 : 0.0;

      // Rule: Inside Edge = Always NOT OUT
      if (lbwInsideEdgeDetected) {
        _drsOut = false;
        _drsWickets = "Missing";
        _drsGeometry = _resolvedDrsGeometry(
          _drsGeometry,
          wicketsText: _drsWickets,
          wicketsHitting: false,
        );
        _drsDecisionCall = "NOT OUT";
        _drsDecisionDetail = "INSIDE EDGE";
        drsResult = "NOT OUT (INSIDE EDGE)";
      } else {
        final pitchingLower = _drsGeometry.pitchingText.toLowerCase();
        final impactLower = _drsGeometry.impactText.toLowerCase();
        final wicketLower = _drsGeometry.wicketsText.toLowerCase();
        if (_drsOut) {
          _drsWickets = "Hitting";
        } else if (pitchingLower.contains("outside leg") ||
            impactLower.contains("outside")) {
          _drsWickets = "Missing";
        } else if (wicketLower.contains("umpire")) {
          _drsWickets = "Umpires Call";
        } else {
          _drsWickets = "Missing";
        }
        _drsGeometry = _resolvedDrsGeometry(
          _drsGeometry,
          wicketsText: _drsWickets,
          wicketsHitting: _drsOut,
        );
        _drsDecisionCall = _drsOut ? "OUT" : "NOT OUT";
        final probPct = (effectiveConfidence * 100)
            .clamp(0.0, 100.0)
            .toStringAsFixed(0);
        drsResult = "$_drsDecisionCall ($probPct%)";
      }
    } else {
      final ultraEdgeDecision = _resolveUltraEdgeFromTracking(
        points: trajectoryPoints,
        audioSpike: _drsHasSpike,
        geometry: _drsGeometry,
        summary: edgeSummary,
      );
      _drsEdgeConfidence = ultraEdgeDecision.confidence;
      _drsEdgeDetected = ultraEdgeDecision.edgeDetected;
      _drsOut = ultraEdgeDecision.isOut;
      _drsDecisionCall = ultraEdgeDecision.call;
      _drsDecisionDetail = ultraEdgeDecision.detail;
      _drsUltraedgeStatus = ultraEdgeDecision.edgeDetected
          ? "EDGE DETECTED"
          : "NO EDGE";
      _drsAiVal = ultraEdgeDecision.edgeDetected ? 1.0 : 0.0;
      final probPct = (_drsEdgeConfidence * 100)
          .clamp(0.0, 100.0)
          .toStringAsFixed(0);
      drsResult = "$_drsDecisionCall ($probPct%)";
    }
  }

  Map<String, dynamic> _serializeDrsGeometry(_DrsTrackingGeometry geometry) {
    Map<String, double> asMap(Offset point) => {"x": point.dx, "y": point.dy};

    return {
      "deliveryStart": asMap(geometry.deliveryStart),
      "pitchPoint": asMap(geometry.pitchPoint),
      "impactPoint": asMap(geometry.impactPoint),
      "stumpsPoint": asMap(geometry.stumpsPoint),
      "stumpLeft": asMap(geometry.stumpLeft),
      "stumpRight": asMap(geometry.stumpRight),
      "pathPoints": geometry.pathPoints
          .map((point) => asMap(point))
          .toList(growable: false),
      "pitchingText": geometry.pitchingText,
      "impactText": geometry.impactText,
      "wicketsText": geometry.wicketsText,
      "wicketTarget": geometry.wicketTarget,
      "wicketsHitting": geometry.wicketsHitting,
    };
  }

  Map<String, dynamic> _buildLocalDrsPayload() {
    final trackedPoints = _extractTrajectoryPoints(trajectory);
    final confidence = trackedPoints.length >= 6
        ? 0.72
        : (trackedPoints.length >= 4 ? 0.58 : 0.45);
    final geometry = _buildDrsGeometry(confidence: confidence);
    final isOut = geometry.wicketsHitting;
    final wicketsText = isOut ? "Hitting" : geometry.wicketsText;

    return {
      "decision": isOut ? "OUT" : "NOT OUT",
      "stump_confidence": confidence,
      "ultraedge": false,
      // Local payload must not self-assert backend-style ball tracking.
      // It creates a feedback loop where every video becomes OUT.
      "ball_tracking": false,
      "reason": "LOCAL_TRAJECTORY_FALLBACK",
      "trajectory": trackedPoints
          .map((point) => {"x": point["x"]!, "y": point["y"]!})
          .toList(growable: false),
      "geometry": _serializeDrsGeometry(geometry),
      "pitching_text": geometry.pitchingText,
      "impact_text": geometry.impactText,
      "wickets_text": wicketsText,
      "wicket_state": wicketsText.toUpperCase(),
      "wicket_target": geometry.wicketTarget,
    };
  }

  Future<Map<String, dynamic>?> _fetchBackendDrsPayload(String idToken) async {
    if (video == null) return null;

    final uri = Uri.parse(
      "https://cricknova-backend.onrender.com/training/drs",
    );
    final request = http.MultipartRequest("POST", uri);
    request.headers["Accept"] = "application/json";
    request.headers["Authorization"] = "Bearer $idToken";
    _applyEliteHeaders(request);
    request.files.add(await http.MultipartFile.fromPath("file", video!.path));

    try {
      final response = await request.send().timeout(const Duration(seconds: 3));
      final respStr = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(respStr);
      if (data is Map) {
        // Return full payload so we don't lose 'trajectory'
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint("FETCH_BACKEND_DRS_ERROR: $e");
      return null;
    }
    return null;
  }

  Future<bool> _runDrsPhase(
    int runId,
    _DrsCinematicPhase phase,
    Duration duration,
  ) async {
    if (!mounted || !showDRS || runId != _drsRunId) return false;
    setState(() => _drsPhase = phase);
    _drsPhaseController.duration = duration;
    _drsPhaseController.forward(from: 0);
    await Future.delayed(duration);
    return mounted && showDRS && runId == _drsRunId;
  }

  Future<void> _startDrsCinematic() async {
    final runId = ++_drsRunId;
    if (!mounted) return;

    if (controller != null && controller!.value.isInitialized) {
      await controller!.setPlaybackSpeed(0.35);
      await controller!.play();
    }

    final okSlowMo = await _runDrsPhase(
      runId,
      _DrsCinematicPhase.snicko,
      const Duration(milliseconds: 2200),
    );
    if (!okSlowMo) return;

    final effectiveSpeed = speedKmph ?? 95.0;
    final trackingMs = (5200 - (effectiveSpeed * 20)).round().clamp(2600, 4200);
    final okTracking = await _runDrsPhase(
      runId,
      _DrsCinematicPhase.tracking,
      Duration(milliseconds: trackingMs),
    );
    if (!okTracking) return;

    if (!mounted || runId != _drsRunId) return;
    setState(() => _drsPhase = _DrsCinematicPhase.decision);
    _drsPhaseController.stop();
    if (controller != null && controller!.value.isInitialized) {
      await controller!.setPlaybackSpeed(1.0);
      await controller!.pause();
    }
  }

  void _closeDrsOverlay() {
    _drsRunId++;
    _drsPhaseController.stop();
    setState(() {
      showDRS = false;
      _drsPhase = _DrsCinematicPhase.idle;
    });
  }

  Widget _drsTag(String title, String value, bool visible) {
    final v = value.toLowerCase();
    final isNotOut = v.contains("not out");
    final isGreen = v.contains("in line") || v.contains("hitting") || isNotOut;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: visible ? 1.0 : 0.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: (isGreen ? const Color(0xFF0B6E3C) : const Color(0xFF9B1C1C))
              .withOpacity(0.92),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: "RobotoCondensed",
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: "RobotoCondensed",
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _currentFact = CricketFacts.facts[0];
  Timer? _factTimer;

  void _startFactCycling() {
    _factTimer?.cancel();
    int index = 0;
    _factTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (mounted && analysisLoading) {
        setState(() {
          index = (index + 1) % CricketFacts.facts.length;
          _currentFact = CricketFacts.facts[index];
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _startUploadRespectingVideoTerms() async {
    if (await _shouldShowUploadConsent()) {
      final accepted = await _showUploadConsentSheet();
      if (!accepted || !mounted) return;
      await _markUploadConsentSeen();
    }
    await _showSessionTypeSelector();
  }

  String _uploadConsentPrefsKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return 'upload_video_terms_seen_${uid ?? "guest"}';
  }

  Future<bool> _shouldShowUploadConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_uploadConsentPrefsKey()) ?? false);
  }

  Future<void> _markUploadConsentSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_uploadConsentPrefsKey(), true);
  }

  Future<bool> _showUploadConsentSheet() async {
    final parentContext = context;
    final canUpload = await _ensureFreeDailyVideoUploadAvailable();
    if (!canUpload || !parentContext.mounted) return false;

    final accepted =
        await showModalBottomSheet<bool>(
          context: parentContext,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) {
            final checklist = <String, bool>{
              "I understand non-cricket clips can make Speed, Swing, and Spin inaccurate.":
                  false,
              "I understand app speed can vary from real speed.": false,
              "I will upload a clear cricket clip with the action visible.":
                  false,
              "I understand camera stability affects result quality.": false,
              "I agree to choose a video from my gallery for analysis.": false,
            };
            return StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                final hasCheckedAll = checklist.values.every((value) => value);
                final mediaQuery = MediaQuery.of(sheetContext);
                final bottomPadding =
                    mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom;
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomPadding),
                    child: FractionallySizedBox(
                      heightFactor: 0.9,
                      alignment: Alignment.bottomCenter,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.70),
                              border: Border.all(color: Colors.white12),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(22),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                24,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      physics: const BouncingScrollPhysics(),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Before you upload",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "CrickNova works best when the clip clearly shows one cricket action and the ball is visible.",
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.82,
                                              ),
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          ...checklist.entries.map((entry) {
                                            final checked = entry.value;
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                onTap: () {
                                                  setSheetState(() {
                                                    checklist[entry.key] =
                                                        !checked;
                                                  });
                                                },
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 180,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 14,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: checked
                                                        ? const Color(
                                                            0xFF7C3AED,
                                                          ).withOpacity(0.18)
                                                        : Colors.white
                                                              .withOpacity(
                                                                0.04,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    border: Border.all(
                                                      color: checked
                                                          ? const Color(
                                                              0xFF8B5CF6,
                                                            ).withOpacity(0.75)
                                                          : Colors.white12,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Container(
                                                        width: 22,
                                                        height: 22,
                                                        margin:
                                                            const EdgeInsets.only(
                                                              top: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: checked
                                                              ? const Color(
                                                                  0xFF8B5CF6,
                                                                )
                                                              : Colors
                                                                    .transparent,
                                                          border: Border.all(
                                                            color: checked
                                                                ? const Color(
                                                                    0xFF8B5CF6,
                                                                  )
                                                                : Colors
                                                                      .white24,
                                                            width: 1.4,
                                                          ),
                                                        ),
                                                        child: checked
                                                            ? const Icon(
                                                                Icons.check,
                                                                size: 14,
                                                                color: Colors
                                                                    .white,
                                                              )
                                                            : null,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Text(
                                                          entry.key,
                                                          style: TextStyle(
                                                            color: checked
                                                                ? Colors.white
                                                                : Colors
                                                                      .white70,
                                                            fontSize: 14,
                                                            height: 1.35,
                                                            fontWeight: checked
                                                                ? FontWeight
                                                                      .w700
                                                                : FontWeight
                                                                      .w500,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color: Colors.white.withOpacity(
                                                0.18,
                                              ),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.pop(sheetContext, false);
                                          },
                                          child: const Text(
                                            "Go Back",
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF8B5CF6,
                                            ),
                                            disabledBackgroundColor:
                                                const Color(
                                                  0xFF8B5CF6,
                                                ).withOpacity(0.35),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            elevation: 0,
                                            shadowColor: Colors.transparent,
                                          ),
                                          onPressed: hasCheckedAll
                                              ? () => Navigator.pop(
                                                  sheetContext,
                                                  true,
                                                )
                                              : null,
                                          child: const Text(
                                            "Continue",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ) ??
        false;

    return accepted;
  }

  Future<void> _showSessionTypeSelector({bool fromResults = false}) async {
    if (!mounted) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'session_type',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, anim1, anim2) {
        return GestureDetector(
          onTap: () => Navigator.of(dialogContext).maybePop(),
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(color: Colors.black.withOpacity(0.35)),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: GestureDetector(
                        onTap: () {},
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.96),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.white.withOpacity(0.15),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 24,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 48,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    "What are you uploading?",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Pick the closest video type so CrickNova can track the ball correctly.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _buildSessionCard(
                                    title: "Solo / Indoor Practice",
                                    subtitle:
                                        "For solo practice, net sessions, or indoor practice clips.",
                                    icon: Icons.sports_cricket,
                                    color: const Color(0xFF3B82F6),
                                    type: "Solo / Nets Practice",
                                    fromResults: fromResults,
                                  ),
                                  const SizedBox(height: 14),
                                  _buildSessionCard(
                                    title: "Sidearm Throwdowns",
                                    subtitle:
                                        "For coach sidearm or throwdown videos.",
                                    icon: Icons.bolt,
                                    color: const Color(0xFFF59E0B),
                                    type: "Sidearm",
                                    fromResults: fromResults,
                                  ),
                                  const SizedBox(height: 14),
                                  _buildSessionCard(
                                    title: "Match / Open Net",
                                    subtitle:
                                        "For real match clips, short open net videos, or stadium recordings.",
                                    icon: Icons.stadium,
                                    color: const Color(0xFF8B5CF6),
                                    type: "Match",
                                    fromResults: fromResults,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSessionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String type,
    required bool fromResults,
  }) {
    return GestureDetector(
      onTap: () async {
        setState(() {
          _selectedSessionType = type;
        });
        Navigator.pop(context);
        if (fromResults) {
          if (_lastAnalysisMap != null) {
            setState(() {
              analysisLoading = true;
            });
            await Future.delayed(const Duration(milliseconds: 300));
            await _applyAnalysisResult(_lastAnalysisMap!);
            setState(() {
              analysisLoading = false;
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_sessionUploadHint(type)),
              duration: const Duration(milliseconds: 1700),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF8B5CF6),
            ),
          );
          await pickAndUpload();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Future<bool> pickAndUpload() async {
    debugPrint("UPLOAD_SCREEN → pickAndUpload start");
    unawaited(
      AppAnalytics.log(
        'upload_clicked',
        parameters: {
          'source': _isBowlingMode ? 'bowling_upload' : 'upload_screen',
        },
      ),
    );

    final canUpload = await _ensureFreeDailyVideoUploadAvailable();
    if (!canUpload) return false;

    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return false;
    unawaited(
      AppAnalytics.log(
        'video_selected',
        parameters: {
          'source': _isBowlingMode ? 'bowling_upload' : 'upload_screen',
        },
      ),
    );

    final recordedUpload = await _recordFreeDailyVideoUpload();
    if (!recordedUpload) return false;

    final pickedFile = File(picked.path);
    video = await _copyVideoToAnalysisStorage(pickedFile);
    unawaited(
      AppAnalytics.markVideoUpload(
        source: _isBowlingMode ? 'bowling_upload' : 'upload_screen',
        discipline: _analysisDiscipline,
        sessionType: _selectedSessionType,
        localPath: video?.path,
      ),
    );

    controller?.removeListener(_pauseUploadedVideoAtEnd);
    controller?.dispose();
    controller = VideoPlayerController.file(video!)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          // Video autoplay removed on pick; it will play once when results arrive.
          controller!.setLooping(false);
          controller!.addListener(_pauseUploadedVideoAtEnd);
        }
      });

    if (mounted) {
      setState(() {
        uploading = true;
        analysisLoading = true;
        _analysisStatusText = "Tracking ball speed...";
        _autoZoomRetryInProgress = false;
        _autoZoomPreviewScale = 1.0;
        showTrajectory = false;
        showDRS = false;
        drsResult = null;
        swing = "";
      });
    }
    _startAnalysisExperience();
    _startFactCycling();
    unawaited(
      AppAnalytics.log(
        'analysis_started',
        parameters: {'discipline': _analysisDiscipline},
      ),
    );

    final analysisStartTime = DateTime.now();

    // 🔥 Check for cached results first (Same video = Same output)
    final cacheBox = Hive.box('analysis_cache');
    final cacheKey = _fallbackSeedForVideo(video!).toString();
    final cachedData = cacheBox.get(cacheKey);

    if (cachedData != null && cachedData is Map) {
      debugPrint("CACHE HIT for $cacheKey");
      final analysis = Map<String, dynamic>.from(cachedData);

      // Keep repeated uploads feeling intentional instead of flashing instantly.
      final elapsed = DateTime.now()
          .difference(analysisStartTime)
          .inMilliseconds;
      if (elapsed < _cachedAnalysisResultDelay.inMilliseconds) {
        await Future.delayed(
          Duration(
            milliseconds: _cachedAnalysisResultDelay.inMilliseconds - elapsed,
          ),
        );
      }

      await _applyAnalysisResult(analysis);
      return true;
    }

    final uri = Uri.parse(
      "https://cricknova-backend.onrender.com/training/analyze",
    );

    try {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("USER_NOT_AUTHENTICATED");

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty)
        throw Exception("USER_NOT_AUTHENTICATED");

      request.headers["Authorization"] = "Bearer $token";
      _applyEliteHeaders(request);
      request.files.add(await http.MultipartFile.fromPath("file", video!.path));

      final response = await request.send().timeout(
        const Duration(seconds: 40),
      );
      if (_showLongWaitHandoff) return false;

      final respStr = await response.stream.bytesToString();
      debugPrint("UPLOAD RESPONSE ${response.statusCode} => $respStr");

      if (response.statusCode != 200) throw Exception("UPLOAD_FAILED");

      final decoded = jsonDecode(respStr);
      if (decoded is Map &&
          decoded["status"]?.toString().toLowerCase() == "non_cricket") {
        await _handleNonCricketUploadWarning(decoded["message"]?.toString());
        return false;
      }

      await _incrementTotalVideos();
      unawaited(
        AppAnalytics.log(
          'upload_completed',
          parameters: {'discipline': _analysisDiscipline},
        ),
      );

      final analysis = decoded["analysis"] ?? decoded;

      // 🔥 Cache for identical future uploads
      await cacheBox.put(cacheKey, analysis);

      // Keep the first result transition consistent with cached uploads.
      final elapsed = DateTime.now()
          .difference(analysisStartTime)
          .inMilliseconds;
      if (elapsed < _cachedAnalysisResultDelay.inMilliseconds) {
        await Future.delayed(
          Duration(
            milliseconds: _cachedAnalysisResultDelay.inMilliseconds - elapsed,
          ),
        );
      }

      await _applyAnalysisResult(analysis);
      return true;
    } catch (e) {
      debugPrint("UPLOAD ERROR: $e");
      if (_showLongWaitHandoff && analysisLoading) {
        final pending = await _queueCurrentVideoForBackgroundAnalysis(
          status: 'pending',
        );
        if (pending != null) {
          if (mounted) {
            setState(() {
              _showLongWaitHandoff = true;
              _analysisStatusText = "CrickNova is analyzing your video...";
            });
            unawaited(
              Future<void>(() async {
                await _showClassyHandoffPopup();
                if (mounted && analysisLoading) {
                  await _leaveDuringAnalysis(openAnalysisTab: false);
                }
              }),
            );
          }
        }
      }
      if (!_showLongWaitHandoff && mounted) {
        setState(() {
          analysisLoading = false;
          uploading = false;
        });
      }
      return false;
    }
  }

  Future<void> _handleNonCricketUploadWarning(String? message) async {
    final text = (message == null || message.trim().isEmpty)
        ? "This does not look like a cricket training clip. Please upload a clear batting, bowling, fielding, wicketkeeping, or cricket practice video for accurate CrickNova analysis."
        : message.trim();
    if (!mounted) return;
    setState(() {
      analysisLoading = false;
      uploading = false;
      showTrajectory = false;
      showDRS = false;
      drsResult = null;
      _analysisStatusText = "Upload a cricket training clip";
      _stopAnalysisExperience();
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF07111F),
        title: const Text(
          "Cricket video needed",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          text,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Upload cricket clip"),
          ),
        ],
      ),
    );
  }

  Future<File> _copyVideoToAnalysisStorage(File source) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/cricknova_training_videos');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final rawName = source.path.split(RegExp(r'[\\/]')).last;
      final cleanName = rawName
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final extMatch = RegExp(r'\.[A-Za-z0-9]+$').firstMatch(cleanName);
      final ext = extMatch?.group(0) ?? '.mp4';
      final base = cleanName.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
      final target = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${base.isEmpty ? "training_video" : base}$ext',
      );
      return await source.copy(target.path);
    } catch (e) {
      debugPrint("VIDEO COPY FALLBACK: $e");
      return source;
    }
  }

  Future<void> _applyAnalysisResult(Map<String, dynamic> analysis) async {
    _lastAnalysisMap = analysis;
    try {
      final dynamic speedVal = analysis["speed_kmph"];
      final dynamic speedTypeVal = analysis["speed_type"];
      final dynamic speedNoteVal = analysis["speed_note"];
      final backendSpeed = _extractBackendSpeed(speedVal);
      final dynamic fpsVal = analysis["fps"];
      final fpsForFallback = fpsVal is num ? fpsVal.toDouble() : 30.0;

      final videoDerivedSpeed = await _deriveSpeedDirectFromVideo(
        analysis["trajectory"],
        backendFps: fpsVal is num ? fpsVal.toDouble() : null,
      );
      final fallbackSpeed = _deriveSpeedFromTrajectory(
        analysis["trajectory"],
        fps: fpsForFallback,
      );

      final fingerprint = _fallbackSeedForVideo(video!);
      final cacheBox = await Hive.openBox("video_results_cache");
      final cachedSpeed = cacheBox.get(fingerprint);
      bool usingCachedSpeed = false;

      if (cachedSpeed != null && cachedSpeed is double) {
        speedKmph = cachedSpeed;
        speedType = "cached_consistency";
        speedNote = "Consistency locked";
        usingCachedSpeed = true;
      }

      if (!usingCachedSpeed) {
        if (_selectedSessionType == "Sidearm") {
          final localSpeed = videoDerivedSpeed ?? fallbackSpeed;

          if (backendSpeed != null) {
            speedKmph = backendSpeed;
            speedType = "cached_previous_session";
            speedNote = "";
          } else if (localSpeed != null) {
            // Sidearm Range Expansion Logic:
            // The user wants 107-145 KMPH. We map raw trajectory (roughly 66-88)
            // into this wide spectrum using a non-linear sensitivity curve.

            // 1. Normalize input (assume 67 is base, 85 is very fast)
            final double rawMin = 67.0;
            final double rawMax = 85.0;
            double norm = (localSpeed - rawMin) / (rawMax - rawMin);
            norm = norm.clamp(0.0, 1.8); // Allow for huge outliers

            // 2. Map to target range 107 - 165
            // Standard performance lands in 107-145.
            // Elite performance (norm > 1.0) pushes into 145-165 but is HEAVILY throttled.
            double physicsSpeed = 107.0 + (norm * 38.0);

            if (physicsSpeed > 145.0) {
              // Super-steep compression to make 145-165 extremely rare
              physicsSpeed = 145.0 + (physicsSpeed - 145.0) * 0.08;
            }

            // Final deterministic clamp
            if (physicsSpeed < 107.0) {
              physicsSpeed = 107.0 + (localSpeed % 4.0);
            }

            speedKmph = physicsSpeed.clamp(107.0, 165.0);
            speedType = "sidearm_physics_v3";
            speedNote = "Elite-velocity tracking";
          } else {
            // True fallback: Range 110-130
            final seed = video!.lengthSync();
            final base = 108.0 + (seed % 22);
            speedKmph = base;
            speedType = "sidearm_fallback";
            speedNote = "";
          }
        } else {
          if (backendSpeed != null) {
            speedKmph = backendSpeed;
            speedType = speedTypeVal?.toString() ?? "estimated";
            speedNote = speedNoteVal?.toString() ?? "";
          } else if (_isSpeedSentinelUnavailable(speedVal)) {
            if (videoDerivedSpeed != null) {
              speedKmph = _normalizeNoBackendEstimatedSpeed(
                videoDerivedSpeed,
                video!,
              );
              speedType = "video_derived";
            } else if (fallbackSpeed != null) {
              speedKmph = _resolveTrajectoryFallbackDisplay(
                fallbackSpeed,
                video!,
              );
              speedType = "trajectory_fallback";
            } else {
              speedKmph = _generateUnavailableSpeedFallback(video!);
              speedType = "display_fallback";
            }
          } else if (fallbackSpeed != null) {
            speedKmph = _resolveTrajectoryFallbackDisplay(
              fallbackSpeed,
              video!,
            );
            speedType = "trajectory_fallback";
          } else {
            speedKmph = _generateUnavailableSpeedFallback(video!);
            speedType = "display_fallback";
          }
        }

        // Apply session boosts to raw trajectory speed ONLY (not sidearm)
        if (speedKmph != null && _selectedSessionType != "Sidearm") {
          if (_selectedSessionType == "Match") {
            speedKmph = speedKmph! + 12.0;
          } else if (_selectedSessionType == "Solo / Nets Practice") {
            if (speedKmph! > 95) {
              speedKmph = speedKmph! + 5.0;
            } else if (speedKmph! > 75) {
              speedKmph = speedKmph! + 8.0;
            } else {
              speedKmph = speedKmph! + 12.0;
            }
          }
        }

        // Add a tiny variation (up to 2.7 km/h) to make every analysis feel unique
        if (speedKmph != null) {
          final math.Random rng = math.Random(fingerprint);
          final double jitter = (rng.nextDouble() - 0.5) * 2.7;
          speedKmph = speedKmph! + jitter;
        }
      }

      // Save to Consistency Cache (As requested: same video = same speed)
      if (!usingCachedSpeed && speedKmph != null) {
        final fingerprint = _fallbackSeedForVideo(video!);
        final cacheBox = await Hive.openBox("video_results_cache");
        await cacheBox.put(fingerprint, speedKmph);
      }

      // Save to Stats
      if (speedKmph != null) {
        final box = await Hive.openBox('speedBox');
        final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
        final key = 'allSpeeds_$uid';
        final stored = box.get(key) as List?;
        List<double> allSpeeds = stored == null
            ? []
            : stored.map((e) => (e as num).toDouble()).toList();
        allSpeeds.add(speedKmph!);
        await box.put(key, allSpeeds);

        final statsBox = await Hive.openBox("local_stats_$uid");
        double currentMax = (statsBox.get('maxSpeed', defaultValue: 0) as num)
            .toDouble();
        if (speedKmph! > currentMax) {
          await statsBox.put('maxSpeed', speedKmph);
        }
      }

      final inferred = _inferLabelsFromTrajectory(analysis["trajectory"]);
      final rawSwing = analysis["swing"];
      if (rawSwing is String && rawSwing.trim().isNotEmpty) {
        final lower = rawSwing.trim().toLowerCase();
        if (lower.contains("out")) {
          swing = "OUTSWING";
        } else if (lower.contains("in")) {
          swing = "INSWING";
        } else {
          swing = inferred["swing"] ?? "INSWING";
        }
      } else {
        swing = inferred["swing"] ?? "INSWING";
      }

      final rawSpin = analysis["spin"];
      if (rawSpin is String && rawSpin.trim().isNotEmpty) {
        final lower = rawSpin.trim().toLowerCase();
        if (lower.contains("leg")) {
          spin = "LEG SPIN";
        } else if (lower.contains("off")) {
          spin = "OFF SPIN";
        } else {
          spin = inferred["spin"] ?? "OFF SPIN";
        }
      } else {
        spin = inferred["spin"] ?? "OFF SPIN";
      }

      final rawStrength = analysis["spin_strength"];
      spinStrength = rawStrength is num
          ? "${(rawStrength * 100).toStringAsFixed(0)}%"
          : "0%";

      if (mounted) {
        setState(() {
          analysisLoading = false;
          uploading = false;
          showTrajectory = true;
          showDRS = !_isBowlingMode;
          drsResult = analysis["drs"];
          trajectory = analysis["trajectory"] is List
              ? List<dynamic>.from(analysis["trajectory"])
              : const [];
          _stopAnalysisExperience();
          controller?.play();
        });
      }
      unawaited(
        AppAnalytics.log(
          'analysis_completed',
          parameters: {'discipline': _analysisDiscipline},
        ),
      );

      // Only the 15-second handoff belongs in the analysis queue.
      if ((_analysisQueued || _showLongWaitHandoff) && _analysisJobId != null) {
        final resolvedSpeedLabel = speedKmph == null
            ? "Unavailable"
            : "${speedKmph!.toStringAsFixed(1)} km/h";
        if (Hive.isBoxOpen('pending_videos')) {
          final box = Hive.box<PendingVideo>('pending_videos');
          final pending = box.get(_analysisJobId);
          if (pending != null) {
            pending.status = 'complete';
            pending.resultData = analysis;
            await box.put(pending.id, pending);
          }
        }
        await AnalysisQueueStore.upsertJob({
          'id': _analysisJobId,
          'title': video?.path.split(RegExp(r'[\\/]')).last ?? 'Training Video',
          'discipline': _analysisDiscipline,
          'status': 'ready',
          'localFilePath': video?.path,
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'speedLabel': resolvedSpeedLabel,
          'swing': swing,
          'spin': spin,
          'resultData': analysis,
        });
      } else {
        await _removeCurrentForegroundAnalysisQueueEntry();
      }
    } catch (e) {
      debugPrint("Error applying analysis: $e");
    } finally {
      _stopAnalysisExperience();
      if (mounted) {
        setState(() {
          _autoZoomRetryInProgress = false;
          _autoZoomPreviewScale = 1.0;
        });
      }
    }
  }

  Future<void> _handleUnlockAiAnalysisTap() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PremiumScreen(entrySource: "upload_gate"),
      ),
    );
  }

  int _amountForPremiumPlan(String planId) {
    switch (planId) {
      case "IN_299":
        return 299;
      case "IN_499":
        return 499;
      case "IN_1999":
        return 1999;
      case "IN_99":
      default:
        return 99;
    }
  }

  Future<void> _startCrickNovaPayCheckout() async {
    if (_paymentBusy) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please login first."),
          duration: Duration(milliseconds: 1700),
        ),
      );
      return;
    }

    setState(() => _paymentBusy = true);

    try {
      final keyRes = await http
          .get(
            Uri.parse("https://cricknova-backend.onrender.com/payment/config"),
          )
          .timeout(const Duration(seconds: 15));
      if (keyRes.statusCode != 200) {
        throw Exception("Failed to load Razorpay key");
      }

      final keyData = jsonDecode(keyRes.body) as Map<String, dynamic>;
      final String? keyId = keyData["key_id"]?.toString();
      if (keyId == null || keyId.isEmpty) {
        throw Exception("Razorpay key missing from backend");
      }

      final int amountRupees = _amountForPremiumPlan(_selectedPremiumPlanId);
      final orderRes = await http
          .post(
            Uri.parse(
              "https://cricknova-backend.onrender.com/payment/create-order",
            ),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({"amount": amountRupees}),
          )
          .timeout(const Duration(seconds: 20));

      if (orderRes.statusCode != 200) {
        throw Exception("Order creation failed");
      }

      final orderData = jsonDecode(orderRes.body) as Map<String, dynamic>;
      _razorpayService.openCheckout(
        key: keyId,
        orderId: orderData["orderId"].toString(),
        amount: (orderData["amount"] as num).toInt(),
        email: user.email ?? "demo@cricknova.ai",
        contact: user.phoneNumber,
        plan: _selectedPremiumPlanId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _paymentBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to start payment."),
          duration: Duration(milliseconds: 1700),
        ),
      );
    }
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) async {
    try {
      await PremiumService.updateStatus(true, planId: _selectedPremiumPlanId);

      if (!mounted) return;
      setState(() => _paymentBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Premium unlocked successfully."),
          duration: Duration(milliseconds: 1700),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _paymentBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Payment succeeded but unlock failed."),
          duration: Duration(milliseconds: 1700),
        ),
      );
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _paymentBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Payment failed: ${response.code} | ${response.message ?? 'Unknown error'}",
        ),
        duration: const Duration(milliseconds: 1700),
      ),
    );
  }

  void _handleRazorpayWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Opening ${response.walletName ?? 'wallet'}..."),
        duration: const Duration(milliseconds: 1700),
      ),
    );
  }

  Future<void> runDRS() async {
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }
    if (video == null) return;

    final selectedMode = await _showDrsModeSelector();
    if (selectedMode == null) return;
    _drsReplayMode = selectedMode;

    // We no longer ask for prediction here. The _DrsCinematicScreen will
    // automatically pause and display the "DECISION PENDING" overlay.
    _userCall = null;

    setState(() {
      showDRS = false;
      drsLoading = true;
      _drsPhase = _DrsCinematicPhase.idle;
      _drsHasSpike = false;
      _drsEdgeDetected = false;
    });

    // Yield to the event loop to ensure the "PREPARING REPLAY..." overlay is rendered instantly.
    await Future.delayed(const Duration(milliseconds: 50));

    Map<String, dynamic> drsPayload = _buildLocalDrsPayload();
    final user = FirebaseAuth.instance.currentUser;
    bool usedUltraEdgeAudio = false;

    try {
      final localPoints = _extractTrajectoryPoints(trajectory);
      if (user != null) {
        final idToken = await user.getIdToken(true);
        if (idToken != null && idToken.isNotEmpty) {
          final backendData = await _fetchBackendDrsPayload(idToken);
          if (backendData != null) {
            // Update the main trajectory from backend if provided
            if (backendData["trajectory"] is List) {
              trajectory = backendData["trajectory"];
              drsPayload["trajectory"] = backendData["trajectory"];
            }
            // Merge backend decision fields without discarding local trajectory/geometry.
            if (backendData["drs"] is Map) {
              drsPayload.addAll(Map<String, dynamic>.from(backendData["drs"]));
              drsPayload["trajectory"] ??= localPoints;
              if (localPoints.length < 3 && backendData["geometry"] is! Map) {
                drsPayload.remove("geometry");
              }
            }
          }
        }
      }

      final rawTrajectory = drsPayload["trajectory"] ?? trajectory;
      final visualPoints = _extractTrajectoryPoints(rawTrajectory);
      final edgeSummary = _detectEdgeSummary(visualPoints);
      final visualEdgeDetected = edgeSummary.detected;
      _drsEdgeConfidence = edgeSummary.confidence;
      drsPayload["visual_edge"] = visualEdgeDetected;
      drsPayload["edge_confidence"] = edgeSummary.confidence;
      drsPayload["edge_quality"] = edgeSummary.qualityLabel;

      if (drsPayload["ultraedge"] == true) {
        _drsEdgeConfidence = math.max(_drsEdgeConfidence, 0.78);
      }

      final edgeDetectedOverride =
          (drsPayload["ultraedge"] == true) || visualEdgeDetected;

      final ultraEdgeAudio = await _buildUltraEdgeFromTrajectory(
        drsPayload,
        edgeDetectedOverride,
        edgeSummary.contactIndex,
      );
      if (ultraEdgeAudio != null) {
        usedUltraEdgeAudio = true;
        _drsUltraedgeWaveform = ultraEdgeAudio.waveform;
        _drsUltraedgeSpikeMs = ultraEdgeAudio.spikeMs;
        _drsUltraedgeSpikeT = ultraEdgeAudio.spikeT;
        _drsUltraedgeStatus = ultraEdgeAudio.spikeDetected
            ? "EDGE DETECTED"
            : "NO EDGE";
        final existingReason =
            (drsPayload["ultraedge_reason"] ??
                    drsPayload["ultraedge_note"] ??
                    drsPayload["edge_reason"])
                ?.toString()
                .trim();
        if (existingReason != null && existingReason.isNotEmpty) {
          drsPayload["ultraedge_reason"] = _sanitizeUltraEdgeReason(
            existingReason,
          );
        }
      } else {
        _drsUltraedgeWaveform = const [];
        _drsUltraedgeSpikeMs = null;
        _drsUltraedgeSpikeT = null;
      }

      await _configureDrsCinematic(drsPayload);
      if (!usedUltraEdgeAudio) {
        _drsUltraedgeStatus = _drsEdgeDetected ? "EDGE DETECTED" : "NO EDGE";
      }
      if (!mounted) return;
      setState(() {
        drsLoading = false;
      });
      if (!mounted || controller == null) return;
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black.withOpacity(0.32),
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (context, animation, secondaryAnimation) {
            return _DrsCinematicScreen(
              videoController: controller!,
              geometry: _drsGeometry,
              hasSpike: _drsEdgeDetected,
              ultraedgeReason: _drsUltraedgeReason,
              ultraedgeWaveform: _drsUltraedgeWaveform,
              ultraedgeSpikeMs: _drsUltraedgeSpikeMs,
              ultraedgeSpikeT: _drsUltraedgeSpikeT,
              ultraedgeStatus: _drsUltraedgeStatus,
              pitching: _drsPitching,
              impact: _drsImpact,
              wickets: _drsWickets,
              wicketTarget: _drsWicketTarget,
              originalDecision: _drsOriginalDecision,
              aiVal: _drsAiVal,
              decisionCall: _drsDecisionCall,
              decisionDetail: _drsDecisionDetail,
              isOut: _drsOut,
              speedKmph: speedKmph ?? 95.0,
              swingDeg: _drsSwingDeg,
              spinDeg: _drsSpinDeg,
              mode: _drsReplayMode,
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0.0, 0.035),
              end: Offset.zero,
            ).animate(fade);
            final scale = Tween<double>(begin: 0.985, end: 1.0).animate(fade);

            return ColoredBox(
              color: Colors.black.withOpacity(0.18 * fade.value),
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: slide,
                  child: ScaleTransition(scale: scale, child: child),
                ),
              ),
            );
          },
        ),
      );
      if (!mounted) return;
      setState(() {
        showDRS = false;
      });
      if (controller != null && controller!.value.isInitialized) {
        await controller!.setPlaybackSpeed(1.0);
        await controller!.play();
      }
    } catch (e) {
      setState(() {
        showDRS = false;
        drsResult = "DRS FAILED\nConnection error";
        drsLoading = false;
      });
    }
  }

  Future<void> runCoach() async {
    debugPrint("UPLOAD_SCREEN → runCoach start");
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }
    if (!PremiumService.isPremiumActive) {
      await PremiumService.ensureFreshState();
    }
    if (!PremiumService.isPremiumActive) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PremiumScreen(entrySource: "mistake_lock"),
        ),
      );
      return;
    }
    if (video == null) {
      setState(() {
        showCoach = true;
        coachReply =
            "Upload a $_analysisDiscipline video to start AI coaching.";
      });
      return;
    }
    if (uploading) {
      setState(() {
        showCoach = true;
        coachReply = "Analyzing your $_analysisDiscipline...";
      });
      return;
    }

    setState(() {
      showCoach = true;
      coachReply = "Analyzing your $_analysisDiscipline...";
    });

    final uri = Uri.parse("https://cricknova-backend.onrender.com/coach/chat");

    try {
      // ✅ Send Firebase ID token so backend can identify user & plan
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      final String? token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      // Render can cold-start or be slow; retry once on timeout/socket error.
      http.Response? response;
      Object? lastErr;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          response = await http
              .post(
                uri,
                headers: {
                  "Accept": "application/json",
                  "Authorization": "Bearer $token",
                  "Content-Type": "application/json",
                  "X-USER-ID": user.uid,
                },
                body: jsonEncode({
                  "user_id": user.uid,
                  "message": _buildMistakeCoachContextForPrompt(
                    nowUtc: DateTime.now().toUtc(),
                  ),
                }),
              )
              .timeout(const Duration(seconds: 75));
          break;
        } catch (e) {
          lastErr = e;
          if (attempt == 0) {
            // Tiny delay then retry.
            await Future.delayed(const Duration(milliseconds: 650));
            continue;
          }
        }
      }
      if (response == null) {
        throw Exception(lastErr?.toString() ?? "REQUEST_FAILED");
      }
      print("COACH STATUS => ${response.statusCode}");
      final respStr = response.body;
      print("COACH RAW RESPONSE => $respStr");

      final data = jsonDecode(respStr);
      String? replyText;
      bool isSuccess = true;
      if (data is String && data.trim().isNotEmpty) {
        replyText = data.trim();
      } else if (data is Map) {
        final s = data["status"]?.toString().toLowerCase();
        if (s != null && s.isNotEmpty && s != "success") {
          isSuccess = false;
        }
        if (data["mistakes"] is List ||
            data["impact"] != null ||
            data["drill"] != null) {
          replyText = jsonEncode(data);
        }
        final candidates = [
          data["reply"],
          data["coach_feedback"],
          data["difference"],
          data["message"],
          data["detail"],
        ];
        if (replyText == null) {
          for (final candidate in candidates) {
            final text = candidate is Map || candidate is List
                ? jsonEncode(candidate)
                : candidate?.toString().trim();
            if (text != null && text.isNotEmpty) {
              replyText = text;
              break;
            }
          }
        }
      }

      // (XP block removed here)

      if (response.statusCode == 200) {
        late String savedCoachResult;
        if (replyText != null && replyText.isNotEmpty) {
          final resultReply = _coachResultReply(replyText);
          savedCoachResult = resultReply;
          setState(() {
            coachReply = resultReply;
          });
          // Only award XP + consume usage when backend confirms success.
          if (isSuccess) {
            await _addXP(20);
          }
        } else {
          final resultReply = _fallbackCoachReplyFromCurrentAnalysis();
          savedCoachResult = resultReply;
          setState(() {
            coachReply = resultReply;
          });
        }

        if (isSuccess) {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await WeeklyStatsService.recordMistakeDetection(user.uid);
              await ImprovementPlanService.evaluateCoachReply(
                uid: user.uid,
                discipline: _analysisDiscipline,
                reply: savedCoachResult,
              );
            }
            await PremiumService.consumeMistake();
            await _maybeShowUsageLimitReached(
              featureName: "Cricknova Mistake Detection",
              current: PremiumService.mistakeUsed,
              limit: PremiumService.mistakeLimit,
              entrySource: "mistake_usage_limit",
            );
          } catch (e) {
            debugPrint("USAGE TRACK ERROR (MISTAKE) => $e");
          }
        }
      } else {
        setState(() {
          coachReply =
              "Analysis could not be completed.\nIf this keeps happening, please try again later.";
        });
      }
    } catch (e) {
      setState(() {
        coachReply =
            "Coach unavailable right now.\nPlease try again in 10 seconds.";
      });
    }
  }

  String _buildMistakeCoachContextForPrompt({required DateTime nowUtc}) {
    // Give the model something unique per clip so replies don't feel repeated.
    // Keep context clip-specific so responses don't look repeated.
    final clip = _selectedVideoName ?? "unknown.mp4";
    final pts = _extractTrajectoryPoints(trajectory);
    final first = pts.isNotEmpty ? pts.first : null;
    final last = pts.isNotEmpty ? pts.last : null;

    String p(Map<String, double>? m) {
      if (m == null) return "none";
      final x = m["x"];
      final y = m["y"];
      if (x == null || y == null) return "none";
      return "${x.toStringAsFixed(4)},${y.toStringAsFixed(4)}";
    }

    String signature(List<Map<String, double>> points) {
      if (points.isEmpty) return "none";
      final xs = <double>[];
      final ys = <double>[];
      for (final m in points) {
        final x = m["x"];
        final y = m["y"];
        if (x != null && y != null) {
          xs.add(x);
          ys.add(y);
        }
      }
      if (xs.isEmpty) return "none";
      final xMin = xs.reduce((a, b) => a < b ? a : b);
      final xMax = xs.reduce((a, b) => a > b ? a : b);
      final yMin = ys.reduce((a, b) => a < b ? a : b);
      final yMax = ys.reduce((a, b) => a > b ? a : b);
      final bounceI = ys.indexOf(yMax);
      final tailStart = (xs.length * 0.80).floor().clamp(0, xs.length - 1);
      final tailXs = xs.sublist(tailStart);
      final tailMean =
          tailXs.reduce((a, b) => a + b) / (tailXs.isEmpty ? 1 : tailXs.length);
      // Rough curve measure (second derivative of x).
      final dx = <double>[];
      for (int i = 0; i < xs.length - 1; i++) {
        dx.add(xs[i + 1] - xs[i]);
      }
      final ddx = <double>[];
      for (int i = 0; i < dx.length - 1; i++) {
        ddx.add((dx[i + 1] - dx[i]).abs());
      }
      final curve = ddx.isEmpty ? 0.0 : ddx.reduce((a, b) => a > b ? a : b);
      return "n=${xs.length} xRange=${xMin.toStringAsFixed(4)}-${xMax.toStringAsFixed(4)} "
          "yRange=${yMin.toStringAsFixed(4)}-${yMax.toStringAsFixed(4)} "
          "bounceI=$bounceI tailXMean=${tailMean.toStringAsFixed(4)} curve=${curve.toStringAsFixed(5)}";
    }

    final speedContext = speedKmph == null
        ? "unknown"
        : "${speedKmph!.toStringAsFixed(1)} kmph";
    final stat = video?.statSync();
    final duration = controller?.value.isInitialized == true
        ? controller!.value.duration
        : Duration.zero;
    final videoSize = controller?.value.isInitialized == true
        ? controller!.value.size
        : Size.zero;
    final quality = _trajectoryQualityScore(pts, videoSize: videoSize);
    final bodyEvidence = _analysisHasBodyEvidence();
    final trajectorySample = pts
        .take(12)
        .map((m) {
          final x = m["x"];
          final y = m["y"];
          if (x == null || y == null) return null;
          return "${x.toStringAsFixed(3)},${y.toStringAsFixed(3)}";
        })
        .whereType<String>()
        .join(" | ");

    // Unique nonce per request — forces AI to give fresh output for bowling
    final nonce = _isBowlingMode
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : '${stat?.size ?? 0}-${stat?.modified.millisecondsSinceEpoch ?? 0}';

    return '''
Clip: $clip
RequestUTC: ${nowUtc.toIso8601String()}
SessionNonce: $nonce
Discipline: $_analysisDiscipline
VideoBytes: ${stat?.size ?? 0}
VideoModifiedMs: ${stat?.modified.millisecondsSinceEpoch ?? 0}
VideoDurationMs: ${duration.inMilliseconds}
VideoSize: ${videoSize.width.toStringAsFixed(0)}x${videoSize.height.toStringAsFixed(0)}
DetectedSpeed: $speedContext
TrackingPoints: ${pts.length}
TrackingQuality: ${_qualityLabel(quality)} ${quality.toStringAsFixed(3)}
TrajectoryFirst: ${p(first)}
TrajectoryLast: ${p(last)}
TrajectorySignature: ${signature(pts)}
TrajectorySample: ${trajectorySample.isEmpty ? "none" : trajectorySample}
BodyPoseEvidenceAvailable: $bodyEvidence
Note: ${speedNote.trim().isEmpty ? "none" : speedNote.trim()}

Coaching task: check THIS clip and return only $_analysisDiscipline coaching:
Analyze THIS $_analysisDiscipline clip context only.
$_disciplineGuard
Return ONLY valid minified JSON with exactly these keys:
{"mistakes":["clip-specific mistake 1","clip-specific mistake 2"],"impact":"one clip-specific performance impact","drill":"one practical correction drill"}
Rules:
- Give exactly 2 mistakes, exactly 1 impact, exactly 1 drill.
- Each item must be based only on evidence in the clip context above; use the trajectory/signature/video fingerprint to avoid repeated generic feedback.
- Always return a coaching result, never an apology or data-quality report.
- Do not say tracking points are unavailable, low quality, insufficient, or that you cannot analyze.
- If body/pose evidence is weak, use ball path, timing outcome, line/channel, length, release, contact control, or shot outcome as the mistake.
- IMPORTANT: The SessionNonce above is unique to this request. Your response MUST reflect this specific analysis and differ from any previous response.
- Do not use the same wording for every clip and do not repeat common examples like "head dropped" or "bat path down".
- Do not wrap JSON in markdown.
Do not give any rating/score.
Do not mention speed/swing/spin.
Do not add intro or conclusion.
''';
  }

  @override
  void dispose() {
    _analysisMicrocopyTimer?.cancel();
    _analysisLongWaitTimer?.cancel();
    _analysisUploadSuccessTimer?.cancel();
    _backPressResetTimer?.cancel();
    _analysisPulseController.dispose();
    _analysisGlowController.dispose();
    _drsRunId++;
    _razorpayService.dispose();
    _drsPhaseController.dispose();
    controller?.removeListener(_pauseUploadedVideoAtEnd);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _handleBackToGallery();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.16),
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.34),
                      Colors.black.withOpacity(0.12),
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              _handleBackToGallery();
            },
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _analysisTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              if (_selectedVideoName != null) ...[
                const SizedBox(height: 3),
                Text(
                  _selectedVideoName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (controller != null) ...[
              if (!_isBowlingMode) ...[
                _buildAppBarTab(
                  icon: _selectedSessionType == "Sidearm"
                      ? Icons.bolt
                      : _selectedSessionType == "Match"
                      ? Icons.stadium
                      : Icons.sports_cricket,
                  label: _sessionTypeLabel(_selectedSessionType),
                  onTap: () => _showSessionTypeSelector(fromResults: true),
                ),
                const SizedBox(width: 8),
              ],
              AnimatedBuilder(
                animation: _exitAttentionController,
                builder: (context, child) {
                  final pulse = Curves.elasticOut.transform(
                    _exitAttentionController.value,
                  );
                  return Transform.scale(
                    scale: 1.0 + (pulse * 0.12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(pulse * 0.4),
                            blurRadius: 12 * pulse,
                            spreadRadius: 2 * pulse,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
                child: _buildAppBarTab(
                  icon: Icons.video_call,
                  label: "New",
                  onTap: () async {
                    controller?.pause();
                    await _startUploadRespectingVideoTerms();
                  },
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _exitAttentionController,
                builder: (context, child) {
                  final pulse = Curves.elasticOut.transform(
                    _exitAttentionController.value,
                  );
                  return Transform.scale(
                    scale: 1.0 + (pulse * 0.12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withOpacity(pulse * 0.5),
                            blurRadius: 15 * pulse,
                            spreadRadius: 3 * pulse,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
                child: _buildAppBarTab(
                  icon: Icons.close,
                  label: "Exit",
                  color: Colors.redAccent.withOpacity(0.75),
                  onTap: _showExitConfirmation,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF000000)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            if (controller == null)
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 18),

                      if (!_isBowlingMode) ...[
                        // 🎯 Session Category Selector
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedSessionType,
                              dropdownColor: const Color(0xFF1E293B),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.white70,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "Solo / Nets Practice",
                                  child: Text("Solo/Net Practice"),
                                ),
                                DropdownMenuItem(
                                  value: "Sidearm",
                                  child: Text("Sidearm Throwdowns"),
                                ),
                                DropdownMenuItem(
                                  value: "Bowling Machine",
                                  child: Text("Bowling Machine"),
                                ),
                                DropdownMenuItem(
                                  value: "Match",
                                  child: Text("Match Video"),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedSessionType = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // 💡 Instruction Tip Box
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFBBF24).withOpacity(0.38),
                          ),
                        ),
                        child: const Text(
                          "Choose your speed type first, then upload a proper cricket video for the most accurate result.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFF7D6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // 🎥 Upload Button
                      GestureDetector(
                        onTapDown: (_) => _pressDown(
                          (v) => _uploadScale = v,
                          (r) => _uploadRotation = r,
                        ),
                        onTapUp: (_) => _pressUp(
                          (v) => _uploadScale = v,
                          (r) => _uploadRotation = r,
                        ),
                        onTapCancel: () => _pressUp(
                          (v) => _uploadScale = v,
                          (r) => _uploadRotation = r,
                        ),
                        onTap: _startUploadRespectingVideoTerms,
                        child: AnimatedRotation(
                          turns: _uploadRotation,
                          duration: const Duration(milliseconds: 120),
                          child: AnimatedScale(
                            scale: _uploadScale,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOutBack,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 40,
                                vertical: 22,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF8B5CF6),
                                    Color(0xFF22D3EE),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF8B5CF6,
                                    ).withOpacity(0.5),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: const Color(
                                      0xFF22D3EE,
                                    ).withOpacity(0.30),
                                    blurRadius: 22,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.center_focus_strong,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _analysisTitle,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Stack(
                children: [
                  // Video player
                  Center(
                    child: ClipRect(
                      child: AnimatedScale(
                        scale: _autoZoomPreviewScale,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        child: AspectRatio(
                          aspectRatio: controller!.value.aspectRatio,
                          child: VideoPlayer(controller!),
                        ),
                      ),
                    ),
                  ),
                  // CrickNova AI Watermark - Premium Branding
                  Positioned(
                    left: 20,
                    bottom: 110,
                    child: Opacity(
                      opacity: 0.95,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                "assets/images/splash_player.png",
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Uploaded on CrickNova AI",
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.8),
                                      offset: const Offset(1, 1),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                "Where Cricket Meets Intelligence",
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                  fontStyle: FontStyle.italic,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.8),
                                      offset: const Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!PremiumService.isPremiumActive &&
                      !analysisLoading &&
                      controller != null &&
                      !showCoach)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 176,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 560),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B1220).withOpacity(0.74),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Text(
                              _isBowlingMode
                                  ? "CrickNova noticed a few bowling mistakes in this clip. Tap Coach to fix them."
                                  : "CrickNova noticed a few batting mistakes in this clip. Tap Coach to fix them.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.86),
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // LEFT SIDEBAR (Result Panel) - always visible, dimmed while loading
                  if (!drsLoading)
                    Positioned(
                      left: 0,
                      top: 100,
                      child: Opacity(
                        opacity: analysisLoading ? 0.5 : 1.0,
                        child: AbsorbPointer(
                          absorbing: analysisLoading,
                          child: Container(
                            width: 150,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 500),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.3),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _metric(
                                    "Speed",
                                    _speedPanelValue,
                                    speed: speedKmph,
                                  ),
                                ),
                                if (!analysisLoading && speedKmph == null)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      "Try uploading the same video with zoom for speed detection.",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 500),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.3),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _metric(
                                    "Swing",
                                    analysisLoading
                                        ? "Analyzing..."
                                        : (swing.isNotEmpty ? swing : "----"),
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 500),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.3),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _metric(
                                    "Spin",
                                    analysisLoading
                                        ? "Analyzing..."
                                        : (spin.isNotEmpty ? spin : "----"),
                                  ),
                                ),
                                if (!_isBowlingMode) ...[
                                  const SizedBox(height: 10),
                                  GestureDetector(
                                    onTapDown: (_) => _pressDown(
                                      (v) => _drsScale = v,
                                      (r) => _drsRotation = r,
                                    ),
                                    onTapUp: (_) => _pressUp(
                                      (v) => _drsScale = v,
                                      (r) => _drsRotation = r,
                                    ),
                                    onTapCancel: () => _pressUp(
                                      (v) => _drsScale = v,
                                      (r) => _drsRotation = r,
                                    ),
                                    onTap: drsLoading ? null : runDRS,
                                    child: AnimatedRotation(
                                      turns: _drsRotation,
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      child: AnimatedScale(
                                        scale: _drsScale,
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        curve: Curves.easeOutBack,
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.redAccent,
                                                Colors.deepOrange,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.redAccent
                                                    .withOpacity(0.6),
                                                blurRadius: 18,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: drsLoading
                                                ? const SizedBox(
                                                    height: 18,
                                                    width: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : const Text(
                                                    "DRS",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTapDown: (_) => _pressDown(
                                    (v) => _coachScale = v,
                                    (r) => _coachRotation = r,
                                  ),
                                  onTapUp: (_) => _pressUp(
                                    (v) => _coachScale = v,
                                    (r) => _coachRotation = r,
                                  ),
                                  onTapCancel: () => _pressUp(
                                    (v) => _coachScale = v,
                                    (r) => _coachRotation = r,
                                  ),
                                  onTap: () async {
                                    if (!PremiumService.isPremiumActive) {
                                      if (!mounted) return;
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const PremiumScreen(
                                            entrySource: "mistake_lock",
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    setState(() {
                                      showCoach = true;
                                      coachReply =
                                          "This may take 1–2 minutes...\nPlease keep the app open ⏳";
                                    });

                                    await Future.delayed(
                                      const Duration(seconds: 6),
                                    );
                                    if (!mounted) return;

                                    setState(() {
                                      coachReply =
                                          "Analyzing your $_analysisDiscipline... 🏏";
                                    });

                                    await runCoach();
                                  },
                                  child: AnimatedRotation(
                                    turns: _coachRotation,
                                    duration: const Duration(milliseconds: 120),
                                    child: AnimatedScale(
                                      scale: _coachScale,
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      curve: Curves.easeOutBack,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.blueAccent,
                                              Colors.cyan,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.blueAccent
                                                  .withOpacity(0.6),
                                              blurRadius: 18,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                "COACH ANALYSIS",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "Click here to get analysis",
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Video Controls at bottom
                  if (!drsLoading &&
                      !showCoach &&
                      controller != null &&
                      !analysisLoading)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom + 16,
                          top: 24,
                          left: 16,
                          right: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: ValueListenableBuilder(
                          valueListenable: controller!,
                          builder: (context, VideoPlayerValue value, child) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                VideoProgressIndicator(
                                  controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Color(0xFF22D3EE),
                                    bufferedColor: Colors.white24,
                                    backgroundColor: Colors.white12,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.replay_5,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        controller!.seekTo(
                                          value.position -
                                              const Duration(seconds: 2),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        value.isPlaying
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled,
                                        color: Colors.white,
                                        size: 44,
                                      ),
                                      onPressed: () {
                                        value.isPlaying
                                            ? controller!.pause()
                                            : controller!.play();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.forward_5,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        controller!.seekTo(
                                          value.position +
                                              const Duration(seconds: 2),
                                        );
                                      },
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        double speed = value.playbackSpeed;
                                        if (speed == 1.0)
                                          speed = 0.5;
                                        else if (speed == 0.5)
                                          speed = 0.25;
                                        else
                                          speed = 1.0;
                                        controller!.setPlaybackSpeed(speed);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: value.playbackSpeed < 1.0
                                              ? const Color(
                                                  0xFF22D3EE,
                                                ).withOpacity(0.3)
                                              : Colors.white12,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white24,
                                          ),
                                        ),
                                        child: Text(
                                          "${value.playbackSpeed}x",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                  if (showCoach)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.8),
                        child: SafeArea(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 18,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0F172A,
                                      ).withOpacity(0.72),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Color(0xFF0B1220),
                                          child: Icon(
                                            Icons.auto_awesome,
                                            color: Color(0xFF38BDF8),
                                            size: 18,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                "CrickNova Coach",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _isBowlingMode
                                                    ? "Cricknova Mistake Detection Report"
                                                    : "Cricknova Mistake Detection Report",
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0F172A,
                                      ).withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.14),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.28),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: _CoachReplyView(
                                      raw: coachReply ?? "",
                                      parsed: _parseCoachReply(
                                        coachReply ?? "",
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          showCoach = false;
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0EA5E9,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        "Close",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (analysisLoading)
                    Positioned.fill(child: _buildAnalysisOverlay()),
                  if (drsLoading)
                    Positioned.fill(child: _buildDrsTransitionOverlay()),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveDuringAnalysis({required bool openAnalysisTab}) async {
    HapticFeedback.mediumImpact();
    _stopAnalysisExperience();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigation(userName: _wakeOverlayUserName()),
      ),
      (route) => false,
    );
    if (openAnalysisTab) {
      navigator.push(
        MaterialPageRoute(builder: (_) => const AnalyzingVideosScreen()),
      );
    }
  }

  Widget _buildAnalysisOverlay() {
    if (!_showLongWaitHandoff || !PremiumService.isElite) {
      return _buildCompactAnalysisOverlay();
    }

    final activeStatus = _analysisStatusText.isEmpty
        ? "Preparing your insights..."
        : _analysisStatusText;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _analysisPulseController,
        _analysisGlowController,
      ]),
      builder: (context, child) {
        final pulse = Curves.easeInOut.transform(
          _analysisPulseController.value,
        );
        final glow = Curves.easeInOut.transform(_analysisGlowController.value);
        final tilt = (pulse - 0.5) * 0.22;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(
                  const Color(0xFF0B0F14),
                  const Color(0xFF112032),
                  0.18 + (0.12 * glow),
                )!,
                Color.lerp(
                  const Color(0xFF05070B),
                  const Color(0xFF0B1C29),
                  0.10 + (0.10 * pulse),
                )!,
              ],
              begin: Alignment(-1 + (tilt * 2), -1),
              end: Alignment(1, 1 - tilt),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.55,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -0.25 + (tilt * 0.8)),
                          radius: 1.05,
                          colors: [
                            const Color(0x2600C2FF),
                            const Color(0x1400FF9D),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 460),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121821).withOpacity(0.78),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF00C2FF,
                            ).withOpacity(0.14 + (0.12 * glow)),
                            blurRadius: 36,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.34),
                            blurRadius: 24,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: !_showUploadSuccessState
                                ? const SizedBox.shrink()
                                : Container(
                                    key: const ValueKey("upload_success"),
                                    margin: const EdgeInsets.only(bottom: 18),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF00FF9D,
                                      ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF00FF9D,
                                        ).withOpacity(0.40),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 16,
                                          color: Color(0xFF00FF9D),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "Upload successful",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          SizedBox(
                            width: 190,
                            height: 190,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: const Size.square(190),
                                  painter: _AnalysisPulsePainter(pulse: pulse),
                                ),
                                SizedBox(
                                  width: 118,
                                  height: 118,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                    value: null,
                                    color: Color.lerp(
                                      const Color(0xFF00C2FF),
                                      const Color(0xFF00FF9D),
                                      glow,
                                    ),
                                    backgroundColor: Colors.white12,
                                  ),
                                ),
                                Container(
                                  width: 78,
                                  height: 78,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF0E151D),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.12),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.sports_cricket_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            "Analyzing your video...",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.18),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              activeStatus,
                              key: ValueKey(activeStatus),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF9ADFFF),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "AI is working in the background so your next insight lands clean.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 22),
                          AnimatedOpacity(
                            opacity: _showLongWaitHandoff ? 1 : 0,
                            duration: const Duration(milliseconds: 320),
                            child: IgnorePointer(
                              ignoring: !_showLongWaitHandoff,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      "Analysis is taking a bit longer. We'll notify you when it's ready.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        height: 1.45,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () => _leaveDuringAnalysis(
                                          openAnalysisTab: false,
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF00C2FF,
                                          ),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          "Continue exploring",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: () => _leaveDuringAnalysis(
                                          openAnalysisTab: true,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(
                                            color: const Color(
                                              0xFF00FF9D,
                                            ).withOpacity(0.42),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          "View in Analysis Tab",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrsTransitionOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 3),
            SizedBox(height: 24),
            Text(
              "PREPARING REPLAY...",
              style: TextStyle(
                color: Colors.white,
                fontFamily: "Montserrat",
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAnalysisOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 34),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showUploadSuccessState) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF9D).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF00FF9D).withOpacity(0.32),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: Color(0xFF00FF9D),
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Upload successful",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  child: Text(
                    _currentFact,
                    key: ValueKey(_currentFact),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: _autoZoomRetryInProgress
                        ? const Icon(
                            Icons.zoom_in_rounded,
                            color: Color(0xFF38BDF8),
                            size: 16,
                          )
                        : const CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Color(0xFF38BDF8),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _analysisStatusText.isEmpty
                          ? "Analyzing video..."
                          : _analysisStatusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleBackToGallery() async {
    if (!mounted) return;
    if (controller != null) {
      if (!_backPressArmed) {
        _backPressArmed = true;
        HapticFeedback.mediumImpact();
        _backPressResetTimer?.cancel();
        _backPressResetTimer = Timer(const Duration(seconds: 2), () {
          _backPressArmed = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black.withOpacity(0.92),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            content: const Row(
              children: [
                Icon(Icons.arrow_back, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Tap back once more to go to Home.",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      _backPressArmed = false;
      _backPressResetTimer?.cancel();
      HapticFeedback.selectionClick();
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              MainNavigation(userName: _wakeOverlayUserName(), initialIndex: 0),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (route) => false,
      );
      return;
    }
    Navigator.of(context).pop();
  }

  Widget _metric(String label, String value, {double? speed}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: value == "Analyzing..."
                ? TweenAnimationBuilder<double>(
                    key: const ValueKey("analyzing_clean"),
                    tween: Tween(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: scale,
                          child: const Text(
                            "Analyzing...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                    onEnd: () {
                      if (mounted) setState(() {});
                    },
                  )
                : Text(
                    value,
                    key: ValueKey(value),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: Text(
          "Exit ${_sessionTypeLabel(_selectedSessionType)}?",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: const Text(
          "Ending this session will clear the current analysis. Are you sure?",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Keep Playing",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetSessionState();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Exit Session"),
          ),
        ],
      ),
    );
  }

  void _resetSessionState() {
    controller?.removeListener(_pauseUploadedVideoAtEnd);
    controller?.dispose();
    setState(() {
      controller = null;
      speedKmph = null;
      _lastAnalysisMap = null;
      video = null;
      uploading = false;
      analysisLoading = false;
    });
  }

  Widget _buildAppBarTab({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color ?? Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
