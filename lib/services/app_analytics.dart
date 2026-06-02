import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';

class AppAnalytics {
  const AppAnalytics._();

  static Future<void> log(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (error) {
      debugPrint('Analytics event failed: $name -> $error');
    }
    unawaited(_writeActivityEvent(name, parameters: parameters));
  }

  static Future<void> logScreenOpen(
    String screenName, {
    Map<String, Object>? parameters,
  }) async {
    final params = <String, Object>{
      'screen': screenName,
      if (parameters != null) ...parameters,
    };
    await log('screen_opened', parameters: params);
  }

  static Future<void> ensureUserTrackingDefaults() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get(
        const GetOptions(source: Source.serverAndCache),
      );
      final data = snap.data() ?? const <String, dynamic>{};
      final patch = <String, dynamic>{
        'uid': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!data.containsKey('onboardingCompleted')) {
        final completed = data['onboarding_completed'] == true;
        patch['onboardingCompleted'] = completed;
        patch['onboarding_completed'] = completed;
        patch['onboardingStatus'] = completed ? 'completed' : 'not_completed';
      }
      if (!data.containsKey('hasUploadedVideo')) {
        final uploaded = data['has_uploaded_video'] == true;
        patch['hasUploadedVideo'] = uploaded;
        patch['has_uploaded_video'] = uploaded;
        patch['videoUploadCount'] = data['videoUploadCount'] ?? 0;
      }
      if (patch.length > 2) {
        await ref.set(patch, SetOptions(merge: true));
      }
    } catch (error) {
      debugPrint('Firestore tracking defaults failed: $error');
    }
  }

  static Future<void> markOnboardingStatus({
    required bool completed,
    Map<String, dynamic>? answers,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final eventRef = userRef.collection('activity_events').doc();
    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();

    batch.set(userRef, {
      'onboardingCompleted': completed,
      'onboarding_completed': completed,
      'onboardingStatus': completed ? 'completed' : 'started',
      if (completed) 'onboardingCompletedAt': now,
      if (!completed) 'onboardingStartedAt': now,
      if (answers != null) 'onboardingAnswers': answers,
      'lastActivityAt': now,
      'lastActivityEvent': completed
          ? 'onboarding_completed'
          : 'onboarding_started',
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(eventRef, {
      'event': completed ? 'onboarding_completed' : 'onboarding_started',
      'uid': user.uid,
      'createdAt': now,
      'screen': 'Onboarding',
      'completed': completed,
    });

    try {
      await batch.commit();
    } catch (error) {
      debugPrint('Firestore onboarding activity failed: $error');
    }
  }

  static Future<void> markVideoUpload({
    required String source,
    required String discipline,
    String? sessionType,
    String? localPath,
  }) async {
    final params = <String, Object>{
      'source': source,
      'discipline': discipline,
      if (sessionType != null && sessionType.isNotEmpty)
        'session_type': sessionType,
    };
    unawaited(log('video_uploaded', parameters: params));

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final eventRef = userRef.collection('activity_events').doc();
    final now = FieldValue.serverTimestamp();
    final batch = FirebaseFirestore.instance.batch();

    batch.set(userRef, {
      'hasUploadedVideo': true,
      'has_uploaded_video': true,
      'videoUploadCount': FieldValue.increment(1),
      'lastVideoUploadAt': now,
      'lastVideoUploadSource': source,
      'lastVideoUploadDiscipline': discipline,
      if (sessionType != null && sessionType.isNotEmpty)
        'lastVideoUploadSessionType': sessionType,
      'lastActivityAt': now,
      'lastActivityEvent': 'video_uploaded',
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(eventRef, {
      'event': 'video_uploaded',
      'uid': user.uid,
      'createdAt': now,
      'source': source,
      'discipline': discipline,
      if (sessionType != null && sessionType.isNotEmpty)
        'sessionType': sessionType,
      if (localPath != null && localPath.isNotEmpty) 'localPath': localPath,
    });

    try {
      await batch.commit();
    } catch (error) {
      debugPrint('Firestore video upload activity failed: $error');
    }
  }

  static Future<void> _writeActivityEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final safeParams = _safeParams(parameters);
    final now = FieldValue.serverTimestamp();
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final eventRef = userRef.collection('activity_events').doc();
    final screen = safeParams['screen']?.toString();

    final userPatch = <String, dynamic>{
      'lastActivityAt': now,
      'lastActivityEvent': name,
      'activityEventCount': FieldValue.increment(1),
      'updatedAt': now,
    };
    if (screen != null && screen.isNotEmpty) {
      userPatch.addAll({
        'currentScreen': screen,
        'lastOpenedScreen': screen,
        'lastScreenOpenedAt': now,
        'screenOpenCount': FieldValue.increment(1),
      });
    }

    final batch = FirebaseFirestore.instance.batch();
    batch.set(userRef, userPatch, SetOptions(merge: true));
    batch.set(eventRef, {
      'event': name,
      'uid': user.uid,
      'createdAt': now,
      if (safeParams.isNotEmpty) 'parameters': safeParams,
      if (screen != null && screen.isNotEmpty) 'screen': screen,
    });

    try {
      await batch.commit();
    } catch (error) {
      debugPrint('Firestore analytics event failed: $name -> $error');
    }
  }

  static Map<String, Object> _safeParams(Map<String, Object>? parameters) {
    if (parameters == null || parameters.isEmpty) return <String, Object>{};
    final safe = <String, Object>{};
    for (final entry in parameters.entries) {
      final value = entry.value;
      if (value is String || value is num || value is bool) {
        safe[entry.key] = value;
      } else {
        safe[entry.key] = value.toString();
      }
    }
    return safe;
  }
}

class FirestoreScreenObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _track(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _track(previousRoute);
  }

  void _track(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    unawaited(
      AppAnalytics.logScreenOpen(name, parameters: {'source': 'navigator'}),
    );
  }
}
