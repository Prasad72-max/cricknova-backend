import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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

  static const String _premiumKey = "is_premium";
  static const String _planKey = "premium_plan";

  static const String _chatLimitKey = "chat_limit";
  static const String _mistakeLimitKey = "mistake_limit";
  static const String _compareLimitKey = "compare_limit";

  /// 🔥 CALL THIS ON APP START (main.dart)
  /// 🔁 BACKWARD-COMPAT (used by login_screen.dart)
  static Future<void> syncFromFirestore(String uid) async {
    await loadPremiumFromUid(uid);
  }

  /// 🌐 Sync premium from backend API (used after Razorpay / PayPal success)
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

    await loadPremiumFromUid(user.uid);

    // 🔔 Force immediate UI update
    premiumNotifier.value = isPremium;
    premiumNotifier.notifyListeners();

    isLoaded = true;
  }

  static Future<void> loadPremiumFromUid(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("subscriptions")
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        await _cache(false, "FREE", 0, 0, 0);
        isLoaded = true;
        premiumNotifier.value = isPremium;
        premiumNotifier.notifyListeners();
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
        premiumNotifier.value = isPremium;
        premiumNotifier.notifyListeners();
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

          await _cache(false, "FREE", 0, 0, 0);

          premiumNotifier.value = false;
          premiumNotifier.notifyListeners();

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
      if (_usageDirty && _lastLocalUsageUpdate != null) {
        debugPrint("⏸️ Skipping usage overwrite (local usage is newer)");
      } else {
        chatUsed = used["chat"] ?? 0;
        mistakeUsed = used["mistake"] ?? 0;
        compareUsed = used["compare"] ?? 0;
      }

      switch (planId) {
        case "IN_99":
          await _cache(firestorePremium, planId, 200, 15, 0);
          break;
        case "IN_299":
          await _cache(firestorePremium, planId, 1200, 30, 0);
          break;
        case "IN_499":
          await _cache(firestorePremium, planId, 3000, 60, 50);
          break;
        case "IN_1999":
          await _cache(firestorePremium, planId, 5000, 150, 150);
          break;
        case "INT_ULTRA":
        case "INTL_ULTRA":
        case "ULTRA":
          await _cache(firestorePremium, planId, 7000, 150, 150);
          break;
        default:
          await _cache(false, "FREE", 0, 0, 0);
      }

      isLoaded = true;
    } catch (e) {
      return;
    }
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

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint("⏳ Auth not ready, premium restore deferred");
      return;
    }

    try {
      // Force fresh token to avoid cached auth state
      final String? idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        debugPrint("❌ No valid token during premium restore");
        return;
      }

      await loadPremiumFromUid(user.uid);

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
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    await _cache(true, planId, chatLimit, mistakeLimit, diffLimit);
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
    int compare,
  ) async {
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
    // ❌ DO NOT reset usage here
  }

  // -----------------------------
  // ACCESS GUARDS (SINGLE TRUTH)
  // -----------------------------
  // -----------------------------
  // 🔄 FORCE USAGE SYNC AFTER EVERY AI USE
  // -----------------------------
  static Future<void> syncAfterUsage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Re-fetch latest usage + limits from Firestore
    await loadPremiumFromUid(user.uid);

    // Notify UI listeners immediately
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
    if (!isLoaded) return true;
    return isPremiumActive && compareUsed < compareLimit;
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
    if (!isPremium) return 0;
    return compareLimit - compareUsed;
  }

  static Future<void> consumeCompare() async {
    if (!canCompare()) return;
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
    await _incrementMonthlyUsage(_UsageType.swing);
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
    await box.put(
      _usageHiveSwingKey(uid, usage.monthKey),
      usage.swingUsed,
    );
    await box.put(
      _usageHiveMistakeKey(uid, usage.monthKey),
      usage.mistakeUsed,
    );
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
    Hive.openBox(_usageHiveBoxName).then((box) async {
      if (controller.isClosed) return;
      controller.add(await _readMonthlyUsageFromHive(user.uid, currentKey));

      sub?.cancel();
      sub = box.watch().listen((event) async {
        final swingKey = _usageHiveSwingKey(user.uid, currentKey);
        final mistakeKey = _usageHiveMistakeKey(user.uid, currentKey);
        if (event.key == swingKey || event.key == mistakeKey) {
          controller.add(await _readMonthlyUsageFromHive(user.uid, currentKey));
        }
      }, onError: controller.addError);
    }).catchError((error, stackTrace) {
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

  // -----------------------------
  // PAYPAL HELPERS
  // -----------------------------
  // -----------------------------
  // PAYPAL CREATE + APPROVAL (INTL)
  // -----------------------------
  static Future<void> startPaypalPayment({
    required double amount,
    required String plan,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not authenticated");
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }
    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/paypal/create-order"),
      headers: {
        "Content-Type": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({
        "amount_usd": amount,
        "currency": "USD",
        "plan": plan,
        "user_id": user.uid,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to create PayPal order");
    }

    final data = jsonDecode(response.body);
    debugPrint("🧾 PayPal create-order response: $data");

    // Support both common backend keys
    String? approvalUrl;

    if (data["approvalUrl"] != null) {
      approvalUrl = data["approvalUrl"];
    } else if (data["approval_url"] != null) {
      approvalUrl = data["approval_url"];
    } else if (data["links"] is List) {
      try {
        final approveLink = (data["links"] as List).firstWhere(
          (e) => e["rel"] == "approve",
        );
        approvalUrl = approveLink["href"];
      } catch (_) {
        approvalUrl = null;
      }
    }

    if (approvalUrl == null || approvalUrl.isEmpty) {
      throw Exception("PayPal approval URL missing from backend response");
    }

    // Normalize URL (force https if backend sent http)
    if (approvalUrl.startsWith("http://")) {
      approvalUrl = approvalUrl.replaceFirst("http://", "https://");
    }

    // Open PayPal approval page in external browser
    await openPayPalApprovalUrl(approvalUrl);
  }

  static Future<void> openPayPalApprovalUrl(String approvalUrl) async {
    final uri = Uri.parse(approvalUrl);
    debugPrint("🌍 Opening PayPal URL: $approvalUrl");

    // First ensure the URL can be launched
    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      throw Exception("No application available to open PayPal URL");
    }

    // Try opening in external browser first
    bool opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    // Fallback to platform default if external fails
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }

    if (!opened) {
      throw Exception(
        "Unable to open PayPal. Please install or enable a browser.",
      );
    }
  }

  // -----------------------------
  // PAYPAL CAPTURE (BACKEND VERIFY)
  // -----------------------------
  static Future<void> capturePaypalOrder({
    required String orderId,
    required String plan,
    required String userId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not authenticated");
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }
    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/paypal/capture"),
      headers: {
        "Content-Type": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({"order_id": orderId, "plan": plan, "user_id": userId}),
    );

    if (response.statusCode != 200) {
      throw Exception("PayPal capture failed");
    }

    final data = jsonDecode(response.body);

    // ✅ Sync premium from backend / Firestore
    await syncFromBackend(userId);
    // 🔥 Force instant UI update after PayPal payment
    await refresh();

    // 🔔 Notify UI immediately after PayPal payment
    premiumNotifier.value = isPremium;
    premiumNotifier.notifyListeners();
  }

  // -----------------------------
  // PAYPAL RETURN HANDLER (DEEPLINK)
  // -----------------------------
  static Future<void> capturePaypalOrderFromReturn(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    final String? idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }

    // Plan can be inferred later or passed via query if needed
    // For now backend already knows plan from order mapping
    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/paypal/capture"),
      headers: {
        "Content-Type": "application/json",
        "authorization": "Bearer $idToken",
      },
      body: jsonEncode({
        "order_id": orderId,
        "user_id": user.uid,
        "plan": "INTL", // backend validates actual plan
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("PayPal capture from return failed");
    }

    // 🔥 Sync premium state after successful capture
    await syncFromBackend(user.uid);
    // 🔥 Force instant UI update after PayPal return
    await refresh();

    // 🔔 Notify UI immediately after PayPal return
    premiumNotifier.value = isPremium;
    premiumNotifier.notifyListeners();
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
