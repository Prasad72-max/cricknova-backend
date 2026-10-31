import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:hive/hive.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ai/ai_coach_screen.dart';
import '../theme/crickx_colors.dart';
import 'edge_saved_reviews_screen.dart';

class ReviewPlayerScreen extends StatefulWidget {
  const ReviewPlayerScreen({
    super.key,
    required this.videoPath,
    required this.sessionId,
    this.sourceLanguage = 'English',
  });

  final String videoPath;
  final String sessionId;
  final String sourceLanguage;

  @override
  State<ReviewPlayerScreen> createState() => _ReviewPlayerScreenState();
}

class _ReviewPlayerScreenState extends State<ReviewPlayerScreen> {
  final FlutterTts _tts = FlutterTts();
  VideoPlayerController? _controller;
  Timer? _ticker;
  List<_Marker> _markers = const [];
  List<_Marker> _displayMarkers = const [];
  _Marker? _activeMarker;
  String _targetLanguage = 'Original';
  bool _translating = false;
  bool _speaking = false;
  bool _saving = false;
  bool _savingCcVoice = false;
  String _languageSearch = '';
  String? _generatingLanguage;
  final Map<String, List<_Marker>> _generatedCaptions = {};

  static const Map<String, TranslateLanguage> _translationLanguages = {
    'English': TranslateLanguage.english,
    'Hindi': TranslateLanguage.hindi,
    'Marathi': TranslateLanguage.marathi,
    'Spanish': TranslateLanguage.spanish,
    'French': TranslateLanguage.french,
    'German': TranslateLanguage.german,
    'Portuguese': TranslateLanguage.portuguese,
    'Arabic': TranslateLanguage.arabic,
    'Bengali': TranslateLanguage.bengali,
    'Tamil': TranslateLanguage.tamil,
    'Telugu': TranslateLanguage.telugu,
    'Urdu': TranslateLanguage.urdu,
    'Indonesian': TranslateLanguage.indonesian,
    'Japanese': TranslateLanguage.japanese,
    'Korean': TranslateLanguage.korean,
    'Chinese': TranslateLanguage.chinese,
  };

