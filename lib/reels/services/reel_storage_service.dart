import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ReelStorageUploadResult {
  final String originalVideoUrl;
  final String reelVideoUrl;
  final String? thumbnailUrl;

  const ReelStorageUploadResult({
    required this.originalVideoUrl,
    required this.reelVideoUrl,
    this.thumbnailUrl,
  });
}

class ReelStorageService {
  static const String bucketName = "cricknova-5f94f.firebasestorage.app";
  static const String storageHost = "https://firebasestorage.googleapis.com/v0/b";

  /// Uploads a reel video file directly to Firebase Storage bucket via authenticated REST API.
  /// Reports upload progress via [onProgress] callback (0.0 to 1.0).
  static Future<String> uploadFile({
    required File file,
    required String storagePath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User must be authenticated to upload Reels.");
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception("Authentication token expired. Please sign in again.");
    }

    final encodedPath = Uri.encodeComponent(storagePath);
    final uploadUri = Uri.parse(
      "$storageHost/$bucketName/o?uploadType=media&name=$encodedPath",
    );

    final fileLength = await file.length();
    if (fileLength == 0) {
      throw Exception("Selected video file is empty.");
    }

    // Stream upload with progress tracking
    final client = http.Client();
    try {
      final request = http.StreamedRequest("POST", uploadUri);
      request.headers["Authorization"] = "Bearer $idToken";
      request.headers["Content-Type"] = contentType;
      request.contentLength = fileLength;

      int bytesUploaded = 0;
      final fileStream = file.openRead();

      final streamSubscription = fileStream.listen(
        (chunk) {
          bytesUploaded += chunk.length;
          request.sink.add(chunk);
          if (onProgress != null && fileLength > 0) {
            onProgress(bytesUploaded / fileLength);
          }
        },
        onDone: () => request.sink.close(),
        onError: (err) => request.sink.addError(err),
        cancelOnError: true,
      );

      final response = await client.send(request).timeout(
        const Duration(minutes: 5),
      );
      await streamSubscription.cancel();

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint("FIREBASE_STORAGE_ERROR: ${response.statusCode} => $responseBody");
        throw Exception("Failed to upload to Firebase Storage: ${response.statusCode}");
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final downloadTokens = (data["downloadTokens"] ?? "").toString();

      final downloadUrl = downloadTokens.isNotEmpty
          ? "$storageHost/$bucketName/o/$encodedPath?alt=media&token=$downloadTokens"
          : "$storageHost/$bucketName/o/$encodedPath?alt=media";

      debugPrint("REEL_STORAGE_UPLOAD_SUCCESS: $downloadUrl");
      return downloadUrl;
    } finally {
      client.close();
    }
  }

  /// Uploads both original video and optional thumbnail to standard Firebase Storage paths:
  /// users/{userId}/reels/{reelId}/original.mp4
  /// users/{userId}/reels/{reelId}/reel.mp4
  /// users/{userId}/reels/{reelId}/thumbnail.jpg
  static Future<ReelStorageUploadResult> uploadReelMedia({
    required String userId,
    required String reelId,
    required File videoFile,
    File? thumbnailFile,
    void Function(double progress)? onProgress,
  }) async {
    final originalPath = "users/$userId/reels/$reelId/original.mp4";
    final reelPath = "users/$userId/reels/$reelId/reel.mp4";
    final thumbPath = "users/$userId/reels/$reelId/thumbnail.jpg";

    // 1. Upload original video
    final videoUrl = await uploadFile(
      file: videoFile,
      storagePath: originalPath,
      contentType: "video/mp4",
      onProgress: (p) => onProgress?.call(p * 0.85),
    );

    // 2. Upload thumbnail if available
    String? thumbUrl;
    if (thumbnailFile != null && await thumbnailFile.exists()) {
      try {
        thumbUrl = await uploadFile(
          file: thumbnailFile,
          storagePath: thumbPath,
          contentType: "image/jpeg",
          onProgress: null,
        );
      } catch (e) {
        debugPrint("THUMBNAIL_UPLOAD_WARNING: $e");
      }
    }

    onProgress?.call(1.0);

    return ReelStorageUploadResult(
      originalVideoUrl: videoUrl,
      reelVideoUrl: videoUrl, // Can be updated if compressed/transcoded
      thumbnailUrl: thumbUrl,
    );
  }
}
