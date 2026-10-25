import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admob_service.dart';
import 'premium_service.dart';
import '../config/admob_config.dart';

/// Manages AI Analysis Credits earned via rewarded ads (free users only).
/// Premium users never interact with this service — they have direct access.
class AnalysisCreditService {
  AnalysisCreditService._();
  static final AnalysisCreditService instance = AnalysisCreditService._();

  static const String _creditKeyPrefix = 'ai_analysis_credit_';

  /// ValueNotifier so UI widgets can reactively update.
  final ValueNotifier<int> creditsNotifier = ValueNotifier<int>(0);

  int get credits => creditsNotifier.value;

  /// Per-UID key — credits never leak between Firebase accounts.
  String _creditKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    return '$_creditKeyPrefix$uid';
  }

  // ─── LOAD ────────────────────────────────────────────────────────────────

  Future<void> loadCredits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_creditKey()) ?? 0;
      creditsNotifier.value = saved.clamp(0, 99);
      debugPrint('[AI] Analysis credits loaded: ${creditsNotifier.value} (uid=${FirebaseAuth.instance.currentUser?.uid})');
    } catch (e) {
      debugPrint('[AI] Failed to load credits: $e');
    }
  }

  // ─── GRANT ───────────────────────────────────────────────────────────────

  /// Grant credits ONLY after AdMob officially confirms the reward.
  /// This is called synchronously inside onUserEarnedReward.
  void grantCredits({int amount = AdMobConfig.rewardedAnalysisCredits}) {
    // NOTE: synchronous path using then() to avoid blocking the AdMob callback.
    SharedPreferences.getInstance().then((prefs) {
      final current = prefs.getInt(_creditKey()) ?? 0;
      final newTotal = (current + amount).clamp(0, 99);
      prefs.setInt(_creditKey(), newTotal);
      creditsNotifier.value = newTotal;
      debugPrint('[AI] Credit granted: +$amount → total=$newTotal (uid=${FirebaseAuth.instance.currentUser?.uid})');
    }).catchError((e) {
      debugPrint('[AI] Failed to grant credits: $e');
    });
  }

  // ─── CONSUME ─────────────────────────────────────────────────────────────

  /// Consume 1 credit. Returns true if credit was available and consumed.
  /// Premium users always return true (no credits needed).
  Future<bool> consumeCredit() async {
    if (PremiumService.isPremiumActive) {
      debugPrint('[AI] Premium user — credit not required');
      return true;
    }

    await loadCredits(); // Refresh from SharedPreferences

    if (creditsNotifier.value <= 0) {
      debugPrint('[AI] No credits remaining');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_creditKey()) ?? 0;
      if (current <= 0) {
        creditsNotifier.value = 0;
        debugPrint('[AI] No credits in SharedPreferences');
        return false;
      }
      final newTotal = current - 1;
      await prefs.setInt(_creditKey(), newTotal);
      creditsNotifier.value = newTotal;
      debugPrint('[AI] Credit consumed → remaining=$newTotal');
      return true;
    } catch (e) {
      debugPrint('[AI] Failed to consume credit: $e');
      return false;
    }
  }

  // ─── WATCH AD → GRANT ────────────────────────────────────────────────────

  /// Full rewarded ad flow: show ad → grant credit only on confirmed reward.
  ///
  /// FIX: onRewardGranted is now SYNCHRONOUS (not async) because AdMobService
  /// uses a Completer to await dismiss. The synchronous grantCredits() schedules
  /// the SharedPreferences write via .then() without blocking the AdMob callback.
  Future<AdWatchResult> watchAdForCredit() async {
    debugPrint('[AdMob] watchAdForCredit() called');
    debugPrint('[AdMob] Checking premium status');

    if (PremiumService.isPremiumActive) {
      debugPrint('[Premium] User is premium — no ad needed');
      return AdWatchResult.premiumUser;
    }

    debugPrint('[AdMob] User is FREE');
    debugPrint('[AdMob] Checking rewarded ad availability: isReady=${AdMobService.instance.isRewardedAdReady}');

    if (!AdMobService.instance.isRewardedAdReady) {
      debugPrint('[AdMob] Ad not ready yet — attempting to load and wait up to 4s');
      unawaited(AdMobService.instance.loadRewardedAd());
      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (AdMobService.instance.isRewardedAdReady) {
          debugPrint('[AdMob] Ad became ready after ${(i + 1) * 500}ms ✅');
          break;
        }
      }
    }

    if (!AdMobService.instance.isRewardedAdReady) {
      debugPrint('[AdMob] Ad still not ready — returning adNotAvailable');
      return AdWatchResult.adNotAvailable;
    }

    bool rewardGranted = false;

    // showRewardedAd() now awaits until ad is fully dismissed via Completer.
    // onRewardGranted is synchronous — no async/await inside it.
    final earned = await AdMobService.instance.showRewardedAd(
      onRewardGranted: () {
        // SYNCHRONOUS — called inside onUserEarnedReward before dismiss
        rewardGranted = true;
        grantCredits(); // synchronous write via .then()
      },
      onAdUnavailable: (reason) {
        debugPrint('[AdMob] Ad unavailable: $reason');
      },
    );

    debugPrint('[AdMob] Ad flow completed — earned=$earned rewardGranted=$rewardGranted');

    if (rewardGranted || earned) {
      return AdWatchResult.rewardEarned;
    }
    return AdWatchResult.adClosedEarly;
  }

  // ─── USER SWITCH ─────────────────────────────────────────────────────────

  /// Call on auth change — credits are user-specific (keyed by Firebase UID).
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
