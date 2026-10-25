import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/admob_config.dart';
import 'premium_service.dart';

/// Manages Google AdMob Rewarded Ads for CrickX.
/// All ad operations are no-ops for premium users.
///
/// ROOT CAUSE FIX: ad.show() is non-blocking and returns immediately.
/// We use a Completer that resolves only after onAdDismissedFullScreenContent,
/// so callers correctly await the full user interaction before reading the result.
class AdMobService {
  AdMobService._();
  static final AdMobService instance = AdMobService._();

  bool _sdkInitialized = false;
  bool _initInFlight = false;
  RewardedAd? _rewardedAd;
  bool _isLoadingAd = false;
  bool _isShowingAd = false;
  int _loadFailCount = 0;
  static const int _maxLoadRetries = 3;

  /// True after SDK init succeeds.
  bool get isInitialized => _sdkInitialized;

  /// True if a rewarded ad is loaded and ready to show.
  bool get isRewardedAdReady => _rewardedAd != null && !_isShowingAd;

  // ─── INITIALIZATION ──────────────────────────────────────────────────────

  /// Call once from main.dart. Safe to call multiple times (idempotent).
  Future<void> initialize() async {
    if (_sdkInitialized || _initInFlight) return;
    _initInFlight = true;
    try {
      debugPrint('[AdMob] Initializing SDK...');
      await MobileAds.instance.initialize();
      _sdkInitialized = true;
      debugPrint('[AdMob] SDK initialized successfully');
      debugPrint('[AdMob] Test mode: ${AdMobConfig.kAdMobTestMode}');
      debugPrint('[AdMob] Ad unit: ${AdMobConfig.rewardedAdUnitId}');
      // Preload first ad for free users
      unawaited(loadRewardedAd());
    } catch (e) {
      debugPrint('[AdMob] SDK initialization failed: $e');
    } finally {
      _initInFlight = false;
    }
  }

  // ─── PREMIUM CHECK ───────────────────────────────────────────────────────

  bool get _isPremiumUser => PremiumService.isPremiumActive;

  // ─── AD LOADING ──────────────────────────────────────────────────────────

