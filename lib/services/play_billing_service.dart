import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'premium_service.dart';
import 'subscription_provider.dart';

class PlayBillingService with WidgetsBindingObserver {
  PlayBillingService._();

  static final PlayBillingService instance = PlayBillingService._();

  static const String proProductId = SubscriptionProvider.premiumProductId;
  static const Set<String> _productIds = <String>{proProductId};

  final ValueNotifier<bool> isProNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> purchasePendingNotifier = ValueNotifier<bool>(
    false,
  );

  bool _initialized = false;
  String? _lastError;
  String _activePlanId = "IN_99";

  bool get isProUser => PremiumService.isPremiumActive;
  bool get isFreeUser => !isProUser;
  bool get isStoreAvailable => SubscriptionProvider.instance.isStoreAvailable;
  String? get lastError => _lastError ?? SubscriptionProvider.instance.lastError;

  GooglePlayProductDetails? get proProductDetails {
    for (final plan in SubscriptionProvider.instance.plans) {
      if (plan.productId == proProductId) {
        return plan.productDetails;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      await syncEntitlementToPremiumService();
      return;
    }

    WidgetsBinding.instance.addObserver(this);

    // Initialize the primary subscription provider and sync verified status
    await SubscriptionProvider.instance.initialize();
    await syncEntitlementToPremiumService();

    _initialized = true;
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
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
        // Fall back to current in-memory status
      }
    }

    isProNotifier.value = PremiumService.isPremiumActive;
  }

  Future<bool> launchProPurchaseSheet({String planId = "IN_99"}) async {
    await initialize();
    _activePlanId = planId;

    if (isProUser) {
      await syncEntitlementToPremiumService();
      return true;
    }

    if (!isStoreAvailable) {
      _lastError =
          "Google Play billing is not available on this device right now.";
      return false;
    }

    final String basePlanId = _basePlanIdForPremiumPlanId(planId);
    await SubscriptionProvider.instance.fetchProducts();
    final GooglePlaySubscriptionPlan? plan = SubscriptionProvider.instance
        .planForBasePlanId(basePlanId);

    if (plan == null) {
      _lastError =
          "Google Play product '$proProductId' or base plan '$basePlanId' was not found in catalog.";
      return false;
    }

    purchasePendingNotifier.value = true;
    _lastError = null;

    final bool launched = await SubscriptionProvider.instance.purchasePlan(
      plan,
      allowFreeTrial: false,
      requireFreeTrial: false,
    );

    if (!launched) {
      purchasePendingNotifier.value = false;
      _lastError = SubscriptionProvider.instance.lastError ??
          "Google Play could not open the purchase sheet.";
    }

    return launched;
  }

  Future<void> restorePurchases() async {
    await initialize();
    await SubscriptionProvider.instance.restorePurchases();
    await syncEntitlementToPremiumService();
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
}
