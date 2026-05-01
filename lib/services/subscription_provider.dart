import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pricing_location_service.dart';
import 'premium_service.dart';

class SubscriptionProvider extends ChangeNotifier with WidgetsBindingObserver {
  SubscriptionProvider({
    InAppPurchase? inAppPurchase,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    WidgetsBinding.instance.addObserver(this);
  }

  static const String premiumProductId = 'cricknova_premium';
  static const String monthlyPlanId = 'monthly-plan';
  static const String sixMonthPlanId = 'six-month-plan';
  static const String oneYearPlanId = 'one-year-plan';
  static const String oneYearElitePlanId = 'one-year-elite';
  static const Set<String> _productIds = <String>{premiumProductId};

  static const String _lastSelectedBasePlanKey =
      'google_play_last_selected_base_plan';

  final InAppPurchase _inAppPurchase;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  List<GooglePlaySubscriptionPlan> _plans = <GooglePlaySubscriptionPlan>[];
  bool _isStoreAvailable = false;
  bool _isLoading = false;
  bool _isPurchasePending = false;
  bool _isPremium = false;
  String _billingState = 'FREE';
  int _aiLimit = 0;
  int _aiUsed = 0;
  DateTime? _expiryDate;
  DateTime? _graceUntil;
  DateTime? _holdUntil;
  DateTime? _trialRevokeAt;
  String? _activeBasePlanId;
  String? _pendingSelectedBasePlanId;
  String? _lastError;
  bool _initialized = false;

  List<GooglePlaySubscriptionPlan> get plans =>
      List<GooglePlaySubscriptionPlan>.unmodifiable(_plans);
  bool get isStoreAvailable => _isStoreAvailable;
  bool get isLoading => _isLoading;
  bool get isPurchasePending => _isPurchasePending;
  bool get isPremium => _isPremium;
  String get billingState => _billingState;
  bool get isInGracePeriod => _billingState == 'IN_GRACE_PERIOD';
  bool get isAccountOnHold =>
      _billingState == 'ACCOUNT_HOLD' || _billingState == 'PAST_DUE';
  int get aiLimit => _aiLimit;
  int get aiUsed => _aiUsed;
  DateTime? get expiryDate => _expiryDate;
  DateTime? get graceUntil => _graceUntil;
  DateTime? get holdUntil => _holdUntil;
  DateTime? get trialRevokeAt => _trialRevokeAt;
  String? get activeBasePlanId => _activeBasePlanId;
  String? get lastError => _lastError;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_isPurchasePending || _pendingSelectedBasePlanId == null) return;

