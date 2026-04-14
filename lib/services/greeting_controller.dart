import 'package:shared_preferences/shared_preferences.dart';

enum GreetingTimeSlot { morning, afternoon, evening, midnight }

class GreetingThemeData {
  const GreetingThemeData({
    required this.slot,
    required this.backgroundColors,
    required this.accentColors,
    required this.glowEnabled,
  });

  final GreetingTimeSlot slot;
  final List<int> backgroundColors;
  final List<int> accentColors;
  final bool glowEnabled;
}

class GreetingPayload {
  const GreetingPayload({
    required this.userName,
    required this.message,
    required this.theme,
  });

  final String userName;
  final String message;
  final GreetingThemeData theme;
}

class GreetingController {
  GreetingController._();

  static const String _profileNameKey = 'profileName';

  static Future<void> cacheUserName(String userName) async {
    final trimmed = userName.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, trimmed);
  }

  static Future<String> loadCachedUserName({String fallback = 'Player'}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_profileNameKey)?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    return fallback;
  }

  static String getDynamicGreeting(String userName, {DateTime? now}) {
    final resolvedName = _firstName(userName);
    switch (_slotFor(now ?? DateTime.now())) {
      case GreetingTimeSlot.morning:
        return 'Good Morning, $resolvedName! The sun is up, and so is the competition. Time to hit the nets! \ud83c\udfcf\u2600\ufe0f';
      case GreetingTimeSlot.afternoon:
        return 'Eyes on the prize, $resolvedName. Don’t let the midday heat slow down your hustle! \ud83d\udcaa\ud83d\udd25';
      case GreetingTimeSlot.evening:
        return 'Evening, $resolvedName. Great session today? Let’s dive into your numbers and review the progress. \ud83d\udcca\ud83c\udfcf';
      case GreetingTimeSlot.midnight:
        return 'The World Sleeps, The Champions Grind. Silence the noise, master the craft. \ud83c\udf11\ud83d\udd25';
    }
  }

  static String getShortGreetingLabel({DateTime? now}) {
    switch (_slotFor(now ?? DateTime.now())) {
      case GreetingTimeSlot.morning:
        return 'Good Morning';
      case GreetingTimeSlot.afternoon:
        return 'Good Afternoon';
      case GreetingTimeSlot.evening:
        return 'Good Evening';
      case GreetingTimeSlot.midnight:
        return 'Midnight Adrenaline';
    }
  }

  static GreetingThemeData themeFor({DateTime? now}) {
    switch (_slotFor(now ?? DateTime.now())) {
      case GreetingTimeSlot.morning:
        return const GreetingThemeData(
          slot: GreetingTimeSlot.morning,
          backgroundColors: [0xFF10223B, 0xFF183A63, 0xFF2A6F97],
          accentColors: [0xFFF9C74F, 0xFFFFE29A],
          glowEnabled: false,
        );
      case GreetingTimeSlot.afternoon:
        return const GreetingThemeData(
          slot: GreetingTimeSlot.afternoon,
          backgroundColors: [0xFF1C1A1A, 0xFF472D1D, 0xFF8C5319],
          accentColors: [0xFFFF8A3D, 0xFFFFD166],
          glowEnabled: false,
        );
      case GreetingTimeSlot.evening:
        return const GreetingThemeData(
          slot: GreetingTimeSlot.evening,
          backgroundColors: [0xFF081827, 0xFF102D45, 0xFF1F4D6B],
          accentColors: [0xFF67E8F9, 0xFFA5F3FC],
          glowEnabled: false,
        );
      case GreetingTimeSlot.midnight:
        return const GreetingThemeData(
          slot: GreetingTimeSlot.midnight,
          backgroundColors: [0xFF03040A, 0xFF090B18, 0xFF111827],
          accentColors: [0xFF00E5FF, 0xFF7C3AED],
          glowEnabled: true,
        );
    }
  }

  static GreetingPayload build(String userName, {DateTime? now}) {
    final resolvedNow = now ?? DateTime.now();
    final resolvedName = _firstName(userName);
    return GreetingPayload(
      userName: resolvedName,
      message: getDynamicGreeting(resolvedName, now: resolvedNow),
      theme: themeFor(now: resolvedNow),
    );
  }

  static GreetingTimeSlot _slotFor(DateTime now) {
    final minutes = (now.hour * 60) + now.minute;
    if (minutes >= 5 * 60 && minutes <= ((10 * 60) + 59)) {
      return GreetingTimeSlot.morning;
    }
    if (minutes >= 11 * 60 && minutes <= ((16 * 60) + 59)) {
      return GreetingTimeSlot.afternoon;
    }
    if (minutes >= 17 * 60 && minutes <= ((21 * 60) + 59)) {
      return GreetingTimeSlot.evening;
    }
    return GreetingTimeSlot.midnight;
  }

  static String _firstName(String userName) {
    final trimmed = userName.trim();
    if (trimmed.isEmpty) return 'Player';
    return trimmed.split(RegExp(r'\s+')).first;
  }
}
