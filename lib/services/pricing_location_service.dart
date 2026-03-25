import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum PricingRegion { india, global }

class PricingLocationService {
  static const _endpoint = 'http://ip-api.com/json';
  static const _pricingModeKey = 'pricingMode';
  static const _countryCodeKey = 'pricingCountryCode';
  static bool _bootstrapped = false;

  static final ValueNotifier<PricingRegion> regionNotifier = ValueNotifier(
    PricingRegion.global,
  );

  static PricingRegion get currentRegion => regionNotifier.value;
  static bool get isIndia => currentRegion == PricingRegion.india;

  static Future<void> bootstrap({
    Duration timeout = const Duration(seconds: 5),
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

    _setRegion(PricingRegion.global);
  }

  static Future<PricingRegion> detectPricingRegion({
    Duration timeout = const Duration(seconds: 5),
    http.Client? client,
  }) async {
    final localClient = client ?? http.Client();

    try {
      final response = await localClient
          .get(Uri.parse(_endpoint))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final countryCode =
              decoded['countryCode']?.toString().toUpperCase();
          if (countryCode != null && countryCode.isNotEmpty) {
            return countryCode == 'IN'
                ? PricingRegion.india
                : PricingRegion.global;
          }
        }
      }
    } catch (_) {}

    final localeCountry = _deviceLocaleCountryCode();
    if (localeCountry != null && localeCountry.isNotEmpty) {
      return localeCountry == 'IN'
          ? PricingRegion.india
          : PricingRegion.global;
    }

    return _cachedOrGlobal();
  }

  static Future<PricingRegion> refreshPricingRegion({
    Duration timeout = const Duration(seconds: 5),
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

  static Future<PricingRegion> _cachedOrGlobal() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedMode = prefs.getString(_pricingModeKey);
    final cachedCountry = prefs.getString(_countryCodeKey)?.toUpperCase();

    if (cachedMode == 'INR' || cachedCountry == 'IN') {
      return PricingRegion.india;
    }
    return PricingRegion.global;
  }

  static String? _deviceLocaleCountryCode() {
    try {
      final Locale locale = WidgetsBinding.instance.platformDispatcher.locale;
      return locale.countryCode?.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}
