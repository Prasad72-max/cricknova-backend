import 'dart:convert';

import 'package:hive/hive.dart';

import 'cricknova_notification_service.dart';

class ImprovementPlanEntry {
  final String discipline;
  final String mistake;
  final List<String> drills;
  final int minDays;
  final int maxDays;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? fixedAt;
  final int attempts;
  final bool completed;

  const ImprovementPlanEntry({
    required this.discipline,
    required this.mistake,
    required this.drills,
    required this.minDays,
    required this.maxDays,
    required this.createdAt,
    required this.updatedAt,
    required this.fixedAt,
    required this.attempts,
    required this.completed,
  });

  factory ImprovementPlanEntry.fromMap(Map data) {
    DateTime parseDate(dynamic value) {
      return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    }

    final rawDrills = data['drills'];
    final drills = rawDrills is List
        ? rawDrills
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return ImprovementPlanEntry(
      discipline: data['discipline']?.toString() ?? 'batting',
      mistake: data['mistake']?.toString() ?? '',
      drills: drills,
      minDays: (data['minDays'] as num?)?.toInt() ?? 35,
      maxDays:
          (data['maxDays'] as num?)?.toInt() ??
          (data['minDays'] as num?)?.toInt() ??
          35,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      fixedAt: data['fixedAt'] == null ? null : parseDate(data['fixedAt']),
      attempts: (data['attempts'] as num?)?.toInt() ?? 1,
      completed: data['completed'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'discipline': discipline,
      'mistake': mistake,
      'drills': drills,
      'minDays': minDays,
      'maxDays': maxDays,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'fixedAt': fixedAt?.toIso8601String(),
      'attempts': attempts,
      'completed': completed,
    };
  }

  ImprovementPlanEntry copyWith({
    List<String>? drills,
    int? minDays,
    int? maxDays,
    DateTime? updatedAt,
    DateTime? fixedAt,
    int? attempts,
    bool? completed,
  }) {
    return ImprovementPlanEntry(
      discipline: discipline,
      mistake: mistake,
      drills: drills ?? this.drills,
      minDays: minDays ?? this.minDays,
      maxDays: maxDays ?? this.maxDays,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fixedAt: fixedAt ?? this.fixedAt,
      attempts: attempts ?? this.attempts,
      completed: completed ?? this.completed,
    );
  }
}

class ImprovementPlanService {
  static String boxName(String uid) => 'improvement_plan_$uid';

  static Future<Box> openBoxForUser(String uid) {
    return Hive.openBox(boxName(uid));
  }

