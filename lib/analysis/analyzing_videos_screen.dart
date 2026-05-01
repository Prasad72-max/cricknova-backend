import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:video_player/video_player.dart';
import '../models/pending_video.dart';

import 'analysis_queue_store.dart';

List<Map<String, double>> _sanitizeTrajectory(dynamic rawPoints) {
  if (rawPoints is! List) return const [];
  final pts = <Map<String, double>>[];
  for (final e in rawPoints) {
    if (e is! Map) continue;
    final x = e["x"];
    final y = e["y"];
    if (x is! num || y is! num) continue;
    pts.add({
      "x": x.toDouble().clamp(0.0, 1.0),
      "y": y.toDouble().clamp(0.0, 1.0),
    });
  }
  return pts;
}

List<Map<String, double>> _unmirrorTrajectoryX(List<Map<String, double>> pts) {
  if (pts.isEmpty) return pts;
  double minX = 1.0;
  double maxX = 0.0;
  for (final p in pts) {
    final x = p["x"] ?? 0.5;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
  }
  return pts
      .map(
        (p) => {
          "x": (maxX - ((p["x"] ?? 0.5) - minX)).clamp(0.0, 1.0),
          "y": (p["y"] ?? 0.5).clamp(0.0, 1.0),
        },
      )
      .toList(growable: false);
}

int _detectBounceIndex(List<Map<String, double>> pts) {
  if (pts.length < 5) return -1;
  // Simple bounce heuristic: max Y along the path.
  int best = -1;
  double bestY = -1;
  for (int i = 2; i < pts.length - 2; i++) {
    final y = pts[i]["y"] ?? 0.0;
    if (y > bestY) {
      bestY = y;
      best = i;
    }
  }
  return best;
}

bool _isBadToken(String s) {
  final t = s.trim().toLowerCase();
  return t.isEmpty ||
      t == "none" ||
      t == "unknown" ||
      t == "unavailable" ||
      t == "na" ||
      t == "n/a" ||
      t == "null" ||
      t == "__" ||
      t == "straight" ||
      t == "no spin";
}

String _resolveSwing(Map<String, dynamic>? resultData) {
  final raw = resultData?["swing"];
  if (raw is String && !_isBadToken(raw)) {
    final lower = raw.trim().toLowerCase();
    if (lower.contains("out")) return "OUTSWING";
    if (lower.contains("in")) return "INSWING";
  }

  final pts = _unmirrorTrajectoryX(
    _sanitizeTrajectory(resultData?["trajectory"]),
  );
  if (pts.length < 2) return "INSWING";
  final bounce = _detectBounceIndex(pts);
  final pivot = bounce <= 0
      ? (pts.length ~/ 2)
      : bounce.clamp(1, pts.length - 2);

  double slopeForX(int start, int end) {
    final n = (end - start + 1);
    if (n <= 1) return 0.0;
    double sumT = 0.0;
    double sumX = 0.0;
    double sumTT = 0.0;
    double sumTX = 0.0;
    for (int i = 0; i < n; i++) {
      final t = i.toDouble();
      final x = pts[start + i]["x"] ?? 0.5;
      sumT += t;
      sumX += x;
      sumTT += (t * t);
      sumTX += (t * x);
    }
    final denom = (n * sumTT) - (sumT * sumT);
    if (denom.abs() < 1e-9) return 0.0;
    return ((n * sumTX) - (sumT * sumX)) / denom;
  }

  final preSlope = slopeForX(0, pivot);
  final overallDx = (pts.last["x"] ?? 0.5) - (pts.first["x"] ?? 0.5);
  const eps = 0.0008;
  final signal = preSlope.abs() < eps ? overallDx : preSlope;
  return signal >= 0 ? "OUTSWING" : "INSWING";
}

String _resolveSpin(Map<String, dynamic>? resultData) {
  final raw = resultData?["spin"];
  if (raw is String && !_isBadToken(raw)) {
    final lower = raw.trim().toLowerCase();
    if (lower.contains("leg")) return "LEG SPIN";
    if (lower.contains("off")) return "OFF SPIN";
  }

  final pts = _unmirrorTrajectoryX(
    _sanitizeTrajectory(resultData?["trajectory"]),
  );
  if (pts.length < 3) return "OFF SPIN";
  final bounce = _detectBounceIndex(pts);
  final pivot = bounce <= 0
      ? (pts.length ~/ 2)
      : bounce.clamp(1, pts.length - 2);

  double slopeForX(int start, int end) {
    final n = (end - start + 1);
    if (n <= 1) return 0.0;
    double sumT = 0.0;
    double sumX = 0.0;
    double sumTT = 0.0;
    double sumTX = 0.0;
    for (int i = 0; i < n; i++) {
      final t = i.toDouble();
      final x = pts[start + i]["x"] ?? 0.5;
      sumT += t;
      sumX += x;
      sumTT += (t * t);
      sumTX += (t * x);
    }
    final denom = (n * sumTT) - (sumT * sumT);
    if (denom.abs() < 1e-9) return 0.0;
    return ((n * sumTX) - (sumT * sumX)) / denom;
  }

  final preSlope = slopeForX(0, pivot);
  final postSlope = slopeForX(pivot, pts.length - 1);
  final curve = postSlope - preSlope;
  const eps = 0.0008;
  final signal = curve.abs() < eps ? postSlope : curve;
  return signal >= 0 ? "LEG SPIN" : "OFF SPIN";
}

