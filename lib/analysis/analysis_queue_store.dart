import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AnalysisQueueStore {
  AnalysisQueueStore._();

  static const String _jobsKey = 'cricknova_analysis_jobs';

  static Future<List<Map<String, dynamic>>> loadJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_jobsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>?> getJob(String jobId) async {
    final jobs = await loadJobs();
    for (final job in jobs) {
      if (job['id'] == jobId) return job;
    }
    return null;
  }

  static Future<void> upsertJob(Map<String, dynamic> job) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = await loadJobs();
    final next = <Map<String, dynamic>>[];
    bool replaced = false;
    for (final existing in jobs) {
      if (existing['id'] == job['id']) {
        next.add(job);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      next.insert(0, job);
    }
    await prefs.setString(_jobsKey, jsonEncode(next));
  }

  static Future<void> removeJob(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = await loadJobs();
    jobs.removeWhere((job) => job['id'] == jobId);
    await prefs.setString(_jobsKey, jsonEncode(jobs));
  }
}
