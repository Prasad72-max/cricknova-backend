import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../navigation/main_navigation.dart';
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
  static const _languagePrefsKey = 'cricknova_edge_language';
  static const _disciplinePrefsKey = 'cricknova_edge_discipline';

  String _selectedLanguage = 'English';
  String _selectedDiscipline = 'Batting';
  String _coachName = 'Player';

  @override
  void initState() {
    super.initState();
    unawaited(_loadEdgePrefs());
  }

  Future<void> _loadEdgePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'guest';
    final savedLanguage = prefs.getString(_languagePrefsKey)?.trim();
    final savedDiscipline = prefs.getString(_disciplinePrefsKey)?.trim();
    final savedName = [
      prefs.getString('profileName_$uid')?.trim(),
      prefs.getString('userName_$uid')?.trim(),
      prefs.getString('profileName')?.trim(),
      prefs.getString('userName')?.trim(),
      MainNavigation.userNameNotifier.value.trim(),
      user?.displayName?.trim(),
    ].whereType<String>().firstWhere(
      (value) => value.isNotEmpty && value.toLowerCase() != 'player',
      orElse: () => 'Player',
    );

    if (!mounted) return;
    setState(() {
      _selectedLanguage = _normalizeLanguage(savedLanguage);
      _selectedDiscipline = _normalizeDiscipline(savedDiscipline);
      _coachName = savedName;
    });
  }

  Future<void> _saveEdgePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefsKey, _selectedLanguage);
    await prefs.setString(_disciplinePrefsKey, _selectedDiscipline);
  }

  String _normalizeLanguage(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.contains('hindi')) return 'Hindi';
    if (value.contains('marathi')) return 'Marathi';
    return 'English';
  }

  String _normalizeDiscipline(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.contains('bowl')) return 'Bowling';
    return 'Batting';
  }

  Future<void> _openCareSheet() async {
    final navigator = Navigator.of(context);
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
    if (!context.mounted) return;
    await _saveEdgePrefs();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => LiveNetsCameraScreen(
          coachName: _coachName,
          language: _selectedLanguage,
          discipline: _selectedDiscipline,
        ),
      ),
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
                      _CoachControlsRow(
                        language: _selectedLanguage,
                        discipline: _selectedDiscipline,
                        onLanguageChanged: (value) {
                          setState(() => _selectedLanguage = value);
                          unawaited(_saveEdgePrefs());
                        },
                        onDisciplineChanged: (value) {
                          setState(() => _selectedDiscipline = value);
                          unawaited(_saveEdgePrefs());
                        },
                      ),
                      const SizedBox(height: 16),
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

class _CoachControlsRow extends StatelessWidget {
  const _CoachControlsRow({
    required this.language,
    required this.discipline,
    required this.onLanguageChanged,
    required this.onDisciplineChanged,
  });

  final String language;
  final String discipline;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onDisciplineChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceSection(
          title: 'Coach Language',
          children: ['English', 'Hindi', 'Marathi']
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: language == value,
                  onSelected: (_) => onLanguageChanged(value),
                  labelStyle: TextStyle(
                    color: language == value ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: const Color(0xFF00E5FF),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 10),
        _ChoiceSection(
          title: 'Training Mode',
          children: ['Batting', 'Bowling']
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: discipline == value,
                  onSelected: (_) => onDisciplineChanged(value),
                  labelStyle: TextStyle(
                    color: discipline == value ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: const Color(0xFF00E5FF),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ChoiceSection extends StatelessWidget {
  const _ChoiceSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: children,
        ),
      ],
    );
  }
}

class _LiveCountdown extends StatefulWidget {
  const _LiveCountdown();

  @override
  State<_LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<_LiveCountdown> {
  final FlutterTts _tickTts = FlutterTts();
  Timer? _timer;
  int _count = 3;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareTickSound());
    unawaited(_playTick());
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_count == 1) {
        timer.cancel();
        Navigator.pop(context);
      } else {
        setState(() {
          _count -= 1;
        });
        unawaited(_playTick());
      }
    });
  }

  Future<void> _prepareTickSound() async {
    try {
      await _tickTts.setLanguage('en-IN');
      await _tickTts.setSpeechRate(0.70);
      await _tickTts.setPitch(1.35);
      await _tickTts.setVolume(1.0);
      await _tickTts.awaitSpeakCompletion(false);
    } catch (_) {}
  }

  Future<void> _playTick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
      await HapticFeedback.selectionClick();
      await _tickTts.stop();
      await _tickTts.speak('tick');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_tickTts.stop());
    super.dispose();
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
  const LiveNetsCameraScreen({
    super.key,
    required this.coachName,
    required this.language,
    required this.discipline,
  });

  final String coachName;
  final String language;
  final String discipline;

  @override
  State<LiveNetsCameraScreen> createState() => _LiveNetsCameraScreenState();
}

