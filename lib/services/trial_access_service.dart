import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrialAccessService {
  TrialAccessService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static final AndroidId _androidId = AndroidId();

  static const String _cacheAvailableKey = 'trial_access_available';
  static const String _cacheDeviceIdKey = 'trial_access_device_id';

  static String? _cachedDeviceId;
  static bool? _cachedTrialAvailable;

  static Future<String?> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString(_cacheDeviceIdKey);
    if (cached != null && cached.isNotEmpty) {
      _cachedDeviceId = cached;
      return cached;
    }

    if (kIsWeb) {
      return null;
    }

    try {
      if (Platform.isAndroid) {
        final String? deviceId = (await _androidId.getId())?.trim();
        if (deviceId != null && deviceId.isNotEmpty) {
          _cachedDeviceId = deviceId;
          await prefs.setString(_cacheDeviceIdKey, deviceId);
          return deviceId;
        }
      } else if (Platform.isIOS) {
        final IosDeviceInfo info = await _deviceInfo.iosInfo;
        final String? deviceId = info.identifierForVendor?.trim();
        if (deviceId != null && deviceId.isNotEmpty) {
          _cachedDeviceId = deviceId;
          await prefs.setString(_cacheDeviceIdKey, deviceId);
          return deviceId;
        }
      }
    } catch (error) {
      debugPrint('❌ Trial device id lookup failed: $error');
    }

    return null;
  }

  static Future<bool> isTrialAvailable({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedTrialAvailable != null) {
      return _cachedTrialAvailable!;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final bool? cached = prefs.getBool(_cacheAvailableKey);
      if (cached != null) {
        _cachedTrialAvailable = cached;
        return cached;
      }
    }

    final String? deviceId = await getDeviceId();
    if (deviceId == null) {
      _cachedTrialAvailable = false;
      await prefs.setBool(_cacheAvailableKey, false);
      return false;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('trial_users')
          .doc(deviceId)
          .get(const GetOptions(source: Source.serverAndCache));

      final Map<String, dynamic>? data = snapshot.data();
      final bool hasUsedTrial =
          data?['hasUsedTrial'] == true || data?['trial_used'] == true;
      final bool available = !hasUsedTrial;

      _cachedTrialAvailable = available;
      await prefs.setBool(_cacheAvailableKey, available);
      return available;
    } catch (error) {
      debugPrint('❌ Trial eligibility check failed: $error');
      return _cachedTrialAvailable ?? false;
    }
  }

  static Future<void> markTrialUsed({String? userId}) async {
    final String? deviceId = await getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      return;
    }

    try {
      await _firestore.collection('trial_users').doc(deviceId).set({
        'device_id': deviceId,
        'hasUsedTrial': true,
        'trial_used': true,
        'platform': kIsWeb
            ? 'web'
            : (Platform.isAndroid
                  ? 'android'
                  : Platform.isIOS
                  ? 'ios'
                  : 'other'),
        'user_id': userId,
        'updated_at': FieldValue.serverTimestamp(),
        'used_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _cachedTrialAvailable = false;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cacheAvailableKey, false);
      await prefs.setString(_cacheDeviceIdKey, deviceId);
    } catch (error) {
      debugPrint('❌ Trial mark used failed: $error');
    }
  }

  static Future<void> clearCache() async {
    _cachedDeviceId = null;
    _cachedTrialAvailable = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheAvailableKey);
    await prefs.remove(_cacheDeviceIdKey);
  }
}
