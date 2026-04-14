import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class LeaderboardService {
  LeaderboardService._();

  static const String boxName = 'leaderboard_box_v1';
  static const String _entriesKey = 'entries';
  static const int topLimit = 200;
  static const int cutoffRank = 150;

  static Future<Box> _box() => Hive.openBox(boxName);

  static double _clampDouble(num v, double min, double max) =>
      v.toDouble().clamp(min, max);

  static double _speedScore10(double speedKmph) {
    // 140 km/h => full marks (10). Anything lower scales down.
    // We keep a sensible floor so normal sessions still score.
    const minKmph = 80.0;
    const fullKmph = 140.0;
    final s = ((speedKmph - minKmph) / (fullKmph - minKmph)) * 10.0;
    return s.clamp(0.0, 10.0);
  }

  static double _accuracyScore10(double accuracyPercent) {
    // 90% => full marks (10). Below 60% trends to 0.
    const minAcc = 60.0;
    const fullAcc = 90.0;
    final a = ((accuracyPercent - minAcc) / (fullAcc - minAcc)) * 10.0;
    return a.clamp(0.0, 10.0);
  }

  static double computeFinalPowerScore({
    required double maxSpeedKmph,
    required double accuracyPercent,
    required double aiRating10,
  }) {
    final speed10 = _speedScore10(maxSpeedKmph);
    final acc10 = _accuracyScore10(accuracyPercent);
    final ai10 = aiRating10.clamp(0.0, 10.0);
    final total = (0.25 * speed10) + (0.25 * acc10) + (0.50 * ai10);
    // Match the "8.9" style.
    return (total * 10).roundToDouble() / 10.0;
  }

  static bool looksSuspicious({
    required double maxSpeedKmph,
    required double accuracyPercent,
    required double aiRating10,
  }) {
    // Local heuristics only. Keep it strict enough to catch obvious fake inputs.
    if (maxSpeedKmph.isNaN ||
        accuracyPercent.isNaN ||
        aiRating10.isNaN ||
        maxSpeedKmph.isInfinite ||
        accuracyPercent.isInfinite ||
        aiRating10.isInfinite) {
      return true;
    }
    if (maxSpeedKmph <= 0 || maxSpeedKmph > 180) return true;
    if (accuracyPercent < 0 || accuracyPercent > 100) return true;
    if (aiRating10 < 0 || aiRating10 > 10) return true;

    // "Too perfect" combination that rarely happens for real practice clips.
    if (maxSpeedKmph >= 165 && accuracyPercent >= 97 && aiRating10 >= 9.8) {
      return true;
    }
    return false;
  }

  static List<Map<String, dynamic>> _readEntries(Box box) {
    final raw = box.get(_entriesKey);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  static Future<List<Map<String, dynamic>>> getEntries() async {
    final box = await _box();
    return _readEntries(box);
  }

  static Future<void> setEntries(List<Map<String, dynamic>> entries) async {
    final box = await _box();
    await box.put(_entriesKey, entries);
  }

  static int? _rankForId(List<Map<String, dynamic>> entries, String id) {
    final idx = entries.indexWhere((e) => (e['id'] ?? '').toString() == id);
    return idx == -1 ? null : (idx + 1);
  }

  static int _compareEntries(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sa = (a['total_score'] as num?)?.toDouble() ?? 0.0;
    final sb = (b['total_score'] as num?)?.toDouble() ?? 0.0;
    final scoreCmp = sb.compareTo(sa);
    if (scoreCmp != 0) return scoreCmp;
    final ta = (a['updated_at_ms'] as num?)?.toInt() ?? 0;
    final tb = (b['updated_at_ms'] as num?)?.toInt() ?? 0;
    return tb.compareTo(ta);
  }

  static Future<LeaderboardUpdateResult> upsertEntry({
    required String id,
    required String name,
    required String region,
    required double maxSpeedKmph,
    required double accuracyPercent,
    required double aiRating10,
    bool verified = true,
  }) async {
    final box = await _box();
    final entries = _readEntries(box);

    final oldRank = _rankForId(entries, id);

    final speed = _clampDouble(maxSpeedKmph, 0.0, 999.0);
    final acc = _clampDouble(accuracyPercent, 0.0, 100.0);
    final ai = _clampDouble(aiRating10, 0.0, 10.0);
    final flagged = looksSuspicious(
      maxSpeedKmph: speed,
      accuracyPercent: acc,
      aiRating10: ai,
    );

    if (!verified || flagged) {
      // Remove if present.
      entries.removeWhere((e) => (e['id'] ?? '').toString() == id);
      entries.sort(_compareEntries);
      final clipped = entries.take(topLimit).toList(growable: false);
      await box.put(_entriesKey, clipped);
      return LeaderboardUpdateResult(
        oldRank: oldRank,
        newRank: null,
        rankStatus: 'Flagged',
        leaderboardAction: oldRank == null ? 'Maintain' : 'Remove',
        totalScore: null,
        flagged: true,
      );
    }

    final totalScore = computeFinalPowerScore(
      maxSpeedKmph: speed,
      accuracyPercent: acc,
      aiRating10: ai,
    );

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final next = <String, dynamic>{
      'id': id,
      'name': name.trim().isEmpty ? 'Player' : name.trim(),
      'region': region.trim().isEmpty ? 'India' : region.trim(),
      'total_score': totalScore,
      'rank_status': 'Top 200 Eligible',
      'metrics': <String, dynamic>{
        'speed_kmph': speed,
        'accuracy_percent': acc,
        'ai_rating': ai,
      },
      'verified': true,
      'flagged': false,
      'updated_at_ms': nowMs,
    };

    final existingIndex = entries.indexWhere(
      (e) => (e['id'] ?? '').toString() == id,
    );
    final action = existingIndex == -1
        ? 'Update'
        : 'Maintain'; // keep UI strings simple
    if (existingIndex == -1) {
      entries.add(next);
    } else {
      entries[existingIndex] = next;
    }

    entries.sort(_compareEntries);
    final clipped = entries.take(topLimit).toList(growable: false);
    await box.put(_entriesKey, clipped);

    final newRank = _rankForId(clipped, id);
    return LeaderboardUpdateResult(
      oldRank: oldRank,
      newRank: newRank,
      rankStatus: 'Top 200 Eligible',
      leaderboardAction: action,
      totalScore: totalScore,
      flagged: false,
    );
  }

  static Future<LeaderboardUpdateResult?> updateFromCurrentUserStats({
    double? maxSpeedKmph,
    double? accuracyPercent,
    double? aiRating10,
    String? overrideName,
    String? overrideRegion,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final uid = user.uid;

    final statsBox = await Hive.openBox('local_stats_$uid');
    final name =
        (overrideName ??
                (statsBox.get('profileName') as String?) ??
                user.displayName ??
                (user.email ?? 'Player').split('@').first)
            .toString();

    final resolvedRegion =
        (overrideRegion ?? (statsBox.get('leaderboardRegion') as String?) ?? '')
            .toString()
            .trim();
    final region = resolvedRegion.isEmpty ? 'Maharashtra' : resolvedRegion;

    final speed =
        (maxSpeedKmph ?? (statsBox.get('maxSpeed') as num?)?.toDouble() ?? 0.0)
            .toDouble();

    // Accuracy in this app is derived from speed consistency (Insights tab logic).
    final acc =
        (accuracyPercent ??
                (statsBox.get('avgAccuracyPercent') as num?)?.toDouble() ??
                0.0)
            .toDouble();

    final aiRating =
        (aiRating10 ??
                (statsBox.get('lastAiBattingRating') as num?)?.toDouble() ??
                5.0)
            .toDouble();

    // Require some minimum data to participate.
    final verified = speed >= 60 && acc >= 40 && aiRating >= 0;
    return upsertEntry(
      id: uid,
      name: name,
      region: region,
      maxSpeedKmph: speed,
      accuracyPercent: acc,
      aiRating10: aiRating,
      verified: verified,
    );
  }

  static double deriveAvgAccuracyPercentFromSpeeds(List<double> speeds) {
    if (speeds.isEmpty) return 0.0;
    final mean = speeds.reduce((a, b) => a + b) / speeds.length;
    final deltas = speeds.map((s) => (s - mean).abs()).toList();
    final maxDelta = deltas.reduce(math.max);
    if (maxDelta == 0) return 95.0;
    final scores = deltas.map((d) {
      final score = 100 - ((d / maxDelta) * 25);
      return score.clamp(60, 100).toDouble();
    }).toList();
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  static Future<void> cacheLastSessionAccuracyFromSpeedBox({
    required String uid,
  }) async {
    try {
      final speedBox = await Hive.openBox('speedBox');
      final key = 'allSpeeds_$uid';
      final stored = speedBox.get(key) as List?;
      if (stored == null || stored.isEmpty) return;
      final all = stored.map((e) => (e as num).toDouble()).toList();
      final last6 = all.length <= 6 ? all : all.sublist(all.length - 6);
      final avgAcc = deriveAvgAccuracyPercentFromSpeeds(last6);
      final statsBox = await Hive.openBox('local_stats_$uid');
      await statsBox.put('avgAccuracyPercent', avgAcc);
    } catch (e) {
      debugPrint('Leaderboard accuracy cache failed: $e');
    }
  }
}

class LeaderboardUpdateResult {
  final int? oldRank;
  final int? newRank;
  final String rankStatus;
  final String leaderboardAction;
  final double? totalScore;
  final bool flagged;

  const LeaderboardUpdateResult({
    required this.oldRank,
    required this.newRank,
    required this.rankStatus,
    required this.leaderboardAction,
    required this.totalScore,
    required this.flagged,
  });

  bool get rankImproved =>
      oldRank != null && newRank != null && newRank! < oldRank!;
}