class _PendingCoachFeedback {
  const _PendingCoachFeedback({
    required this.text,
    required this.mood,
    required this.clipIndex,
  });

  final String text;
  final String mood;
  final int clipIndex;
}

class _PendingVideoChunk {
  const _PendingVideoChunk({
    required this.bytes,
    required this.clipIndex,
  });

  final List<int> bytes;
  final int clipIndex;
}

class _LiveNetsCameraScreenState extends State<LiveNetsCameraScreen> {
  final FlutterTts _tts = FlutterTts();
  final Queue<_PendingCoachFeedback> _coachFeedbackQueue =
      Queue<_PendingCoachFeedback>();
  final List<String> _captionHistory = <String>[];
  final List<String> _recordedChunkPaths = <String>[];
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
  bool _chunkInFlight = false;
  int _socketReconnectAttempts = 0;
  String? _connectError;
  String _status = 'Connecting';
  Timer? _connectWatchdog;
  Timer? _socketReconnectTimer;
  bool _coachFeedbackActive = false;
  bool _allowFinalFeedbackDrain = false;
  Completer<void>? _ttsCompletion;
  int _chunksSent = 0;
  int _chunksAnalysed = 0;
  bool _coachProcessing = false;
  bool _feedbackUploadInFlight = false;
  _PendingCoachFeedback? _pendingCoachFeedback;
  _PendingVideoChunk? _queuedFeedbackChunk;
  String? _latestCaption;
  String _effectiveLanguage = 'English';
  DateTime? _currentClipStartedAt;
  bool _chunkRestartScheduled = false;

  static const Duration _chunkDuration = Duration(seconds: 10);
  static const Duration _minimumChunkDuration = Duration(seconds: 7);

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

    _effectiveLanguage = _normalizeLanguage(widget.language);

