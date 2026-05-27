import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/api_config.dart';
import 'review_player_screen.dart';

class LiveNetsAccessCard extends StatelessWidget {
  const LiveNetsAccessCard({super.key});

  static int balanceMsFrom(Map<String, dynamic> data) {
    final ms = (data['live_milliseconds_remaining'] as num?)?.toInt();
    if (ms != null) return ms;
    return ((data['live_seconds_remaining'] as num?)?.toInt() ?? 0) * 1000;
  }

  static String formatBalance(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds.remainder(60);
    final ms = milliseconds.remainder(1000);
    if (minutes >= 60) {
      return '${minutes ~/ 60}h ${minutes.remainder(60)}m';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final balanceMs = balanceMsFrom(snapshot.data?.data() ?? {});
        if (balanceMs <= 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF07111F),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                blurRadius: 24,
              ),
            ],
          ),
          child: ListTile(
            leading: const Icon(Icons.bolt_rounded, color: Color(0xFF00E5FF)),
            title: const Text(
              'Live Nets Session',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Balance ${formatBalance(balanceMs)}. Tripod mode with live AI coaching.',
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFF00E5FF),
              size: 18,
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LiveNetsTab())),
          ),
        );
      },
    );
  }
}

class LiveNetsTab extends StatefulWidget {
  const LiveNetsTab({super.key});

  @override
  State<LiveNetsTab> createState() => _LiveNetsTabState();
}

