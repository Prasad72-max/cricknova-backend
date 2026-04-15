import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:CrickNova_Ai/config/api_config.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PremiumService {
  // ⚠️ RULE: Usage counters are NEVER reset on client.
  // They are restored ONLY from Firestore backend.
  // Logout / reinstall must NOT affect usage.

  // 🔒 Prevent backend sync from overwriting newer local usage
  static bool _usageDirty = false;
  static DateTime? _lastLocalUsageUpdate;

  // Single source of truth for UI
  static bool isPremium = false;
  static final ValueNotifier<bool> premiumNotifier = ValueNotifier<bool>(false);
  // 🔔 Expiry tracking
  static bool justExpired = false;
  static DateTime? expiryDate;
  static DateTime? startedDate;

  /// 🔐 Premium validity = premium flag only
  /// Limits are enforced strictly by backend
  static bool get isPremiumActive {
    return isPremium;
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

  static const String _chatLimitKey = "chat_limit";
  static const String _mistakeLimitKey = "mistake_limit";
  static const String _compareLimitKey = "compare_limit";

  static void _resetUsageState() {
    chatUsed = 0;
    mistakeUsed = 0;
    compareUsed = 0;
    _usageDirty = false;
    _lastLocalUsageUpdate = null;
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

    // 🔔 Force immediate UI update
    premiumNotifier.value = isPremium;
    premiumNotifier.notifyListeners();

    isLoaded = true;
  }

  static Future<void> loadPremiumFromUid(String uid) async {
    if (_loadInFlight != null) {
      await _loadInFlight;
      return;
    }

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
        await _cache(false, "FREE", 0, 0, 0);
        isLoaded = true;
        _lastLoadedUid = uid;
        premiumNotifier.value = isPremium;
        premiumNotifier.notifyListeners();
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

      if (!firestorePremium) {
        await _cache(false, "FREE", 0, 0, 0);
        isLoaded = true;
        _lastLoadedUid = uid;
        premiumNotifier.value = isPremium;
        premiumNotifier.notifyListeners();
        completer.complete();
        return;
      }

      final rawExpiry = data["expiry"] ?? data["expiryDate"];
      final rawStarted = data["started_at"] ?? data["startedAt"];

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

        if (nowUtc.isAfter(expiryUtc)) {
          debugPrint("🚨 PLAN EXPIRED DETECTED");

          final prefs = await SharedPreferences.getInstance();
          final expiryKey = "expiry_handled_${expiryUtc.toIso8601String()}";
          final alreadyHandled = prefs.getBool(expiryKey) ?? false;

          if (!alreadyHandled) {
            justExpired = true;
            await prefs.setBool(expiryKey, true);
          }

          _resetUsageState();
          await _cache(false, "FREE", 0, 0, 0);
          _lastLoadedUid = uid;

          premiumNotifier.value = false;
          premiumNotifier.notifyListeners();

          completer.complete();
          return;
        }
      }

      final planId = data["plan"] ?? "FREE";

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

      switch (planId) {
        case "IN_99":
          await _cache(firestorePremium, planId, 200, 15, 0);
          break;
        case "IN_299":
          await _cache(firestorePremium, planId, 1200, 30, 0);
          break;
        case "IN_499":
          await _cache(firestorePremium, planId, 3000, 60, 60);
          break;
        case "IN_1999":
          await _cache(firestorePremium, planId, 5000, 150, 150);
          break;
        case "INTL_MONTHLY":
          await _cache(firestorePremium, planId, 200, 15, 0);
          break;
        case "INTL_6M":
          await _cache(firestorePremium, planId, 1200, 30, 0);
          break;
        case "INTL_YEARLY":
          await _cache(firestorePremium, planId, 3000, 60, 60);
          break;
        case "INT_ULTRA":
        case "INTL_ULTRA":
        case "ULTRA":
          await _cache(firestorePremium, planId, 7000, 150, 150);
          break;
        default:
          _resetUsageState();
          await _cache(false, "FREE", 0, 0, 0);
      }

      isLoaded = true;
      _lastLoadedUid = uid;
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
    final cachedChatLimit = prefs.getInt(_chatLimitKey);
    final cachedMistakeLimit = prefs.getInt(_mistakeLimitKey);
    final cachedCompareLimit = prefs.getInt(_compareLimitKey);

    if (cachedPremium != null) {
      isPremium = cachedPremium;
      premiumNotifier.value = cachedPremium;
    }

    if (cachedPlan != null) {
      plan = cachedPlan;
    }

    if (cachedChatLimit != null) chatLimit = cachedChatLimit;
    if (cachedMistakeLimit != null) mistakeLimit = cachedMistakeLimit;
    if (cachedCompareLimit != null) compareLimit = cachedCompareLimit;

    debugPrint("💾 Premium restored from cache: $isPremium ($plan)");
    isLoaded = cachedPremium != null || cachedPlan != null;
    if (isLoaded) {
      premiumNotifier.notifyListeners();
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
      premiumNotifier.value = isPremium;
      premiumNotifier.notifyListeners();

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
    premiumNotifier.value = isPremium;
    premiumNotifier.notifyListeners();
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

    // 🔔 Notify UI immediately after payment
    premiumNotifier.value = isPremium;
    premiumNotifier.notifyListeners();
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
    final prefs = await SharedPreferences.getInstance();

    // Persist limits
    await prefs.setBool(_premiumKey, premium);
    await prefs.setString(_planKey, planId);
    await prefs.setInt(_chatLimitKey, chat);
    await prefs.setInt(_mistakeLimitKey, mistake);
    await prefs.setInt(_compareLimitKey, compare);

    // In-memory state (single source for UI)
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
    premiumNotifier.notifyListeners();
  }

  /// Lets external billing flows reuse the app's existing premium state.
  static Future<void> applyExternalPremiumState({
    required bool premium,
    String planId = "FREE",
    int chatLimit = 0,
    int mistakeLimit = 0,
    int compareLimit = 0,
  }) async {
    await _cache(
      premium,
      planId,
      chatLimit,
      mistakeLimit,
      compareLimit,
      resetUsage: premium,
    );
    isLoaded = true;
    premiumNotifier.notifyListeners();
  }

  // -----------------------------
  // ACCESS GUARDS (SINGLE TRUTH)
  // -----------------------------
  // -----------------------------
  // 🔄 FORCE USAGE SYNC AFTER EVERY AI USE
  // -----------------------------
  static Future<void> syncAfterUsage() async {
    isLoaded = true;
    premiumNotifier.notifyListeners();
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
