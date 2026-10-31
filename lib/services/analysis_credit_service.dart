import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admob_service.dart';
import 'premium_service.dart';
import '../config/admob_config.dart';

/// Manages AI Analysis and Chat Credits earned via rewarded ads (free users only).
/// - CricX Chat: 5 credits per ad
/// - Analyze Yourself Batting: 2 credits per ad
/// - Bowling Mistake Detection: 4 credits per ad
/// - Bowling Comparison: 2 credits per ad
class AnalysisCreditService {
  AnalysisCreditService._();
  static final AnalysisCreditService instance = AnalysisCreditService._();

  static const String _creditKeyPrefix = 'ai_analysis_credit_';
  static const String _chatCreditKeyPrefix = 'cricx_chat_credit_';
  static const String _battingCompareKeyPrefix = 'cricx_batting_compare_credit_';
  static const String _bowlingCompareKeyPrefix = 'cricx_bowling_compare_credit_';

  /// ValueNotifiers so UI widgets can reactively update.
  final ValueNotifier<int> creditsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> chatCreditsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> battingCompareCreditsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> bowlingCompareCreditsNotifier = ValueNotifier<int>(0);

  int get credits => creditsNotifier.value;
  int get chatCredits => chatCreditsNotifier.value;
  int get battingCompareCredits => battingCompareCreditsNotifier.value;
  int get bowlingCompareCredits => bowlingCompareCreditsNotifier.value;

  String _uid() => FirebaseAuth.instance.currentUser?.uid ?? 'anon';
  String _creditKey() => '$_creditKeyPrefix${_uid()}';
  String _chatCreditKey() => '$_chatCreditKeyPrefix${_uid()}';
  String _battingCompareKey() => '$_battingCompareKeyPrefix${_uid()}';
  String _bowlingCompareKey() => '$_bowlingCompareKeyPrefix${_uid()}';

  // ─── LOAD ────────────────────────────────────────────────────────────────