    await _tts.setSpeechRate(0.50);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.95);
    try {
      await _tts.setLanguage(_languageCodeFor(_effectiveLanguage));
    } catch (_) {
      await _tts.setLanguage('en-IN');
    }
    _tts.setCompletionHandler(() {
      final completer = _ttsCompletion;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    });
    _tts.setErrorHandler((_) {
      final completer = _ttsCompletion;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    });
    _tts.setCancelHandler(() {
      final completer = _ttsCompletion;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    });
    unawaited(_applyPreferredVoice(_effectiveLanguage));
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
      socket.add(
        jsonEncode({
          'type': 'client_config',
          'name': widget.coachName,
          'language': _effectiveLanguage,
          'discipline': widget.discipline,
        }),
      );
      if (mounted) {
        setState(() {
          _status = 'Starting live detection';
        });
      }
      await controller.startVideoRecording().timeout(
        const Duration(seconds: 12),
      );
      _currentClipStartedAt = DateTime.now();
      _frameTimer = Timer.periodic(
        _chunkDuration,
        (_) => _sendVideoChunk(),
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

  String _normalizeLanguage(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('hindi')) return 'Hindi';
    if (value.contains('marathi')) return 'Marathi';
    return 'English';
  }

  String _languageCodeFor(String language) {
    switch (language) {
      case 'Hindi':
        return 'hi-IN';
      case 'Marathi':
        return 'mr-IN';
      case 'English':
      default:
        return 'en-IN';
    }
  }

  Future<void> _applyPreferredVoice(String language) async {
    final locale = _languageCodeFor(language);
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        final voice = voices.cast<dynamic>().firstWhere(
          (item) {
            if (item is! Map) return false;
            final localeValue = (item['locale'] ?? '').toString().toLowerCase();
            return localeValue.startsWith(locale.split('-').first.toLowerCase());
          },
          orElse: () => null,
        );
        if (voice is Map) {
          await _tts.setVoice({
            'name': (voice['name'] ?? '').toString(),
            'locale': (voice['locale'] ?? locale).toString(),
          });
        }
      }
    } catch (_) {}
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

  Future<void> _sendVideoChunk() async {
    final controller = _camera;
    final socket = _socket;
    if (controller == null ||
        socket == null ||
        _ending ||
        _paused ||
        _chunkInFlight ||
        !controller.value.isInitialized) {
      return;
    }
    final startedAt = _currentClipStartedAt;
    if (startedAt != null) {
      final age = DateTime.now().difference(startedAt);
      if (age < _minimumChunkDuration) {
        if (!_chunkRestartScheduled) {
          _chunkRestartScheduled = true;
          final wait = _minimumChunkDuration - age;
          Future<void>.delayed(wait, () {
            _chunkRestartScheduled = false;
            if (!mounted || _ending || _paused) return;
            unawaited(_sendVideoChunk());
          });
        }
        return;
      }
    }
    if (!controller.value.isRecordingVideo) {
      try {
        await controller.startVideoRecording();
        _currentClipStartedAt = DateTime.now();
      } catch (error) {
        debugPrint('CrickNova Edge chunk restart failed: $error');
      }
      return;
    }

    _chunkInFlight = true;
    try {
      final file = await controller.stopVideoRecording();
      _recordedChunkPaths.add(file.path);
      _chunksSent += 1;
      final clipIndex = _chunksSent;
      if (mounted) {
        setState(() {
          _coachProcessing = true;
          _status = 'Observing clip $clipIndex';
        });
      }
      debugPrint(
        'CrickNova Edge preparing 10-second video #$clipIndex: ${file.path}',
      );
      if (!_ending && !_paused && controller.value.isInitialized) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await controller.startVideoRecording();
        _currentClipStartedAt = DateTime.now();
      }
      unawaited(() async {
        try {
          final bytes = await file.readAsBytes();
          if (_ending) return;
          debugPrint(
            'CrickNova Edge sending 10-second video #$clipIndex: ${bytes.length} bytes',
          );
          _enqueueVideoChunkForFeedback(bytes, clipIndex);
        } catch (error) {
          debugPrint('CrickNova Edge chunk read failed: $error');
        }
      }());
      _flushPendingCoachFeedback();
    } catch (error) {
      debugPrint('CrickNova Edge video chunk failed: $error');
      if (!_ending && !_paused && controller.value.isInitialized) {
        try {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await controller.startVideoRecording();
          _currentClipStartedAt = DateTime.now();
        } catch (restartError) {
          debugPrint('CrickNova Edge recovery restart failed: $restartError');
        }
      }
    } finally {
      _chunkInFlight = false;
    }
  }

  void _enqueueVideoChunkForFeedback(List<int> bytes, int clipIndex) {
    if (_ending) return;
    if (_feedbackUploadInFlight) {
      _queuedFeedbackChunk = _PendingVideoChunk(
        bytes: bytes,
        clipIndex: clipIndex,
      );
      debugPrint('CrickNova Edge queued latest clip #$clipIndex for feedback');
      return;
    }
    unawaited(_uploadVideoChunkForFeedback(bytes, clipIndex));
  }

  Future<void> _uploadVideoChunkForFeedback(
    List<int> bytes,
    int clipIndex,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (_ending && !_allowFinalFeedbackDrain)) return;
    _feedbackUploadInFlight = true;
    try {
      if (mounted) {
        setState(() {
          _coachProcessing = true;
          _status = 'Coach reading clip $clipIndex';
        });
      }
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/live-nets/analyze-chunk/${user.uid}',
      );
      final request = http.MultipartRequest('POST', uri)
        ..fields['name'] = widget.coachName
        ..fields['language'] = _effectiveLanguage
        ..fields['discipline'] = widget.discipline
        ..fields['clip_index'] = clipIndex.toString()
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: 'edge_clip_$clipIndex.mp4',
          ),
        );
      final token = await user.getIdToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      debugPrint('CrickNova Edge uploading clip #$clipIndex for feedback');
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      debugPrint(
        'CrickNova Edge feedback response #$clipIndex: '
        '${response.statusCode} ${response.body}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'CrickNova Edge chunk feedback failed: ${response.statusCode} ${response.body}',
        );
        if (mounted) {
          setState(() {
            _chunksAnalysed = clipIndex;
            _coachProcessing = false;
            _status = 'Gemini feedback failed';
          });
        }
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        if (mounted) {
          setState(() {
            _chunksAnalysed = clipIndex;
            _coachProcessing = false;
            _status = 'Gemini response unreadable';
          });
        }
        return;
      }
      final text = _cleanCoachTranscript(decoded['text']?.toString() ?? '');
      final mood = decoded['mood']?.toString().trim().toLowerCase() ?? '';
      if (mounted) {
        setState(() {
          _chunksAnalysed = clipIndex;
          _coachProcessing = false;
        });
      }
      if (text.isNotEmpty) {
        await _showCoachFeedback(text, mood: mood, clipIndex: clipIndex);
      } else {
        debugPrint('CrickNova Edge feedback empty for clip #$clipIndex');
        if (mounted) {
          setState(() {
            _status = 'Waiting for real Gemini feedback';
          });
        }
      }
    } catch (error) {
      debugPrint('CrickNova Edge chunk upload failed: $error');
      if (mounted) {
        setState(() {
          _chunksAnalysed = clipIndex;
          _coachProcessing = false;
          _status = 'Gemini upload failed';
        });
      }
    } finally {
      _feedbackUploadInFlight = false;
      final queued = _queuedFeedbackChunk;
      _queuedFeedbackChunk = null;
      if (queued != null && (!_ending || _allowFinalFeedbackDrain)) {
        unawaited(_uploadVideoChunkForFeedback(queued.bytes, queued.clipIndex));
      }
    }
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
      final text = _cleanCoachTranscript(decoded['text']?.toString() ?? '');
      final mood = decoded['mood']?.toString().trim().toLowerCase() ?? '';
      final clipIndex = (decoded['clip_index'] as num?)?.toInt();
      if (text.isNotEmpty) {
        if (mounted) {
          setState(() {
            _chunksAnalysed = clipIndex ?? _chunksAnalysed + 1;
            _coachProcessing = false;
          });
        } else {
          _chunksAnalysed = clipIndex ?? _chunksAnalysed + 1;
          _coachProcessing = false;
        }
        if (clipIndex != null && clipIndex >= _chunksSent) {
          _pendingCoachFeedback = _PendingCoachFeedback(
            text: text,
            mood: mood,
            clipIndex: clipIndex,
          );
        } else {
          await _showCoachFeedback(
            text,
            mood: mood,
            clipIndex: clipIndex,
          );
        }
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

  Future<void> _showCoachFeedback(
    String text, {
    String mood = '',
    int? clipIndex,
  }) async {
    final clean = _cleanCoachTranscript(text);
    if (clean.isEmpty) return;
    _coachFeedbackQueue.add(
      _PendingCoachFeedback(
        text: clean,
        mood: mood,
        clipIndex: clipIndex ?? _chunksAnalysed,
      ),
    );
    unawaited(_drainCoachFeedbackQueue());
  }

  void _flushPendingCoachFeedback() {
    final pending = _pendingCoachFeedback;
    if (pending == null || pending.clipIndex >= _chunksSent) return;
    _pendingCoachFeedback = null;
    unawaited(
      _showCoachFeedback(
        pending.text,
        mood: pending.mood,
        clipIndex: pending.clipIndex,
      ),
    );
  }

  Future<void> _drainCoachFeedbackQueue({bool allowWhileEnding = false}) async {
    if (_coachFeedbackActive) {
      while (_coachFeedbackActive && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (_coachFeedbackQueue.isEmpty) return;
    }
    _coachFeedbackActive = true;
    try {
      while (_coachFeedbackQueue.isNotEmpty &&
          mounted &&
          (!_ending || allowWhileEnding)) {
        final feedback = _coachFeedbackQueue.removeFirst();
        _updateCaption(feedback.text);
        await _saveMarker(feedback.text);
        await _speakCoachFeedback(
          feedback.text,
          mood: feedback.mood,
          allowWhileEnding: allowWhileEnding,
        );
      }
    } finally {
      _coachFeedbackActive = false;
    }
  }

  Future<void> _speakCoachFeedback(
    String text, {
    String mood = '',
    bool allowWhileEnding = false,
  }) async {
    if (_ending && !allowWhileEnding) return;
    try {
      await _applyCoachVoiceStyle(mood);
      await _speakCoachLine(text);
    } catch (_) {}
  }

  Future<void> _waitForPendingFeedbackUploads() async {
    final deadline = DateTime.now().add(const Duration(seconds: 28));
    while (mounted &&
        DateTime.now().isBefore(deadline) &&
        (_feedbackUploadInFlight || _queuedFeedbackChunk != null)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  String _cleanCoachTranscript(String raw) {
    return raw
        .replaceFirst(
          RegExp(
            r'^\s*[\[\(\{,\s]*(praise|correction)?[\]\)\},\s:;\-–—]*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

  Future<void> _speakCoachLine(String text) async {
    final completer = Completer<void>();
    _ttsCompletion = completer;
    await _tts.speak(text);
    final seconds = (text.length / 8).ceil().clamp(4, 45);
    try {
      await completer.future.timeout(Duration(seconds: seconds));
    } catch (_) {
      final active = _ttsCompletion;
      if (active == completer) {
        _ttsCompletion = null;
      }
    }
  }

  Future<void> _applyCoachVoiceStyle(String mood) async {
    if (mood == 'praise') {
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.02);
      await _tts.setVolume(1.0);
      return;
    }
    if (mood == 'correction') {
      await _tts.setSpeechRate(0.56);
      await _tts.setPitch(0.82);
      await _tts.setVolume(1.0);
      return;
    }
    await _tts.setSpeechRate(0.50);
    await _tts.setPitch(0.95);
    await _tts.setVolume(1.0);
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
    SystemSound.play(SystemSoundType.click);
    _socketReconnectTimer?.cancel();
    _frameTimer?.cancel();
    _coachFeedbackQueue.clear();
    _allowFinalFeedbackDrain = false;
    await _tts.stop();

    final controller = _camera;
    if (controller != null) {
      try {
        if (controller.value.isRecordingVideo) {
          await controller.stopVideoRecording();
          _currentClipStartedAt = null;
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
    _coachFeedbackQueue.clear();
    _pendingCoachFeedback = null;
    _queuedFeedbackChunk = null;
    _chunksSent = 0;
    _chunksAnalysed = 0;
    _currentClipStartedAt = null;
    _chunkRestartScheduled = false;
    _coachProcessing = false;
    _feedbackUploadInFlight = false;
    _allowFinalFeedbackDrain = false;
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
          _currentClipStartedAt = null;
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
          _currentClipStartedAt = DateTime.now();
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
    _allowFinalFeedbackDrain = true;
    SystemSound.play(SystemSoundType.click);
    _socketReconnectTimer?.cancel();
    _frameTimer?.cancel();
    if (mounted) {
      setState(() {
        _status = 'Finishing coach feedback';
      });
    }

    final controller = _camera;
    String? tempVideoPath;
    if (controller != null && controller.value.isRecordingVideo) {
      if (_paused) {
        try {
          await controller.resumeVideoRecording();
          _currentClipStartedAt = DateTime.now();
        } catch (_) {}
      }
      final file = await controller.stopVideoRecording();
      tempVideoPath = file.path;
      _recordedChunkPaths.add(file.path);
    }
    _socket?.add(jsonEncode({'type': 'stop'}));
    await _socket?.close();
    await _waitForPendingFeedbackUploads();
    await _drainCoachFeedbackQueue(allowWhileEnding: true);
    await _tts.stop();
    _allowFinalFeedbackDrain = false;
    if (user != null) {
      await PremiumService.refreshLiveEdgeBalance(uid: user.uid);
      PremiumService.premiumNotifier.forceNotify();
    }

    final reviewSource = _recordedChunkPaths.isNotEmpty
        ? _recordedChunkPaths.first
        : tempVideoPath;
    if (reviewSource != null && _recordedPath != null) {
      await File(reviewSource).copy(_recordedPath!);
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
    _coachFeedbackQueue.clear();
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
          if (_connectError == null && !_ending)
            Positioned(
              left: 18,
              right: 18,
              top: 84 + MediaQuery.of(context).padding.top,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _paused
                            ? Colors.amberAccent
                            : const Color(0xFFFF3B30),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_paused
                                    ? Colors.amberAccent
                                    : const Color(0xFFFF3B30))
                                .withValues(alpha: 0.65),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _paused
                            ? 'Paused'
                            : _coachProcessing
                                ? 'Coach analysing clip $_chunksSent'
                                : _chunksSent == 0
                                    ? 'Live: observing first 10 seconds'
                                    : 'Live: clips $_chunksSent, feedback $_chunksAnalysed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFF00E5FF),
                      size: 18,
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
                if (_latestCaption == null && _connectError == null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _chunksSent == 0
                                ? 'CrickNova Coach is watching your first 10 seconds...'
                                : 'Coach is reading your movement and preparing feedback...',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.3,
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
