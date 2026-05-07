import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/pending_video.dart';
import '../analysis/analysis_queue_store.dart';
import 'cricknova_notification_service.dart';

class BackgroundAnalysisService {
  BackgroundAnalysisService._();
  static final BackgroundAnalysisService instance =
      BackgroundAnalysisService._();

  Timer? _timer;
  bool _isProcessing = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAndProcess(),
    );
    // Run immediately on start
    _checkAndProcess();
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _checkAndProcess() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final box = Hive.box<PendingVideo>('pending_videos');
      final pendingVideos = box.values
          .where((v) => v.status == 'pending' || v.status == 'uploading')
          .toList();

      for (final video in pendingVideos) {
        await _processVideo(video);
      }
    } catch (e) {
      debugPrint("BackgroundAnalysisService Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processVideo(PendingVideo video) async {
    final file = File(video.localFilePath);
    if (!file.existsSync()) {
      debugPrint("BackgroundAnalysis: File not found ${video.localFilePath}");
      final box = Hive.box<PendingVideo>('pending_videos');
      await box.delete(video.id);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      video.status = 'uploading';
      final box = Hive.box<PendingVideo>('pending_videos');
      await box.put(video.id, video);

      final token = await user.getIdToken(true);
      final uri = Uri.parse(
        "https://cricknova-backend.onrender.com/training/analyze",
      );

      final request = http.MultipartRequest("POST", uri);
      request.headers["Accept"] = "application/json";
      request.headers["Authorization"] = "Bearer $token";
      request.files.add(await http.MultipartFile.fromPath("file", file.path));

      // Long timeout for background process to handle Render cold start
      final response = await request.send().timeout(const Duration(minutes: 3));
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(respStr);
        final analysis = decoded["analysis"] ?? decoded;

        video.status = 'complete';
        video.resultData = analysis;
        await box.put(video.id, video);

        // Update the legacy AnalysisQueueStore too
        await AnalysisQueueStore.upsertJob({
          'id': video.id,
          'title': file.path.split(RegExp(r'[\\/]')).last,
          'discipline': 'training',
          'status': 'ready',
          'localFilePath': video.localFilePath,
          'resultData': analysis,
          'speedLabel': analysis["speed_kmph"] ?? "0",
          'swing': analysis["swing"] ?? "NONE",
          'spin': analysis["spin"] ?? "NONE",
        });

        await CrickNovaNotificationService.instance.maybeNotifyAnalysisComplete(
          resultJobId: video.id,
        );

        debugPrint("BackgroundAnalysis: Success for ${video.id}");
      } else {
        debugPrint(
          "BackgroundAnalysis: Failed with status ${response.statusCode}",
        );
        video.status = 'pending'; // Retry later
        await box.put(video.id, video);
      }
    } catch (e) {
      debugPrint("BackgroundAnalysis: Error processing ${video.id}: $e");
      video.status = 'pending'; // Retry later
      final box = Hive.box<PendingVideo>('pending_videos');
      await box.put(video.id, video);
    }
  }
}