class _LiveNetsTabState extends State<LiveNetsTab> {
  Future<void> _openCareSheet() async {
    final start = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MoneyCareSheet(),
    );
    if (start != true || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LiveCountdown(),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LiveNetsCameraScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        foregroundColor: Colors.white,
        title: const Text('Live Nets'),
      ),
      body: user == null
          ? const Center(
              child: Text(
                'Sign in to use Live Nets.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final balanceMs = LiveNetsAccessCard.balanceMsFrom(
                  snapshot.data?.data() ?? {},
                );
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF00E5FF,
                            ).withValues(alpha: 0.6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pay-as-you-go balance',
                              style: TextStyle(color: Colors.white60),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              LiveNetsAccessCard.formatBalance(balanceMs),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: balanceMs > 0 ? _openCareSheet : null,
                        icon: const Icon(Icons.videocam_rounded),
                        label: const Text('Start Tripod Live AI Coach'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _MoneyCareSheet extends StatelessWidget {
  const _MoneyCareSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'We Care For Your Hard-Earned Money! 💎',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            const _CareBullet(
              icon: Icons.timer_outlined,
              text: 'Save Time: start only when you are padded up.',
            ),
            const _CareBullet(
              icon: Icons.visibility_outlined,
              text: 'Good Visibility: keep bat, ball and pitch clearly lit.',
            ),
            const _CareBullet(
              icon: Icons.video_camera_back_outlined,
              text:
                  'Perfect Camera Angle: tripod side-on, stable, full body visible.',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel & Prep'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('Start Live Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CareBullet extends StatelessWidget {
  const _CareBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCountdown extends StatefulWidget {
  const _LiveCountdown();

  @override
  State<_LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<_LiveCountdown> {
  int _count = 3;

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_count == 1) {
        timer.cancel();
        Navigator.pop(context);
      } else {
        setState(() => _count -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            '$_count',
            key: ValueKey(_count),
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 92,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class LiveNetsCameraScreen extends StatefulWidget {
  const LiveNetsCameraScreen({super.key});

  @override
  State<LiveNetsCameraScreen> createState() => _LiveNetsCameraScreenState();
}

class _LiveNetsCameraScreenState extends State<LiveNetsCameraScreen> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  CameraController? _camera;
  WebSocket? _socket;
  Timer? _frameTimer;
  DateTime? _startedAt;
  String? _sessionId;
  String? _recordedPath;
  int? _remainingMs;
  bool _connecting = true;
  bool _ending = false;
  String _status = 'Connecting';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Uri _liveUri(String uid) {
    final base = Uri.parse(ApiConfig.baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/live-nets/$uid',
    );
  }

  Future<void> _start() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _startedAt = DateTime.now();

    await _tts.setSpeechRate(0.52);
    await _tts.setPitch(1.0);

    final cameras = await availableCameras();
    final selected = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await controller.initialize();

    final dir = await getApplicationDocumentsDirectory();
    final sessionDir = Directory(p.join(dir.path, 'live_nets_sessions'));
    if (!sessionDir.existsSync()) sessionDir.createSync(recursive: true);
    _recordedPath = p.join(
      sessionDir.path,
      'live_nets_${user.uid}_$_sessionId.mp4',
    );

    final socket = await WebSocket.connect(_liveUri(user.uid).toString());
    socket.listen(
      _handleSocketMessage,
      onDone: _finishFromServer,
      onError: (_) => _finishFromServer(),
    );

    _socket = socket;
    _camera = controller;
    await controller.startVideoRecording();
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 850),
      (_) => _sendSnapshot(),
    );
    await _startSpeechLoop();

    if (mounted) {
      setState(() {
        _connecting = false;
        _status = 'Live';
      });
    }
  }

  Future<void> _startSpeechLoop() async {
    final available = await _speech.initialize();
    if (!available) return;
    await _speech.listen(
      listenMode: stt.ListenMode.dictation,
      partialResults: false,
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (text.isEmpty || _socket == null) return;
        _socket!.add(jsonEncode({'type': 'user_text', 'text': text}));
      },
    );
  }

  Future<void> _sendSnapshot() async {
    final controller = _camera;
    final socket = _socket;
    if (controller == null ||
        socket == null ||
        _ending ||
        !controller.value.isInitialized) {
      return;
    }
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      socket.add(jsonEncode({'type': 'video', 'data': base64Encode(bytes)}));
      await File(file.path).delete();
    } catch (_) {}
  }

  Future<void> _handleSocketMessage(dynamic message) async {
    if (message is List<int>) return;
    if (message is! String) return;
    final decoded = jsonDecode(message);
    if (decoded is! Map) return;
    if (decoded['type'] == 'ready' || decoded['type'] == 'billing') {
      final ms = (decoded['live_milliseconds_remaining'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _remainingMs = ms);
    }
    if (decoded['type'] == 'transcript') {
      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        await _saveMarker(text);
        await _tts.speak(text);
      }
    }
    if (decoded['type'] == 'termination') {
      await _endSession();
    }
  }

  Future<void> _saveMarker(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    final startedAt = _startedAt;
    final sessionId = _sessionId;
    if (user == null || startedAt == null || sessionId == null) return;
    final offset = DateTime.now().difference(startedAt).inSeconds;
    final box = await Hive.openBox('live_session_markers_${user.uid}');
    final existing = (box.get(sessionId, defaultValue: <dynamic>[]) as List)
        .cast<dynamic>();
    existing.add({'offset_seconds': offset, 'note': text});
    await box.put(sessionId, existing);
  }

  Future<void> _finishFromServer() async {
    await _endSession();
  }

  Future<void> _endSession() async {
    if (_ending) return;
    _ending = true;
    _frameTimer?.cancel();
    await _speech.stop();
    await _tts.stop();

    final controller = _camera;
    String? tempVideoPath;
    if (controller != null && controller.value.isRecordingVideo) {
      final file = await controller.stopVideoRecording();
      tempVideoPath = file.path;
    }
    _socket?.add(jsonEncode({'type': 'stop'}));
    await _socket?.close();

    if (tempVideoPath != null && _recordedPath != null) {
      await File(tempVideoPath).copy(_recordedPath!);
      await ImageGallerySaver.saveFile(
        _recordedPath!,
        name: p.basename(_recordedPath!),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReviewPlayerScreen(
          videoPath: _recordedPath ?? '',
          sessionId: _sessionId ?? '',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _speech.stop();
    _tts.stop();
    _socket?.close();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final remaining = _remainingMs;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (camera != null && camera.value.isInitialized)
            Positioned.fill(child: CameraPreview(camera))
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            ),
          Positioned(
            left: 18,
            top: 18 + MediaQuery.of(context).padding.top,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
                ),
              ),
              child: Text(
                remaining == null
                    ? _status
                    : LiveNetsAccessCard.formatBalance(remaining),
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 32 + MediaQuery.of(context).padding.bottom,
            child: ElevatedButton.icon(
              onPressed: _connecting ? null : _endSession,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End Session & Save to Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
