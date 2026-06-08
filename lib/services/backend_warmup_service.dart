import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class BackendWarmupService {
  BackendWarmupService._();

  static final BackendWarmupService instance = BackendWarmupService._();

  static final Uri _warmupUri = Uri.parse(
    '${ApiConfig.baseUrl.replaceFirst(RegExp(r'/$'), '')}/__alive',
  );
  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 8),
    Duration(seconds: 20),
    Duration(seconds: 45),
    Duration(seconds: 90),
  ];

  bool _isRunning = false;
  DateTime? _lastSuccessAt;

  Future<void> wake({bool force = false}) async {
    final lastSuccessAt = _lastSuccessAt;
    if (!force &&
        lastSuccessAt != null &&
        DateTime.now().difference(lastSuccessAt) <
            const Duration(minutes: 10)) {
      return;
    }
    if (_isRunning) return;

    _isRunning = true;
    try {
      if (await _ping()) return;

      for (final delay in _retryDelays) {
        await Future<void>.delayed(delay);
        if (await _ping()) return;
      }
    } finally {
      _isRunning = false;
    }
  }

  Future<bool> _ping() async {
    try {
      final response = await http
          .get(
            _warmupUri,
            headers: const <String, String>{
              'Accept': 'application/json, text/plain, */*',
              'X-CrickNova-Warmup': 'app-open',
            },
          )
          .timeout(const Duration(seconds: 6));

      final ok = response.statusCode >= 200 && response.statusCode < 400;
      if (ok) {
        _lastSuccessAt = DateTime.now();
        debugPrint('Backend warmup sent: ${response.statusCode}');
      } else {
        debugPrint('Backend warmup rejected: ${response.statusCode}');
      }
      return ok;
    } catch (e) {
      debugPrint('Backend warmup skipped/retry later: $e');
      return false;
    }
  }
}
