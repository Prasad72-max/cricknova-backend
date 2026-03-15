import 'package:hive/hive.dart';

class WeeklyStats {
  final String weekKey;
  final DateTime weekStart;
  final DateTime weekEnd;
  final int aiChats;
  final int analyseAi;
  final int mistakeDetection;
  final int appOpens;
  final int appMinutes;

  const WeeklyStats({
    required this.weekKey,
    required this.weekStart,
    required this.weekEnd,
    required this.aiChats,
    required this.analyseAi,
    required this.mistakeDetection,
    required this.appOpens,
    required this.appMinutes,
  });

  factory WeeklyStats.empty(String weekKey) {
    final start = WeeklyStatsService.weekStartFromKey(weekKey);
    final end = start.add(const Duration(days: 6));
    return WeeklyStats(
      weekKey: weekKey,
      weekStart: start,
      weekEnd: end,
      aiChats: 0,
      analyseAi: 0,
      mistakeDetection: 0,
      appOpens: 0,
      appMinutes: 0,
    );
  }

  factory WeeklyStats.fromMap(String weekKey, Map<String, dynamic> data) {
    final start = WeeklyStatsService.weekStartFromKey(weekKey);
    final end = start.add(const Duration(days: 6));
    return WeeklyStats(
      weekKey: weekKey,
      weekStart: start,
      weekEnd: end,
      aiChats: (data[WeeklyStatsService.fieldAiChat] as num?)?.toInt() ?? 0,
      analyseAi:
          (data[WeeklyStatsService.fieldAnalyseAi] as num?)?.toInt() ?? 0,
      mistakeDetection:
          (data[WeeklyStatsService.fieldMistakeDetection] as num?)?.toInt() ??
          0,
      appOpens: (data[WeeklyStatsService.fieldAppOpens] as num?)?.toInt() ?? 0,
      appMinutes:
          (data[WeeklyStatsService.fieldAppMinutes] as num?)?.toInt() ?? 0,
    );
  }
}

class WeeklyStatsService {
  static const String _weeklyStatsKey = "weekly_stats";
  static const String fieldDaily = "daily";
  static const String fieldAiChat = "ai_chat";
  static const String fieldAnalyseAi = "analyse_ai";
  static const String fieldMistakeDetection = "mistake_detection";
  static const String fieldAppOpens = "app_opens";
  static const String fieldAppMinutes = "app_minutes";
  static const String fieldUpdatedAt = "updated_at";

  static String currentWeekKey([DateTime? now]) {
    final current = now ?? DateTime.now();
    final start = current.subtract(Duration(days: current.weekday - 1));
    final normalized = DateTime(start.year, start.month, start.day);
    return _formatDateKey(normalized);
  }

  static DateTime weekStartFromKey(String key) {
    final parts = key.split("-");
    if (parts.length != 3) {
      final fallback = DateTime.now();
      return DateTime(fallback.year, fallback.month, fallback.day);
    }
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final day = int.tryParse(parts[2]) ?? DateTime.now().day;
    return DateTime(year, month, day);
  }

  static Future<WeeklyStats> loadCurrentWeek(String uid) async {
    final box = await Hive.openBox("local_stats_$uid");
    final weekKey = currentWeekKey();
    final raw = box.get(_weeklyStatsKey);
    if (raw is Map && raw[weekKey] is Map) {
      return WeeklyStats.fromMap(
        weekKey,
        Map<String, dynamic>.from(raw[weekKey] as Map),
      );
    }
    return WeeklyStats.empty(weekKey);
  }

  static Future<void> recordAiChat(String uid) async {
    await _increment(uid, fieldAiChat, 1);
  }

  static Future<void> recordAnalyseAi(String uid) async {
    await _increment(uid, fieldAnalyseAi, 1);
  }

  static Future<void> recordMistakeDetection(String uid) async {
    await _increment(uid, fieldMistakeDetection, 1);
  }

  static Future<void> recordAppOpen(String uid) async {
    await _increment(uid, fieldAppOpens, 1);
  }

  static Future<void> addAppMinutes(String uid, int minutes) async {
    if (minutes <= 0) return;
    await _increment(uid, fieldAppMinutes, minutes);
  }

  static Future<void> _increment(String uid, String field, int by) async {
    final box = await Hive.openBox("local_stats_$uid");
    final weekKey = currentWeekKey();
    final raw = box.get(_weeklyStatsKey);
    final allWeeks = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final existing = allWeeks[weekKey];
    final weekData = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};

    final current = (weekData[field] as num?)?.toInt() ?? 0;
    weekData[field] = current + by;
    weekData[fieldUpdatedAt] = DateTime.now().toIso8601String();

    final dailyRaw = weekData[fieldDaily];
    final daily = dailyRaw is Map
        ? Map<String, dynamic>.from(dailyRaw)
        : <String, dynamic>{};
    final dayKey = _formatDateKey(DateTime.now());
    final dayExisting = daily[dayKey];
    final dayData = dayExisting is Map
        ? Map<String, dynamic>.from(dayExisting)
        : <String, dynamic>{};
    final dayCurrent = (dayData[field] as num?)?.toInt() ?? 0;
    dayData[field] = dayCurrent + by;
    dayData[fieldUpdatedAt] = DateTime.now().toIso8601String();
    daily[dayKey] = dayData;
    weekData[fieldDaily] = daily;
    allWeeks[weekKey] = weekData;

    await box.put(_weeklyStatsKey, allWeeks);
  }

  static Future<Map<String, Map<String, int>>> loadCurrentWeekDaily(
    String uid,
  ) async {
    final box = await Hive.openBox("local_stats_$uid");
    final weekKey = currentWeekKey();
    final raw = box.get(_weeklyStatsKey);
    if (raw is! Map) return <String, Map<String, int>>{};
    final weekRaw = raw[weekKey];
    if (weekRaw is! Map) return <String, Map<String, int>>{};
    final dailyRaw = weekRaw[fieldDaily];
    if (dailyRaw is! Map) return <String, Map<String, int>>{};

    final out = <String, Map<String, int>>{};
    for (final entry in dailyRaw.entries) {
      final key = entry.key?.toString() ?? "";
      final val = entry.value;
      if (key.isEmpty || val is! Map) continue;
      final m = Map<String, dynamic>.from(val);
      out[key] = {
        fieldAiChat: (m[fieldAiChat] as num?)?.toInt() ?? 0,
        fieldAnalyseAi: (m[fieldAnalyseAi] as num?)?.toInt() ?? 0,
        fieldMistakeDetection: (m[fieldMistakeDetection] as num?)?.toInt() ?? 0,
        fieldAppOpens: (m[fieldAppOpens] as num?)?.toInt() ?? 0,
        fieldAppMinutes: (m[fieldAppMinutes] as num?)?.toInt() ?? 0,
      };
    }
    return out;
  }

  static String _formatDateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }
}
