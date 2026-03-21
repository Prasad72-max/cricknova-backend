import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum PricingRegion { india, global }

class PricingLocationService {
  static const _endpoint = 'https://api.country.is/';
  static const _pricingModeKey = 'pricingMode';
  static const _countryCodeKey = 'pricingCountryCode';
  static bool _bootstrapped = false;

  static final ValueNotifier<PricingRegion> regionNotifier = ValueNotifier(
    PricingRegion.global,
  );

  static PricingRegion get currentRegion => regionNotifier.value;
  static bool get isIndia => currentRegion == PricingRegion.india;

  static Future<void> bootstrap({
    Duration timeout = const Duration(seconds: 2),
    http.Client? client,
  }) async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    await refreshPricingRegion(timeout: timeout, client: client);
  }

  static Future<void> primeFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedMode = prefs.getString(_pricingModeKey);
    final cachedCountry = prefs.getString(_countryCodeKey)?.toUpperCase();

    if (cachedMode == 'INR' || cachedCountry == 'IN') {
      _setRegion(PricingRegion.india);
      return;
    }

    if (cachedMode == 'USD') {
      _setRegion(PricingRegion.global);
      return;
    }

    _setRegion(PricingRegion.global);
  }

  /// Returns INR region only for countryCode == IN.
  /// Falls back to global on any error, timeout, or invalid response.
  static Future<PricingRegion> detectPricingRegion({
    Duration timeout = const Duration(seconds: 2),
    http.Client? client,
  }) async {
    final localClient = client ?? http.Client();
    final shouldClose = client == null;

    try {
      final response = await localClient
          .get(Uri.parse(_endpoint))
          .timeout(timeout);

      if (response.statusCode != 200) {
        return PricingRegion.global;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return PricingRegion.global;
      }

      final countryCode =
          (decoded['country'] ?? decoded['country_code'])
              ?.toString()
              .toUpperCase();

      if (countryCode == 'IN') {
        return PricingRegion.india;
      }
      return PricingRegion.global;
    } catch (_) {
      return PricingRegion.global;
    } finally {
      if (shouldClose) {
        localClient.close();
      }
    }
  }

  static Future<PricingRegion> refreshPricingRegion({
    Duration timeout = const Duration(seconds: 2),
    http.Client? client,
  }) async {
    final region = await detectPricingRegion(timeout: timeout, client: client);
    await _persistRegion(region);
    _setRegion(region);
    debugPrint(
      region == PricingRegion.india
          ? '🇮🇳 PRICING MODE SET => INR'
          : '🌎 PRICING MODE SET => USD',
    );
    return region;
  }

  static void _setRegion(PricingRegion region) {
    if (regionNotifier.value == region) return;
    regionNotifier.value = region;
  }

  static Future<void> _persistRegion(PricingRegion region) async {
    final prefs = await SharedPreferences.getInstance();
    if (region == PricingRegion.india) {
      await prefs.setString(_pricingModeKey, 'INR');
      await prefs.setString(_countryCodeKey, 'IN');
      return;
    }

    await prefs.setString(_pricingModeKey, 'USD');
    await prefs.setString(_countryCodeKey, 'GLOBAL');
  }
}
