import 'dart:convert';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../security/vpn_guard.dart';

enum PricingRegion { india, global }

class PricingLocationService {
  static const List<String> _endpoints = <String>[
    'https://ipwho.is/',
    'https://ipapi.co/json/',
  ];
  static const _pricingModeKey = 'pricingMode';
  static const _countryCodeKey = 'pricingCountryCode';
  static bool _bootstrapped = false;
  static bool _refreshInFlight = false;
  static Timer? _autoRefreshTimer;

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
    _startAutoRefresh(timeout: timeout);
  }

  static Future<void> primeFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (await VpnGuard.isVpnActive()) {
      _setRegion(PricingRegion.global);
      return;
    }

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
    if (await VpnGuard.isVpnActive()) {
      debugPrint('🌎 VPN detected -> forcing global pricing (USD)');
      return PricingRegion.global;
    }

    final localClient = client ?? http.Client();

    try {
      for (final endpoint in _endpoints) {
        final response = await localClient
            .get(Uri.parse(endpoint))
            .timeout(timeout);

        if (response.statusCode != 200) {
          continue;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final String? countryCode = _extractCountryCode(decoded);
        if (countryCode != null && countryCode.isNotEmpty) {
          debugPrint('🌍 Pricing region via IP => $countryCode');
          return countryCode == 'IN'
              ? PricingRegion.india
              : PricingRegion.global;
        }
      }
    } catch (error) {
      debugPrint('❌ Pricing IP detection failed: $error');
    } finally {
      if (client == null) {
        localClient.close();
      }
    }

    final localeCountry = _deviceLocaleCountryCode();
    if (localeCountry != null && localeCountry.isNotEmpty) {
      debugPrint('📱 Pricing region via locale => $localeCountry');
      return localeCountry == 'IN' ? PricingRegion.india : PricingRegion.global;
    }

    return _cachedOrGlobal();
  }

  static Future<PricingRegion> refreshPricingRegion({
    Duration timeout = const Duration(seconds: 5),
    http.Client? client,
  }) async {
    if (_refreshInFlight) {
      return currentRegion;
    }
    _refreshInFlight = true;
    try {
      final region = await detectPricingRegion(
        timeout: timeout,
        client: client,
      );
      await _persistRegion(region);
      _setRegion(region);
      debugPrint(
        region == PricingRegion.india
            ? '🇮🇳 PRICING MODE SET => INR'
            : '🌎 PRICING MODE SET => USD',
      );
      return region;
    } finally {
      _refreshInFlight = false;
    }
  }

  static void _startAutoRefresh({
    Duration timeout = const Duration(seconds: 5),
  }) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(refreshPricingRegion(timeout: timeout));
    });
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

  static String? _extractCountryCode(Map<String, dynamic> payload) {
    final List<dynamic> candidates = <dynamic>[
      payload['countryCode'],
      payload['country_code'],
      payload['country'],
    ];

    for (final dynamic candidate in candidates) {
      final String? normalized = candidate?.toString().trim().toUpperCase();
      if (normalized == null || normalized.isEmpty) {
        continue;
      }
      if (normalized.length == 2) {
        return normalized;
      }
    }

    return null;
  }
}