  /// Load a rewarded ad. No-op for premium users or if already loading/loaded.
  Future<void> loadRewardedAd() async {
    debugPrint('[AdMob] Checking premium status before load');
    if (_isPremiumUser) {
      debugPrint('[Premium] User is premium — skipping ad load');
      _disposeCurrentAd();
      return;
    }
    if (!_sdkInitialized) {
      debugPrint('[AdMob] SDK not ready yet, skipping load');
      return;
    }
    if (_isLoadingAd) {
      debugPrint('[AdMob] Already loading, skipping duplicate load');
      return;
    }
    if (_rewardedAd != null) {
      debugPrint('[AdMob] Ad already loaded, skipping load');
      return;
    }

    _isLoadingAd = true;
    debugPrint('[AdMob] Rewarded ad loading... unit=${AdMobConfig.rewardedAdUnitId}');

    try {
      await RewardedAd.load(
        adUnitId: AdMobConfig.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('[AdMob] Rewarded ad loaded ✅');
            _rewardedAd = ad;
            _isLoadingAd = false;
            _loadFailCount = 0;
          },
          onAdFailedToLoad: (error) {
            debugPrint('[AdMob] Rewarded ad failed to load: ${error.message} (code=${error.code})');
            _rewardedAd = null;
            _isLoadingAd = false;
            _loadFailCount++;
            if (_loadFailCount < _maxLoadRetries) {
              final delay = Duration(seconds: _loadFailCount * 30);
              debugPrint('[AdMob] Retry load in ${delay.inSeconds}s (attempt $_loadFailCount/$_maxLoadRetries)');
              Future.delayed(delay, loadRewardedAd);
            } else {
              debugPrint('[AdMob] Max retries reached — resetting in 5 min');
              Future.delayed(const Duration(minutes: 5), () {
                _loadFailCount = 0;
              });
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('[AdMob] Exception during load: $e');
      _isLoadingAd = false;
    }
  }

  // ─── AD SHOWING ──────────────────────────────────────────────────────────

  /// Show a rewarded ad and wait until it is DISMISSED before returning.
  ///
  /// KEY FIX: Uses a Completer so this Future only completes after
  /// onAdDismissedFullScreenContent fires — not immediately after ad.show().
  /// This ensures the caller sees the correct reward state.
  ///
  /// [onRewardGranted] — called synchronously inside onUserEarnedReward.
  /// Returns true if the user earned a reward, false otherwise.
  Future<bool> showRewardedAd({
    required void Function() onRewardGranted,
    void Function(String reason)? onAdUnavailable,
  }) async {
    debugPrint('[AdMob] Watch Ad button tapped');
    debugPrint('[AdMob] Checking premium status');

    if (_isPremiumUser) {
      debugPrint('[Premium] User is premium — no ads shown');
      return false;
    }

    debugPrint('[AdMob] User is FREE');
    debugPrint('[AdMob] Checking rewarded ad availability');
    debugPrint('[AdMob] isRewardedAdReady=$isRewardedAdReady  _rewardedAd=${_rewardedAd != null}  _isShowingAd=$_isShowingAd');

    if (_isShowingAd) {
      debugPrint('[AdMob] Ad already showing — ignoring duplicate call');
      return false;
    }

    if (_rewardedAd == null) {
      debugPrint('[AdMob] No rewarded ad available — triggering reload');
      onAdUnavailable?.call('ad_not_loaded');
      unawaited(loadRewardedAd());
      return false;
    }

    _isShowingAd = true;
    bool rewardGrantedThisSession = false;

    // Take ownership — set to null to prevent accidental reuse
    final ad = _rewardedAd!;
    _rewardedAd = null;
    debugPrint('[AdMob] Rewarded ad object acquired, ready to show');

    // Completer resolves ONLY after the ad is dismissed (or fails to show).
    // Without this, ad.show() returns immediately and rewardGranted is always false.
    final dismissCompleter = Completer<void>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        debugPrint('[AdMob] Showing rewarded ad ✅');
      },
      onAdDismissedFullScreenContent: (dismissedAd) {
        debugPrint('[AdMob] Rewarded ad dismissed');
        dismissedAd.dispose();
        _isShowingAd = false;
        unawaited(loadRewardedAd()); // Preload next ad
        if (!dismissCompleter.isCompleted) dismissCompleter.complete();
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint('[AdMob] Rewarded ad failed to show: ${error.message}');
        failedAd.dispose();
        _isShowingAd = false;
        onAdUnavailable?.call('show_failed: ${error.message}');
        unawaited(loadRewardedAd());
        if (!dismissCompleter.isCompleted) dismissCompleter.complete();
      },
      onAdImpression: (_) {
        debugPrint('[AdMob] Rewarded ad impression recorded');
      },
    );

    try {
      debugPrint('[AdMob] Calling ad.show()...');
      await ad.show(
        onUserEarnedReward: (AdWithoutView adView, RewardItem reward) {
          // This fires BEFORE dismiss — only grant reward here
          debugPrint('[AdMob] Reward callback received: amount=${reward.amount} type=${reward.type}');
          if (!rewardGrantedThisSession) {
            rewardGrantedThisSession = true;
            debugPrint('[AI] Credit granted');
            onRewardGranted(); // synchronous — no async here
          }
        },
      );
      debugPrint('[AdMob] ad.show() returned — waiting for dismiss...');
    } catch (e) {
      debugPrint('[AdMob] Exception calling ad.show(): $e');
      _isShowingAd = false;
      onAdUnavailable?.call('show_exception: $e');
      if (!dismissCompleter.isCompleted) dismissCompleter.complete();
    }

    // CRITICAL: wait here until ad is dismissed before returning
    await dismissCompleter.future;
    debugPrint('[AdMob] Flow complete — rewardGranted=$rewardGrantedThisSession');
    return rewardGrantedThisSession;
  }

  // ─── CLEANUP ─────────────────────────────────────────────────────────────

  void _disposeCurrentAd() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }

  void dispose() {
    _disposeCurrentAd();
    _isShowingAd = false;
    _isLoadingAd = false;
  }
}