  static Future<List<ImprovementPlanEntry>> entriesForUser(String uid) async {
    final box = await openBoxForUser(uid);
    final entries = <ImprovementPlanEntry>[];
    for (final discipline in ['batting', 'bowling']) {
      final active = box.get(discipline);
      if (active is Map) {
        entries.add(ImprovementPlanEntry.fromMap(active));
      }
      final history = box.get('${discipline}_fixed');
      if (history is List) {
        entries.addAll(
          history
              .whereType<Map>()
              .map(ImprovementPlanEntry.fromMap)
              .where((entry) => entry.mistake.trim().isNotEmpty),
        );
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.where((entry) => entry.mistake.trim().isNotEmpty).toList();
  }

  static Future<void> evaluateCoachReply({
    required String uid,
    required String discipline,
    required String reply,
  }) async {
    final normalizedDiscipline = discipline.toLowerCase().contains('bowl')
        ? 'bowling'
        : 'batting';
    final now = DateTime.now();
    final box = await openBoxForUser(uid);
    final existingRaw = box.get(normalizedDiscipline);
    final existing = existingRaw is Map
        ? ImprovementPlanEntry.fromMap(existingRaw)
        : null;

    final extracted = _extractPlan(reply, normalizedDiscipline);
    if (extracted == null) {
      return;
    }

    if (existing != null && !existing.completed) {
      final sameMistake = _looksLikeSameMistake(
        existing.mistake,
        extracted.mistake,
      );
      final nextAttempts = existing.attempts + 1;
      if (sameMistake || nextAttempts < 4) {
        await box.put(
          normalizedDiscipline,
          existing
              .copyWith(
                drills: sameMistake ? extracted.drills : existing.drills,
                minDays: sameMistake ? extracted.minDays : existing.minDays,
                maxDays: sameMistake ? extracted.maxDays : existing.maxDays,
                updatedAt: now,
                attempts: nextAttempts,
                completed: false,
              )
              .toMap(),
        );
        await _scheduleOverdueReminder(
          uid: uid,
          discipline: normalizedDiscipline,
          mistake: extracted.mistake,
          createdAt: existing.createdAt,
          maxDays: extracted.maxDays,
        );
        return;
      }

      await _saveFixedEntry(
        box: box,
        discipline: normalizedDiscipline,
        entry: existing.copyWith(updatedAt: now, fixedAt: now, completed: true),
      );
    }

    final newEntry = ImprovementPlanEntry(
      discipline: normalizedDiscipline,
      mistake: extracted.mistake,
      drills: extracted.drills,
      minDays: extracted.minDays,
      maxDays: extracted.maxDays,
      createdAt: now,
      updatedAt: now,
      fixedAt: null,
      attempts: 1,
      completed: false,
    );
    await box.put(normalizedDiscipline, newEntry.toMap());
    await _scheduleOverdueReminder(
      uid: uid,
      discipline: normalizedDiscipline,
      mistake: extracted.mistake,
      createdAt: now,
      maxDays: extracted.maxDays,
    );
  }

  static Future<void> _scheduleOverdueReminder({
    required String uid,
    required String discipline,
    required String mistake,
    required DateTime createdAt,
    required int maxDays,
  }) async {
    await CrickNovaNotificationService.instance
        .scheduleImprovementOverdueReminder(
          uid: uid,
          discipline: discipline,
          mistake: mistake,
          dueAt: createdAt.add(Duration(days: maxDays)),
        );
  }

  static Future<void> _saveFixedEntry({
    required Box box,
    required String discipline,
    required ImprovementPlanEntry entry,
  }) async {
    final key = '${discipline}_fixed';
    final raw = box.get(key);
    final history = raw is List ? raw.cast<dynamic>() : <dynamic>[];
    final next = [
      entry.toMap(),
      ...history.whereType<Map>().where((item) {
        final mistake = item['mistake']?.toString() ?? '';
        return !_looksLikeSameMistake(mistake, entry.mistake);
      }),
    ].take(3).toList(growable: false);
    await box.put(key, next);
  }

  static _ExtractedPlan? _extractPlan(String raw, String discipline) {
    final cleaned = raw.replaceAll('\r', '').trim();
    if (cleaned.isEmpty) return null;

    final jsonPlan = _extractJsonPlan(cleaned);
    if (jsonPlan != null) return jsonPlan;

    final mistake =
        _lineAfterLabel(cleaned, [
          'Mistake',
          'Main mistake',
          'Critical mistake',
          'Biggest mistake',
          'Core issue',
          'Issue',
        ]) ??
        _firstUsefulLine(cleaned) ??
        '${discipline == 'bowling' ? 'Bowling' : 'Batting'} mistake';

    final drills = _extractDrills(cleaned, discipline);
    final minDays = (_extractMinDays(cleaned) ?? 14).clamp(7, 35);
    final extractedMaxDays = _extractMaxDays(cleaned);
    final maxDays = (extractedMaxDays ?? (minDays + 7)).clamp(minDays, 35);

    return _ExtractedPlan(
      mistake: _compact(mistake, 150),
      drills: drills,
      minDays: minDays,
      maxDays: maxDays,
    );
  }

  static _ExtractedPlan? _extractJsonPlan(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! Map) return null;
      final rawMistakes = decoded['mistakes'];
      String? mistake;
      if (rawMistakes is List && rawMistakes.isNotEmpty) {
        mistake = rawMistakes.first?.toString().trim();
      } else {
        mistake = rawMistakes?.toString().trim();
      }
      if (mistake == null || mistake.isEmpty) return null;
      final drill = decoded['drill']?.toString().trim();
      final drills = drill == null || drill.isEmpty
          ? const <String>[]
          : <String>[_compact(drill, 120)];
      return _ExtractedPlan(
        mistake: _compact(mistake, 150),
        drills: drills,
        minDays: 21,
        maxDays: 35,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _lineAfterLabel(String text, List<String> labels) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    for (final line in lines) {
      for (final label in labels) {
        final pattern = RegExp(
          '^${RegExp.escape(label)}\\s*[:\\-]\\s*(.+)\$',
          caseSensitive: false,
        );
        final match = pattern.firstMatch(line);
        final value = match?.group(1)?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String? _firstUsefulLine(String text) {
    final ignored = RegExp(
      r'^(severity|drill|minimum|min days|how to fix)\b',
      caseSensitive: false,
    );
    for (final line in text.split('\n')) {
      final cleaned = line
          .replaceFirst(RegExp(r'^\s*[-•]\s*'), '')
          .replaceFirst(RegExp(r'^\s*\d+[\).\]]\s*'), '')
          .trim();
      if (cleaned.length > 16 && !ignored.hasMatch(cleaned)) return cleaned;
    }
    return null;
  }

  static List<String> _extractDrills(String text, String discipline) {
    final drills = <String>[];
    final lines = text.split('\n');
    for (final line in lines) {
      final match = RegExp(
        r'^\s*(?:[-•]\s*)?(?:drill\s*[12]?|exercise\s*[12]?)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line.trim());
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) drills.add(_compact(value, 120));
    }

    if (drills.length >= 2) return drills.take(2).toList(growable: false);
    final defaults = discipline == 'bowling'
        ? [
            'Target-stump drill: 24 balls with the same run-up rhythm.',
            'Release marker drill: 3 sets of 8 balls focusing only on a repeatable release point.',
          ]
        : [
            'Shadow-bat 30 reps with head still and front shoulder closed.',
            'Drop-ball drill: 40 controlled contacts under the eyes.',
          ];
    return [...drills, ...defaults].take(2).toList(growable: false);
  }

  static int? _extractMinDays(String text) {
    final match = RegExp(
      r'(?:minimum|min\.?|min days|days to fix|fix)\D{0,16}(\d{1,2})\s*days?',
      caseSensitive: false,
    ).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  static int? _extractMaxDays(String text) {
    final match = RegExp(
      r'(?:maximum|max\.?|max days|deadline|latest)\D{0,18}(\d{1,2})\s*days?',
      caseSensitive: false,
    ).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  static bool _looksLikeSameMistake(String a, String b) {
    final aTokens = _tokens(a);
    final bTokens = _tokens(b);
    if (aTokens.isEmpty || bTokens.isEmpty) return false;
    final overlap = aTokens.intersection(bTokens).length;
    final smaller = aTokens.length < bTokens.length
        ? aTokens.length
        : bTokens.length;
    return overlap / smaller >= 0.45;
  }

  static Set<String> _tokens(String value) {
    const stopWords = {
      'the',
      'and',
      'your',
      'you',
      'with',
      'for',
      'from',
      'this',
      'that',
      'mistake',
      'critical',
      'normal',
      'minor',
      'main',
      'issue',
      'needs',
      'work',
    };
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 2 && !stopWords.contains(token))
        .toSet();
  }

  static String _compact(String value, int maxChars) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= maxChars) return oneLine;
    return '${oneLine.substring(0, maxChars).trimRight()}...';
  }
}

class _ExtractedPlan {
  final String mistake;
  final List<String> drills;
  final int minDays;
  final int maxDays;

  const _ExtractedPlan({
    required this.mistake,
    required this.drills,
    required this.minDays,
    required this.maxDays,
  });
}
