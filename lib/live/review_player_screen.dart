import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:video_player/video_player.dart';

import '../ai/ai_coach_screen.dart';

class ReviewPlayerScreen extends StatefulWidget {
  const ReviewPlayerScreen({
    super.key,
    required this.videoPath,
    required this.sessionId,
  });

  final String videoPath;
  final String sessionId;

  @override
  State<ReviewPlayerScreen> createState() => _ReviewPlayerScreenState();
}

class _ReviewPlayerScreenState extends State<ReviewPlayerScreen> {
  VideoPlayerController? _controller;
  Timer? _ticker;
  List<_Marker> _markers = const [];
  _Marker? _activeMarker;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final box = await Hive.openBox('live_session_markers_${user.uid}');
      final raw = (box.get(widget.sessionId, defaultValue: <dynamic>[]) as List)
          .cast<dynamic>();
      _markers =
          raw
              .whereType<Map>()
              .map(
                (item) => _Marker(
                  offsetSeconds: (item['offset_seconds'] as num?)?.toInt() ?? 0,
                  note: item['note']?.toString() ?? '',
                ),
              )
              .where((marker) => marker.note.isNotEmpty)
              .toList()
            ..sort((a, b) => a.offsetSeconds.compareTo(b.offsetSeconds));
    }

    final controller = VideoPlayerController.file(File(widget.videoPath));
    await controller.initialize();
    await controller.play();
    _controller = controller;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _syncMarker(),
    );
    if (mounted) setState(() {});
  }

  void _syncMarker() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final seconds = controller.value.position.inSeconds;
    final match = _markers.cast<_Marker?>().firstWhere(
      (marker) => marker != null && (seconds - marker.offsetSeconds).abs() <= 1,
      orElse: () => null,
    );
    if (match != _activeMarker && mounted) {
      setState(() => _activeMarker = match);
    }
  }

  void _askCoach(_Marker marker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AICoachScreen(
          payloadContext: {
            'source': 'live_nets_review',
            'video_path': widget.videoPath,
            'session_id': widget.sessionId,
            'offset_seconds': marker.offsetSeconds,
            'fault_note': marker.note,
          },
          initialQuestion:
              'Fix this batting issue at ${marker.offsetSeconds}s: ${marker.note}',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Live Nets Review'),
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            )
          : Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 24 + MediaQuery.of(context).padding.bottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_activeMarker != null)
                        _MarkerCard(
                          marker: _activeMarker!,
                          onAskCoach: () => _askCoach(_activeMarker!),
                        ),
                      const SizedBox(height: 12),
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF00E5FF),
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      IconButton.filled(
                        onPressed: () {
                          controller.value.isPlaying
                              ? controller.pause()
                              : controller.play();
                          setState(() {});
                        },
                        icon: Icon(
                          controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _MarkerCard extends StatelessWidget {
  const _MarkerCard({required this.marker, required this.onAskCoach});

  final _Marker marker;
  final VoidCallback onAskCoach;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xDD050915),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            marker.note,
            style: const TextStyle(color: Colors.white, height: 1.35),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onAskCoach,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Ask CrickNova to Fix This'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _Marker {
  const _Marker({required this.offsetSeconds, required this.note});

  final int offsetSeconds;
  final String note;
}
