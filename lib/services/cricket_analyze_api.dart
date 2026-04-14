import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class CricketAnalyzeApi {
  static Future<String> analyzeCricketMarkdown({
    required String query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      throw Exception("EMPTY_QUERY");
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }

    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception("USER_NOT_AUTHENTICATED");
    }

    final uri = Uri.parse("${ApiConfig.baseUrl}/analyze-cricket");
    final resp = await http
        .post(
          uri,
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
            "X-USER-ID": user.uid,
          },
          // Cost optimization: send only the query (no chat history).
          body: jsonEncode({"query": q}),
        )
        .timeout(timeout);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final md = (decoded["markdown"] ?? "").toString().trim();
        if (md.isNotEmpty) return md;
      }
      throw Exception("EMPTY_RESPONSE");
    }

    if (resp.statusCode == 400) {
      try {
        final decoded = jsonDecode(resp.body);
        final detail = (decoded is Map) ? decoded["detail"]?.toString() : null;
        throw Exception(detail ?? "BAD_REQUEST");
      } catch (_) {
        throw Exception("BAD_REQUEST");
      }
    }

    if (resp.statusCode == 401) throw Exception("USER_NOT_AUTHENTICATED");
    if (resp.statusCode == 403) throw Exception("PREMIUM_REQUIRED");

    throw Exception("SERVER_ERROR_${resp.statusCode}");
  }
}
