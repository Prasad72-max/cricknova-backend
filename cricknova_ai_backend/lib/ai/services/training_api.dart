import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class TrainingApi {
  static const String baseUrl = "http://192.168.1.14:8000";

  static Future<Map<String, dynamic>> analyzeVideo(File video) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse("$baseUrl/training/analyze"),
    );

    request.files.add(
      await http.MultipartFile.fromPath('file', video.path),
    );

    final response = await request.send();
    final responseData = await response.stream.bytesToString();

    return jsonDecode(responseData);
  }
}