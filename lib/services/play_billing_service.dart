import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_service.dart';
import 'subscription_provider.dart';

class PlayBillingService with WidgetsBindingObserver {
  PlayBillingService._();

  static final PlayBillingService instance = PlayBillingService._();

  static const String proProductId = "cricknova_premium";
  static const Set<String> _productIds = <String>{proProductId};

  static const String _prefsUnlockedKey = "play_billing_pro_unlocked";
  static const String _prefsProductIdKey = "play_billing_product_id";
  static const String _prefsPurchaseIdKey = "play_billing_purchase_id";
  static const String _prefsPurchaseDateKey = "play_billing_purchase_date";
  static const String _prefsPlanIdKey = "play_billing_plan_id";

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final ValueNotifier<bool> isProNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> purchasePendingNotifier = ValueNotifier<bool>(
    false,
  );

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<GooglePlayProductDetails> _products = const <GooglePlayProductDetails>[];
  bool _initialized = false;
  bool _storeAvailable = false;
  String? _lastError;
  String _activePlanId = "IN_99";

  bool get isProUser => isProNotifier.value || PremiumService.isPremiumActive;
  bool get isFreeUser => !isProUser;
  bool get isStoreAvailable => _storeAvailable;
  String? get lastError => _lastError;

  GooglePlayProductDetails? get proProductDetails {
    for (final product in _products) {
      if (product.id == proProductId) return product;
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      await syncEntitlementToPremiumService();
      return;
    }

    WidgetsBinding.instance.addObserver(this);

    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        _lastError = error.toString();
        purchasePendingNotifier.value = false;
      },
    );

    await _restoreEntitlementFromPrefs();
    await _refreshCatalog();

    if (_storeAvailable) {
      unawaited(
        _inAppPurchase.restorePurchases(
          applicationUserName: FirebaseAuth.instance.currentUser?.uid,
        ),
      );
    }

    _initialized = true;
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _initialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    if (!purchasePendingNotifier.value) {
      return;
    }

    purchasePendingNotifier.value = false;
  }

  Future<void> syncEntitlementToPremiumService() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await PremiumService.syncFromFirestore(user.uid);
        isProNotifier.value = PremiumService.isPremiumActive;
        if (PremiumService.isPremiumActive) {
          _activePlanId = PremiumService.plan;
          return;
        }
      } catch (_) {
        // Fall back only if Firestore refresh is unavailable.
      }
    }

    if (!isProNotifier.value) return;
    await PremiumService.updateStatus(true, planId: _activePlanId);
  }

  Future<bool> launchProPurchaseSheet({String planId = "IN_99"}) async {
    await initialize();
    _activePlanId = planId;

    if (isProUser) {
      await syncEntitlementToPremiumService();
      return true;
    }

    if (!_storeAvailable) {
      _lastError =
          "Google Play billing is not available on this device right now.";
      return false;
    }

    final _PlayBillingOffer? offer = _offerForPremiumPlanId(planId);
    if (offer == null) {
      _lastError =
          "Play product '$proProductId' or base plan for '$planId' was not found. Check Play Console base plan IDs.";
      return false;
    }

    purchasePendingNotifier.value = true;
    _lastError = null;

    final GooglePlayPurchaseParam purchaseParam = GooglePlayPurchaseParam(
      productDetails: offer.productDetails,
      applicationUserName: FirebaseAuth.instance.currentUser?.uid,
      offerToken: offer.offerToken,
    );

    final bool launched = await _inAppPurchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );

    if (!launched) {
      purchasePendingNotifier.value = false;
      _lastError = "Google Play could not open the purchase sheet.";
    }

    return launched;
  }

  Future<void> restorePurchases() async {
    await initialize();
    if (!_storeAvailable) return;

    await _inAppPurchase.restorePurchases(
      applicationUserName: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  Future<void> _refreshCatalog() async {
    _storeAvailable = await _inAppPurchase.isAvailable();
    if (!_storeAvailable) {
      _products = const <GooglePlayProductDetails>[];
      return;
    }

    final ProductDetailsResponse response = await _inAppPurchase
        .queryProductDetails(_productIds);
    final List<GooglePlayProductDetails> googleProducts =
        <GooglePlayProductDetails>[];
    for (final ProductDetails product in response.productDetails) {
      if (product is GooglePlayProductDetails && product.id == proProductId) {
        googleProducts.add(product);
      }
    }
    _products = googleProducts;

    if (response.error != null) {
      _lastError = response.error!.message;
    } else if (response.notFoundIDs.contains(proProductId)) {
      _lastError =
          "Google Play product '$proProductId' is missing from the store catalog.";
    }
  }

  _PlayBillingOffer? _offerForPremiumPlanId(String planId) {
    final String basePlanId = _basePlanIdForPremiumPlanId(planId);
    _PlayBillingOffer? fallback;

    for (final GooglePlayProductDetails product in _products) {
      final offers = product.productDetails.subscriptionOfferDetails;
      if (offers == null || offers.isEmpty) continue;

      for (final offer in offers) {
        if (offer.basePlanId != basePlanId) continue;
        fallback ??= _PlayBillingOffer(
          productDetails: product,
          offerToken: offer.offerIdToken,
        );

        final offerId = (offer.offerId ?? '').toLowerCase();
        final hasTrialTag = offer.offerTags.any(
          (tag) => tag.toLowerCase().contains('trial'),
        );
        final hasFreeTrialPhase = offer.pricingPhases.any(
          (phase) => phase.priceAmountMicros == 0,
        );
        if (offerId.contains('trial') || hasTrialTag || hasFreeTrialPhase) {
          return _PlayBillingOffer(
            productDetails: product,
            offerToken: offer.offerIdToken,
          );
        }
      }

      final int? subscriptionIndex = product.subscriptionIndex;
      if (fallback == null &&
          subscriptionIndex != null &&
          subscriptionIndex >= 0 &&
          subscriptionIndex < offers.length &&
          offers[subscriptionIndex].basePlanId == basePlanId) {
        fallback = _PlayBillingOffer(
          productDetails: product,
          offerToken: offers[subscriptionIndex].offerIdToken,
        );
      }
    }

    return fallback;
  }

  String _basePlanIdForPremiumPlanId(String planId) {
    switch (planId) {
      case 'IN_299':
      case 'INTL_6M':
        return SubscriptionProvider.sixMonthPlanId;
      case 'IN_499':
      case 'INTL_YEARLY':
        return SubscriptionProvider.oneYearPlanId;
      case 'IN_1999':
      case 'INTL_ULTRA':
      case 'INT_ULTRA':
      case 'ULTRA':
        return SubscriptionProvider.oneYearElitePlanId;
      case 'IN_99':
      case 'INTL_MONTHLY':
      default:
        return SubscriptionProvider.monthlyPlanId;
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      if (!_productIds.contains(purchase.productID)) {
        if (purchase.pendingCompletePurchase) {
          await _safeCompletePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          purchasePendingNotifier.value = true;
          break;
        case PurchaseStatus.error:
          purchasePendingNotifier.value = false;
          _lastError = _friendlyPurchaseError(purchase.error?.message);
          break;
        case PurchaseStatus.canceled:
          purchasePendingNotifier.value = false;
          _lastError = "Purchase cancelled.";
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final bool verified = await _verifyAndUnlock(purchase);
          purchasePendingNotifier.value = false;
          if (!verified) {
            _lastError = "Purchase could not be verified.";
          }
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _safeCompletePurchase(purchase);
      }
    }
  }

  String _friendlyPurchaseError(String? rawMessage) {
    final String message = (rawMessage ?? '').toLowerCase();
    if (message.contains('already owned') ||
        message.contains('already own') ||
        message.contains('item already owned') ||
        message.contains('owned by another user')) {
      return 'This plan is already active on your Google account. Restore purchases if the app does not reflect it yet.';
    }
    return rawMessage ?? 'Purchase failed.';
  }

  Future<bool> _verifyAndUnlock(PurchaseDetails purchase) async {
    final bool hasVerificationData =
        purchase.verificationData.localVerificationData.isNotEmpty ||
        purchase.verificationData.serverVerificationData.isNotEmpty;
    if (!hasVerificationData) return false;

    await _persistUnlockedPurchase(purchase);
    return true;
  }

  Future<void> _persistUnlockedPurchase(PurchaseDetails purchase) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsUnlockedKey, true);
    await prefs.setString(_prefsProductIdKey, purchase.productID);
    await prefs.setString(_prefsPlanIdKey, _activePlanId);
    if (purchase.purchaseID != null) {
      await prefs.setString(_prefsPurchaseIdKey, purchase.purchaseID!);
    }
    if (purchase.transactionDate != null) {
      await prefs.setString(_prefsPurchaseDateKey, purchase.transactionDate!);
    }

    isProNotifier.value = true;
    _lastError = null;
    await syncEntitlementToPremiumService();
  }

  Future<void> _restoreEntitlementFromPrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool unlocked = prefs.getBool(_prefsUnlockedKey) ?? false;
    final String? productId = prefs.getString(_prefsProductIdKey);
    _activePlanId = prefs.getString(_prefsPlanIdKey) ?? "IN_99";

    if (!unlocked || productId == null || !_productIds.contains(productId)) {
      isProNotifier.value = false;
      return;
    }

    isProNotifier.value = true;
  }

  Future<void> _safeCompletePurchase(PurchaseDetails purchase) async {
    try {
      await _inAppPurchase.completePurchase(purchase);
    } catch (_) {
      // Access is already persisted locally; completion can be retried later.
    }
  }
}

class _PlayBillingOffer {
  const _PlayBillingOffer({
    required this.productDetails,
    required this.offerToken,
  });

  final GooglePlayProductDetails productDetails;
  final String offerToken;
}
