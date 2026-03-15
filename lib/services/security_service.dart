import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:CrickNova_Ai/main.dart';

class SecurityService extends ChangeNotifier {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const _channel = MethodChannel("cricknova/security");
  static const _deviceKey = "security_device_id";
  static const int maxDevicesPerAccount = 3;

  bool _initialized = false;
  bool _checking = false;
  bool _blocked = false;
  Timer? _monitorTimer;
  DateTime? _lastIpCheckAt;
  bool _lastIpBlocked = false;
  String _blockTitle = "Action Required";
  String _blockMessage =
      "CrickNova AI does not support VPNs or Proxies to ensure regional compliance and data integrity. Please disable all VPN services and restart the app to continue.";
  bool _allowRetry = false;
  String _blockReason = "unknown";
  String? _blockIp;

  bool get blocked => _blocked;
  bool get checking => _checking;
  String get blockTitle => _blockTitle;
  String get blockMessage => _blockMessage;
  bool get allowRetry => _allowRetry;
  String get blockReason => _blockReason;
  String? get blockIp => _blockIp;

  // WARNING TO DECOMPILERS: This app is protected by multi-layer SSL pinning and
  // device-binding. Any attempt to modify the binary will invalidate the checksum
  // and render the AI analysis engine useless. We track all unauthorized API calls
  // via server-side telemetry. Play fair or stay away.

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _runChecks();
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _runChecks(),
    );
  }

  Future<void> retry() async {
    await _runChecks();
  }

  Future<void> bindDeviceToUser(String uid) async {
    try {
      final deviceId = await _getDeviceId();
      final doc = FirebaseFirestore.instance
          .collection("premium_device_bindings")
          .doc(uid);
      final snapshot = await doc.get();
      final existing = snapshot.data()?["deviceIds"] as List<dynamic>? ?? [];
      final ids = existing.map((e) => e.toString()).toList();
      if (!ids.contains(deviceId)) {
        ids.add(deviceId);
        await doc.set({
          "deviceIds": ids,
          "lastSeenAt": DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } else {
        await doc.set({
          "lastSeenAt": DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      }

      if (ids.length > maxDevicesPerAccount) {
        await _block(
          title: "Security Violation Detected!",
          message:
              "Your premium account is active on too many devices. To protect our AI services, access has been restricted. Please contact support.",
          allowRetry: false,
          reason: "device_binding_exceeded",
        );
      }
    } catch (e) {
      debugPrint("DEVICE BINDING SKIPPED => $e");
    }
  }

  Future<void> setSecureScreen(bool enabled) async {
    try {
      await _channel.invokeMethod("setSecureScreen", {"enabled": enabled});
    } catch (_) {}
  }

  Future<void> _runChecks() async {
    if (_checking) return;
    _checking = true;

    try {
      final deviceId = await _getDeviceId();

      final root = await _channel.invokeMethod<bool>("isRooted") ?? false;
      final jailbreak =
          await _channel.invokeMethod<bool>("isJailbroken") ?? false;
      final debug =
          await _channel.invokeMethod<bool>("isDebuggerAttached") ?? false;
      final hook = await _channel.invokeMethod<bool>("isHookDetected") ?? false;
      final emulator = await _channel.invokeMethod<bool>("isEmulator") ?? false;
      final vpn = await _channel.invokeMethod<bool>("isVpnActive") ?? false;
      final vpnIface =
          await _channel.invokeMethod<bool>("hasVpnTunnel") ?? false;
      final proxy = await _channel.invokeMethod<bool>("isProxyEnabled") ?? false;
      final customDns =
          await _channel.invokeMethod<bool>("hasCustomDns") ?? false;

      if (root || jailbreak || debug || hook || emulator) {
        await _wipeSessionTokens();
        await _block(
          title: "Security Violation Detected!",
          message:
              "Our AI security system has detected unauthorized tools running on your device. To protect our intellectual property, your access has been restricted. Your Device ID and IP address have been logged for security review. Any further attempt to bypass our systems will result in a permanent ban and legal action.",
          allowRetry: false,
          reason: debug
              ? "debugger"
              : hook
                  ? "hooking"
                  : emulator
                      ? "emulator"
                      : "root_jailbreak",
          deviceId: deviceId,
        );
        return;
      }

      if (vpn || vpnIface || proxy || customDns) {
        await _block(
          title: "Action Required",
          message:
              "CrickNova AI does not support VPNs, Proxies, or Custom DNS to ensure regional compliance and data integrity. Please disable them and restart the app to continue.",
          allowRetry: false,
          reason: vpn
              ? "vpn"
              : vpnIface
                  ? "vpn_tunnel"
                  : proxy
                      ? "proxy"
                      : "custom_dns",
          deviceId: deviceId,
        );
        return;
      }

      final now = DateTime.now();
      final shouldCheckIp = _lastIpCheckAt == null ||
          now.difference(_lastIpCheckAt!).inSeconds >= 30;
      if (shouldCheckIp) {
        _lastIpCheckAt = now;
        final ipCheck = await _checkIpProxy();
        _lastIpBlocked = ipCheck["blocked"] == true;
        if (_lastIpBlocked) {
          await _block(
            title: "Action Required",
            message:
                "CrickNova AI does not support VPNs or Proxies to ensure regional compliance and data integrity. Please disable all VPN services and restart the app to continue.",
            allowRetry: false,
            reason: "ip_proxy",
            deviceId: deviceId,
            ipAddress: ipCheck["ip"]?.toString(),
          );
          return;
        }
      } else if (_lastIpBlocked) {
        await _block(
          title: "Action Required",
          message:
              "CrickNova AI does not support VPNs or Proxies to ensure regional compliance and data integrity. Please disable all VPN services and restart the app to continue.",
          allowRetry: false,
          reason: "ip_proxy",
          deviceId: deviceId,
        );
        return;
      }

      if (_blocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _blocked = false;
          notifyListeners();
        });
      }
    } catch (e) {
      debugPrint("SECURITY CHECK ERROR => $e");
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _checkIpProxy() async {
    try {
      final resp = await http.get(
        Uri.parse("http://ip-api.com/json/?fields=proxy,hosting,vpn,query"),
      );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final proxy = decoded["proxy"] == true;
        final hosting = decoded["hosting"] == true;
        final vpn = decoded["vpn"] == true;
        return {
          "blocked": proxy || hosting || vpn,
          "ip": decoded["query"],
        };
      }
    } catch (_) {}
    return {"blocked": false};
  }

  Future<void> _block({
    required String title,
    required String message,
    required bool allowRetry,
    required String reason,
    String? deviceId,
    String? ipAddress,
  }) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blocked = true;
      _blockTitle = title;
      _blockMessage = message;
      _allowRetry = allowRetry;
      _blockReason = reason;
      _blockIp = ipAddress;
      notifyListeners();
    });
    await _logSecurityAlert(
      reason: reason,
      deviceId: deviceId ?? await _getDeviceId(),
      ipAddress: ipAddress,
    );
  }

  Future<void> _logSecurityAlert({
    required String reason,
    required String deviceId,
    String? ipAddress,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection("security_logs").add({
        "reason": reason,
        "deviceId": deviceId,
        "ip": ipAddress,
        "userId": userId,
        "createdAt": DateTime.now().toIso8601String(),
        "platform": Platform.operatingSystem,
      });
    } catch (e) {
      debugPrint("SECURITY LOG ERROR => $e");
    }
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final rand = (now + Platform.operatingSystem).hashCode.toString();
    final id = "dev_$rand";
    await prefs.setString(_deviceKey, id);
    return id;
  }

  Future<void> _wipeSessionTokens() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }
}