class AnalyzingVideosScreen extends StatefulWidget {
  const AnalyzingVideosScreen({super.key});

  @override
  State<AnalyzingVideosScreen> createState() => _AnalyzingVideosScreenState();
}

class _AnalyzingVideosScreenState extends State<AnalyzingVideosScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _jobs = const [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadJobs();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadJobs());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadJobs();
    }
  }

  Future<void> _loadJobs() async {
    final jobs = await AnalysisQueueStore.loadJobs();

    // 🔥 Fetch from Hive pending box too
    final box = Hive.box<PendingVideo>('pending_videos');
    final pending = box.values
        .map(
          (v) => {
            'id': v.id,
            'title': v.localFilePath.split(RegExp(r'[\\/]')).last,
            'status': v.status == 'complete' ? 'ready' : 'processing',
            'discipline': 'training',
            'localFilePath': v.localFilePath,
            'resultData': v.resultData,
            'speedLabel': v.resultData?['speed_kmph'] ?? '0',
            'swing': _resolveSwing(v.resultData),
            'spin': _resolveSpin(v.resultData),
          },
        )
        .toList();

    // Combine and remove duplicates by ID
    final combinedMap = <String, Map<String, dynamic>>{};
    for (var j in jobs) {
      combinedMap[j['id'].toString()] = j;
    }
    for (var p in pending) {
      combinedMap[p['id'].toString()] = p;
    }

    if (!mounted) return;
    setState(() {
      _jobs = combinedMap.values.toList();
      _jobs.sort((a, b) => b['id'].toString().compareTo(a['id'].toString()));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        title: const Text("Analyzing Vid"),
      ),
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF121821).withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Elite Processing Queue",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Slow analyses land here while CrickNova keeps working in the background.",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: CircularProgressIndicator(color: Color(0xFF00C2FF)),
                ),
              )
            else if (_jobs.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF121821).withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.video_library_outlined,
                      color: Color(0xFF00C2FF),
                      size: 36,
                    ),
                    SizedBox(height: 12),
                    Text(
                      "No slow analyses right now.",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "When an upload takes longer than 15 seconds, it will show up here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.45),
                    ),
                  ],
                ),
              )
            else
              ..._jobs.map((job) => _AnalysisJobCard(job: job)),
          ],
        ),
      ),
    );
  }
}

class _AnalysisJobCard extends StatelessWidget {
  final Map<String, dynamic> job;

  const _AnalysisJobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final status = (job['status'] ?? 'processing').toString();
    final isReady = status == 'ready';
    final title = (job['title'] ?? 'Training Video').toString();
    final discipline = (job['discipline'] ?? 'batting').toString();
    final localFilePath = job['localFilePath']?.toString();
    final hasSavedVideo =
        localFilePath != null &&
        localFilePath.isNotEmpty &&
        File(localFilePath).existsSync();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isReady
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AnalysisResultScreen(jobId: job['id'].toString()),
                  ),
                );
              }
            : hasSavedVideo
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoredTrainingVideoScreen(
                      title: title,
                      filePath: localFilePath,
                    ),
                  ),
                );
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121821).withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isReady
                  ? const Color(0xFF00FF9D).withValues(alpha: 0.32)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: isReady
                ? [
                    BoxShadow(
                      color: const Color(0xFF00C2FF).withValues(alpha: 0.14),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isReady
                              ? const [Color(0xFF183247), Color(0xFF10212D)]
                              : const [Color(0xFF1A212D), Color(0xFF121821)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    if (!isReady)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: const Icon(
                          Icons.sports_cricket_rounded,
                          color: Colors.white54,
                          size: 34,
                        ),
                      )
                    else
                      const Icon(
                        Icons.sports_cricket_rounded,
                        color: Color(0xFF00FF9D),
                        size: 34,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      discipline == 'bowling'
                          ? 'Bowling Analysis'
                          : 'Training Analysis',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isReady
                                ? const Color(
                                    0xFF00FF9D,
                                  ).withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isReady
                                  ? const Color(
                                      0xFF00FF9D,
                                    ).withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isReady)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Color(0xFF00C2FF),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF00FF9D),
                                  size: 14,
                                ),
                              const SizedBox(width: 8),
                              Text(
                                isReady ? 'Ready' : 'Analyzing...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isReady || hasSavedVideo)
                const Icon(Icons.chevron_right_rounded, color: Colors.white60),
            ],
          ),
        ),
      ),
    );
  }
}

class StoredTrainingVideoScreen extends StatefulWidget {
  final String title;
  final String filePath;

  const StoredTrainingVideoScreen({
    super.key,
    required this.title,
    required this.filePath,
  });

  @override
  State<StoredTrainingVideoScreen> createState() =>
      _StoredTrainingVideoScreenState();
}

