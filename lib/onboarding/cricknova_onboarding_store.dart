import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CricknovaOnboardingStore {
  CricknovaOnboardingStore._();

  static const int _currentVersion = 2;
  static const String _completedPrefix = 'cricknova_onboarding_completed_';
  static const String _answersPrefix = 'cricknova_onboarding_answers_';
  static const String _versionPrefix = 'cricknova_onboarding_version_';
  static const String _pendingCompletedKey =
      'cricknova_onboarding_pending_done';
  static const String _pendingAnswersKey =
      'cricknova_onboarding_pending_answers';
  static const String _pendingVersionKey =
      'cricknova_onboarding_pending_version';

  static Future<bool> isCompleted(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('$_completedPrefix$uid') ?? false;
    final version = prefs.getInt('$_versionPrefix$uid') ?? 0;
    if (!completed) return false;
    return version >= _currentVersion;
  }

  static Future<Map<String, dynamic>> loadAnswers(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_answersPrefix$uid');
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> saveProgress(
    String uid,
    Map<String, dynamic> answers, {
    bool completed = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_answersPrefix$uid', jsonEncode(answers));
    await prefs.setInt('$_versionPrefix$uid', _currentVersion);
    if (completed) {
      await prefs.setBool('$_completedPrefix$uid', true);
    }
  }

  static Future<void> markCompleted(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_versionPrefix$uid', _currentVersion);
    await prefs.setBool('$_completedPrefix$uid', true);
  }

  static Future<void> savePendingProgress(
    Map<String, dynamic> answers, {
    bool completed = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingAnswersKey, jsonEncode(answers));
    await prefs.setInt(_pendingVersionKey, _currentVersion);
    if (completed) {
      await prefs.setBool(_pendingCompletedKey, true);
    }
  }

  static Future<Map<String, dynamic>> loadPendingAnswers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingAnswersKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<bool> isPendingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_pendingCompletedKey) ?? false;
    final version = prefs.getInt(_pendingVersionKey) ?? 0;
    if (!completed) return false;
    return version >= _currentVersion;
  }

  static Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingAnswersKey);
    await prefs.remove(_pendingCompletedKey);
    await prefs.remove(_pendingVersionKey);
  }

  static Future<void> promotePendingToUser(String uid) async {
    final answers = await loadPendingAnswers();
    final done = await isPendingCompleted();
    if (answers.isEmpty && !done) {
      return;
    }
    await saveProgress(uid, answers, completed: done);
    await clearPending();
  }
}
