import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'cricknova_marketing_notification_service.dart';

class CrickNovaNotificationService {
  CrickNovaNotificationService._();

  static final CrickNovaNotificationService instance =
      CrickNovaNotificationService._();

  static const String _channelId = 'cricknova_engagement';
  static const String _channelName = 'CrickNova Engagement';
  static const String _channelDescription =
      'Witty practice nudges and analysis alerts from CrickNova AI.';

  static const int _analysisCompleteId = 1101;
  static const int _personalBestId = 1102;
  static const int _inactivityId = 1103;
  static const int _eveningReminderId = 1104;
  static const int _leaderboardAlertId = 1105;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _initialized = false;

  String _optInKey(String uid) => 'notifications_opt_in_$uid';
  String _promptSeenKey(String uid) => 'notifications_prompt_seen_$uid';
  String _lastOpenKey(String uid) => 'notifications_last_open_$uid';

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    await _configureLocalTimezone();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundRemoteMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedRemoteMessage);
    _messaging.onTokenRefresh.listen(_persistFcmToken);

    _initialized = true;
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final location = tz.getLocation(timezoneInfo.identifier);
      tz.setLocalLocation(location);
    } catch (e) {
      debugPrint('NOTIFICATIONS timezone setup failed: $e');
    }
  }

  Future<bool> shouldPromptForOptIn(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_promptSeenKey(uid)) ?? false);
  }

  Future<bool> isOptedIn(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_optInKey(uid)) ?? false;
  }

  Future<bool> enableForUser(String uid) async {
    await initialize();
    final granted = await requestUserPermission();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptSeenKey(uid), true);
    await prefs.setBool(_optInKey(uid), granted);

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notificationsEnabled': granted,
      'notificationPermissionAskedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!granted) {
      await cancelEngagementNotifications();
      return false;
    }

    await _persistFcmToken(await _messaging.getToken());
    await handleAppOpened(uid);
    await CrickNovaMarketingNotificationService.instance.refreshForUser(uid);
    return true;
  }

  Future<void> disableForUser(String uid, {bool rememberChoice = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberChoice) {
      await prefs.setBool(_promptSeenKey(uid), true);
    }
    await prefs.setBool(_optInKey(uid), false);
    await cancelEngagementNotifications();
    await CrickNovaMarketingNotificationService.instance
        .cancelScheduledMarketingNotifications();
    await CrickNovaMarketingNotificationService.instance.unsubscribeTesterTopic();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notificationsEnabled': false,
      'notificationPermissionAskedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> requestUserPermission() async {
    await initialize();

    final notificationSettings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted =
        await androidPlugin?.requestNotificationsPermission() ?? true;

    final fcmGranted =
        notificationSettings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        notificationSettings.authorizationStatus ==
            AuthorizationStatus.provisional;

    return fcmGranted && androidGranted;
  }

  Future<void> handleAppOpened(String uid) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastOpenKey(uid), DateTime.now().toUtc().toIso8601String());

    if (!await isOptedIn(uid)) {
      await cancelEngagementNotifications();
      return;
    }

    await _scheduleInactivityReminder();
    await _scheduleEveningPracticeReminder();
    await _persistFcmToken(await _messaging.getToken());
    await CrickNovaMarketingNotificationService.instance.refreshForUser(uid);
  }

  Future<void> maybeNotifyAnalysisComplete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await isOptedIn(uid)) return;

    await _showNow(
      id: _analysisCompleteId,
      title: 'CrickNova AI',
      body:
          'Are you a Yorker? Because you just bowled me over! 😍 Great session! Check out your stats.',
    );
  }

  Future<void> maybeNotifyPersonalBest(double speedKmph) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await isOptedIn(uid)) return;

    await _showNow(
      id: _personalBestId,
      title: 'New Personal Best',
      body:
          "New Feature Alert: We added 'Ego Boost'! 🚀 Just kidding, but your new top speed of ${speedKmph.toStringAsFixed(1)} km/h will definitely boost your ego.",
    );
  }

  Future<void> notifyLeaderboardAlert({
    required double nearbyTopSpeedKmph,
    String? areaLabel,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await isOptedIn(uid)) return;

    final suffix = areaLabel == null || areaLabel.trim().isEmpty
        ? ''
        : ' in $areaLabel';
    await _showNow(
      id: _leaderboardAlertId,
      title: 'Leaderboard Alert',
      body:
          "The local leaderboard is looking for a King... 👑 Someone nearby$suffix just clocked ${nearbyTopSpeedKmph.toStringAsFixed(1)} km/h. Don't let them keep the crown!",
    );
  }

  Future<void> cancelEngagementNotifications() async {
    await _localNotifications.cancel(id: _inactivityId);
    await _localNotifications.cancel(id: _eveningReminderId);
  }

  Future<void> _scheduleInactivityReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    final reminderAt = now.add(const Duration(days: 3));
    await _localNotifications.zonedSchedule(
      id: _inactivityId,
      title: 'CrickNova AI',
      body:
          "My grandma runs faster than your last delivery! 👵💨 You haven't bowled in 3 days. Want to prove me wrong?",
      scheduledDate: reminderAt,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'inactivity_reminder',
    );
  }

  Future<void> _scheduleEveningPracticeReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    var reminderAt = tz.TZDateTime(tz.local, now.year, now.month, now.day, 17);
    if (!reminderAt.isAfter(now)) {
      reminderAt = reminderAt.add(const Duration(days: 1));
    }

    await _localNotifications.zonedSchedule(
      id: _eveningReminderId,
      title: 'CrickNova AI',
      body:
          'The stumps are getting lonely... 🪵 They miss the sound of you crashing into them. Come give them company!',
      scheduledDate: reminderAt,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'evening_practice_reminder',
    );
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(),
    );
  }

  NotificationDetails _notificationDetails() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      await _showNow(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: notification.title ?? 'CrickNova AI',
        body: notification.body ?? 'You have a new update waiting.',
      );
      return;
    }

    await _handleRemoteDataMessage(message);
  }

  Future<void> _handleOpenedRemoteMessage(RemoteMessage message) async {
    await _handleRemoteDataMessage(message);
  }

  Future<void> _handleRemoteDataMessage(RemoteMessage message) async {
    final type = message.data['type']?.toString();
    if (type == 'leaderboard_alert') {
      final speed = double.tryParse(message.data['speedKmph']?.toString() ?? '');
      await notifyLeaderboardAlert(
        nearbyTopSpeedKmph: speed ?? 0,
        areaLabel: message.data['areaLabel']?.toString(),
      );
    }
  }

  Future<void> _persistFcmToken(String? token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || token == null || token.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('NOTIFICATIONS token persist failed: $e');
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    debugPrint('NOTIFICATIONS tapped payload=${response.payload}');
  }
}

@pragma('vm:entry-point')
Future<void> crickNovaFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}