class _StoredTrainingVideoScreenState extends State<StoredTrainingVideoScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      setState(() {
        _loading = false;
        _error = "Saved video not found.";
      });
      return;
    }

    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Could not open saved video.";
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Color(0xFF00C2FF))
            : _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white70))
            : controller == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(18),
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(controller),
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFF00C2FF),
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  controller.value.isPlaying
                                      ? controller.pause()
                                      : controller.play();
                                });
                              },
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: controller.value.isPlaying ? 0 : 1,
                                  duration: const Duration(milliseconds: 180),
                                  child: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white,
                                    size: 68,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class AnalysisResultScreen extends StatefulWidget {
  final String jobId;

  const AnalysisResultScreen({super.key, required this.jobId});

  @override
  State<AnalysisResultScreen> createState() => _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends State<AnalysisResultScreen> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  VideoPlayerController? _videoController;
  bool _videoInit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var job = await AnalysisQueueStore.getJob(widget.jobId);
    if (job == null && Hive.isBoxOpen('pending_videos')) {
      final pending = Hive.box<PendingVideo>(
        'pending_videos',
      ).get(widget.jobId);
      if (pending != null) {
        job = {
          'id': pending.id,
          'title': pending.localFilePath.split(RegExp(r'[\\/]')).last,
          'status': pending.status == 'complete' ? 'ready' : 'processing',
          'discipline': 'training',
          'localFilePath': pending.localFilePath,
          'resultData': pending.resultData,
          'speedLabel': pending.resultData?['speed_kmph'] ?? 'Unavailable',
          'swing': _resolveSwing(pending.resultData),
          'spin': _resolveSpin(pending.resultData),
        };
      }
    }
    if (!mounted) return;
    setState(() {
      _job = job;
      _loading = false;
    });

    final localFilePath = job?['localFilePath']?.toString();
    if (localFilePath == null || localFilePath.isEmpty) return;
    if (_videoInit) return;
    final file = File(localFilePath);
    if (!file.existsSync()) return;

    _videoInit = true;
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
      await controller.play();
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultData = _job?['resultData'];
    final result = resultData is Map
        ? Map<String, dynamic>.from(resultData)
        : const <String, dynamic>{};
    final drs = result['drs'];
    final drsDecision = drs is Map && drs['decision'] != null
        ? drs['decision'].toString().toUpperCase()
        : 'Unavailable';
    final localFilePath = _job?['localFilePath']?.toString();
    final hasSavedVideo =
        localFilePath != null &&
        localFilePath.isNotEmpty &&
        File(localFilePath).existsSync();
    final videoController = _videoController;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        foregroundColor: Colors.white,
        title: const Text("Analysis Result"),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C2FF)),
            )
          : _job == null
          ? const Center(
              child: Text(
                "Result not found.",
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF102536), Color(0xFF121821)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Your CrickNova result is ready",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (_job!['discipline'] ?? 'batting') == 'bowling'
                            ? 'Bowling analysis'
                            : 'Training analysis',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (hasSavedVideo)
                  _InlineVideoCard(
                    controller: videoController,
                    title: _job!['title']?.toString() ?? 'Training Video',
                    filePath: localFilePath,
                  ),
                if (hasSavedVideo) const SizedBox(height: 12),
                _ResultMetricCard(
                  label: 'Speed',
                  value: _job!['speedLabel']?.toString() ?? 'Unavailable',
                  accent: const Color(0xFF00C2FF),
                ),
                _ResultMetricCard(
                  label: 'Swing',
                  value: _job!['swing']?.toString() ?? 'Unavailable',
                  accent: const Color(0xFF00FF9D),
                ),
                _ResultMetricCard(
                  label: 'Spin',
                  value: _job!['spin']?.toString() ?? 'Unavailable',
                  accent: const Color(0xFFFFC857),
                ),
                _ResultMetricCard(
                  label: 'DRS',
                  value: drsDecision,
                  accent: const Color(0xFFFF6B6B),
                ),
              ],
            ),
    );
  }
}

class _InlineVideoCard extends StatelessWidget {
  final VideoPlayerController? controller;
  final String title;
  final String filePath;

  const _InlineVideoCard({
    required this.controller,
    required this.title,
    required this.filePath,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ready = c != null && c.value.isInitialized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: ready ? c.value.aspectRatio : (16 / 9),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(color: const Color(0xFF121821)),
                if (ready) VideoPlayer(c),
                if (ready)
                  VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF00C2FF),
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: ready
                          ? () {
                              c.value.isPlaying ? c.pause() : c.play();
                            }
                          : null,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: ready && c.value.isPlaying ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            ready
                                ? Icons.play_circle_fill_rounded
                                : Icons.hourglass_top_rounded,
                            color: Colors.white,
                            size: 68,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    StoredTrainingVideoScreen(title: title, filePath: filePath),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF121821).withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Row(
              children: [
                Icon(Icons.video_library_outlined, color: Color(0xFF00C2FF)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Open video full screen",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white60),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _ResultMetricCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF121821).withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.insights_rounded, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
