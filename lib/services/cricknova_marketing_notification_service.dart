import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'cricknova_notification_templates.dart';

class CrickNovaMarketingNotificationService {
  CrickNovaMarketingNotificationService._();

  static final CrickNovaMarketingNotificationService instance =
      CrickNovaMarketingNotificationService._();

  static const String _channelId = 'cricknova_marketing';
  static const String _channelName = 'CrickNova Marketing';
  static const String _channelDescription =
      'Daily cricket nudges, banter, and engagement reminders.';

  static const int _lunchNotificationId = 2101;
  static const int _practiceNotificationId = 2102;

  static const String _refreshTaskName = 'cricknova_marketing_refresh';
  static const String _refreshUniqueName =
      'cricknova_marketing_refresh_unique';
  static const String _activeUidKey = 'marketing_notifications_active_uid';
  static const String _testerTopic = 'cricknova_testers';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _workerRegistered = false;

  String _optInKey(String uid) => 'notifications_opt_in_$uid';

  Future<void> initialize({bool registerWorker = true}) async {
    if (_initialized) {
      if (registerWorker && !_workerRegistered) {
        await _registerWorker();
      }
      return;
    }

    tz.initializeTimeZones();
    await _configureLocalTimezone();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(settings: settings);

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

    _initialized = true;

    if (registerWorker) {
      await _registerWorker();
    }
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (e) {
      debugPrint('MARKETING NOTIFICATIONS timezone setup failed: $e');
    }
  }

  Future<void> _registerWorker() async {
    if (_workerRegistered) return;

    await Workmanager().initialize(
      crickNovaMarketingCallbackDispatcher,
    );
    await Workmanager().registerPeriodicTask(
      _refreshUniqueName,
      _refreshTaskName,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
      ),
    );
    _workerRegistered = true;
  }

  Future<void> refreshForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await refreshForUser(user.uid);
  }

  Future<void> refreshForUser(String uid) async {
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeUidKey, uid);

    final isOptedIn = prefs.getBool(_optInKey(uid)) ?? false;
    if (!isOptedIn) {
      await cancelScheduledMarketingNotifications();
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    final lunchDate = _nextSlot(now, hour: 13);
    final practiceDate = _nextSlot(now, hour: 18);

    final lunchTemplate = _pickTemplate(
      uid: uid,
      date: lunchDate,
      slotLabel: 'lunch',
    );
    final practiceTemplate = _pickTemplate(
      uid: uid,
      date: practiceDate,
      slotLabel: 'practice',
      avoidId: lunchDate.year == practiceDate.year &&
              lunchDate.month == practiceDate.month &&
              lunchDate.day == practiceDate.day
          ? lunchTemplate.id
          : null,
    );

    await _localNotifications.cancel(id: _lunchNotificationId);
    await _localNotifications.cancel(id: _practiceNotificationId);

    await _scheduleTemplate(
      notificationId: _lunchNotificationId,
      scheduledDate: lunchDate,
      template: lunchTemplate,
      payload: 'marketing_lunch_${lunchTemplate.id}',
    );
    await _scheduleTemplate(
      notificationId: _practiceNotificationId,
      scheduledDate: practiceDate,
      template: practiceTemplate,
      payload: 'marketing_practice_${practiceTemplate.id}',
    );

    await FirebaseMessaging.instance.subscribeToTopic(_testerTopic);
  }

  Future<void> cancelScheduledMarketingNotifications() async {
    await _localNotifications.cancel(id: _lunchNotificationId);
    await _localNotifications.cancel(id: _practiceNotificationId);
  }

  Future<void> unsubscribeTesterTopic() async {
    await FirebaseMessaging.instance.unsubscribeFromTopic(_testerTopic);
  }

  Future<void> _scheduleTemplate({
    required int notificationId,
    required tz.TZDateTime scheduledDate,
    required CrickNovaNotificationTemplate template,
    required String payload,
  }) async {
    await _localNotifications.zonedSchedule(
      id: notificationId,
      title: template.title,
      body: template.body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  tz.TZDateTime _nextSlot(
    tz.TZDateTime now, {
    required int hour,
  }) {
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  CrickNovaNotificationTemplate _pickTemplate({
    required String uid,
    required tz.TZDateTime date,
    required String slotLabel,
    int? avoidId,
  }) {
    final seedSource =
        '$uid|${date.year}-${date.month}-${date.day}|$slotLabel';
    final seed = seedSource.codeUnits.fold<int>(
      0,
      (accumulator, element) => (accumulator * 31 + element) & 0x7fffffff,
    );
    final random = math.Random(seed);
    var template = crickNovaNotifications[
        random.nextInt(crickNovaNotifications.length)];

    if (avoidId != null && crickNovaNotifications.length > 1) {
      while (template.id == avoidId) {
        template = crickNovaNotifications[
            random.nextInt(crickNovaNotifications.length)];
      }
    }
    return template;
  }

  Future<void> refreshFromBackground() async {
    await initialize(registerWorker: false);

    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_activeUidKey);
    if (uid == null || uid.isEmpty) return;

    await refreshForUser(uid);
  }
}

@pragma('vm:entry-point')
void crickNovaMarketingCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    switch (task) {
      case CrickNovaMarketingNotificationService._refreshTaskName:
        await CrickNovaMarketingNotificationService.instance
            .refreshFromBackground();
        break;
    }
    return Future.value(true);
  });
}
