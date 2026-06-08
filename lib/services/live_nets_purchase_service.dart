import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class LiveNetsPackConfig {
  const LiveNetsPackConfig({
    required this.productId,
    required this.minutes,
    required this.amountInr,
    required this.amountUsd,
  });

  final String productId;
  final int minutes;
  final int amountInr;
  final double amountUsd;
}

class LiveNetsPurchaseService {
  LiveNetsPurchaseService._();

  static final LiveNetsPurchaseService instance = LiveNetsPurchaseService._();

  static const List<LiveNetsPackConfig> packs = <LiveNetsPackConfig>[
    LiveNetsPackConfig(
      productId: 'live_3min',
      minutes: 3,
      amountInr: 29,
      amountUsd: 4.99,
    ),
    LiveNetsPackConfig(
      productId: 'live_10min',
      minutes: 10,
      amountInr: 79,
      amountUsd: 8.99,
    ),
    LiveNetsPackConfig(
      productId: 'live_30min',
      minutes: 30,
      amountInr: 149,
      amountUsd: 17.77,
    ),
  ];

  static const Set<String> productIds = <String>{
    'live_3min',
    'live_10min',
    'live_30min',
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final Map<String, ProductDetails> _productsById = <String, ProductDetails>{};
  final StreamController<LiveNetsPackConfig> _purchaseSuccessController =
      StreamController<LiveNetsPackConfig>.broadcast();
  bool _initialized = false;
  bool _available = false;
  bool _purchaseInFlight = false;
  String? _lastError;

  bool get isAvailable => _available;
  bool get isPurchaseInFlight => _purchaseInFlight;
  String? get lastError => _lastError;
  Stream<LiveNetsPackConfig> get purchaseSuccessStream =>
      _purchaseSuccessController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _purchaseSub ??= _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('LiveNets purchaseStream error: $error');
        debugPrintStack(stackTrace: stackTrace);
        _purchaseInFlight = false;
        _lastError = _friendlyPurchaseError(error.toString());
      },
    );
    await refreshCatalog();
    _initialized = true;
  }

  String _friendlyPurchaseError(String rawMessage) {
    final message = rawMessage.toLowerCase();
    if (message.contains('already owned') ||
        message.contains('already own') ||
        message.contains('item already owned') ||
        message.contains('owned by another user')) {
      return 'This Edge pack is already active. If the balance is not updated yet, tap refresh and try again.';
    }
    return rawMessage;
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialized = false;
  }

  Future<void> refreshCatalog() async {
    _available = await _iap.isAvailable();
    _productsById.clear();
    if (!_available) return;

    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      _lastError = response.error!.message;
    }
    for (final product in response.productDetails) {
      _productsById[product.id] = product;
    }
  }

  ProductDetails? productForId(String productId) => _productsById[productId];

  Future<bool> buyPack(String productId) async {
    await initialize();
    if (!_available) {
      _lastError = 'Google Play billing is not available on this device.';
      return false;
    }
    final product = _productsById[productId];
    if (product == null) {
      _lastError = 'Product not found: $productId';
      return false;
    }

    _purchaseInFlight = true;
    _lastError = null;

    final purchaseParam = _purchaseParamFor(product);
    // Use buyConsumable so users can purchase Edge minutes multiple times.
    final launched = await _iap.buyConsumable(purchaseParam: purchaseParam);
    if (!launched) {
      _purchaseInFlight = false;
      _lastError = 'Google Play could not open the purchase sheet.';
    }
    return launched;
  }

  GooglePlayPurchaseParam _purchaseParamFor(ProductDetails product) {
    if (product is GooglePlayProductDetails) {
      return GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: FirebaseAuth.instance.currentUser?.uid,
      );
    }
    return GooglePlayPurchaseParam(
      productDetails: product,
      applicationUserName: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status != PurchaseStatus.purchased &&
          purchaseDetails.status != PurchaseStatus.restored) {
        continue;
      }

      final productIds = purchaseDetails.productID.split(',');
      for (final productId in productIds) {
        final pack = packs.firstWhere(
          (element) => element.productId == productId,
          orElse: () => const LiveNetsPackConfig(
            productId: '',
            minutes: 0,
            amountInr: 0,
            amountUsd: 0,
          ),
        );
        if (pack.productId.isEmpty) continue;
        final granted = await _grantLiveMinutes(pack);
        if (granted) {
          await _consumeIfAndroid(purchaseDetails);
          _purchaseSuccessController.add(pack);
        }
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
      _purchaseInFlight = false;
    }
  }

  Future<void> _consumeIfAndroid(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails is! GooglePlayPurchaseDetails) return;
    try {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await addition.consumePurchase(purchaseDetails);
    } catch (error) {
      debugPrint('LiveNets consume skipped: $error');
    }
  }

  Future<bool> _grantLiveMinutes(LiveNetsPackConfig pack) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _lastError = 'Sign in required to unlock Edge minutes.';
      return false;
    }

    final now = FieldValue.serverTimestamp();
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'live_seconds_remaining': FieldValue.increment(pack.minutes * 60),
        'live_milliseconds_remaining': FieldValue.increment(
          pack.minutes * 60 * 1000,
        ),
        'last_live_pack_minutes': pack.minutes,
        'last_live_pack_amount_inr': pack.amountInr,
        'last_live_pack_amount_usd': pack.amountUsd,
        'last_live_pack_product_id': pack.productId,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      _lastError = error.toString();
      debugPrint('LiveNets minutes grant failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }

    try {
      await FirebaseFirestore.instance.collection('live_nets_orders').add({
        'uid': user.uid,
        'product_id': pack.productId,
        'minutes': pack.minutes,
        'amount_inr': pack.amountInr,
        'amount_usd': pack.amountUsd,
        'purchase_state': 'purchased',
        'createdAt': now,
      });
    } catch (error) {
      debugPrint('LiveNets order log skipped: $error');
    }

    return true;
  }
}
