import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';
import 'package:google_fonts/google_fonts.dart';

import 'review_player_screen.dart';
import '../theme/crickx_colors.dart';

String edgeSavedReviewsBoxName(String uid) => 'edge_saved_reviews_$uid';

class EdgeSavedReviewsScreen extends StatefulWidget {
  const EdgeSavedReviewsScreen({super.key, required this.uid});

  final String uid;

  @override
  State<EdgeSavedReviewsScreen> createState() => _EdgeSavedReviewsScreenState();
}

class _EdgeSavedReviewsScreenState extends State<EdgeSavedReviewsScreen> {
  late Future<Box> _boxFuture;
  Box? _box;

  @override
  void initState() {
    super.initState();
    _boxFuture = _openBox();
  }

  Future<Box> _openBox() async {
    final box = await Hive.openBox(edgeSavedReviewsBoxName(widget.uid));
    _box = box;
    return box;
  }

  List<Map<String, dynamic>> _entriesFrom(Box box) {
    return box.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.cast()))
        .toList()
        .reversed
        .toList();
  }

  Future<void> _refresh() async {
    await _box?.flush();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Saved Edge Reviews'),
      ),
      body: FutureBuilder<Box>(
        future: _boxFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: CrickXColors.limeSpark),
            );
          }
          final box = snapshot.data!;
          final entries = _entriesFrom(box);
          if (entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(
                    child: Text(
                      'No saved CricX Edge reviews yet.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _SavedReviewCard(
                  entry: entry,
                  onOpenVideo: () {
                    final path = entry['video_path']?.toString() ?? '';
                    final sessionId = entry['session_id']?.toString() ?? '';
                    final sourceLanguage =
                        entry['source_language']?.toString() ?? 'English';
                    if (path.isEmpty || !File(path).existsSync()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Saved video file is not available.'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReviewPlayerScreen(
                          videoPath: path,
                          sessionId: sessionId,
                          sourceLanguage: sourceLanguage,
                        ),
                      ),
                    );
                  },
                  onOpenText: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            EdgeSavedReviewDetailScreen(entry: entry),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class EdgeSavedReviewDetailScreen extends StatefulWidget {
  const EdgeSavedReviewDetailScreen({super.key, required this.entry});

  final Map<String, dynamic> entry;

  @override
  State<EdgeSavedReviewDetailScreen> createState() =>
      _EdgeSavedReviewDetailScreenState();
}

class _EdgeSavedReviewDetailScreenState
    extends State<EdgeSavedReviewDetailScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  List<Map<String, dynamic>> get _captions {
    final raw = (widget.entry['captions'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.cast()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final text = _captions
        .map((item) => item['note']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .join('. ');
    if (text.isEmpty) return;
    if (mounted) setState(() => _speaking = true);
    await _tts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.entry['mode']?.toString() ?? 'saved_review';
    final language = widget.entry['target_language']?.toString() ?? 'Original';
    final createdAt = DateTime.tryParse(
      widget.entry['created_at']?.toString() ?? '',
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          mode == 'cc_voice' ? 'Saved CC + Voice' : 'Saved Video + CC',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: _speaking ? 'Stop voice' : 'Play saved voice',
            onPressed: _captions.isEmpty ? null : _toggleVoice,
            icon: Icon(
              _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              color: CrickXColors.limeSpark,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CrickXColors.graphiteBg,
              border: Border(bottom: BorderSide(color: CrickXColors.graphiteBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  language == 'Original'
                      ? 'Original coach captions'
                      : 'Generated $language captions',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _captions.isEmpty
                ? Center(
                    child: Text(
                      'No saved caption lines available.',
                      style: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _captions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _captions[index];
                      final second =
                          (item['offset_seconds'] as num?)?.toInt() ?? 0;
                      final note = item['note']?.toString() ?? '';
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: CrickXColors.graphite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$second s',
                              style: GoogleFonts.poppins(
                                color: CrickXColors.limeSpark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              note,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SavedReviewCard extends StatelessWidget {
  const _SavedReviewCard({
    required this.entry,
    required this.onOpenVideo,
    required this.onOpenText,
  });

  final Map<String, dynamic> entry;
  final VoidCallback onOpenVideo;
  final VoidCallback onOpenText;

  @override
  Widget build(BuildContext context) {
    final mode = entry['mode']?.toString() ?? 'saved_review';
    final language = entry['target_language']?.toString() ?? 'Original';
    final createdAt = DateTime.tryParse(entry['created_at']?.toString() ?? '');
    final preview = ((entry['captions'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item['note']?.toString().trim() ?? '')
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: CrickXColors.limeSpark.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: CrickXColors.limeSpark.withOpacity(0.3)),
                ),
                child: Text(
                  mode == 'cc_voice' ? 'CC + Voice' : 'Video + CC',
                  style: GoogleFonts.poppins(
                    color: CrickXColors.limeSpark,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              if (createdAt != null)
                Text(
                  '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                  style: GoogleFonts.poppins(color: const Color(0xFF71717A), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            language == 'Original' ? 'Original captions' : '$language captions',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: const Color(0xFFA1A1AA),
                height: 1.4,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenText,
                  icon: const Icon(Icons.notes_rounded),
                  label: Text('Open Saved', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CrickXColors.limeSpark,
                    side: BorderSide(color: CrickXColors.limeSpark),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenVideo,
                  icon: Icon(Icons.play_circle_fill_rounded, color: CrickXColors.onLime),
                  label: Text('Open Review', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: CrickXColors.onLime)),
                  style: FilledButton.styleFrom(
                    backgroundColor: CrickXColors.limeSpark,
                    foregroundColor: CrickXColors.onLime,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