  static const Map<String, String> _ttsLocales = {
    'English': 'en-IN',
    'Hindi': 'hi-IN',
    'Marathi': 'mr-IN',
    'Spanish': 'es-ES',
    'French': 'fr-FR',
    'German': 'de-DE',
    'Portuguese': 'pt-BR',
    'Arabic': 'ar-SA',
    'Bengali': 'bn-IN',
    'Tamil': 'ta-IN',
    'Telugu': 'te-IN',
    'Urdu': 'ur-PK',
    'Indonesian': 'id-ID',
    'Japanese': 'ja-JP',
    'Korean': 'ko-KR',
    'Chinese': 'zh-CN',
  };

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
      _displayMarkers = List<_Marker>.from(_markers);
    }

    final file = File(widget.videoPath);
    if (widget.videoPath.isNotEmpty && file.existsSync()) {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.play();
      _controller = controller;
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _syncMarker(),
      );
    }
    if (mounted) setState(() {});
  }

  void _syncMarker() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final seconds = controller.value.position.inSeconds;
    final match = _displayMarkers.cast<_Marker?>().firstWhere(
      (marker) => marker != null && (seconds - marker.offsetSeconds).abs() <= 2,
      orElse: () => null,
    );
    if (match != _activeMarker && mounted) {
      setState(() => _activeMarker = match);
    }
  }

  TranslateLanguage _sourceTranslateLanguage() {
    return _translationLanguages[widget.sourceLanguage] ??
        TranslateLanguage.english;
  }

  Future<void> _translateTo(String language) async {
    if (language == 'Original') {
      setState(() {
        _targetLanguage = language;
        _generatingLanguage = null;
        _displayMarkers = List<_Marker>.from(_markers);
        _activeMarker = null;
      });
      return;
    }
    final target = _translationLanguages[language];
    if (target == null || _translating) return;

    final cached = _generatedCaptions[language];
    if (cached != null) {
      setState(() {
        _targetLanguage = language;
        _generatingLanguage = null;
        _displayMarkers = List<_Marker>.from(cached);
        _activeMarker = null;
      });
      return;
    }

    setState(() {
      _generatingLanguage = language;
      _translating = true;
    });

    final translator = OnDeviceTranslator(
      sourceLanguage: _sourceTranslateLanguage(),
      targetLanguage: target,
    );
    try {
      final translated = <_Marker>[];
      for (final marker in _markers) {
        translated.add(
          _Marker(
            offsetSeconds: marker.offsetSeconds,
            note: await translator.translateText(marker.note),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _generatedCaptions[language] = List<_Marker>.from(translated);
          _targetLanguage = language;
          _generatingLanguage = null;
          _displayMarkers = translated;
          _activeMarker = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$language CC is still preparing. Try again in a moment.',
            ),
          ),
        );
      }
    } finally {
      await translator.close();
      if (mounted) {
        setState(() {
          _translating = false;
          _generatingLanguage = null;
        });
      }
    }
  }

  Future<void> _toggleVoice() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final text = _displayMarkers.map((marker) => marker.note).join('. ');
    if (text.trim().isEmpty) return;
    final language = _targetLanguage == 'Original'
        ? widget.sourceLanguage
        : _targetLanguage;
    await _tts.setLanguage(_ttsLocales[language] ?? 'en-IN');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(0.95);
    await _tts.setVolume(1);
    if (mounted) setState(() => _speaking = true);
    await _tts.speak(text);
  }

  String get _captionHeading {
    final generating = _generatingLanguage;
    if (_translating && generating != null) {
      return 'Generating $generating CC...';
    }
    if (_targetLanguage == 'Original') {
      return 'Original AI Captions';
    }
    return 'Generated $_targetLanguage CC';
  }

  String get _voiceLabel {
    if (_targetLanguage == 'Original') {
      return 'Play original coach voice';
    }
    return 'Play $_targetLanguage coach voice';
  }

  List<String> get _filteredLanguages {
    final query = _languageSearch.trim().toLowerCase();
    final languages = ['Original', ..._translationLanguages.keys];
    if (query.isEmpty) return languages;
    return languages
        .where((language) => language.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openLanguagePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CrickXColors.graphiteBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final languages = _filteredLanguages;
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: CrickXColors.graphiteBorder,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Text(
                      'Choose CC Language',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      style: GoogleFonts.poppins(color: Colors.white),
                      onChanged: (value) =>
                          setSheetState(() => _languageSearch = value),
                      decoration: InputDecoration(
                        hintText: 'Search language...',
                        hintStyle: GoogleFonts.poppins(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: CrickXColors.limeSpark,
                        ),
                        filled: true,
                        fillColor: CrickXColors.graphite,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: CrickXColors.limeSpark, width: 1.2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: languages.length,
                        itemBuilder: (context, index) {
                          final language = languages[index];
                          final selected =
                              language.toLowerCase() ==
                              _targetLanguage.toLowerCase();
                          return ListTile(
                            onTap: () => Navigator.pop(context, language),
                            leading: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.language_rounded,
                              color: selected ? CrickXColors.limeSpark : Colors.white70,
                            ),
                            title: Text(
                              language,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.done_rounded,
                                    color: CrickXColors.limeSpark,
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    setState(() => _languageSearch = '');
    if (selected != null) {
      unawaited(_translateTo(selected));
    }
  }

  Future<void> _saveVideoWithCaptions() async {
    if (_saving || widget.videoPath.isEmpty) return;
    final file = File(widget.videoPath);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved video file is not available.')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ImageGallerySaverPlus.saveFile(
        widget.videoPath,
        name: p.basenameWithoutExtension(widget.videoPath),
      );
      final saved =
          result is Map &&
          (result['isSuccess'] == true ||
              result['success'] == true ||
              result['filePath'] != null);
      if (!saved) {
        throw StateError('Gallery saver returned $result');
      }
      await _saveReviewToHive(mode: 'video_cc');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Video + CC saved to gallery and CricX Edge Saved.',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('CricX Edge review save failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save the video. Check photo/video permission and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCcVoiceToHive() async {
    if (_savingCcVoice) return;
    setState(() => _savingCcVoice = true);
    try {
      await _saveReviewToHive(mode: 'cc_voice');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CC + Voice saved inside CricX Edge Saved.'),
          ),
        );
      }
    } catch (error) {
      debugPrint('CricX Edge CC + Voice save failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save CC + Voice. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCcVoice = false);
    }
  }

  Future<void> _saveReviewToHive({required String mode}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User not signed in');
    }
    final box = await Hive.openBox(edgeSavedReviewsBoxName(user.uid));
    final record = <String, dynamic>{
      'id': '${DateTime.now().millisecondsSinceEpoch}_$mode',
      'mode': mode,
      'session_id': widget.sessionId,
      'video_path': widget.videoPath,
      'source_language': widget.sourceLanguage,
      'target_language': _targetLanguage,
      'created_at': DateTime.now().toIso8601String(),
      'captions': _displayMarkers
          .map(
            (marker) => {
              'offset_seconds': marker.offsetSeconds,
              'note': marker.note,
            },
          )
          .toList(),
    };
    await box.put(record['id'], record);
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
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            'CricX Edge Review',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            indicatorColor: CrickXColors.limeSpark,
            labelColor: CrickXColors.limeSpark,
            unselectedLabelColor: Colors.white60,
            indicatorWeight: 2.5,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(Icons.video_library_rounded), text: 'Video + CC'),
              Tab(icon: Icon(Icons.closed_caption_rounded), text: 'CC + Voice'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildVideoTab(), _buildCaptionTab()]),
      ),
    );
  }

  Widget _buildVideoTab() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(color: CrickXColors.limeSpark),
      );
    }
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_activeMarker != null)
                        _MarkerCard(
                          marker: _activeMarker!,
                          onAskCoach: () => _askCoach(_activeMarker!),
                        ),
                      const SizedBox(height: 10),
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: CrickXColors.limeSpark,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: CrickXColors.limeSpark,
                              foregroundColor: CrickXColors.onLime,
                            ),
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
                              color: CrickXColors.onLime,
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: CrickXColors.limeSpark,
                              foregroundColor: CrickXColors.onLime,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _saving ? null : _saveVideoWithCaptions,
                            icon: Icon(Icons.download_rounded, color: CrickXColors.onLime),
                            label: Text(
                              _saving ? 'Saving...' : 'Save Video',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: CrickXColors.onLime),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: CrickXColors.graphiteBg,
              border: Border(top: BorderSide(color: CrickXColors.graphiteBorder)),
            ),
            child: _displayMarkers.isEmpty
                ? Center(
                    child: Text(
                      'No AI reply timeline available yet.',
                      style: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: CrickXColors.limeSpark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AI Reply Timeline',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _displayMarkers.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final marker = _displayMarkers[index];
                            final isActive =
                                _activeMarker?.offsetSeconds ==
                                    marker.offsetSeconds &&
                                _activeMarker?.note == marker.note;
                            return InkWell(
                              onTap: () {
                                controller.seekTo(
                                    Duration(seconds: marker.offsetSeconds),
                                );
                                controller.play();
                                setState(() => _activeMarker = marker);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? CrickXColors.graphiteElevated
                                      : CrickXColors.graphite,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive
                                        ? CrickXColors.limeSpark
                                        : CrickXColors.graphiteBorder,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'AI replied at ${marker.offsetSeconds}s',
                                      style: GoogleFonts.poppins(
                                        color: CrickXColors.limeSpark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      marker.note,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        height: 1.35,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _translating ? null : _openLanguagePicker,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.translate_rounded,
                          color: CrickXColors.limeSpark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generate language CC',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _translating && _generatingLanguage != null
                                    ? 'Generating ${_generatingLanguage!}...'
                                    : _targetLanguage == 'Original'
                                    ? 'Choose a language'
                                    : 'Generated $_targetLanguage',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _translating
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CrickXColors.limeSpark,
                                ),
                              )
                            : const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white70,
                              ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: CrickXColors.limeSpark,
                  foregroundColor: CrickXColors.onLime,
                ),
                tooltip: _voiceLabel,
                onPressed: _displayMarkers.isEmpty ? null : _toggleVoice,
                icon: Icon(
                  _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  color: CrickXColors.onLime,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: CrickXColors.limeSpark,
                  foregroundColor: CrickXColors.onLime,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _displayMarkers.isEmpty || _savingCcVoice
                    ? null
                    : _saveCcVoiceToHive,
                icon: Icon(Icons.bookmark_add_rounded, color: CrickXColors.onLime),
                label: Text(
                  _savingCcVoice ? 'Saving...' : 'Save',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: CrickXColors.onLime),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _captionHeading,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_translating)
          LinearProgressIndicator(color: CrickXColors.limeSpark),
        Expanded(
          child: _displayMarkers.isEmpty
              ? Center(
                  child: Text(
                    'No coach captions were recorded.',
                    style: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _displayMarkers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final marker = _displayMarkers[index];
                    return _MarkerCard(
                      marker: marker,
                      onAskCoach: () => _askCoach(_markers[index]),
                    );
                  },
                ),
        ),
      ],
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
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CrickXColors.graphiteBorder,
          width: 1.2,
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${marker.offsetSeconds}s',
            style: GoogleFonts.poppins(
              color: CrickXColors.limeSpark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            marker.note,
            style: GoogleFonts.poppins(
              color: Colors.white,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: CrickXColors.limeSpark,
            ),
            onPressed: onAskCoach,
            icon: const Icon(Icons.auto_awesome_rounded, color: CrickXColors.limeSpark),
            label: Text(
              'Ask CricX to Fix This',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: CrickXColors.limeSpark),
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
