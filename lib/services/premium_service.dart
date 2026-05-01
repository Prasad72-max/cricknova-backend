import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:CrickNova_Ai/config/api_config.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum SubscriptionAccessState {
  unknown,
  free,
  trialActive,
  trialRevokeScheduled,
  active,
  gracePeriod,
  pastDue,
  accountHold,
  expired,
}

class PremiumService {
  // ⚠️ RULE: Usage counters are NEVER reset on client.
  // They are restored ONLY from Firestore backend.
  // Logout / reinstall must NOT affect usage.

  // 🔒 Prevent backend sync from overwriting newer local usage
  static bool _usageDirty = false;
  static DateTime? _lastLocalUsageUpdate;

  // ValueNotifier doesn't expose a public "force notify" API.
  // We use a tiny subclass so we can safely emit updates when the boolean
  // doesn't change but other premium fields (plan/limits/usage) do.
  static final PremiumStateNotifier premiumNotifier = PremiumStateNotifier(
    false,
  );

  // Single source of truth for UI
  static bool isPremium = false;
  // 🔔 Expiry tracking
  static bool justExpired = false;
  static DateTime? expiryDate;
  static DateTime? startedDate;
  static DateTime? graceUntil;
  static DateTime? holdUntil;
  static DateTime? trialRevokeAt;
  static SubscriptionAccessState accessState = SubscriptionAccessState.unknown;
  static String billingState = "UNKNOWN";

  /// 🔐 Premium validity = premium flag only
  /// Limits are enforced strictly by backend
  static bool get isPremiumActive {
    return isPremium && !isAccountOnHold;
  }

  static bool get isInGracePeriod => accessState == SubscriptionAccessState.gracePeriod;
  static bool get isAccountOnHold =>
      accessState == SubscriptionAccessState.accountHold ||
      accessState == SubscriptionAccessState.pastDue;
  static bool get isTrialRevokeScheduled =>
      accessState == SubscriptionAccessState.trialRevokeScheduled;
  static bool get isReadOnlyMode => isAccountOnHold;
  static bool get shouldShowBillingBanner => isInGracePeriod;
  static String? get billingBannerMessage {
    if (isInGracePeriod) {
      return 'Payment failed! Please update your balance within 48 hours to avoid losing Pro access.';
    }
    if (isAccountOnHold) {
      return 'Account on Hold. Please settle your ₹499 payment to continue your training.';
    }
    return null;
  }

  // Backward-compat alias (used by UI)
  static bool? get cachedIsPremium => isPremium;
  static String plan = "FREE";

  // Usage counters (used by HomeScreen UI)
  static int chatUsed = 0;
  static int mistakeUsed = 0;
  static int compareUsed = 0;

  static int chatLimit = 0;
  static int mistakeLimit = 0;
  static int compareLimit = 0;

  // Init guard
  static bool isLoaded = false;
  static bool _initialized = false;
  static String? _lastLoadedUid;
  static Future<void>? _loadInFlight;

  static const String _premiumKey = "is_premium";
  static const String _planKey = "premium_plan";
  static const String _billingStateKey = "premium_billing_state";
  static const String _accessStateKey = "premium_access_state";
  static const String _trialRevokeAtKey = "premium_trial_revoke_at";
  static const String _graceUntilKey = "premium_grace_until";
  static const String _holdUntilKey = "premium_hold_until";

  static const String _chatLimitKey = "chat_limit";
  static const String _mistakeLimitKey = "mistake_limit";
  static const String _compareLimitKey = "compare_limit";

  static ({
    bool premium,
    String plan,
    int chatUsed,
    int mistakeUsed,
    int compareUsed,
    int chatLimit,
    int mistakeLimit,
    int compareLimit,
    DateTime? expiryDate,
    DateTime? startedDate,
    DateTime? graceUntil,
    DateTime? holdUntil,
    DateTime? trialRevokeAt,
    bool justExpired,
    SubscriptionAccessState accessState,
    String billingState,
  })
  _snapshot() {
    return (
      premium: isPremium,
      plan: plan,
      chatUsed: chatUsed,
      mistakeUsed: mistakeUsed,
      compareUsed: compareUsed,
      chatLimit: chatLimit,
      mistakeLimit: mistakeLimit,
      compareLimit: compareLimit,
      expiryDate: expiryDate,
      startedDate: startedDate,
      graceUntil: graceUntil,
      holdUntil: holdUntil,
      trialRevokeAt: trialRevokeAt,
      justExpired: justExpired,
      accessState: accessState,
      billingState: billingState,
    );
  }

  static void _notifyPremium({required bool force}) {
    if (premiumNotifier.value != isPremium) {
      premiumNotifier.value = isPremium;
      return;
    }
    if (force) {
      premiumNotifier.forceNotify();
    }
  }

