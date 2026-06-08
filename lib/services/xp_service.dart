import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class XpAwardResult {
  final int baseAmount;
  final int awardedAmount;
  final int totalXp;
  final bool midnightBonusApplied;

  const XpAwardResult({
    required this.baseAmount,
    required this.awardedAmount,
    required this.totalXp,
    required this.midnightBonusApplied,
  });
}

class XpService {
  static const int _midnightBonusEndHour = 5;
  static const double _midnightMultiplier = 1.5;

  static bool isMidnightBonusActive([DateTime? now]) {
    final localTime = now ?? DateTime.now();
    return localTime.hour < _midnightBonusEndHour;
  }

  static Future<XpAwardResult> award({
    required String uid,
    required int amount,
    String source = 'unknown',
    DateTime? now,
  }) async {
    final bonusApplied = isMidnightBonusActive(now);
    final awardedAmount = bonusApplied
        ? (amount * _midnightMultiplier).round()
        : amount;
    final box = await Hive.openBox("local_stats_$uid");
    final currentXp = (box.get('xp', defaultValue: 0) as num).toInt();
    final totalXp = currentXp + awardedAmount;

    await box.put('xp', totalXp);

    debugPrint(
      'XP UPDATED ($source) => +$awardedAmount'
      '${bonusApplied ? ' (MIDNIGHT 1.5x)' : ''} | TOTAL => $totalXp',
    );

    return XpAwardResult(
      baseAmount: amount,
      awardedAmount: awardedAmount,
      totalXp: totalXp,
      midnightBonusApplied: bonusApplied,
    );
  }
}
