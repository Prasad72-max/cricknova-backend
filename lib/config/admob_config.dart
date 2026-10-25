/// ─────────────────────────────────────────────
///  AdMob Configuration — CrickX
///  Change kAdMobTestMode to false for production.
/// ─────────────────────────────────────────────
class AdMobConfig {
  AdMobConfig._();

  // ── TEST/PROD SWITCH ────────────────────────
  /// Set to false ONLY when releasing to production.
  static const bool kAdMobTestMode = true;

  // ── ANDROID APP ID ─────────────────────────
  static const String androidAppId = 'ca-app-pub-8703805552383133~3928397402';

  // ── REWARDED AD UNIT IDs ───────────────────
  static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _prodRewardedAdUnitId =
      'ca-app-pub-8703805552383133/6177684048';

  static String get rewardedAdUnitId =>
      kAdMobTestMode ? _testRewardedAdUnitId : _prodRewardedAdUnitId;

  // ── REWARD AMOUNTS ─────────────────────────
  static const int rewardedAnalysisCredits = 4;
}
