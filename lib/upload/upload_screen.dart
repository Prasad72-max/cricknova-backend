import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';

enum _DrsCinematicPhase { idle, snicko, tracking, decision }

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

class _DrsCinematicScreen extends StatefulWidget {
  final String videoPath;
  final _DrsTrackingGeometry geometry;
  final bool hasSpike;
  final String ultraedgeReason;
  final String pitching;
  final String impact;
  final String wickets;
  final String wicketTarget;
  final String originalDecision;
  final bool isOut;
  final double speedKmph;
  final double swingDeg;
  final double spinDeg;

  const _DrsCinematicScreen({
    required this.videoPath,
    required this.geometry,
    required this.hasSpike,
    required this.ultraedgeReason,
    required this.pitching,
    required this.impact,
    required this.wickets,
    required this.wicketTarget,
    required this.originalDecision,
    required this.isOut,
    required this.speedKmph,
    required this.swingDeg,
    required this.spinDeg,
  });

  @override
  State<_DrsCinematicScreen> createState() => _DrsCinematicScreenState();
}

class _DrsCinematicScreenState extends State<_DrsCinematicScreen>
    with TickerProviderStateMixin {
  late final VideoPlayerController _videoController;
  late final AnimationController _phaseController;
  _DrsCinematicPhase _phase = _DrsCinematicPhase.idle;
  bool _ready = false;
  late bool _finalOut;
  String _reasonText = "";
  bool _orbitMode = true;
  double _orbitYaw = 0;
  double _orbitPitch = 0;
  double _videoProgress = 0.0;
  DateTime? _reviewStartedAt;

  @override
  void initState() {
    super.initState();
    _finalOut = widget.isOut;
    _videoController = VideoPlayerController.file(File(widget.videoPath));
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _initAndRun();
  }

  Future<void> _initAndRun() async {
    await _videoController.initialize();
    await _videoController.setLooping(false);
    _videoController.addListener(_handleVideoTick);
    if (!mounted) return;
    await _videoController.setPlaybackSpeed(0.25);
    _phaseController.duration = const Duration(milliseconds: 1800);
    _phaseController.repeat(reverse: true);
    setState(() {
      _ready = true;
      _phase = _DrsCinematicPhase.tracking;
      _reviewStartedAt = DateTime.now();
    });
    await _videoController.play();
  }

  @override
  void dispose() {
    _videoController.removeListener(_handleVideoTick);
    _phaseController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  void _handleVideoTick() {
    if (!mounted || !_videoController.value.isInitialized) return;
    final durationMs = _videoController.value.duration.inMilliseconds;
    final positionMs = _videoController.value.position.inMilliseconds;
    final progress = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0);
    if ((progress - _videoProgress).abs() > 0.004) {
      setState(() {
        _videoProgress = progress;
        _phase = progress >= 0.985
            ? _DrsCinematicPhase.decision
            : _DrsCinematicPhase.tracking;
      });
    }
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
    if (title == "IMPACT") {
      return lower.contains("in line")
          ? const Color(0xFF29B6F6)
          : const Color(0xFF42A5F5);
    }
    if (title == "WICKET") {
      return lower.contains("hitting")
          ? const Color(0xFF00E676)
          : const Color(0xFFFF5252);
    }
    return const Color(0xFF00E676);
  }

  Widget _statusIndicator(String title, String value) {
    final accent = _statusAccent(title, value);
    final lower = value.toLowerCase();
    final isWicket = title == "WICKET";
    final positive = lower.contains("in line") || lower.contains("hitting");
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isWicket ? Colors.transparent : accent.withOpacity(0.18),
        border: Border.all(color: accent.withOpacity(0.95), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.55),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: isWicket
            ? Icon(
                positive ? Icons.check_rounded : Icons.close_rounded,
                size: 18,
                color: accent,
              )
            : Container(
                width: 12,
                height: 12,
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
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              _statusIndicator(title, value),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 10.5,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.toUpperCase(),
                      style: TextStyle(
                        color: _statusAccent(title, value),
                        fontSize: 14,
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
    final child = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 21, color: const Color(0xFF616161)),
    );
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  void _resetOrbitView() {
    setState(() {
      _orbitYaw = 0;
      _orbitPitch = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ready
          ? AnimatedBuilder(
              animation: Listenable.merge([_phaseController, _videoController]),
              builder: (context, _) {
                final progress = _videoProgress;
                final milestones = _timelineMilestones();
                final revealProgress = _reviewStartedAt == null
                    ? 0.0
                    : ((DateTime.now()
                                  .difference(_reviewStartedAt!)
                                  .inMilliseconds) /
                              2000.0)
                          .clamp(0.0, 1.0);
                final showPitch = revealProgress >= 0.25;
                final showImpact = revealProgress >= 0.55;
                final showWicket =
                    revealProgress >= 0.85 ||
                    _phase == _DrsCinematicPhase.decision;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController.value.size.width,
                          height: _videoController.value.size.height,
                          child: VideoPlayer(_videoController),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
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
                              const Color(0xFF8FD1FF).withOpacity(0.08),
                              const Color(0xFF001018).withOpacity(0.06),
                              Colors.transparent,
                            ],
                            stops: const [0.00, 0.20, 0.42],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox.shrink(),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 6,
                      right: 8,
                      child: _sideToolButton(
                        Icons.close,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.26),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.14),
                          ),
                        ),
                        child: const Text(
                          "CRICKNOVA REPLAY",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: "Montserrat",
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 60,
                      left: 14,
                      child: SizedBox(
                        width: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.24),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sidebarRow(
                                    title: "PITCHING",
                                    value: widget.pitching,
                                    visible: showPitch,
                                  ),
                                  _sidebarRow(
                                    title: "IMPACT",
                                    value: widget.impact,
                                    visible: showImpact,
                                  ),
                                  _sidebarRow(
                                    title: "WICKET",
                                    value: widget.wickets == "Hitting"
                                        ? "HITTING"
                                        : "MISSING",
                                    visible: showWicket,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 18,
                      right: 64,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: showWicket ? 1.0 : 0.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.28),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _finalOut
                                  ? const Color(0xFFFF5252)
                                  : const Color(0xFF2EED79),
                            ),
                          ),
                          child: Text(
                            _finalOut ? "OUT" : "NOT OUT",
                            style: TextStyle(
                              color: _finalOut
                                  ? const Color(0xFFFF6E6E)
                                  : const Color(0xFF7DFFB1),
                              fontFamily: "Montserrat",
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 18,
                      child: Text(
                        "LIVE MOTION ANALYSIS - 120 FPS INTERPOLATED",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontFamily: "Montserrat",
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                );
              },
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
  String _drsPitching = "In Line";
  String _drsImpact = "In Line";
  String _drsWickets = "Hitting";
  String _drsWicketTarget = "Middle";
  String _drsOriginalDecision = "OUT";
  double _drsSwingDeg = 0.0;
  double _drsSpinDeg = 0.0;
  _DrsTrackingGeometry _drsGeometry = const _DrsTrackingGeometry.fallback();
  bool _drsOut = false;
  int _drsRunId = 0;
  late final AnimationController _drsPhaseController;

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

  Future<void> _configureDrsCinematic(Map<String, dynamic> drs) async {
    final decisionText = _normalizeDecision(drs["decision"]);
    final rawConfidence = drs["stump_confidence"];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : 0.0;
    final ultraedge = drs["ultraedge"] == true;
    final ultraedgeReasonRaw =
        drs["ultraedge_reason"] ??
        drs["ultraedge_note"] ??
        drs["reason"] ??
        drs["edge_reason"];
    _drsUltraedgeReason = ultraedgeReasonRaw?.toString().trim() ?? "";

    _drsHasSpike = ultraedge;
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
    drsResult = "${_drsOut ? "OUT" : "NOT OUT"}$confidenceText";
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
                    child: IconButton(
                      onPressed: _closeDrsOverlay,
                      icon: const Icon(Icons.close, color: Colors.white),
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
                                freezeAtBat: _drsHasSpike,
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
                                hasSpike: _drsHasSpike,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "ULTRA-EDGE: ${_drsHasSpike ? "SPIKE DETECTED" : "CHECKING FOR SPIKE..."}",
                            style: TextStyle(
                              color: _drsHasSpike
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
                    child: IconButton(
                      onPressed: _closeDrsOverlay,
                      icon: const Icon(Icons.close, color: Colors.white),
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
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return Padding(
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
                    backgroundColor: Colors.deepPurpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    debugPrint("UPLOAD_SCREEN → pickAndUpload triggered");
                    pickAndUpload();
                  },
                  child: const Text(
                    "Next",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> pickAndUpload() async {
    debugPrint("UPLOAD_SCREEN → pickAndUpload start");

    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepPurpleAccent,
            content: Text(
              "🎥 Video added! Total videos: $currentVideos",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

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
      if (!mounted) return;

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
  }

  Future<void> runDRS() async {
    if (video == null || drsLoading) return;

    setState(() {
      showDRS = false;
      drsLoading = true;
      drsResult = "Reviewing decision...";
      _drsPhase = _DrsCinematicPhase.idle;
    });

    final uri = Uri.parse(
      "https://cricknova-backend.onrender.com/training/drs",
    );

    final request = http.MultipartRequest("POST", uri);
    request.headers["Accept"] = "application/json";

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        drsResult = "USER NOT AUTHENTICATED";
        drsLoading = false;
      });
      return;
    }

    final String? idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      setState(() {
        drsResult = "USER NOT AUTHENTICATED";
        drsLoading = false;
      });
      return;
    }

    request.headers["Authorization"] = "Bearer $idToken";
    request.files.add(await http.MultipartFile.fromPath("file", video!.path));

    try {
      final response = await request.send().timeout(
        const Duration(seconds: 40),
      );

      final respStr = await response.stream.bytesToString();
      // 🎯 Give 20 XP for DRS usage (stored in Hive)
      await _addXP(20);

      if (response.statusCode != 200) {
        setState(() {
          drsResult = "DRS FAILED\nServer error";
          drsLoading = false;
        });
        return;
      }

      final data = jsonDecode(respStr);
      final drs = data["drs"];

      if (drs == null || drs is! Map) {
        setState(() {
          drsResult = "DRS DATA INVALID";
          drsLoading = false;
        });
        return;
      }
      await _configureDrsCinematic(Map<String, dynamic>.from(drs));
      if (!mounted) return;
      setState(() {
        drsLoading = false;
      });
      if (controller != null && controller!.value.isInitialized) {
        await controller!.pause();
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _DrsCinematicScreen(
            videoPath: video!.path,
            geometry: _drsGeometry,
            hasSpike: _drsHasSpike,
            ultraedgeReason: _drsUltraedgeReason,
            pitching: _drsPitching,
            impact: _drsImpact,
            wickets: _drsWickets,
            wicketTarget: _drsWicketTarget,
            originalDecision: _drsOriginalDecision,
            isOut: _drsOut,
            speedKmph: speedKmph ?? 95.0,
            swingDeg: _drsSwingDeg,
            spinDeg: _drsSpinDeg,
          ),
        ),
      );
      if (mounted && controller != null && controller!.value.isInitialized) {
        await controller!.play();
      }
    } catch (e) {
      setState(() {
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
                  "Plan Limit Reached 🔒",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: const Text(
                  "Your AI mistake detection limit has ended.\n\nUpgrade to Premium to continue getting advanced AI feedback.",
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        showCoach = false;
                      });
                    },
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
                          builder: (_) =>
                              const PremiumScreen(entrySource: "mistake_limit"),
                        ),
                      );
                    },
                    child: const Text(
                      "Buy Premium",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          );
          return;
        }
      }

      // 🔐 Redirect ONLY if backend explicitly blocks access
      final bool premiumRequired = data["premium_required"] == true;
      final bool success = data["success"] == true;

      if (premiumRequired && !success) {
        if (!mounted) return;

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
                "Premium Feature 🔒",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: const Text(
                "AI Coach is a premium feature.\n\nUpgrade your plan to unlock personalised batting & bowling analysis from our AI coach.",
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      showCoach = false;
                    });
                  },
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PremiumScreen(entrySource: "coach"),
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

        return;
      }

      // (XP block removed here)

      if (response.statusCode == 200) {
        if (data["success"] == true && data["reply"] != null) {
          await _addXP(20);
          setState(() {
            coachReply = data["reply"];
          });
        } else if (data["coach_feedback"] != null) {
          await _addXP(20);
          setState(() {
            coachReply = data["coach_feedback"];
          });
        } else {
          setState(() {
            coachReply =
                "Analysis completed, but no clear coaching feedback was generated.";
          });
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
        // Always go back to previous screen, never jump to Home
        Navigator.of(context).pop();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text("Upload Training Video"),
        ),
        body: controller == null
            ? Center(
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
                                  Colors.blueAccent,
                                  Colors.deepPurpleAccent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.deepPurpleAccent.withOpacity(
                                    0.6,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Text(
                              "Upload Training Video",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller!.value.aspectRatio,
                      child: VideoPlayer(controller!),
                    ),
                  ),

                  // LEFT SIDEBAR
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
                              setState(() {
                                showCoach = true;
                                coachReply =
                                    "This may take 1–2 minutes...\nPlease keep the app open ⏳";
                              });

                              await Future.delayed(const Duration(seconds: 6));
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
                                      colors: [Colors.blueAccent, Colors.cyan],
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
                        child: Center(
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
                              const SizedBox(height: 20),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  coachReply ?? "",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    showCoach = false;
                                  });
                                },
                                child: const Text("Close"),
                              ),
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
                            child: AnimatedSwitcher(
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
                                key: ValueKey(_cricketFacts[_currentFactIndex]),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
      ),
    );
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