  static void _resetUsageState() {
    chatUsed = 0;
    mistakeUsed = 0;
    compareUsed = 0;
    _usageDirty = false;
    _lastLocalUsageUpdate = null;
  }

  static String _stringField(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = "",
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }

  static DateTime? _dateField(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    }
    return null;
  }

  static SubscriptionAccessState _stateFromRaw(String raw) {
    switch (raw.toUpperCase()) {
      case "IN_GRACE_PERIOD":
      case "GRACE_PERIOD":
        return SubscriptionAccessState.gracePeriod;
      case "ACCOUNT_HOLD":
        return SubscriptionAccessState.accountHold;
      case "PAST_DUE":
        return SubscriptionAccessState.pastDue;
      case "TRIAL_ACTIVE":
      case "TRIAL":
        return SubscriptionAccessState.trialActive;
      case "TRIAL_REVOKE_SCHEDULED":
        return SubscriptionAccessState.trialRevokeScheduled;
      case "ACTIVE":
      case "SUBSCRIBED":
      case "PREMIUM":
        return SubscriptionAccessState.active;
      case "EXPIRED":
      case "CANCELLED":
      case "CANCELED":
        return SubscriptionAccessState.expired;
      default:
        return SubscriptionAccessState.unknown;
    }
  }

  static SubscriptionAccessState _resolveAccessState(
    Map<String, dynamic> data,
    DateTime? now,
  ) {
    final String billing = _stringField(
      data,
      const ["subscription_state", "billing_state", "state"],
    );
    final rawState = _stateFromRaw(billing);

    final DateTime? trialRevoke = _dateField(
      data,
      const ["trial_revoke_at", "trial_revokeAt", "revoke_at"],
    );
    final DateTime? grace = _dateField(
      data,
      const ["grace_until", "graceUntil", "grace_ends_at"],
    );
    final DateTime? hold = _dateField(
      data,
      const ["hold_until", "holdUntil", "account_hold_until"],
    );

    trialRevokeAt = trialRevoke;
    graceUntil = grace;
    holdUntil = hold;
    billingState = billing.isEmpty ? "UNKNOWN" : billing.toUpperCase();

    if (trialRevoke != null && now != null && now.isBefore(trialRevoke)) {
      return SubscriptionAccessState.trialRevokeScheduled;
    }
    if (trialRevoke != null &&
        now != null &&
        now.isAfter(trialRevoke) &&
        rawState == SubscriptionAccessState.trialRevokeScheduled) {
      return SubscriptionAccessState.expired;
    }
    if (rawState == SubscriptionAccessState.gracePeriod) {
      if (grace != null && now != null && now.isAfter(grace)) {
        return SubscriptionAccessState.pastDue;
      }
      return SubscriptionAccessState.gracePeriod;
    }
    if (rawState == SubscriptionAccessState.accountHold) {
      if (hold != null && now != null && now.isAfter(hold)) {
        return SubscriptionAccessState.expired;
      }
      return SubscriptionAccessState.accountHold;
    }
    if (rawState == SubscriptionAccessState.pastDue) {
      if (hold != null && now != null && now.isAfter(hold)) {
        return SubscriptionAccessState.expired;
      }
      return SubscriptionAccessState.pastDue;
    }
    if (rawState == SubscriptionAccessState.trialRevokeScheduled) {
      return SubscriptionAccessState.trialRevokeScheduled;
    }
    if (rawState == SubscriptionAccessState.active) {
      return SubscriptionAccessState.active;
    }

    final bool hasPremiumFlag =
        data["isPremium"] == true || data["premium"] == true;
    if (hasPremiumFlag) {
      return SubscriptionAccessState.active;
    }

    return SubscriptionAccessState.free;
  }

  static bool _stateIsUnlocked(SubscriptionAccessState state) {
    switch (state) {
      case SubscriptionAccessState.active:
      case SubscriptionAccessState.gracePeriod:
      case SubscriptionAccessState.trialActive:
      case SubscriptionAccessState.trialRevokeScheduled:
        return true;
      case SubscriptionAccessState.unknown:
      case SubscriptionAccessState.free:
      case SubscriptionAccessState.pastDue:
      case SubscriptionAccessState.accountHold:
      case SubscriptionAccessState.expired:
        return false;
    }
  }

  static void _setAccessState(SubscriptionAccessState state) {
    accessState = state;
    isPremium = _stateIsUnlocked(state);
  }

  static void _cancelScheduledStateTimer() {
    _trialRevokeTimer?.cancel();
    _trialRevokeTimer = null;
  }

  static Timer? _trialRevokeTimer;

  static void _scheduleStateRefresh({
    required String uid,
    DateTime? at,
  }) {
    _cancelScheduledStateTimer();
    if (at == null) return;

    final now = DateTime.now();
    final delay = at.difference(now);
    if (delay.isNegative || delay == Duration.zero) {
      unawaited(_runSingleLoad(uid, force: true));
      return;
    }

    _trialRevokeTimer = Timer(delay, () {
      unawaited(_runSingleLoad(uid, force: true));
    });
  }

  static Future<void> _setCachedState({
    required bool premium,
    required String planId,
    required int chat,
    required int mistake,
    required int compare,
    SubscriptionAccessState? state,
    String? billing,
    DateTime? trialRevoke,
    DateTime? grace,
    DateTime? hold,
    bool resetUsage = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, premium);
    await prefs.setString(_planKey, planId);
    await prefs.setInt(_chatLimitKey, chat);
    await prefs.setInt(_mistakeLimitKey, mistake);
    await prefs.setInt(_compareLimitKey, compare);
    await prefs.setString(_billingStateKey, billing ?? billingState);
    await prefs.setString(
      _accessStateKey,
      (state ?? accessState).name,
    );
    if (trialRevoke != null) {
      await prefs.setString(_trialRevokeAtKey, trialRevoke.toIso8601String());
    }
    if (grace != null) {
      await prefs.setString(_graceUntilKey, grace.toIso8601String());
    }
    if (hold != null) {
      await prefs.setString(_holdUntilKey, hold.toIso8601String());
    }

    if (state != null) {
      accessState = state;
    }
    billingState = billing ?? billingState;
    isPremium = premium;
    premiumNotifier.value = premium;
    plan = planId;
    chatLimit = chat;
    mistakeLimit = mistake;
    compareLimit = compare;

    if (resetUsage) {
      _resetUsageState();
    }
  }

  /// 🔥 CALL THIS ON APP START (main.dart)
  /// 🔁 BACKWARD-COMPAT (used by login_screen.dart)
  static Future<void> syncFromFirestore(String uid) async {
    await _runSingleLoad(uid);
  }

  /// 🌐 Sync premium from backend API (used after payment success)
  static Future<void> syncFromBackend(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Always trust backend via Firestore mirror
      await loadPremiumFromUid(uid);
      _usageDirty = false;
      _lastLocalUsageUpdate = null;
    } catch (e) {
      debugPrint("Premium sync failed: $e");
    }
  }

  /// 🔄 Force refresh premium state (used after login / app resume)
  static Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Force token refresh to avoid stale auth
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }

    await _runSingleLoad(user.uid, force: true);
    isLoaded = true;
  }

  static Future<void> loadPremiumFromUid(String uid) async {
    if (_loadInFlight != null) {
      await _loadInFlight;
      return;
    }

    final before = _snapshot();
    final bool switchedUser = _lastLoadedUid != null && _lastLoadedUid != uid;
    if (switchedUser) {
      _resetUsageState();
    }

    final completer = Completer<void>();
    _loadInFlight = completer.future;
    try {
      final doc = await FirebaseFirestore.instance
          .collection("subscriptions")
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        _resetUsageState();
        _setAccessState(SubscriptionAccessState.free);
        await _setCachedState(
          premium: false,
          planId: "FREE",
          chat: 0,
          mistake: 0,
          compare: 0,
          state: accessState,
          billing: billingState,
          resetUsage: false,
        );
        isLoaded = true;
        _lastLoadedUid = uid;
        _notifyPremium(force: before != _snapshot());
        completer.complete();
        return;
      }

      final data = doc.data()!;
      // 1) Read isPremium from Firestore
      // Support both old and new backend schemas
      final bool firestorePremium =
          data["isPremium"] == true || data["premium"] == true;
      debugPrint(
        "🔥 Premium flag from Firestore = $firestorePremium | raw keys: ${data.keys}",
      );

      final rawExpiry = data["expiry"] ?? data["expiryDate"];
      final rawStarted = data["started_at"] ?? data["startedAt"];
      final planId = (data["plan"] ?? "FREE").toString();
      final resolvedState = _resolveAccessState(data, DateTime.now());
      final limits = _limitsForPlan(planId);
      if (resolvedState == SubscriptionAccessState.expired &&
          trialRevokeAt != null &&
          DateTime.now().isAfter(trialRevokeAt!)) {
        justExpired = true;
      }

      if (rawExpiry is Timestamp) {
        expiryDate = rawExpiry.toDate();
      } else if (rawExpiry is String) {
        expiryDate = DateTime.tryParse(rawExpiry);
      }

      if (rawStarted is Timestamp) {
        startedDate = rawStarted.toDate();
      } else if (rawStarted is String) {
        startedDate = DateTime.tryParse(rawStarted);
      }

      if (expiryDate != null) {
        final nowUtc = DateTime.now().toUtc();
        final expiryUtc = expiryDate!.toUtc();

        debugPrint("🕒 NOW(UTC): $nowUtc");
        debugPrint("🕒 EXPIRY(UTC): $expiryUtc");

        if (nowUtc.isAfter(expiryUtc) &&
            resolvedState != SubscriptionAccessState.gracePeriod &&
            resolvedState != SubscriptionAccessState.trialRevokeScheduled) {
          debugPrint("🚨 PLAN EXPIRED DETECTED");

          final prefs = await SharedPreferences.getInstance();
          final expiryKey = "expiry_handled_${expiryUtc.toIso8601String()}";
          final alreadyHandled = prefs.getBool(expiryKey) ?? false;

          if (!alreadyHandled) {
            justExpired = true;
            await prefs.setBool(expiryKey, true);
          }

          _resetUsageState();
          _setAccessState(SubscriptionAccessState.expired);
          await _setCachedState(
            premium: false,
            planId: planId,
            chat: limits.chat,
            mistake: limits.mistake,
            compare: limits.compare,
            state: SubscriptionAccessState.expired,
            billing: billingState,
            resetUsage: false,
          );
          _lastLoadedUid = uid;
          _scheduleStateRefresh(uid: uid, at: expiryDate);

          _notifyPremium(force: before != _snapshot());

          completer.complete();
          return;
        }
      }

      // 2) Read usage from nested "used" map, fallback to root-level fields
      final usedMap = (data["used"] is Map)
          ? Map<String, dynamic>.from(data["used"])
          : {};
      final used = {
        "chat": usedMap["chat"] ?? data["chat_used"] ?? 0,
        "mistake": usedMap["mistake"] ?? data["mistake_used"] ?? 0,
        "compare": usedMap["compare"] ?? data["compare_used"] ?? 0,
      };

      // 🛑 Do not overwrite newer local usage with stale server data
      final bool hasFreshLocalUsageForSameUser =
          _usageDirty && _lastLocalUsageUpdate != null && !switchedUser;
      if (hasFreshLocalUsageForSameUser) {
        debugPrint("⏸️ Skipping usage overwrite (local usage is newer)");
      } else {
        chatUsed = used["chat"] ?? 0;
        mistakeUsed = used["mistake"] ?? 0;
        compareUsed = used["compare"] ?? 0;
        _usageDirty = false;
        _lastLocalUsageUpdate = null;
      }

      final bool isHold =
          resolvedState == SubscriptionAccessState.accountHold ||
          resolvedState == SubscriptionAccessState.pastDue;
      final bool isGrace =
          resolvedState == SubscriptionAccessState.gracePeriod;
      final bool isTrialRevoke =
          resolvedState == SubscriptionAccessState.trialRevokeScheduled ||
          resolvedState == SubscriptionAccessState.trialActive;
      final bool isUnlocked =
          firestorePremium ||
          isGrace ||
          isTrialRevoke ||
          resolvedState == SubscriptionAccessState.active;

      _setAccessState(
        isHold
            ? resolvedState
            : isGrace
                ? SubscriptionAccessState.gracePeriod
                : isTrialRevoke
                    ? SubscriptionAccessState.trialRevokeScheduled
                    : isUnlocked
                        ? SubscriptionAccessState.active
                        : SubscriptionAccessState.free,
      );

      if (isHold) {
        isPremium = false;
        await _setCachedState(
          premium: false,
          planId: planId,
          chat: limits.chat,
          mistake: limits.mistake,
          compare: limits.compare,
          state: accessState,
          billing: billingState,
          grace: graceUntil,
          hold: holdUntil,
          trialRevoke: trialRevokeAt,
          resetUsage: false,
        );
      } else if (isUnlocked) {
        await _setCachedState(
          premium: true,
          planId: planId,
          chat: limits.chat,
          mistake: limits.mistake,
          compare: limits.compare,
          state: accessState,
          billing: billingState,
          grace: graceUntil,
          hold: holdUntil,
          trialRevoke: trialRevokeAt,
          resetUsage: false,
        );
      } else {
        _resetUsageState();
        await _setCachedState(
          premium: false,
          planId: planId,
          chat: 0,
          mistake: 0,
          compare: 0,
          state: accessState,
          billing: billingState,
          grace: graceUntil,
          hold: holdUntil,
          trialRevoke: trialRevokeAt,
          resetUsage: false,
        );
      }

      _scheduleStateRefresh(
        uid: uid,
        at: trialRevokeAt ?? graceUntil ?? holdUntil ?? expiryDate,
      );

      isLoaded = true;
      _lastLoadedUid = uid;
      _notifyPremium(force: before != _snapshot());
      completer.complete();
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete();
      }
      return;
    } finally {
      _loadInFlight = null;
    }
  }

  static Future<void> _runSingleLoad(String uid, {bool force = false}) async {
    if (_lastLoadedUid != null && _lastLoadedUid != uid) {
      _resetUsageState();
    }
    if (!force && isLoaded && _lastLoadedUid == uid) {
      return;
    }
    await loadPremiumFromUid(uid);
  }

  /// 🔁 Call this on every app launch (Splash / main)
  static Future<void> restoreOnLaunch() async {
    // 🔁 Always check expiry on app open
    if (_initialized) {
      debugPrint("⏭️ Premium restore skipped (already running)");
      return;
    }
    _initialized = true;
    // 🔥 STEP 1: Restore from local cache FIRST (no Firestore read)
    final prefs = await SharedPreferences.getInstance();

    final cachedPremium = prefs.getBool(_premiumKey);
    final cachedPlan = prefs.getString(_planKey);
    final cachedBilling = prefs.getString(_billingStateKey);
    final cachedAccess = prefs.getString(_accessStateKey);
    final cachedChatLimit = prefs.getInt(_chatLimitKey);
    final cachedMistakeLimit = prefs.getInt(_mistakeLimitKey);
    final cachedCompareLimit = prefs.getInt(_compareLimitKey);
    final cachedTrialRevoke = prefs.getString(_trialRevokeAtKey);
    final cachedGraceUntil = prefs.getString(_graceUntilKey);
    final cachedHoldUntil = prefs.getString(_holdUntilKey);

    if (cachedPremium != null) {
      isPremium = cachedPremium;
      premiumNotifier.value = cachedPremium;
    }

    if (cachedPlan != null) {
      plan = cachedPlan;
    }
    if (cachedBilling != null && cachedBilling.isNotEmpty) {
      billingState = cachedBilling;
    }
    if (cachedAccess != null && cachedAccess.isNotEmpty) {
      accessState = SubscriptionAccessState.values.firstWhere(
        (state) => state.name == cachedAccess,
        orElse: () => SubscriptionAccessState.unknown,
      );
    }
    if (cachedTrialRevoke != null && cachedTrialRevoke.isNotEmpty) {
      trialRevokeAt = DateTime.tryParse(cachedTrialRevoke);
    }
    if (cachedGraceUntil != null && cachedGraceUntil.isNotEmpty) {
      graceUntil = DateTime.tryParse(cachedGraceUntil);
    }
    if (cachedHoldUntil != null && cachedHoldUntil.isNotEmpty) {
      holdUntil = DateTime.tryParse(cachedHoldUntil);
    }

    if (cachedChatLimit != null) chatLimit = cachedChatLimit;
    if (cachedMistakeLimit != null) mistakeLimit = cachedMistakeLimit;
    if (cachedCompareLimit != null) compareLimit = cachedCompareLimit;

    debugPrint("💾 Premium restored from cache: $isPremium ($plan)");
    isLoaded = cachedPremium != null || cachedPlan != null;
    if (isLoaded) {
      _notifyPremium(force: true);
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint("⏳ Auth not ready, premium restore deferred");
      _initialized = false;
      return;
    }

    try {
      // Force fresh token to avoid cached auth state
      final String? idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        debugPrint("❌ No valid token during premium restore");
        _initialized = false;
        return;
      }

      await _runSingleLoad(user.uid);

      // Mark loaded and notify UI immediately
      isLoaded = true;
      _notifyPremium(force: true);

      debugPrint("✅ Premium restored on launch: $isPremium ($plan)");
    } catch (e) {
      debugPrint("❌ restoreOnLaunch failed: $e");
    }
    _initialized = false;
  }

  static Future<void> ensureFreshState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _runSingleLoad(user.uid, force: true);
    isLoaded = true;
    _notifyPremium(force: true);
  }

  /// ✅ CALL THIS AFTER PAYMENT SUCCESS
  static Future<void> setPremiumTrue({
    required String planId,
    required int chatLimit,
    required int mistakeLimit,
    required int diffLimit,
  }) async {
    // ⚠️ WARNING: Do NOT use this after Razorpay payment.
    // Premium must be activated only after backend / webhook verification.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection("subscriptions")
        .doc(user.uid)
        .set({
          "isPremium": true,
          "premium": true,
          "subscription_state": "ACTIVE",
          "billing_state": "ACTIVE",
          "plan": planId,
          "chatLimit": chatLimit,
          "mistakeLimit": mistakeLimit,
          "diffLimit": diffLimit,
          "chat_used": 0,
          "mistake_used": 0,
          "compare_used": 0,
          "used": {"chat": 0, "mistake": 0, "compare": 0},
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    _setAccessState(SubscriptionAccessState.active);
    billingState = "ACTIVE";
    await _cache(
      true,
      planId,
      chatLimit,
      mistakeLimit,
      diffLimit,
      resetUsage: true,
    );
  }

  /// 🔐 ACTIVATE PREMIUM AFTER SUCCESSFUL PAYMENT (USED BY premium_screen.dart)
  /// 🔐 VERIFY RAZORPAY PAYMENT WITH BACKEND (SINGLE SOURCE OF TRUTH)
  static Future<void> verifyRazorpayPayment({
    required String paymentId,
    required String orderId,
    required String signature,
    required String plan,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }

    // 🔁 Normalize UI plan to backend plan ID
    String normalizedPlan;
    switch (plan) {
      case "monthly":
      case "99":
      case "IN_99":
        normalizedPlan = "IN_99";
        break;
      case "299":
      case "IN_299":
        normalizedPlan = "IN_299";
        break;
      case "499":
      case "IN_499":
        normalizedPlan = "IN_499";
        break;
      case "1999":
      case "IN_1999":
        normalizedPlan = "IN_1999";
        break;
      default:
        throw Exception("Invalid plan selected: $plan");
    }

    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/payment/verify-payment"),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({
        "razorpay_payment_id": paymentId,
        "razorpay_order_id": orderId,
        "razorpay_signature": signature,
        "plan": normalizedPlan,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Payment verification failed");
    }

    // ✅ Always resync from backend after verification
    await syncFromBackend(user.uid);
    // 🔥 FORCE local premium refresh so UI updates instantly
    await refresh();
  }

  // -----------------------------
  // CACHE HELPERS
  // -----------------------------
  static Future<void> _cache(
    bool premium,
    String planId,
    int chat,
    int mistake,
    int compare, {
    bool resetUsage = false,
  }) async {
    await _setCachedState(
      premium: premium,
      planId: planId,
      chat: chat,
      mistake: mistake,
      compare: compare,
      resetUsage: resetUsage,
    );
  }

  // -----------------------------
  // LOGOUT / RESET
  // -----------------------------
  static Future<void> clearPremium() async {
    isPremium = false;
    premiumNotifier.value = false;
    plan = "FREE";
    chatLimit = 0;
    mistakeLimit = 0;
    compareLimit = 0;
    billingState = "UNKNOWN";
    accessState = SubscriptionAccessState.free;
    expiryDate = null;
    startedDate = null;
    graceUntil = null;
    holdUntil = null;
    trialRevokeAt = null;
    _cancelScheduledStateTimer();
    _resetUsageState();
    isLoaded = false;
    _lastLoadedUid = null;
  }

  static ({int chat, int mistake, int compare}) _limitsForPlan(String planId) {
    switch (planId) {
      case "IN_99":
        return (chat: 200, mistake: 15, compare: 0);
      case "IN_299":
        return (chat: 1200, mistake: 30, compare: 0);
      case "IN_499":
        return (chat: 3000, mistake: 60, compare: 60);
      case "IN_1999":
        return (chat: 5000, mistake: 150, compare: 150);
      case "INTL_MONTHLY":
        return (chat: 200, mistake: 15, compare: 0);
      case "INTL_6M":
        return (chat: 1200, mistake: 30, compare: 0);
      case "INTL_YEARLY":
        return (chat: 3000, mistake: 60, compare: 60);
      case "INT_ULTRA":
      case "INTL_ULTRA":
      case "ULTRA":
        return (chat: 7000, mistake: 150, compare: 150);
      default:
        return (chat: 0, mistake: 0, compare: 0);
    }
  }

  static Future<void> updateStatus(
    bool premium, {
    String planId = "FREE",
  }) async {
    final before = _snapshot();
    _setAccessState(
      premium ? SubscriptionAccessState.active : SubscriptionAccessState.free,
    );
    billingState = premium ? "ACTIVE" : "FREE";
    final limits = premium
        ? _limitsForPlan(planId)
        : (chat: 0, mistake: 0, compare: 0);
    await _cache(
      premium,
      premium ? planId : "FREE",
      limits.chat,
      limits.mistake,
      limits.compare,
      resetUsage: premium,
    );
    isLoaded = true;
    _notifyPremium(force: before != _snapshot());
  }

  /// Lets external billing flows reuse the app's existing premium state.
  static Future<void> applyExternalPremiumState({
    required bool premium,
    String planId = "FREE",
    int chatLimit = 0,
    int mistakeLimit = 0,
    int compareLimit = 0,
    String billing = "ACTIVE",
    SubscriptionAccessState? state,
  }) async {
    final before = _snapshot();
    _setAccessState(
      state ?? (premium ? SubscriptionAccessState.active : SubscriptionAccessState.free),
    );
    billingState = billing;
    await _cache(
      premium,
      planId,
      chatLimit,
      mistakeLimit,
      compareLimit,
      resetUsage: premium,
    );
    isLoaded = true;
    _notifyPremium(force: before != _snapshot());
  }

  // -----------------------------
  // ACCESS GUARDS (SINGLE TRUTH)
  // -----------------------------
  // -----------------------------
  // 🔄 FORCE USAGE SYNC AFTER EVERY AI USE
  // -----------------------------
  static Future<void> syncAfterUsage() async {
    isLoaded = true;
    _notifyPremium(force: true);
  }

  static bool canChat() {
    if (!isLoaded) return true;
    return isPremium && chatUsed < chatLimit;
  }

  static bool canMistake() {
    if (!isLoaded) return false;
    if (!isPremium) return false;
    return mistakeUsed < mistakeLimit;
  }

  static bool canCompare() {
    if (!isLoaded) return false;
    if (!isPremium) return false;
    return compareLimit > 0 && compareUsed < compareLimit;
  }

  static bool get hasCompareAccess {
    if (!isLoaded) return false;
    if (!isPremium) return false;
    return compareLimit > 0;
  }

  static bool get hasBowlingAnalysisAccess {
    if (!isLoaded) return false;
    if (!isPremium) return false;
    // Bowling Analysis screen is visible for any premium tier.
    // Individual features (Compare) are gated via hasCompareAccess.
    return true;
  }

  static bool get isElite {
    if (!isPremium) return false;
    return plan == "IN_1999" || plan.toUpperCase().contains("ULTRA");
  }

  // -----------------------------
  // CHAT HELPERS
  // -----------------------------
  static Future<int> getChatLimit() async {
    if (!isLoaded) return 0;
    if (!isPremium) return 0;
    final remaining = chatLimit - chatUsed;
    return remaining > 0 ? remaining : 0;
  }

  static Future<void> consumeChat() async {
    if (!isLoaded) return; // never block, backend decides
    chatUsed++;
    _usageDirty = true;
    _lastLocalUsageUpdate = DateTime.now();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection("subscriptions")
          .doc(user.uid)
          .update({
            "chat_used": FieldValue.increment(1),
            "updatedAt": FieldValue.serverTimestamp(),
          });
    }
    await syncAfterUsage();
  }

  // -----------------------------
  // MISTAKE HELPERS
  // -----------------------------
  static Future<int> getMistakeRemaining() async {
    if (!isLoaded) return 0;
    if (!isPremium) return 0;

    final remaining = mistakeLimit - mistakeUsed;
    return remaining > 0 ? remaining : 0;
  }

  static Future<void> consumeMistake() async {
    if (!isLoaded) return;
    if (!canMistake()) return;

    mistakeUsed++;

    _usageDirty = true;
    _lastLocalUsageUpdate = DateTime.now();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection("subscriptions")
          .doc(user.uid)
          .update({
            "mistake_used": FieldValue.increment(1),
            "updatedAt": FieldValue.serverTimestamp(),
          });
    }
    await _incrementMonthlyUsage(_UsageType.mistake);
    await syncAfterUsage();
  }

  // -----------------------------
  // COMPARE HELPERS
  // -----------------------------
  static Future<int> getCompareLimit() async {
    if (!isLoaded) return 0;
    if (!isPremium) return 0;
    final remaining = compareLimit - compareUsed;
    return remaining > 0 ? remaining : 0;
  }

  static Future<void> consumeCompare() async {
    if (!isLoaded) return;
    if (!hasCompareAccess) return;

    compareUsed++;
    _usageDirty = true;
    _lastLocalUsageUpdate = DateTime.now();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection("subscriptions")
          .doc(user.uid)
          .update({
            "compare_used": FieldValue.increment(1),
            "updatedAt": FieldValue.serverTimestamp(),
          });
    }
    await syncAfterUsage();
  }

  // -----------------------------
  // MONTHLY USAGE (Elite Dashboard)
  // -----------------------------
  static const String _usageHiveBoxName = "usage_cache";

  static String _usageMonthKey([DateTime? now]) {
    final current = now ?? DateTime.now();
    final month = current.month.toString().padLeft(2, '0');
    return "${current.year}-$month";
  }

  static String currentUsageMonthKey() {
    return _usageMonthKey();
  }

  static String _usageHiveSwingKey(String uid, String monthKey) =>
      "swing_used_${uid}_$monthKey";

  static String _usageHiveMistakeKey(String uid, String monthKey) =>
      "mistake_used_${uid}_$monthKey";

  static Future<void> _persistMonthlyUsageToHive(
    String uid,
    MonthlyUsage usage,
  ) async {
    final box = await Hive.openBox(_usageHiveBoxName);
    await box.put(_usageHiveSwingKey(uid, usage.monthKey), usage.swingUsed);
    await box.put(_usageHiveMistakeKey(uid, usage.monthKey), usage.mistakeUsed);
  }

  static Future<MonthlyUsage> _readMonthlyUsageFromHive(
    String uid,
    String monthKey,
  ) async {
    final box = await Hive.openBox(_usageHiveBoxName);
    return MonthlyUsage(
      monthKey: monthKey,
      swingUsed:
          (box.get(_usageHiveSwingKey(uid, monthKey), defaultValue: 0) as num)
              .toInt(),
      mistakeUsed:
          (box.get(_usageHiveMistakeKey(uid, monthKey), defaultValue: 0) as num)
              .toInt(),
    );
  }

  static Stream<MonthlyUsage> monthlyUsageStream() {
    final user = FirebaseAuth.instance.currentUser;
    final initialKey = _usageMonthKey();
    if (user == null) {
      return Stream.value(MonthlyUsage.empty(initialKey));
    }

    final controller = StreamController<MonthlyUsage>();
    StreamSubscription<BoxEvent>? sub;
    Timer? monthTimer;
    var currentKey = initialKey;
    Hive.openBox(_usageHiveBoxName)
        .then((box) async {
          if (controller.isClosed) return;
          controller.add(await _readMonthlyUsageFromHive(user.uid, currentKey));

          sub?.cancel();
          sub = box.watch().listen((event) async {
            final swingKey = _usageHiveSwingKey(user.uid, currentKey);
            final mistakeKey = _usageHiveMistakeKey(user.uid, currentKey);
            if (event.key == swingKey || event.key == mistakeKey) {
              controller.add(
                await _readMonthlyUsageFromHive(user.uid, currentKey),
              );
            }
          }, onError: controller.addError);
        })
        .catchError((error, stackTrace) {
          controller.addError(error, stackTrace);
        });

    monthTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final newKey = _usageMonthKey();
      if (newKey != currentKey) {
        currentKey = newKey;
        _readMonthlyUsageFromHive(user.uid, currentKey).then(controller.add);
      }
    });

    controller.onCancel = () {
      monthTimer?.cancel();
      sub?.cancel();
    };

    return controller.stream;
  }

  static Future<MonthlyUsage> fetchMonthlyUsage() async {
    final user = FirebaseAuth.instance.currentUser;
    final monthKey = _usageMonthKey();
    if (user == null) return MonthlyUsage.empty(monthKey);
    return _readMonthlyUsageFromHive(user.uid, monthKey);
  }

  static Future<MonthlyUsage> recordSwingUsage() {
    return _incrementMonthlyUsage(_UsageType.swing);
  }

  static Future<MonthlyUsage> recordMistakeUsage() {
    return _incrementMonthlyUsage(_UsageType.mistake);
  }

  static Future<MonthlyUsage> _incrementMonthlyUsage(_UsageType type) async {
    final user = FirebaseAuth.instance.currentUser;
    final monthKey = _usageMonthKey();
    if (user == null) return MonthlyUsage.empty(monthKey);
    final current = await _readMonthlyUsageFromHive(user.uid, monthKey);
    final usage = MonthlyUsage(
      monthKey: monthKey,
      swingUsed: current.swingUsed + (type == _UsageType.swing ? 1 : 0),
      mistakeUsed: current.mistakeUsed + (type == _UsageType.mistake ? 1 : 0),
    );
    await _persistMonthlyUsageToHive(user.uid, usage);
    return usage;
  }

  // -----------------------------
  // PAYWALL HELPER
  // -----------------------------
  // UI-only helper. Must be called ONLY from explicit user actions.
  static void showPaywall(
    BuildContext context, {
    String? source,
    List<String>? allowedPlans,
  }) {
    // Intentionally empty: navigation is controlled by UI, not service
  }
}

class PremiumStateNotifier extends ValueNotifier<bool> {
  PremiumStateNotifier(super.value);

  void forceNotify() => notifyListeners();
}

enum _UsageType { swing, mistake }

class MonthlyUsage {
  final String monthKey;
  final int swingUsed;
  final int mistakeUsed;

  const MonthlyUsage({
    required this.monthKey,
    required this.swingUsed,
    required this.mistakeUsed,
  });

  factory MonthlyUsage.empty(String monthKey) {
    return MonthlyUsage(monthKey: monthKey, swingUsed: 0, mistakeUsed: 0);
  }
  bool get isEmpty => swingUsed == 0 && mistakeUsed == 0;
}