  Future<void> loadCredits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      creditsNotifier.value = (prefs.getInt(_creditKey()) ?? 0).clamp(0, 99);
      chatCreditsNotifier.value = (prefs.getInt(_chatCreditKey()) ?? 0).clamp(0, 99);
      battingCompareCreditsNotifier.value = (prefs.getInt(_battingCompareKey()) ?? 0).clamp(0, 99);
      bowlingCompareCreditsNotifier.value = (prefs.getInt(_bowlingCompareKey()) ?? 0).clamp(0, 99);
      debugPrint('[Credits] Loaded: analysis=${creditsNotifier.value}, chat=${chatCreditsNotifier.value}, battingComp=${battingCompareCreditsNotifier.value}, bowlingComp=${bowlingCompareCreditsNotifier.value}');
    } catch (e) {
      debugPrint('[Credits] Failed to load credits: $e');
    }
  }

  // ─── GRANT ───────────────────────────────────────────────────────────────

  void grantCredits({int amount = 4}) {
    SharedPreferences.getInstance().then((prefs) {
      final current = prefs.getInt(_creditKey()) ?? 0;
      final newTotal = (current + amount).clamp(0, 99);
      prefs.setInt(_creditKey(), newTotal);
      creditsNotifier.value = newTotal;
      debugPrint('[Credits] Bowling mistake / analysis +$amount → $newTotal');
    }).catchError((e) {
      debugPrint('[Credits] Failed to grant credits: $e');
    });
  }

  void grantChatCredits({int amount = 5}) {
    SharedPreferences.getInstance().then((prefs) {
      final current = prefs.getInt(_chatCreditKey()) ?? 0;
      final newTotal = (current + amount).clamp(0, 99);
      prefs.setInt(_chatCreditKey(), newTotal);
      chatCreditsNotifier.value = newTotal;
      debugPrint('[Credits] Chat credits +$amount → $newTotal');
    }).catchError((e) {
      debugPrint('[Credits] Failed to grant chat credits: $e');
    });
  }

  void grantBattingCompareCredits({int amount = 2}) {
    SharedPreferences.getInstance().then((prefs) {
      final current = prefs.getInt(_battingCompareKey()) ?? 0;
      final newTotal = (current + amount).clamp(0, 99);
      prefs.setInt(_battingCompareKey(), newTotal);
      battingCompareCreditsNotifier.value = newTotal;
      debugPrint('[Credits] Batting compare credits +$amount → $newTotal');
    }).catchError((e) {
      debugPrint('[Credits] Failed to grant batting compare credits: $e');
    });
  }

  void grantBowlingCompareCredits({int amount = 2}) {
    SharedPreferences.getInstance().then((prefs) {
      final current = prefs.getInt(_bowlingCompareKey()) ?? 0;
      final newTotal = (current + amount).clamp(0, 99);
      prefs.setInt(_bowlingCompareKey(), newTotal);
      bowlingCompareCreditsNotifier.value = newTotal;
      debugPrint('[Credits] Bowling compare credits +$amount → $newTotal');
    }).catchError((e) {
      debugPrint('[Credits] Failed to grant bowling compare credits: $e');
    });
  }

  // ─── CONSUME ─────────────────────────────────────────────────────────────

  Future<bool> consumeCredit() async {
    if (PremiumService.isPremiumActive) return true;
    await loadCredits();
    if (creditsNotifier.value <= 0) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_creditKey()) ?? 0;
      if (current <= 0) {
        creditsNotifier.value = 0;
        return false;
      }
      final newTotal = current - 1;
      await prefs.setInt(_creditKey(), newTotal);
      creditsNotifier.value = newTotal;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> consumeChatCredit() async {
    if (PremiumService.isPremiumActive) return true;
    await loadCredits();
    if (chatCreditsNotifier.value <= 0) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_chatCreditKey()) ?? 0;
      if (current <= 0) {
        chatCreditsNotifier.value = 0;
        return false;
      }
      final newTotal = current - 1;
      await prefs.setInt(_chatCreditKey(), newTotal);
      chatCreditsNotifier.value = newTotal;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> consumeBattingCompareCredit() async {
    if (PremiumService.isPremiumActive || PremiumService.hasCompareAccess) return true;
    await loadCredits();
    if (battingCompareCreditsNotifier.value <= 0) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_battingCompareKey()) ?? 0;
      if (current <= 0) {
        battingCompareCreditsNotifier.value = 0;
        return false;
      }
      final newTotal = current - 1;
      await prefs.setInt(_battingCompareKey(), newTotal);
      battingCompareCreditsNotifier.value = newTotal;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> consumeBowlingCompareCredit() async {
    if (PremiumService.isPremiumActive || PremiumService.hasCompareAccess) return true;
    await loadCredits();
    if (bowlingCompareCreditsNotifier.value <= 0) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_bowlingCompareKey()) ?? 0;
      if (current <= 0) {
        bowlingCompareCreditsNotifier.value = 0;
        return false;
      }
      final newTotal = current - 1;
      await prefs.setInt(_bowlingCompareKey(), newTotal);
      bowlingCompareCreditsNotifier.value = newTotal;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── WATCH AD FLOWS ──────────────────────────────────────────────────────

  Future<AdWatchResult> _watchGenericAd({required VoidCallback onReward}) async {
    if (PremiumService.isPremiumActive) return AdWatchResult.premiumUser;

    if (!AdMobService.instance.isRewardedAdReady) {
      unawaited(AdMobService.instance.loadRewardedAd());
      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (AdMobService.instance.isRewardedAdReady) break;
      }
    }

    if (!AdMobService.instance.isRewardedAdReady) {
      return AdWatchResult.adNotAvailable;
    }

    bool rewardGranted = false;
    final earned = await AdMobService.instance.showRewardedAd(
      onRewardGranted: () {
        rewardGranted = true;
        onReward();
      },
      onAdUnavailable: (reason) {
        debugPrint('[AdMob] Ad unavailable: $reason');
      },
    );

    if (rewardGranted || earned) return AdWatchResult.rewardEarned;
    return AdWatchResult.adClosedEarly;
  }

  /// Watch Ad for 4 Bowling Mistake Detection / Analysis Credits
  Future<AdWatchResult> watchAdForCredit({int amount = 4}) async {
    return _watchGenericAd(onReward: () => grantCredits(amount: amount));
  }

  /// Watch Ad for 5 CricX Chat Credits
  Future<AdWatchResult> watchAdForChatCredit({int amount = 5}) async {
    return _watchGenericAd(onReward: () => grantChatCredits(amount: amount));
  }

  /// Watch Ad for 2 Analyze Yourself Batting Credits
  Future<AdWatchResult> watchAdForBattingCompare({int amount = 2}) async {
    return _watchGenericAd(onReward: () => grantBattingCompareCredits(amount: amount));
  }

  /// Watch Ad for 2 Bowling Compare Credits
  Future<AdWatchResult> watchAdForBowlingCompare({int amount = 2}) async {
    return _watchGenericAd(onReward: () => grantBowlingCompareCredits(amount: amount));
  }

  // ─── USER SWITCH ─────────────────────────────────────────────────────────

  Future<void> onUserChanged() async {
    await loadCredits();
  }
}

enum AdWatchResult {
  rewardEarned,
  adNotAvailable,
  adClosedEarly,
  premiumUser,
}