    _isPurchasePending = false;
    _pendingSelectedBasePlanId = null;
    notifyListeners();
  }

  void _ensurePurchaseSubscription() {
    _purchaseSubscription ??= _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('purchaseStream error: $error');
        debugPrintStack(stackTrace: stackTrace);
        _isPurchasePending = false;
        _setError(
          'Google Play purchase updates are unavailable right now. Please try again.',
        );
      },
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _setLoading(true);
    try {
      _ensurePurchaseSubscription();

      await syncPremiumFromFirestore();
      await fetchProducts();
      await restorePurchases();
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('SubscriptionProvider.initialize failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setError(
        'Unable to initialize Google Play subscriptions. Please check billing and network connectivity.',
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> syncPremiumFromFirestore() async {
    final User? user = _auth.currentUser;
    if (user == null) {
      _resetPremiumState();
      return;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> subscriptionSnapshot =
          await _firestore
              .collection('subscriptions')
              .doc(user.uid)
              .get(const GetOptions(source: Source.serverAndCache));
      final DocumentSnapshot<Map<String, dynamic>> userSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!subscriptionSnapshot.exists && !userSnapshot.exists) {
        _resetPremiumState();
        return;
      }

      final Map<String, dynamic> subscriptionData =
          subscriptionSnapshot.data() ?? <String, dynamic>{};
      final Map<String, dynamic> userData = userSnapshot.data() ?? <String, dynamic>{};
      final Map<String, dynamic> data = <String, dynamic>{
        ...userData,
        ...subscriptionData,
      };
      final DateTime? expiry = _parseExpiry(data['expiry']);
      final int aiLimit = _asInt(
        data['ai_limit'] ?? data['chatLimit'] ?? data['chat_limit'],
      );
      final int aiUsed = _asInt(
        data['ai_used'] ?? data['chat_used'] ?? data['aiUsed'],
      );
      final String? planId = data['plan'] as String?;
      final String billingState = _parseBillingState(data);
      final bool onHold =
          billingState == 'ACCOUNT_HOLD' || billingState == 'PAST_DUE';
      final bool inGrace = billingState == 'IN_GRACE_PERIOD';
      final DateTime? graceUntil = _parseDate(
        data['grace_until'] ?? data['graceUntil'],
      );
      final DateTime? holdUntil = _parseDate(
        data['hold_until'] ?? data['holdUntil'],
      );
      final DateTime? trialRevokeAt = _parseDate(
        data['trial_revoke_at'] ?? data['trialRevokeAt'],
      );
      final bool premium =
          !onHold &&
          (inGrace ||
              (expiry != null &&
                  DateTime.now().isBefore(expiry) &&
                  aiUsed < aiLimit) ||
              data['isPremium'] == true ||
              data['premium'] == true);

      _expiryDate = expiry;
      _graceUntil = graceUntil;
      _holdUntil = holdUntil;
      _trialRevokeAt = trialRevokeAt;
      _aiLimit = aiLimit;
      _aiUsed = aiUsed;
      _billingState = billingState;
      _activeBasePlanId = planId;
      _isPremium = premium;
      _clearError(notify: false);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('syncPremiumFromFirestore failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setError(
        'Unable to read subscription status from Firestore. Please try again.',
      );
    }
  }

  Future<void> fetchProducts() async {
    _ensurePurchaseSubscription();
    _setLoading(true);
    try {
      _clearError(notify: false);
      _isStoreAvailable = await _inAppPurchase.isAvailable();
      if (!_isStoreAvailable) {
        _plans = <GooglePlaySubscriptionPlan>[];
        _setError(
          'Google Play Store is not available on this device right now.',
        );
        return;
      }

      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(_productIds);

      if (response.error != null) {
        throw Exception(response.error!.message);
      }

      final List<GooglePlaySubscriptionPlan> plans =
          <GooglePlaySubscriptionPlan>[];

      for (final ProductDetails product in response.productDetails) {
        if (product is! GooglePlayProductDetails ||
            product.id != premiumProductId) {
          continue;
        }

        final int? subscriptionIndex = product.subscriptionIndex;
        if (subscriptionIndex == null) {
          continue;
        }

        final offerDetails =
            product.productDetails.subscriptionOfferDetails?[subscriptionIndex];
        if (offerDetails == null) {
          continue;
        }

        plans.add(
          GooglePlaySubscriptionPlan.fromGooglePlayProductDetails(
            product,
            offerDetails.basePlanId,
          ),
        );
      }

      plans.sort(
        (GooglePlaySubscriptionPlan a, GooglePlaySubscriptionPlan b) =>
            a.sortOrder.compareTo(b.sortOrder),
      );

      _plans = plans;

      if (response.notFoundIDs.contains(premiumProductId)) {
        _setError(
          'Product $premiumProductId was not found in Google Play Console.',
        );
      } else {
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('fetchProducts failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _plans = <GooglePlaySubscriptionPlan>[];
      _setError(
        'Unable to load Google Play subscription plans. Please try again shortly.',
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> purchasePlan(GooglePlaySubscriptionPlan plan) async {
    _ensurePurchaseSubscription();
    _clearError();
    try {
      await fetchProducts();

      if (!_isStoreAvailable) {
        throw Exception('Google Play Store is unavailable.');
      }

      final GooglePlaySubscriptionPlan? latestPlan = planForBasePlanId(
        plan.basePlanId,
      );
      if (latestPlan == null) {
        throw Exception(
          'Base plan ${plan.basePlanId} was not returned by Google Play for product $premiumProductId.',
        );
      }
      if (latestPlan.offerToken == null || latestPlan.offerToken!.isEmpty) {
        throw Exception(
          'Base plan ${latestPlan.basePlanId} has no valid offer token from Google Play.',
        );
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSelectedBasePlanKey, latestPlan.basePlanId);
      _pendingSelectedBasePlanId = latestPlan.basePlanId;

      _isPurchasePending = true;
      notifyListeners();

      debugPrint(
        'Launching Google Play purchase: '
        'productId=${latestPlan.productId}, '
        'basePlanId=${latestPlan.basePlanId}, '
        'price=${latestPlan.priceLabel}, '
        'offerToken=${latestPlan.offerToken}',
      );

      final GooglePlayPurchaseParam purchaseParam = GooglePlayPurchaseParam(
        productDetails: latestPlan.productDetails,
        applicationUserName: _auth.currentUser?.uid,
        offerToken: latestPlan.offerToken,
      );

      final bool launched = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!launched) {
        _isPurchasePending = false;
        _setError('Google Play could not launch the purchase flow.');
      }

      return launched;
    } catch (error, stackTrace) {
      debugPrint('purchasePlan failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _isPurchasePending = false;
      _setError('Unable to start the Google Play purchase right now. $error');
      return false;
    }
  }

  GooglePlaySubscriptionPlan? planForBasePlanId(String basePlanId) {
    for (final GooglePlaySubscriptionPlan plan in _plans) {
      if (plan.basePlanId == basePlanId) {
        return plan;
      }
    }
    return null;
  }

  Future<void> restorePurchases() async {
    _ensurePurchaseSubscription();
    try {
      if (!_isStoreAvailable) {
        return;
      }

      await _inAppPurchase.restorePurchases(
        applicationUserName: _auth.currentUser?.uid,
      );
    } catch (error, stackTrace) {
      debugPrint('restorePurchases failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setError(
        'Unable to restore Google Play purchases right now. Please try again.',
      );
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          _isPurchasePending = true;
          _clearError(notify: false);
          notifyListeners();
          break;
        case PurchaseStatus.error:
          _isPurchasePending = false;
          _pendingSelectedBasePlanId = null;
          _setError(
            purchaseDetails.error?.message ??
                'The Google Play purchase failed.',
          );
          break;
        case PurchaseStatus.canceled:
          _isPurchasePending = false;
          _pendingSelectedBasePlanId = null;
          _setError('Purchase cancelled.');
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _processPurchasedState(purchaseDetails);
          break;
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _completePurchaseSafely(purchaseDetails);
      }
    }
  }

  Future<void> _processPurchasedState(PurchaseDetails purchaseDetails) async {
    _isPurchasePending = false;
    try {
      final PurchaseVerificationResult verification = await verifyPurchase(
        purchaseDetails,
      );

      if (!verification.isValid || verification.basePlanId == null) {
        _setError(
          'Purchase verification failed. Premium access was not granted.',
        );
        return;
      }

      final DateTime expiryDate =
          verification.expiryDate ??
          _fallbackExpiryForPlan(verification.basePlanId!);

      final int aiLimit = _aiLimitForPlan(verification.basePlanId!);

      await _savePurchaseToFirestore(
        basePlanId: verification.basePlanId!,
        aiLimit: aiLimit,
        expiryDate: expiryDate,
        purchaseToken: verification.purchaseToken!,
      );

      final String premiumPlanId = _premiumServicePlanIdForBasePlan(
        verification.basePlanId!,
      );
      final ({int chat, int mistake, int compare}) premiumLimits =
          _premiumLimitsForBasePlan(verification.basePlanId!);

      await _savePurchaseToSubscriptions(
        premiumPlanId: premiumPlanId,
        expiryDate: expiryDate,
        purchaseToken: verification.purchaseToken!,
        chatLimit: premiumLimits.chat,
        mistakeLimit: premiumLimits.mistake,
        compareLimit: premiumLimits.compare,
      );

      await PremiumService.applyExternalPremiumState(
        premium: true,
        planId: premiumPlanId,
        chatLimit: premiumLimits.chat,
        mistakeLimit: premiumLimits.mistake,
        compareLimit: premiumLimits.compare,
      );

      _activeBasePlanId = verification.basePlanId;
      _pendingSelectedBasePlanId = null;
      _aiLimit = aiLimit;
      _aiUsed = 0;
      _expiryDate = expiryDate;
      _isPremium = DateTime.now().isBefore(expiryDate);
      _clearError(notify: false);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('_processPurchasedState failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _pendingSelectedBasePlanId = null;
      _setError(
        'We could not finish activating your subscription. Please restore purchases and try again.',
      );
    }
  }

  Future<PurchaseVerificationResult> verifyPurchase(
    PurchaseDetails purchaseDetails,
  ) async {
    try {
      final String purchaseToken =
          purchaseDetails.verificationData.serverVerificationData;
      final Map<String, dynamic> purchaseJson = _decodePurchaseJson(
        purchaseDetails.verificationData.localVerificationData,
      );

      String? basePlanId = _extractBasePlanIdFromPurchase(
        purchaseDetails,
        purchaseJson,
      );
      basePlanId ??= await _loadLastSelectedBasePlanId();
      final DateTime? expiryDate = _extractExpiryDate(purchaseJson);

      // TODO: Replace this placeholder with a secure backend verification call
      // that validates the purchase token with Google Play Developer API and
      // returns authoritative basePlanId + expiryTimeMillis.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      return PurchaseVerificationResult(
        isValid: purchaseToken.isNotEmpty,
        purchaseToken: purchaseToken,
        basePlanId: basePlanId,
        expiryDate: expiryDate,
      );
    } catch (error, stackTrace) {
      debugPrint('verifyPurchase failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const PurchaseVerificationResult(isValid: false);
    }
  }

  Future<void> _savePurchaseToFirestore({
    required String basePlanId,
    required int aiLimit,
    required DateTime expiryDate,
    required String purchaseToken,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be logged in to save subscription data.');
    }

    await _firestore.collection('users').doc(user.uid).set({
      'plan': basePlanId,
      'ai_limit': aiLimit,
      'ai_used': 0,
      'expiry': Timestamp.fromDate(expiryDate),
      'subscription_state': 'ACTIVE',
      'billing_state': 'ACTIVE',
      'source': 'google_play',
      'product_id': premiumProductId,
      'purchase_token': purchaseToken,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _savePurchaseToSubscriptions({
    required String premiumPlanId,
    required DateTime expiryDate,
    required String purchaseToken,
    required int chatLimit,
    required int mistakeLimit,
    required int compareLimit,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'User must be logged in to save Google Play subscription state.',
      );
    }

    final DateTime now = DateTime.now();
    await _firestore.collection('subscriptions').doc(user.uid).set({
      'isPremium': true,
      'premium': true,
      'subscription_state': 'ACTIVE',
      'billing_state': 'ACTIVE',
      'plan': premiumPlanId,
      'chatLimit': chatLimit,
      'mistakeLimit': mistakeLimit,
      'diffLimit': compareLimit,
      'chat_used': 0,
      'mistake_used': 0,
      'compare_used': 0,
      'used': {'chat': 0, 'mistake': 0, 'compare': 0},
      'expiry': Timestamp.fromDate(expiryDate),
      'started_at': Timestamp.fromDate(now),
      'source': 'google_play',
      'purchase_token': purchaseToken,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> _loadLastSelectedBasePlanId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(_lastSelectedBasePlanKey);
    if (saved == null || saved.isEmpty) {
      return null;
    }
    return saved;
  }

  String? _extractBasePlanIdFromPurchase(
    PurchaseDetails purchaseDetails,
    Map<String, dynamic> purchaseJson,
  ) {
    final dynamic directBasePlan = purchaseJson['basePlanId'];
    if (directBasePlan is String && directBasePlan.isNotEmpty) {
      return directBasePlan;
    }

    final dynamic lineItems = purchaseJson['lineItems'];
    if (lineItems is List) {
      for (final dynamic item in lineItems) {
        if (item is Map<String, dynamic>) {
          final dynamic basePlanId = item['basePlanId'];
          if (basePlanId is String && basePlanId.isNotEmpty) {
            return basePlanId;
          }
        } else if (item is Map) {
          final dynamic basePlanId = item['basePlanId'];
          if (basePlanId is String && basePlanId.isNotEmpty) {
            return basePlanId;
          }
        }
      }
    }

    if (_pendingSelectedBasePlanId != null &&
        _pendingSelectedBasePlanId!.isNotEmpty) {
      return _pendingSelectedBasePlanId;
    }

    if (purchaseDetails.productID == premiumProductId) {
      final dynamic obfuscatedAccountId = purchaseJson['obfuscatedAccountId'];
      if (obfuscatedAccountId is String &&
          obfuscatedAccountId == _auth.currentUser?.uid) {
        return _activeBasePlanId;
      }
    }

    return null;
  }

  DateTime? _extractExpiryDate(Map<String, dynamic> purchaseJson) {
    final dynamic expiryMillis = purchaseJson['expiryTimeMillis'];
    if (expiryMillis is String) {
      return DateTime.fromMillisecondsSinceEpoch(
        int.parse(expiryMillis),
        isUtc: true,
      ).toLocal();
    }
    if (expiryMillis is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        expiryMillis,
        isUtc: true,
      ).toLocal();
    }

    final dynamic lineItems = purchaseJson['lineItems'];
    if (lineItems is List) {
      for (final dynamic item in lineItems) {
        if (item is Map) {
          final dynamic lineExpiry = item['expiryTimeMillis'];
          if (lineExpiry is String && lineExpiry.isNotEmpty) {
            return DateTime.fromMillisecondsSinceEpoch(
              int.parse(lineExpiry),
              isUtc: true,
            ).toLocal();
          }
          if (lineExpiry is int) {
            return DateTime.fromMillisecondsSinceEpoch(
              lineExpiry,
              isUtc: true,
            ).toLocal();
          }
        }
      }
    }

    return null;
  }

  DateTime _fallbackExpiryForPlan(String basePlanId) {
    final DateTime now = DateTime.now();
    switch (basePlanId) {
      case monthlyPlanId:
        return DateTime(now.year, now.month + 1, now.day, now.hour, now.minute);
      case sixMonthPlanId:
        return DateTime(now.year, now.month + 6, now.day, now.hour, now.minute);
      case oneYearPlanId:
      case oneYearElitePlanId:
        return DateTime(now.year + 1, now.month, now.day, now.hour, now.minute);
      default:
        return now.add(const Duration(days: 30));
    }
  }

  int _aiLimitForPlan(String basePlanId) {
    switch (basePlanId) {
      case monthlyPlanId:
        return 30;
      case sixMonthPlanId:
        return 100;
      case oneYearPlanId:
        return 180;
      case oneYearElitePlanId:
        return 365;
      default:
        return 0;
    }
  }

  bool _isIndiaStoreCatalog() {
    if (_plans.isEmpty) {
      return PricingLocationService.isIndia;
    }

    for (final GooglePlaySubscriptionPlan plan in _plans) {
      if (plan.currencyCode.toUpperCase() == 'INR' ||
          plan.priceLabel.contains('₹')) {
        return true;
      }
    }

    return false;
  }

  String _premiumServicePlanIdForBasePlan(String basePlanId) {
    final bool isIndiaPlan = _isIndiaStoreCatalog();
    switch (basePlanId) {
      case monthlyPlanId:
        return isIndiaPlan ? 'IN_99' : 'INTL_MONTHLY';
      case sixMonthPlanId:
        return isIndiaPlan ? 'IN_299' : 'INTL_6M';
      case oneYearPlanId:
        return isIndiaPlan ? 'IN_499' : 'INTL_YEARLY';
      case oneYearElitePlanId:
        return isIndiaPlan ? 'IN_1999' : 'INTL_ULTRA';
      default:
        return 'FREE';
    }
  }

  ({int chat, int mistake, int compare}) _premiumLimitsForBasePlan(
    String basePlanId,
  ) {
    final bool isIndiaPlan = _isIndiaStoreCatalog();
    switch (basePlanId) {
      case monthlyPlanId:
        return isIndiaPlan
            ? (chat: 200, mistake: 15, compare: 0)
            : (chat: 200, mistake: 15, compare: 0);
      case sixMonthPlanId:
        return (chat: 1200, mistake: 30, compare: 0);
      case oneYearPlanId:
        return isIndiaPlan
            ? (chat: 3000, mistake: 60, compare: 60)
            : (chat: 3000, mistake: 60, compare: 60);
      case oneYearElitePlanId:
        return isIndiaPlan
            ? (chat: 5000, mistake: 150, compare: 150)
            : (chat: 7000, mistake: 150, compare: 150);
      default:
        return (chat: 0, mistake: 0, compare: 0);
    }
  }

  DateTime? _parseExpiry(dynamic rawExpiry) {
    if (rawExpiry is Timestamp) {
      return rawExpiry.toDate();
    }
    if (rawExpiry is String && rawExpiry.isNotEmpty) {
      return DateTime.tryParse(rawExpiry);
    }
    return null;
  }

  DateTime? _parseDate(dynamic rawValue) {
    if (rawValue is Timestamp) {
      return rawValue.toDate();
    }
    if (rawValue is String && rawValue.isNotEmpty) {
      return DateTime.tryParse(rawValue);
    }
    if (rawValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(rawValue);
    }
    return null;
  }

  String _parseBillingState(Map<String, dynamic> data) {
    final dynamic raw = data['subscription_state'] ??
        data['billing_state'] ??
        data['state'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim().toUpperCase();
    }
    return 'FREE';
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Map<String, dynamic> _decodePurchaseJson(String rawJson) {
    if (rawJson.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (dynamic key, dynamic value) => MapEntry(key.toString(), value),
        );
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _completePurchaseSafely(PurchaseDetails purchaseDetails) async {
    try {
      await _inAppPurchase.completePurchase(purchaseDetails);
    } catch (error, stackTrace) {
      debugPrint('completePurchase failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _resetPremiumState() {
    _isPremium = false;
    _billingState = 'FREE';
    _aiLimit = 0;
    _aiUsed = 0;
    _expiryDate = null;
    _graceUntil = null;
    _holdUntil = null;
    _trialRevokeAt = null;
    _activeBasePlanId = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void _clearError({bool notify = true}) {
    if (_lastError == null) {
      return;
    }
    _lastError = null;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}

class GooglePlaySubscriptionPlan {
  GooglePlaySubscriptionPlan({
    required this.productId,
    required this.basePlanId,
    required this.title,
    required this.description,
    required this.priceLabel,
    required this.billingLabel,
    required this.aiLimit,
    required this.offerToken,
    required this.productDetails,
    required this.sortOrder,
  });

  factory GooglePlaySubscriptionPlan.fromGooglePlayProductDetails(
    GooglePlayProductDetails productDetails,
    String basePlanId,
  ) {
    final String billingLabel = _billingLabelForPlan(basePlanId);
    final int aiLimit = _aiLimitForPlan(basePlanId);

    return GooglePlaySubscriptionPlan(
      productId: productDetails.id,
      basePlanId: basePlanId,
      title: _titleForPlan(basePlanId),
      description: productDetails.description,
      priceLabel: productDetails.price,
      billingLabel: billingLabel,
      aiLimit: aiLimit,
      offerToken: productDetails.offerToken,
      productDetails: productDetails,
      sortOrder: _sortOrderForPlan(basePlanId),
    );
  }

  final String productId;
  final String basePlanId;
  final String title;
  final String description;
  final String priceLabel;
  final String billingLabel;
  final int aiLimit;
  final String? offerToken;
  final GooglePlayProductDetails productDetails;
  final int sortOrder;

  String get currencyCode => productDetails.currencyCode;

  String get displayPrice => '$priceLabel/$billingLabel';

  static String _titleForPlan(String basePlanId) {
    switch (basePlanId) {
      case SubscriptionProvider.monthlyPlanId:
        return 'Monthly Plan';
      case SubscriptionProvider.sixMonthPlanId:
        return '6 Month Plan';
      case SubscriptionProvider.oneYearPlanId:
        return '1 Year Plan';
      case SubscriptionProvider.oneYearElitePlanId:
        return '1 Year Elite Plan';
      default:
        return basePlanId;
    }
  }

  static String _billingLabelForPlan(String basePlanId) {
    switch (basePlanId) {
      case SubscriptionProvider.monthlyPlanId:
        return 'month';
      case SubscriptionProvider.sixMonthPlanId:
        return '6 months';
      case SubscriptionProvider.oneYearPlanId:
      case SubscriptionProvider.oneYearElitePlanId:
        return 'year';
      default:
        return 'subscription';
    }
  }

  static int _aiLimitForPlan(String basePlanId) {
    switch (basePlanId) {
      case SubscriptionProvider.monthlyPlanId:
        return 30;
      case SubscriptionProvider.sixMonthPlanId:
        return 100;
      case SubscriptionProvider.oneYearPlanId:
        return 180;
      case SubscriptionProvider.oneYearElitePlanId:
        return 365;
      default:
        return 0;
    }
  }

  static int _sortOrderForPlan(String basePlanId) {
    switch (basePlanId) {
      case SubscriptionProvider.monthlyPlanId:
        return 0;
      case SubscriptionProvider.sixMonthPlanId:
        return 1;
      case SubscriptionProvider.oneYearPlanId:
        return 2;
      case SubscriptionProvider.oneYearElitePlanId:
        return 3;
      default:
        return 99;
    }
  }
}

class PurchaseVerificationResult {
  const PurchaseVerificationResult({
    required this.isValid,
    this.purchaseToken,
    this.basePlanId,
    this.expiryDate,
  });

  final bool isValid;
  final String? purchaseToken;
  final String? basePlanId;
  final DateTime? expiryDate;
}
