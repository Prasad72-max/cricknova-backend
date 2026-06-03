import 'dart:async';
import 'dart:collection';
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

import '../config/api_config.dart';
import '../services/premium_service.dart';
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
              'CrickNova Edge',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Balance ${formatBalance(balanceMs)}. Live AI net feedback with coach voice.',
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
        title: const Text('CrickNova Edge'),
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
                          color: const Color(0xFF07111F),
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
                            const Row(
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  color: Color(0xFF00E5FF),
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'CrickNova Edge Balance',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ],
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
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: const [
                              _EdgeInstructionCard(
                                icon: Icons.savings_outlined,
                                title: 'Your Money Matters',
                                body:
                                    'We respect every minute you purchase. Your training time and money are valuable, and CrickNova is designed to protect both.',
                              ),
                              _EdgeInstructionCard(
                                icon: Icons.play_circle_outline_rounded,
                                title:
                                    'Minutes Start Only When You Press Start',
                                body:
                                    'Live Analysis never begins automatically. Your session starts only when you choose to begin.',
                              ),
                              _EdgeInstructionCard(
                                icon: Icons.pause_circle_outline_rounded,
                                title: 'Pause Or Stop Anytime',
                                body:
                                    'Need a break? Adjusting your setup? Taking a rest between drills? Pause or stop your session whenever you want.',
                              ),
                              _EdgeInstructionCard(
                                icon: Icons.tune_rounded,
                                title: "You're Always In Control",
                                body:
                                    'No hidden timers. No wasted minutes. No unexpected usage. Every minute remains under your control.',
                              ),
                              _EdgeInstructionCard(
                                icon: Icons.sports_cricket_rounded,
                                title: 'Train With Confidence',
                                body:
                                    'Focus on your cricket while CrickNova Coach focuses on the analysis.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: balanceMs > 0 ? _openCareSheet : null,
                        icon: const Icon(Icons.videocam_rounded),
                        label: const Text('Start CrickNova Edge'),
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

class _EdgeInstructionCard extends StatelessWidget {
  const _EdgeInstructionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: const Color(0xFF00E5FF), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.8,
                    height: 1.42,
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
              'Your Money Matters',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            const _CareBullet(
              icon: Icons.play_circle_outline_rounded,
              text:
                  'Your minutes start only after you confirm Start Live Session.',
            ),
            const _CareBullet(
              icon: Icons.pause_circle_outline_rounded,
              text:
                  'Pause or stop whenever you need to adjust, rest, or reset.',
            ),
            const _CareBullet(
              icon: Icons.video_camera_back_outlined,
              text:
                  'Place your phone stable and side-on so the coach can see your full movement.',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Not Ready'),
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
  final Queue<String> _coachSpeechQueue = Queue<String>();
  final List<String> _captionHistory = <String>[];
  CameraController? _camera;
  WebSocket? _socket;
  Timer? _frameTimer;
  DateTime? _startedAt;
  String? _sessionId;
  String? _recordedPath;
  int? _remainingMs;
  bool _connecting = true;
  bool _ending = false;
  bool _paused = false;
  bool _streamStarted = false;
  int _socketReconnectAttempts = 0;
  String? _connectError;
  String _status = 'Connecting';
  Timer? _connectWatchdog;
  Timer? _socketReconnectTimer;
  bool _coachSpeechActive = false;
  String? _latestCaption;

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
    CameraController? localController;
    _armConnectWatchdog();

    await _tts.setSpeechRate(0.52);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setLanguage('en-US');
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.setSharedInstance(true);
    } catch (_) {}
    if (Platform.isIOS) {
      try {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          <IosTextToSpeechAudioCategoryOptions>[
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      } catch (_) {}
    }

    try {
      if (mounted) {
        setState(() {
          _status = 'Opening camera';
          _connectError = null;
        });
      }

      final cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
      );
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize().timeout(const Duration(seconds: 12));
      localController = controller;
      _camera = controller;
      if (mounted) {
        setState(() {
          _status = 'Camera ready';
        });
      }

      final dir = await getApplicationDocumentsDirectory();
      final sessionDir = Directory(p.join(dir.path, 'live_nets_sessions'));
      if (!sessionDir.existsSync()) sessionDir.createSync(recursive: true);
      _recordedPath = p.join(
        sessionDir.path,
        'live_nets_${user.uid}_$_sessionId.mp4',
      );

      if (mounted) {
        setState(() {
          _status = 'Connecting to CrickNova AI';
        });
      }

      final socket = await WebSocket.connect(
        _liveUri(user.uid).toString(),
      ).timeout(const Duration(seconds: 15));
      socket.listen(
        _handleSocketMessage,
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
      );

      _socket = socket;
      if (mounted) {
        setState(() {
          _status = 'Starting live detection';
        });
      }
      await controller.startVideoRecording().timeout(
        const Duration(seconds: 12),
      );
      _frameTimer = Timer.periodic(
        const Duration(milliseconds: 850),
        (_) => _sendSnapshot(),
      );

      if (mounted) {
        setState(() {
          _connecting = false;
          _status = 'AI live';
        });
      }
      _streamStarted = true;
      _socketReconnectAttempts = 0;
      _cancelConnectWatchdog();

      unawaited(_sendSnapshot());
    } catch (error) {
      _cancelConnectWatchdog();
      if (localController != null) {
        try {
          await localController.dispose();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _connectError = _friendlyStartError(error);
        _connecting = false;
        _status = 'Connection failed';
      });
    }
  }

  void _armConnectWatchdog() {
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted || !_connecting || _ending) return;
      setState(() {
        _connectError =
            'Live AI did not respond in time. Please retry once more.';
        _connecting = false;
        _status = 'Connection timed out';
      });
      unawaited(_cleanupForRetry());
    });
  }

  void _cancelConnectWatchdog() {
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
  }

  String _friendlyStartError(Object error) {
    final message = error.toString();
    if (message.contains('Timeout')) {
      return 'CrickNova AI took too long to respond. Please try again.';
    }
    if (message.contains('FIRESTORE') || message.contains('DATABASE')) {
      return 'CrickNova backend started, but live data storage is not ready yet.';
    }
    if (message.contains('SocketException')) {
      return 'Could not reach the live AI backend. Check internet and backend deployment.';
    }
    return 'Live session could not start: $message';
  }

  Future<void> _sendSnapshot() async {
    final controller = _camera;
    final socket = _socket;
    if (controller == null ||
        socket == null ||
        _ending ||
        _paused ||
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
    if (decoded['type'] == 'connected') {
      if (mounted) {
        setState(() {
          _status = 'AI connected';
        });
      }
    }
    if (decoded['type'] == 'transcript') {
      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        _updateCaption(text);
        await _saveMarker(text);
        unawaited(_enqueueCoachSpeech(text));
      }
    }
    if (decoded['type'] == 'termination') {
      await _finishFromServer(decoded['reason']?.toString());
    }
    if (decoded['type'] == 'error') {
      if (_streamStarted) {
        _scheduleSocketReconnect();
        return;
      }
      if (mounted) {
        setState(() {
          _connectError = 'Live AI could not start. Please try again.';
          _connecting = false;
          _status = 'Connection failed';
        });
      }
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

  Future<void> _enqueueCoachSpeech(String text) async {
    if (_ending) return;
    for (final finalChunk in _splitSpeech(text)) {
      _coachSpeechQueue.add(finalChunk);
    }
    if (_coachSpeechActive) return;
    _coachSpeechActive = true;
    try {
      while (_coachSpeechQueue.isNotEmpty && !_ending) {
        final next = _coachSpeechQueue.removeFirst();
        if (next.trim().isEmpty) continue;
        try {
          await _tts.speak(next);
        } catch (_) {}
      }
    } finally {
      _coachSpeechActive = false;
    }
  }

  void _updateCaption(String text) {
    if (!mounted) return;
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    setState(() {
      _latestCaption = clean;
      _captionHistory.insert(0, clean);
      while (_captionHistory.length > 3) {
        _captionHistory.removeLast();
      }
    });
  }

  List<String> _splitSpeech(String text) {
    final clean = text
        .replaceAll(RegExp(r'[*_`#>]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return const <String>[];

    final parts = clean
        .split(RegExp(r'(?<=[\.\!\?\:;])\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return <String>[clean];
    return parts;
  }

  Future<void> _finishFromServer([String? reason]) async {
    final startedAt = _startedAt;
    final elapsedSeconds = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;
    final earlyStop = !_streamStarted || elapsedSeconds < 8;

    if (earlyStop &&
        (reason == null ||
            reason == 'UNKNOWN' ||
            !reason.contains('NO_LIVE_BALANCE'))) {
      _scheduleSocketReconnect();
      return;
    }

    await _endSession(
      navigateToReview: _streamStarted &&
          (_startedAt == null ||
              DateTime.now().difference(_startedAt!).inSeconds >= 5),
      serverReason: reason,
    );
  }

  Future<void> _handleSocketClosed() async {
    if (_ending) return;
    if (!_streamStarted) {
      await _cleanupForRetry();
      if (!mounted || _ending) return;
      setState(() {
        _connectError = 'Live AI could not start. Please try again.';
        _connecting = false;
        _status = 'Connection failed';
      });
      return;
    }

    _scheduleSocketReconnect();
  }

  void _scheduleSocketReconnect() {
    if (_ending) return;
    _socketReconnectTimer?.cancel();
    _socketReconnectAttempts += 1;
    final delayMs = (1000 * (1 << (_socketReconnectAttempts - 1)))
        .clamp(1000, 5000);
    if (mounted) {
      setState(() {
        _status = 'AI live';
      });
    }
    _socketReconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _ending) return;
      unawaited(_reconnectSocketOnly());
    });
  }

  Future<void> _reconnectSocketOnly() async {
    if (_ending) return;
    final user = FirebaseAuth.instance.currentUser;
    final controller = _camera;
    if (user == null || controller == null || !controller.value.isInitialized) {
      _scheduleSocketReconnect();
      return;
    }
    if (!controller.value.isRecordingVideo) {
      _scheduleSocketReconnect();
      return;
    }

    try {
      final socket = await WebSocket.connect(
        _liveUri(user.uid).toString(),
      ).timeout(const Duration(seconds: 12));
      socket.listen(
        _handleSocketMessage,
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
      );
      _socket = socket;
      _socketReconnectAttempts = 0;
      if (mounted) {
        setState(() {
          _connectError = null;
          _status = 'AI live';
        });
      }
      unawaited(_sendSnapshot());
    } catch (_) {
      _scheduleSocketReconnect();
    }
  }

  Future<void> _retryStart() async {
    _socketReconnectTimer?.cancel();
    await _cleanupForRetry();
    if (_ending) return;
    if (!mounted) return;
    setState(() {
      _connectError = null;
      _connecting = true;
      _status = 'Connecting';
    });
    unawaited(_start());
  }

  Future<void> _goBack() async {
    if (_ending) return;
    _ending = true;
    _socketReconnectTimer?.cancel();
    _frameTimer?.cancel();
    _coachSpeechQueue.clear();
    await _tts.stop();

    final controller = _camera;
    if (controller != null) {
      try {
        if (controller.value.isRecordingVideo) {
          await controller.stopVideoRecording();
        }
      } catch (_) {}
    }

    try {
      _socket?.add(jsonEncode({'type': 'stop'}));
      await _socket?.close();
    } catch (_) {}

    if (mounted) {
      await _cleanupForRetry();
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _cleanupForRetry() async {
    _cancelConnectWatchdog();
    _socketReconnectTimer?.cancel();
    _frameTimer?.cancel();
    _frameTimer = null;
    _coachSpeechQueue.clear();
    await _tts.stop();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    final controller = _camera;
    _camera = null;
    if (controller != null) {
      try {
        if (controller.value.isRecordingVideo) {
          await controller.stopVideoRecording();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _togglePause() async {
    final controller = _camera;
    final socket = _socket;
    if (_connecting || _ending || controller == null) return;

    final nextPaused = !_paused;
    setState(() {
      _paused = nextPaused;
      _status = nextPaused ? 'Paused' : 'Live';
    });

    try {
      socket?.add(jsonEncode({'type': nextPaused ? 'pause' : 'resume'}));
      if (controller.value.isRecordingVideo) {
        if (nextPaused) {
          await controller.pauseVideoRecording();
        } else {
          await controller.resumeVideoRecording();
        }
      }
    } catch (_) {}
  }

  Future<void> _endSession({
    bool navigateToReview = true,
    String? serverReason,
  }) async {
    if (_ending) return;
    final user = FirebaseAuth.instance.currentUser;
    _ending = true;
    _socketReconnectTimer?.cancel();
    _frameTimer?.cancel();
    await _tts.stop();

    final controller = _camera;
    String? tempVideoPath;
    if (controller != null && controller.value.isRecordingVideo) {
      if (_paused) {
        try {
          await controller.resumeVideoRecording();
        } catch (_) {}
      }
      final file = await controller.stopVideoRecording();
      tempVideoPath = file.path;
    }
    _socket?.add(jsonEncode({'type': 'stop'}));
    await _socket?.close();
    if (user != null) {
      await PremiumService.refreshLiveEdgeBalance(uid: user.uid);
      PremiumService.premiumNotifier.forceNotify();
    }

    if (tempVideoPath != null && _recordedPath != null) {
      await File(tempVideoPath).copy(_recordedPath!);
      await ImageGallerySaver.saveFile(
        _recordedPath!,
        name: p.basename(_recordedPath!),
      );
    }

    if (!mounted) return;
    if (navigateToReview) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReviewPlayerScreen(
            videoPath: _recordedPath ?? '',
            sessionId: _sessionId ?? '',
          ),
        ),
      );
      return;
    }

    await _cleanupForRetry();
    if (!mounted) return;
    setState(() {
      _ending = false;
      _connectError = serverReason?.isNotEmpty == true
          ? serverReason
          : 'Live session stopped before it could fully start.';
      _status = 'Disconnected';
    });
  }

  @override
  void dispose() {
    _connectWatchdog?.cancel();
    _socketReconnectTimer?.cancel();
    _frameTimer?.cancel();
    _coachSpeechQueue.clear();
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
            right: 18,
            child: Row(
              children: [
                Material(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _goBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Color(0xFF00E5FF),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              ),
          ),
          if (_connectError != null)
            Positioned(
              left: 18,
              right: 18,
              top: 84 + MediaQuery.of(context).padding.top,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xDD0B1118),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _connectError!,
                      style: const TextStyle(color: Colors.white, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _retryStart,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 96 + MediaQuery.of(context).padding.bottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_latestCaption != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.closed_caption_rounded,
                          color: Color(0xFF00E5FF),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _latestCaption!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_captionHistory.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _captionHistory
                          .take(3)
                          .map(
                            (caption) => Container(
                              constraints: const BoxConstraints(maxWidth: 220),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Text(
                                caption,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 32 + MediaQuery.of(context).padding.bottom,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _connecting ? null : _togglePause,
                    icon: Icon(
                      _paused
                          ? Icons.play_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                    ),
                    label: Text(_paused ? 'Resume' : 'Pause'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _connecting ? null : _endSession,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End & Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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
