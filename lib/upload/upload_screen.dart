import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../services/weekly_stats_service.dart';

enum _DrsCinematicPhase { idle, snicko, tracking, decision }

enum _DrsReplayMode { ultraEdge, lbw }

enum _DrsUmpireCall { out, notOut, umpire }

enum _DrsViewMode { keeper, umpire, striker }

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
  final decisionText = (input["decision"] as String? ?? "NOT OUT")
      .toUpperCase();
  final confidence = (input["confidence"] as num?)?.toDouble() ?? 0.0;

  if (points.length < 3) {
    return {
      "deliveryStart": {"x": 0.16, "y": 0.20},
      "pitchPoint": {"x": 0.47, "y": 0.58},
      "impactPoint": {"x": 0.66, "y": 0.72},
      "stumpsPoint": {"x": 0.79, "y": 0.82},
      "stumpLeft": {"x": 0.463, "y": 0.82},
      "stumpRight": {"x": 0.537, "y": 0.82},
      "pathPoints": points,
      "pitchingText": confidence >= 0.35 ? "In Line" : "Outside Off",
      "impactText": confidence >= 0.55 ? "In Line" : "Outside",
      "wicketsText": decisionText == "OUT" ? "Hitting" : "Missing",
      "wicketTarget": "Middle",
      "wicketsHitting": decisionText == "OUT",
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
  final projectedDx = (impactPoint["x"]! - pitchPoint["x"]!) * 1.15;
  // Dynamic stump centerline from last tracked points (more robust than fixed X).
  final tailCount = math.min(4, points.length);
  final tail = points.sublist(points.length - tailCount);
  final stumpCenterX =
      tail.fold<double>(0.0, (a, p) => a + p["x"]!) / tailCount;
  final offStumpX = stumpCenterX + 0.030;
  final legStumpX = stumpCenterX - 0.030;
  const stumpRadius = 0.030;
  const stumpY = 0.82;
  final projectedAtStumpsX = (impactPoint["x"]! + projectedDx).clamp(
    0.10,
    0.92,
  );
  final stumpsPoint = {"x": stumpCenterX, "y": stumpY};
  final stumpLeft = {"x": legStumpX, "y": stumpY};
  final stumpRight = {"x": offStumpX, "y": stumpY};

  String pitchingText;
  final pitchDelta = pitchPoint["x"]! - stumpCenterX;
  if (pitchDelta < -0.075) {
    pitchingText = "Outside Leg";
  } else if (pitchDelta > 0.075) {
    pitchingText = "Outside Off";
  } else {
    pitchingText = "In Line";
  }

  final impactText = (impactPoint["x"]! - stumpCenterX).abs() > 0.090
      ? "Outside"
      : "In Line";

  final dOff = (projectedAtStumpsX - offStumpX).abs();
  final dMid = (projectedAtStumpsX - stumpCenterX).abs();
  final dLeg = (projectedAtStumpsX - legStumpX).abs();
  final minD = math.min(dOff, math.min(dMid, dLeg));
  final wicketsHitting = decisionText == "OUT";

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
      : (confidence >= 0.50 ? "Umpires Call" : "Missing");

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
      wicketsText = "Hitting",
      wicketTarget = "Middle",
      wicketsHitting = true;
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
      if (_mode == _DrsReplayMode.lbw) {
        _awaitingUmpireCall = true;
        _stageText = "DECISION PENDING";
      } else {
        _stageText = "ANALYZING $_modeLabel...";
      }
    });
    if (_mode == _DrsReplayMode.lbw) {
      await _videoController.pause();
      await _startDecisionHeartbeat();
      return;
    }
    await _videoController.play();
    unawaited(_startTimedRevealSequence());
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
      _isUmpiresCall ? "UMPIRE'S CALL" : widget.decisionCall.toUpperCase();

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
    if (_mode != _DrsReplayMode.lbw || !_awaitingUmpireCall || _hasUserCall) {
      return;
    }
    HapticFeedback.heavyImpact();
    await _stopDecisionHeartbeat();
    if (!mounted) return;
    setState(() {
      _userCall = call;
      _awaitingUmpireCall = false;
      _showUserCallChip = true;
      _showOutcomePanel = false;
      _showDecisionBanner = false;
      _showSidebarDecision = false;
      _stageText = "RUNNING BALL TRACKING";
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
        _stageText = "CHECKING EDGE";
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
      _stageText = _impactVisualLocked ? "IMPACT CONFIRMED" : "TRACKING IMPACT";
    });
    await _playTickSound();
    if (!await _waitStage(const Duration(milliseconds: 500), token)) return;

    setState(() {
      _showPath = true;
      _stageText = "PROJECTING TO WICKETS";
    });
    unawaited(_pathController.forward(from: 0));
    if (!await _waitStage(const Duration(milliseconds: 600), token)) return;

    setState(() {
      _showWicket = true;
    });
    await revealDecision();
  }

  int? _detectBounceIndex(List<Offset> points) {
    if (points.length < 3) return null;
    int bestIdx = -1;
    double bestY = -1e9;
    for (int i = 1; i < points.length - 1; i++) {
      final current = points[i].dy;
      if (current >= points[i - 1].dy &&
          current >= points[i + 1].dy &&
          current > bestY) {
        bestY = current;
        bestIdx = i;
      }
    }
    if (bestIdx == -1) return null;
    return bestIdx;
  }

  ({double pitch, double impact, double wicket}) _timelineMilestones() {
    final points = widget.geometry.pathPoints;
    if (points.length < 3) {
      return (pitch: 0.50, impact: 0.88, wicket: 0.97);
    }
    final bounceIdx =
        _detectBounceIndex(points) ?? (points.length * 0.52).round();
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
                    highlightSpike: widget.hasSpike,
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
        ? (widget.hasSpike ? const Color(0xFF6FE7FF) : Colors.white70)
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
                  widget.decisionCall.toUpperCase(),
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

  Widget _lbwDecisionOverlay() {
    if (_mode != _DrsReplayMode.lbw || !_awaitingUmpireCall) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
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
                      final buttons = stackButtons
                          ? Column(
                              children: [
                                _predictionActionButton(
                                  title: "OUT",
                                  subtitle:
                                      "Finger goes up. You are calling it dead straight.",
                                  accent: const Color(0xFFD93D47),
                                  icon: Icons.gavel_rounded,
                                  onTap: () =>
                                      _submitUmpireCall(_DrsUmpireCall.out),
                                ),
                                const SizedBox(height: 12),
                                _predictionActionButton(
                                  title: "NOT OUT",
                                  subtitle:
                                      "Batter survives. You think the ball is missing.",
                                  accent: const Color(0xFF12B76A),
                                  icon: Icons.shield_rounded,
                                  onTap: () =>
                                      _submitUmpireCall(_DrsUmpireCall.notOut),
                                ),
                                const SizedBox(height: 12),
                                _predictionActionButton(
                                  title: "UMPIRE'S CALL",
                                  subtitle:
                                      "Marginal impact. You leave it with the on-field umpire.",
                                  accent: const Color(0xFFFFD54F),
                                  icon: Icons.sports_cricket,
                                  onTap: () =>
                                      _submitUmpireCall(_DrsUmpireCall.umpire),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _predictionActionButton(
                                        title: "OUT",
                                        subtitle:
                                            "Finger goes up. You are calling it dead straight.",
                                        accent: const Color(0xFFD93D47),
                                        icon: Icons.gavel_rounded,
                                        onTap: () => _submitUmpireCall(
                                          _DrsUmpireCall.out,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _predictionActionButton(
                                        title: "NOT OUT",
                                        subtitle:
                                            "Batter survives. You think the ball is missing.",
                                        accent: const Color(0xFF12B76A),
                                        icon: Icons.shield_rounded,
                                        onTap: () => _submitUmpireCall(
                                          _DrsUmpireCall.notOut,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _predictionActionButton(
                                  title: "UMPIRE'S CALL",
                                  subtitle:
                                      "Marginal impact. You leave it with the on-field umpire.",
                                  accent: const Color(0xFFFFD54F),
                                  icon: Icons.sports_cricket,
                                  onTap: () =>
                                      _submitUmpireCall(_DrsUmpireCall.umpire),
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
                      _lbwDecisionOverlay(),
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
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with TickerProviderStateMixin {
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
    if (!mounted) return null;
    return showGeneralDialog<_DrsReplayMode>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "DRS Mode",
      barrierColor: Colors.black.withOpacity(0.38),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ),
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B121A).withOpacity(0.78),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "SELECT REVIEW MODE",
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: "Montserrat",
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _drsModeButton(
                        title: "ULTRA-EDGE",
                        icon: Icons.sports_cricket,
                        accent: const Color(0xFFFFD54F),
                        onTap: () =>
                            Navigator.of(context).pop(_DrsReplayMode.ultraEdge),
                      ),
                      const SizedBox(height: 12),
                      _drsModeButton(
                        title: "LBW ANALYSIS",
                        icon: Icons.shield_rounded,
                        accent: const Color(0xFF4FC3F7),
                        onTap: () =>
                            Navigator.of(context).pop(_DrsReplayMode.lbw),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  double? speedKmph;
  String speedType = "unavailable";
  String speedNote = "";

  String swing = "";
  String spin = "";
  bool analysisLoading = false;

  // 🧠 Rotating Cricket Facts
  final List<String> _cricketFacts = [
    "Did you know? Sachin Tendulkar's bat weighed around 3.2 lbs!",
    "Fun Fact: The first-ever international cricket match was USA vs Canada in 1844.",
    "Elite Tip: A stable head position is the secret to 90% of successful shots.",
    "Fast Fact: Shoaib Akhtar bowled the fastest delivery ever recorded at 161.3 km/h.",
    "Cricket Insight: Yorkers are most effective in the last 4 overs of a T20 match.",
    "Did you know? Muttiah Muralitharan has 800 Test wickets.",
    "Elite Tip: Watch the seam position to read swing early.",
    "Fun Fact: MS Dhoni has the fastest stumping record at 0.08 seconds.",
    "Cricket Insight: Wrist position defines swing direction.",
    "Did you know? Don Bradman averaged 99.94 in Test cricket.",
    "Elite Tip: Strong core muscles improve bowling speed.",
    "Fun Fact: The longest Test match lasted 12 days in 1939.",
    "Cricket Insight: Backlift height influences shot power.",
    "Did you know? Lasith Malinga took 4 wickets in 4 balls twice.",
    "Elite Tip: Landing foot alignment controls bowling direction.",
    "Fun Fact: India won the 1983 World Cup as underdogs.",
    "Cricket Insight: Reverse swing starts when the ball gets rough.",
    "Did you know? AB de Villiers scored the fastest ODI 100 in 31 balls.",
    "Elite Tip: Keep your elbow high during drives.",
    "Fun Fact: Chris Gayle scored the first T20I century.",
    "Cricket Insight: Consistency beats raw pace.",
    "Did you know? Jacques Kallis scored 10,000+ runs and took 250+ wickets.",
    "Elite Tip: Follow through fully to avoid injuries.",
    "Fun Fact: The Ashes started in 1882.",
    "Cricket Insight: Balance at release improves accuracy.",
    "Did you know? Virat Kohli has 70+ international centuries.",
    "Elite Tip: Soft hands help in defensive shots.",
    "Fun Fact: An over once had 8 balls in some countries.",
    "Cricket Insight: Length is more important than speed.",
    "Did you know? Kumar Sangakkara scored four consecutive ODI hundreds in a World Cup.",
    "Elite Tip: Focus on rhythm, not just power.",
    "Fun Fact: Cricket was once played in the Olympics in 1900.",
    "Cricket Insight: Bat speed generates boundary power.",
    "Did you know? Wasim Akram took two hat-tricks in ODIs.",
    "Elite Tip: Keep your eyes level while batting.",
    "Fun Fact: The highest Test total is 952/6 declared.",
    "Cricket Insight: Short run-up can improve control.",
    "Did you know? Ben Stokes played one of the greatest innings in 2019 Ashes.",
    "Elite Tip: Grip pressure affects spin turn.",
    "Fun Fact: The pink ball is used in day-night Tests.",
    "Cricket Insight: Field placement defines bowling strategy.",
    "Did you know? Rohit Sharma has three ODI double centuries.",
    "Elite Tip: Practice under pressure situations.",
    "Fun Fact: The first Cricket World Cup was in 1975.",
    "Cricket Insight: Seam upright means better swing.",
    "Did you know? Glenn McGrath took 563 Test wickets.",
    "Elite Tip: Mental strength wins close matches.",
    "Fun Fact: Brendon McCullum scored 158 in the first IPL match.",
    "Cricket Insight: Footwork is the foundation of batting.",
    "Elite Tip: Recovery and sleep boost performance.",
  ];
  int _currentFactIndex = 0;
  Timer? _factTimer;

  String spinStrength = "NONE";
  double spinTurnDeg = 0.0;

  Future<void> _incrementTotalVideos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final box = await Hive.openBox("local_stats_$uid");

    int current = (box.get('totalVideos', defaultValue: 0) as num).toInt();
    int updated = current + 1;

    await box.put('totalVideos', updated);

    debugPrint("TOTAL VIDEOS UPDATED (HIVE) => $updated");
  }

  Future<void> _addXP(int amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final box = await Hive.openBox("local_stats_$uid");

    int currentXp = box.get('xp', defaultValue: 0);
    int updatedXp = currentXp + amount;

    await box.put('xp', updatedXp);

    debugPrint("XP UPDATED (HIVE) => +$amount | TOTAL => $updatedXp");
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

  Widget _eliteSpeedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD86B).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFD86B)),
      ),
      child: const Text(
        "Processing with Elite Speed: 2x Faster",
        style: TextStyle(
          color: Color(0xFFFFD86B),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
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
    _factTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      setState(() {
        _currentFactIndex = (_currentFactIndex + 1) % _cricketFacts.length;
      });
    });
    _drsPhaseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  File? video;
  VideoPlayerController? controller;

  bool uploading = false;
  bool showTrajectory = false;

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

  double _trajectoryQualityScore(List<Map<String, double>> points) {
    if (points.isEmpty) return 0.0;
    final size = controller?.value.isInitialized == true
        ? controller!.value.size
        : null;
    final minDim = size == null || size.width <= 0 || size.height <= 0
        ? 720.0
        : math.min(size.width, size.height);
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
      jitterScore = (1.0 - (ratio / 0.9)).clamp(0.0, 1.0);
    }

    final score = (0.5 * resScore) + (0.3 * countScore) + (0.2 * jitterScore);
    return score.clamp(0.0, 1.0);
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

    final quality = _trajectoryQualityScore(points);
    final proximity = _edgeProximityThreshold(quality: quality);
    final batRect = Rect.fromLTRB(_batXMin, _batYMin, _batXMax, _batYMax);
    final tight = proximity * (0.60 + ((1.0 - quality) * 0.25));
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

    final strongHit = intersectsTight || minDist <= tight;
    final softHit = intersectsLoose || minDist <= proximity;
    final base =
        (strongHit
            ? 0.62
            : softHit
            ? 0.38
            : 0.0) +
        (0.24 * directionScore) +
        (0.14 * nearScore) +
        (0.10 * proximityScore);
    final confidence = (base * (0.82 + (0.18 * quality))).clamp(0.0, 1.0);
    final threshold = (0.62 - (quality * 0.14));
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

  ({bool isOut, String call, String detail, bool edgeDetected})
  _resolveUltraEdgeDecision({
    required List<Map<String, double>> points,
    required bool spikeDetected,
    required _DrsTrackingGeometry geometry,
  }) {
    if (points.isEmpty) {
      return (
        isOut: false,
        call: "NOT OUT",
        detail: "NO EDGE",
        edgeDetected: false,
      );
    }
    final summary = _detectEdgeSummary(points);
    final visualDetected = summary.detected;
    final edgeDetected = visualDetected || spikeDetected;
    if (!edgeDetected) {
      return (
        isOut: false,
        call: "NOT OUT",
        detail: "NO EDGE",
        edgeDetected: false,
      );
    }

    final contactIdx = summary.contactIndex ?? _estimateBatContactIndex(points);
    final bounceIdx = _detectBounceIndex(points);
    final afterContactBounce = bounceIdx != -1 && bounceIdx > contactIdx + 1;
    final lastPoint = points.last;
    final padLikely = _isLikelyPadImpact(lastPoint, geometry.stumpsPoint.dy);
    final caught = !afterContactBounce && !padLikely;

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
    final deltas = <double>[];
    for (int i = 1; i < pts.length; i++) {
      final dx = pts[i]["x"]! - pts[i - 1]["x"]!;
      final dy = pts[i]["y"]! - pts[i - 1]["y"]!;
      final d = math.sqrt((dx * dx) + (dy * dy));
      if (d > 0.0008 && d < 0.18) {
        deltas.add(d);
      }
    }
    if (deltas.length < 2) return null;
    deltas.sort();
    final medianNorm = deltas[deltas.length ~/ 2];

    final ys = pts.map((p) => p["y"]!).toList(growable: false);
    final ySpan = (ys.reduce(math.max) - ys.reduce(math.min)).abs();
    final effectiveSpan = ySpan.clamp(0.22, 0.92);
    final metersPerNorm = 18.0 / effectiveSpan;
    final kmph = medianNorm * clampedFps * metersPerNorm * 3.6;
    if (!kmph.isFinite || kmph <= 0) return null;

    return double.parse(kmph.clamp(45.0, 170.0).toStringAsFixed(1));
  }

  Map<String, String> _inferLabelsFromTrajectory(dynamic rawTrajectory) {
    final pts = _extractTrajectoryPoints(rawTrajectory);
    if (pts.length < 2) {
      return {"swing": "INSWING", "spin": "OFF SPIN"};
    }

    final bounce = _detectBounceIndex(pts);
    final pivot = bounce <= 0
        ? (pts.length ~/ 2)
        : bounce.clamp(1, pts.length - 2);
    final preDx = pts[pivot]["x"]! - pts.first["x"]!;
    final postDx = pts.last["x"]! - pts[pivot]["x"]!;
    final curveDx = postDx - preDx;

    // Derive from observed trajectory (video points), not fixed assumptions.
    final swingLabel = preDx >= 0 ? "OUTSWING" : "INSWING";
    final spinLabel = curveDx >= 0 ? "LEG SPIN" : "OFF SPIN";

    return {"swing": swingLabel, "spin": spinLabel};
  }

  _DrsTrackingGeometry _buildDrsGeometry({
    required String decisionText,
    required double confidence,
  }) {
    final points = _extractTrajectoryPoints(trajectory);
    if (points.length < 3) {
      return _DrsTrackingGeometry(
        deliveryStart: const Offset(0.16, 0.20),
        pitchPoint: const Offset(0.47, 0.58),
        impactPoint: const Offset(0.66, 0.72),
        stumpsPoint: const Offset(0.80, 0.80),
        stumpLeft: const Offset(0.463, 0.82),
        stumpRight: const Offset(0.537, 0.82),
        pathPoints: points
            .map((p) => Offset(p["x"]!, p["y"]!))
            .toList(growable: false),
        pitchingText: confidence >= 0.35 ? "In Line" : "Outside Off",
        impactText: confidence >= 0.55 ? "In Line" : "Outside",
        wicketsText: decisionText == "OUT"
            ? "Hitting"
            : (confidence >= 0.45 ? "Umpires Call" : "Missing"),
        wicketTarget: "Middle",
        wicketsHitting: decisionText == "OUT",
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
    final projectedDx = (impactPoint.dx - pitchPoint.dx) * 1.15;
    final tailCount = math.min(4, points.length);
    final tail = points.sublist(points.length - tailCount);
    final stumpCenterX =
        tail.fold<double>(0.0, (a, p) => a + p["x"]!) / tailCount;
    final offStumpX = stumpCenterX + 0.030;
    final legStumpX = stumpCenterX - 0.030;
    const stumpRadius = 0.030;
    const stumpY = 0.82;
    final projectedAtStumpsX = (impactPoint.dx + projectedDx).clamp(0.10, 0.92);
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
    if ((impactPoint.dx - stumpCenterX).abs() > 0.090) {
      impactText = "Outside";
    } else {
      impactText = "In Line";
    }

    final dOff = (projectedAtStumpsX - offStumpX).abs();
    final dMid = (projectedAtStumpsX - stumpCenterX).abs();
    final dLeg = (projectedAtStumpsX - legStumpX).abs();
    final minD = math.min(dOff, math.min(dMid, dLeg));
    final projectionHitting = minD <= stumpRadius;
    final wicketsHitting = decisionText == "OUT" || projectionHitting;

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
        : (confidence >= 0.50 ? "Umpires Call" : "Missing");

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
      wicketsText: (result["wicketsText"] as String?) ?? "Hitting",
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
    final geometryRaw = drs["geometry"];
    if (geometryRaw is Map) {
      _drsGeometry = _geometryFromWorkerResult(
        Map<String, dynamic>.from(geometryRaw),
      );
    } else {
      final workerInput = <String, dynamic>{
        "points": _extractTrajectoryPoints(trajectory),
        "decision": decisionText,
        "confidence": confidence,
      };

      try {
        final result = await compute(_drsGeometryWorker, workerInput);
        _drsGeometry = _geometryFromWorkerResult(result);
      } catch (_) {
        _drsGeometry = _buildDrsGeometry(
          decisionText: decisionText,
          confidence: confidence,
        );
      }
    }
    _drsPitching =
        (drs["pitching_text"] as String?) ?? _drsGeometry.pitchingText;
    _drsImpact = (drs["impact_text"] as String?) ?? _drsGeometry.impactText;
    _drsWickets = (drs["wickets_text"] as String?) ?? _drsGeometry.wicketsText;
    _drsWicketTarget =
        (drs["wicket_target"] as String?) ?? _drsGeometry.wicketTarget;
    final backendHitStumps =
        drs["ball_tracking"] == true ||
        _drsWickets.toLowerCase().contains("hitting") ||
        _drsGeometry.wicketsHitting;
    if (backendHitStumps) {
      _drsWickets = "Hitting";
    }
    _drsOut = decisionText == "OUT" || backendHitStumps;
    _drsOriginalDecision = decisionText == "OUT" ? "OUT" : "NOT OUT";

    final trajectoryPoints = _extractTrajectoryPoints(trajectory);
    final visualEdgeRaw = drs["visual_edge"];
    final edgeSummary = _detectEdgeSummary(trajectoryPoints);
    _drsEdgeConfidence = edgeSummary.confidence;
    final visualEdgeDetected = visualEdgeRaw is bool
        ? visualEdgeRaw
        : edgeSummary.detected;
    if (visualEdgeRaw is bool) {
      if (visualEdgeRaw) {
        _drsEdgeConfidence = math.max(_drsEdgeConfidence, 0.70);
      } else {
        _drsEdgeConfidence = math.min(_drsEdgeConfidence, 0.35);
      }
    }
    if (audioSpike) {
      _drsEdgeConfidence = math.max(_drsEdgeConfidence, 0.78);
    }
    _drsEdgeDetected = audioSpike || visualEdgeDetected;

    if (_drsHasSpike && _drsReplayMode == _DrsReplayMode.lbw) {
      _drsOut = false;
      _drsWickets = "Missing";
      _drsOriginalDecision = "NOT OUT";
      _drsGeometry = _DrsTrackingGeometry(
        deliveryStart: _drsGeometry.deliveryStart,
        pitchPoint: _drsGeometry.pitchPoint,
        impactPoint: _drsGeometry.impactPoint,
        stumpsPoint: _drsGeometry.stumpsPoint,
        stumpLeft: _drsGeometry.stumpLeft,
        stumpRight: _drsGeometry.stumpRight,
        pathPoints: _drsGeometry.pathPoints,
        pitchingText: _drsGeometry.pitchingText,
        impactText: _drsGeometry.impactText,
        wicketsText: "Missing",
        wicketTarget: _drsGeometry.wicketTarget,
        wicketsHitting: false,
      );
    }
    _drsSwingDeg =
        ((_drsGeometry.pitchPoint.dx - _drsGeometry.deliveryStart.dx).abs() *
                6.0)
            .clamp(0.1, 5.0);
    _drsSpinDeg =
        ((_drsGeometry.impactPoint.dx - _drsGeometry.pitchPoint.dx).abs() * 7.0)
            .clamp(0.1, 6.0);

    final confidenceText = confidence > 0
        ? " (${(confidence * 100).toStringAsFixed(0)}%)"
        : "";
    if (_drsReplayMode == _DrsReplayMode.ultraEdge) {
      final decision = _resolveUltraEdgeDecision(
        points: trajectoryPoints,
        spikeDetected: audioSpike,
        geometry: _drsGeometry,
      );
      _drsOut = decision.isOut;
      _drsEdgeDetected = decision.edgeDetected;
      _drsDecisionCall = decision.edgeDetected ? "EDGE DETECTED" : "NO EDGE";
      _drsDecisionDetail = "";
      drsResult = _drsDecisionCall;
    } else {
      _drsDecisionCall = _drsOut ? "OUT" : "NOT OUT";
      _drsDecisionDetail = _drsHasSpike ? "INSIDE EDGE" : "";
      _drsEdgeDetected = _drsHasSpike;
      if (_drsHasSpike) {
        drsResult = "NOT OUT (INSIDE EDGE)";
      } else {
        drsResult = "${_drsOut ? "OUT" : "NOT OUT"}$confidenceText";
      }
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
    final confidence = trackedPoints.length >= 6 ? 0.64 : 0.42;
    final geometry = _buildDrsGeometry(
      decisionText: "NOT OUT",
      confidence: confidence,
    );
    final isOut = geometry.wicketsHitting;
    final wicketsText = isOut ? "Hitting" : geometry.wicketsText;

    return {
      "decision": isOut ? "OUT" : "NOT OUT",
      "stump_confidence": confidence,
      "ultraedge": false,
      "ball_tracking": isOut,
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
      final drs = data["drs"];
      if (drs is Map) {
        return Map<String, dynamic>.from(drs);
      }
    } catch (_) {
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

  Widget _buildDrsCinematicOverlay() {
    return Positioned.fill(
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _drsPhaseController,
          builder: (context, _) {
            final progress = _drsPhaseController.value;
            if (drsLoading && _drsPhase == _DrsCinematicPhase.idle) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      "Preparing DRS tracking...",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
            }

            if (_drsPhase == _DrsCinematicPhase.snicko) {
              return Stack(
                children: [
                  Positioned(
                    top: 6,
                    right: 8,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: _closeDrsOverlay,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 90,
                            child: CustomPaint(
                              painter: _BatBallPainter(
                                progress,
                                freezeAtBat: _drsEdgeDetected,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 62,
                            child: CustomPaint(
                              painter: _SnickoWavePainter(
                                progress: progress,
                                hasSpike: _drsEdgeDetected,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "ULTRA-EDGE: ${_drsEdgeDetected ? "EDGE DETECTED" : "NO EDGE"}",
                            style: TextStyle(
                              color: _drsEdgeDetected
                                  ? Colors.redAccent
                                  : Colors.white,
                              fontFamily: "RobotoCondensed",
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            if (_drsPhase == _DrsCinematicPhase.idle ||
                _drsPhase == _DrsCinematicPhase.tracking ||
                _drsPhase == _DrsCinematicPhase.decision) {
              final showPitch = progress > 0.22;
              final showImpact = progress > 0.52;
              final showWickets = progress > 0.77;
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DrsTrajectoryPainter(
                        geometry: _drsGeometry,
                        progress: progress,
                        viewMode: _DrsViewMode.umpire,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 8,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: _closeDrsOverlay,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                  if (showPitch)
                    Positioned(
                      left: (0.18 * MediaQuery.of(context).size.width).clamp(
                        18,
                        120,
                      ),
                      top: 70,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "[PITCHING] ${_drsPitching.toUpperCase()}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: "RobotoCondensed",
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  if (showImpact)
                    Positioned(
                      left: 24,
                      bottom: 94,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "[IMPACT] ${_drsImpact.toUpperCase()}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: "RobotoCondensed",
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  if (showWickets)
                    Positioned(
                      right: 110,
                      bottom: 50,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "[WICKETS] ${_drsWickets.toUpperCase()} ${_drsWickets == "Hitting" ? "(${_drsWicketTarget.toUpperCase()})" : ""}",
                          style: TextStyle(
                            color: _drsWickets == "Hitting"
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            fontFamily: "RobotoCondensed",
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 24,
                    left: 10,
                    child: Container(
                      width: 205,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.36),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        children: [
                          _drsTag("Pitching", _drsPitching, showPitch),
                          _drsTag("Impact", _drsImpact, showImpact),
                          _drsTag(
                            "Wickets",
                            _drsWickets == "Hitting"
                                ? "$_drsWickets ($_drsWicketTarget)"
                                : _drsWickets,
                            showWickets,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  void _showVideoRulesThenPick() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "🎥 Video Recording Guidelines",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "• Record in normal speed (no slow motion)\n"
                      "• Ball must be clearly visible\n"
                      "• Keep camera stable\n"
                      "• Full pitch & batsman visible\n"
                      "• Prefer side-on or behind bowler angle\n"
                      "• Avoid heavy zoom or filters\n\n"
                      "⚠️ AI accuracy depends on video quality.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          debugPrint("UPLOAD_SCREEN → pickAndUpload triggered");
                          pickAndUpload();
                        },
                        child: const Text(
                          "Next",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
      },
    );
  }

  Future<bool> pickAndUpload() async {
    debugPrint("UPLOAD_SCREEN → pickAndUpload start");

    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return false;

    video = File(picked.path);

    controller?.dispose();
    controller = VideoPlayerController.file(video!)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });

    if (mounted) {
      setState(() {
        uploading = true;
        analysisLoading = true;
        showTrajectory = false;
        showDRS = false;
        drsResult = null;
        swing = "";
        spin = "";
      });
    }

    final uri = Uri.parse(
      "https://cricknova-backend.onrender.com/training/analyze",
    );
    bool analysisSucceeded = false;

    try {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("USER_NOT_AUTHENTICATED");

      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      request.headers["Authorization"] = "Bearer $token";
      _applyEliteHeaders(request);
      request.files.add(await http.MultipartFile.fromPath("file", video!.path));

      final response = await request.send().timeout(
        const Duration(seconds: 40),
      );

      final respStr = await response.stream.bytesToString();
      debugPrint("UPLOAD RESPONSE ${response.statusCode} => $respStr");

      if (response.statusCode != 200) {
        throw Exception("UPLOAD_FAILED");
      }
      // ✅ Increment total uploaded videos (only on successful analysis)
      await _incrementTotalVideos();

      // 🔥 Also update & show total videos from Hive (for instant UI feedback)
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
      final statsBox = await Hive.openBox("local_stats_$uid");

      int currentVideos = (statsBox.get('totalVideos', defaultValue: 0) as num)
          .toInt();

      currentVideos += 1;
      await statsBox.put('totalVideos', currentVideos);

      final decoded = jsonDecode(respStr);
      final analysis = decoded["analysis"] ?? decoded;

      final dynamic speedVal = analysis["speed_kmph"] ?? decoded["speed_kmph"];

      final dynamic speedTypeVal =
          analysis["speed_type"] ?? decoded["speed_type"];

      final dynamic speedNoteVal =
          analysis["speed_note"] ?? decoded["speed_note"];
      final dynamic fpsVal = analysis["fps"] ?? decoded["fps"];
      final fpsForFallback = fpsVal is num ? fpsVal.toDouble() : 30.0;
      final fallbackSpeed = _deriveSpeedFromTrajectory(
        analysis["trajectory"],
        fps: fpsForFallback,
      );

      if (speedVal is num && speedVal > 0) {
        speedKmph = speedVal.toDouble();
        speedType = speedTypeVal?.toString() ?? "estimated";
        speedNote = speedNoteVal?.toString() ?? "";
      } else if (fallbackSpeed != null) {
        speedKmph = fallbackSpeed;
        speedType = "trajectory_fallback";
        speedNote = "Fallback from real tracked trajectory (non-scripted)";
      } else {
        speedKmph = null;
        speedType = "unavailable";
        speedNote = speedNoteVal?.toString() ?? "";
      }

      // 🔥 Save speed to Hive for graph (user-specific key)
      if (speedKmph != null) {
        final box = await Hive.openBox('speedBox');

        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid ?? "guest";
        final key = 'allSpeeds_$uid';

        final stored = box.get(key) as List?;
        List<double> allSpeeds = [];

        if (stored != null) {
          allSpeeds = stored.map((e) => (e as num).toDouble()).toList();
        }

        allSpeeds.add(speedKmph!);

        await box.put(key, allSpeeds);

        // 🔥 Save MAX SPEED to Hive (user-specific for profile screen)
        final statsBox = await Hive.openBox("local_stats_$uid");
        double currentMax = (statsBox.get('maxSpeed', defaultValue: 0) as num)
            .toDouble();

        if (speedKmph! > currentMax) {
          await statsBox.put('maxSpeed', speedKmph);
          debugPrint("NEW MAX SPEED SAVED (HIVE) => ${speedKmph}");
        }

        debugPrint("HIVE SPEED UPDATED => $allSpeeds");
      }
      if (!mounted) return true;

      setState(() {
        final inferred = _inferLabelsFromTrajectory(analysis["trajectory"]);

        // -------- SWING (Direct Backend Value) --------
        final rawSwing = analysis["swing"];
        final inferredSwing = inferred["swing"];
        final backendSwing = rawSwing is String && rawSwing.trim().isNotEmpty
            ? _normalizeSwingLabel(rawSwing)
            : null;
        swing = inferredSwing ?? backendSwing ?? "INSWING";

        // -------- SPIN (Direct Backend Value) --------
        final rawSpin = analysis["spin"];
        final inferredSpin = inferred["spin"];
        final backendSpin = rawSpin is String && rawSpin.trim().isNotEmpty
            ? _normalizeSpinLabel(rawSpin)
            : null;
        spin = inferredSpin ?? backendSpin ?? "OFF SPIN";

        // -------- SPIN STRENGTH & TURN (BACKEND: NUMERIC STRENGTH 0–1) --------
        final rawStrength = analysis["spin_strength"];
        if (rawStrength is num) {
          // Backend now returns numeric strength (0–1)
          spinStrength = "${(rawStrength * 100).toStringAsFixed(0)}%";
        } else if (rawStrength is String && rawStrength.isNotEmpty) {
          spinStrength = rawStrength.toUpperCase();
        } else {
          spinStrength = "0%";
        }

        // Spin turn degree no longer shown in UI
        spinTurnDeg = 0.0;

        trajectory = analysis["trajectory"] is List
            ? List<dynamic>.from(analysis["trajectory"])
            : const [];
        showTrajectory = false;

        analysisLoading = false;

        controller?.play();
      });
      analysisSucceeded = true;

      try {
        final usage = await PremiumService.recordSwingUsage();
        await _maybeShowUsageLimitReached(
          featureName: "CrickNova Swing Analysis",
          current: usage.swingUsed,
          limit: PremiumService.compareLimit,
          entrySource: "swing_usage_limit",
        );
      } catch (e) {
        debugPrint("USAGE TRACK ERROR (SWING) => $e");
      }
    } catch (e) {
      debugPrint("UPLOAD ERROR => $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Analysis failed. Please try again.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          uploading = false;
        });
      }
    }
    // Review prompt removed (manual rating only).
    return true;
  }

  Future<void> runDRS() async {
    if (video == null || drsLoading) return;

    final selectedMode = await _showDrsModeSelector();
    if (selectedMode == null) return;
    _drsReplayMode = selectedMode;

    setState(() {
      showDRS = false;
      drsLoading = true;
      drsResult = "Reviewing decision...";
      _drsPhase = _DrsCinematicPhase.idle;
      _drsHasSpike = false;
      _drsEdgeDetected = false;
    });

    Map<String, dynamic> drsPayload = _buildLocalDrsPayload();
    final user = FirebaseAuth.instance.currentUser;
    bool usedUltraEdgeAudio = false;

    try {
      final localPoints = _extractTrajectoryPoints(trajectory);
      final shouldAskBackend = localPoints.length < 2;
      if (shouldAskBackend && user != null) {
        final idToken = await user.getIdToken(true);
        if (idToken != null && idToken.isNotEmpty) {
          final backendDrs = await _fetchBackendDrsPayload(idToken);
          if (backendDrs != null) {
            drsPayload = backendDrs;
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
      await _addXP(20);
      if (!mounted) return;
      setState(() {
        showDRS = true;
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
    if (video == null) {
      setState(() {
        showCoach = true;
        coachReply = "No analysis data available yet.";
      });
      return;
    }
    if (uploading) {
      setState(() {
        showCoach = true;
        coachReply = "Analysis in progress. Please wait.";
      });
      return;
    }

    setState(() {
      showCoach = true;
      coachReply = "Analyzing your batting...";
    });

    final uri = Uri.parse(
      "https://cricknova-backend.onrender.com/coach/analyze",
    );

    try {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";

      // ✅ Send Firebase ID token so backend can identify user & plan
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      final String? token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw Exception("USER_NOT_AUTHENTICATED");
      }

      request.headers["Authorization"] = "Bearer $token";
      _applyEliteHeaders(request);

      // send video (REQUIRED by backend)
      request.files.add(await http.MultipartFile.fromPath("file", video!.path));

      // optional metadata (safe)
      if (speedKmph != null) {
        request.fields["speed_kmph"] = speedKmph!.toString();
      }
      request.fields["swing"] = swing;
      request.fields["spin"] = spin;

      final response = await request.send();
      print("COACH STATUS => ${response.statusCode}");

      final respStr = await response.stream.bytesToString();
      print("COACH RAW RESPONSE => $respStr");

      final data = jsonDecode(respStr);

      // 🔒 Handle premium / limit errors explicitly
      if (response.statusCode == 403) {
        final detail = data["detail"]?.toString() ?? "";

        if (detail.contains("PREMIUM_REQUIRED") ||
            detail.contains("MISTAKE_LIMIT_REACHED") ||
            detail.contains("LIMIT")) {
          if (!mounted) return;
          setState(() => showCoach = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PremiumScreen(entrySource: "mistake_limit"),
            ),
          );
          return;
        }
      }

      // 🔐 Redirect ONLY if backend explicitly blocks access
      final bool premiumRequired = data["premium_required"] == true;
      final bool success = data["success"] == true;

      if (premiumRequired && !success) {
        if (!mounted) return;
        setState(() => showCoach = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(entrySource: "coach"),
          ),
        );

        return;
      }

      // (XP block removed here)

      if (response.statusCode == 200) {
        bool didProduceReply = false;
        if (data["success"] == true && data["reply"] != null) {
          await _addXP(20);
          setState(() {
            coachReply = data["reply"];
          });
          didProduceReply = true;
        } else if (data["coach_feedback"] != null) {
          await _addXP(20);
          setState(() {
            coachReply = data["coach_feedback"];
          });
          didProduceReply = true;
        } else {
          setState(() {
            coachReply =
                "Analysis completed, but no clear coaching feedback was generated.";
          });
        }

        if (didProduceReply) {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await WeeklyStatsService.recordMistakeDetection(user.uid);
            }
            final usage = await PremiumService.recordMistakeUsage();
            await _maybeShowUsageLimitReached(
              featureName: "Mistake Detection",
              current: usage.mistakeUsed,
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
        coachReply = "Coach unavailable. Connection error.";
      });
    }
  }

  @override
  void dispose() {
    _factTimer?.cancel();
    _drsRunId++;
    _drsPhaseController.dispose();
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              _handleBackToGallery();
            },
          ),
          title: const Text("Upload Training Video"),
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
                      // 🏏 Mode Selection Label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.blueAccent.withOpacity(0.4),
                          ),
                        ),
                        child: const Text(
                          "🏏 Batting Analysis Mode",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 💡 Instruction Tip Box
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text(
                          "Tip: Ensure your full body is visible from the side for better AI analysis.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
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
                        onTap: _showVideoRulesThenPick,
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
                                  const Text(
                                    "Upload Training Video",
                                    style: TextStyle(
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
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller!.value.aspectRatio,
                      child: VideoPlayer(controller!),
                    ),
                  ),

                  // LEFT SIDEBAR
                  if (!showDRS)
                    Positioned(
                      left: 0,
                      top: 100,
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
                                analysisLoading
                                    ? "Analyzing..."
                                    : (speedKmph != null
                                          ? "${speedKmph!.toStringAsFixed(1)} km/h"
                                          : ""),
                              ),
                            ),
                            if (speedKmph != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  speedType == "measured_release"
                                      ? "Measured speed"
                                      : speedType == "very_slow_estimate"
                                      ? "Very slow delivery"
                                      : speedType == "camera_normalized"
                                      ? "Estimated from camera motion"
                                      : speedType == "video_derived"
                                      ? "Estimated from video motion"
                                      : speedType == "derived_physics"
                                      ? "Physics fallback estimate"
                                      : "",
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
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
                                duration: const Duration(milliseconds: 120),
                                child: AnimatedScale(
                                  scale: _drsScale,
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOutBack,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
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
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.redAccent.withOpacity(
                                            0.6,
                                          ),
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
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              "DRS",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                                  coachReply = "Analyzing your batting... 🏏";
                                });

                                await runCoach();
                              },
                              child: AnimatedRotation(
                                turns: _coachRotation,
                                duration: const Duration(milliseconds: 120),
                                child: AnimatedScale(
                                  scale: _coachScale,
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOutBack,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
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
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blueAccent.withOpacity(
                                            0.6,
                                          ),
                                          blurRadius: 18,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Text(
                                        "COACH",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
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
                                  const Text(
                                    "AI COACH REVIEW",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
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
                                    ),
                                    child: Text(
                                      coachReply ?? "",
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        height: 1.35,
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
                                      child: const Text("Close"),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (drsLoading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.78),
                        alignment: Alignment.center,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 28),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 26,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101722),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Color(0xFFFF5252),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "Preparing DRS Replay",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Analyzing impact, line and wickets...",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              if (PremiumService.isElite) ...[
                                const SizedBox(height: 12),
                                _eliteSpeedBadge(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (analysisLoading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.55),
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 28),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 600),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0.0, 0.3),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Text(
                                    _cricketFacts[_currentFactIndex],
                                    key: ValueKey(
                                      _cricketFacts[_currentFactIndex],
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (PremiumService.isElite) ...[
                                  const SizedBox(height: 12),
                                  _eliteSpeedBadge(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (uploading)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBackToGallery() async {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _metric(String label, String value) {
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
}
