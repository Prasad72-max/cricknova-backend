import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../services/reel_storage_service.dart';
import '../services/reel_ai_service.dart';
import '../../theme/crickx_colors.dart';

class ReelUploadScreen extends StatefulWidget {
  final File? initialVideoFile;

  const ReelUploadScreen({super.key, this.initialVideoFile});

  @override
  State<ReelUploadScreen> createState() => _ReelUploadScreenState();
}

class _ReelUploadScreenState extends State<ReelUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagsController = TextEditingController(text: "#cricket #training #cricknova");

  File? _videoFile;
  VideoPlayerController? _previewController;
  bool _isPreviewInitialized = false;

  ReelVisibility _selectedVisibility = ReelVisibility.public;
  bool _runAiAnalysis = true;

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatusMessage = "";

  @override
  void initState() {
    super.initState();
    if (widget.initialVideoFile != null) {
      _setVideo(widget.initialVideoFile!);
    } else {
      _pickVideo(ImageSource.gallery);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _hashtagsController.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 90),
      );
      if (picked != null) {
        _setVideo(File(picked.path));
      } else if (_videoFile == null && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("PICK_VIDEO_ERROR: $e");
    }
  }

  Future<void> _setVideo(File file) async {
    _previewController?.dispose();
    setState(() {
      _videoFile = file;
      _isPreviewInitialized = false;
    });

    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();

    if (mounted) {
      setState(() {
        _previewController = controller;
        _isPreviewInitialized = true;
      });
    }
  }

  List<String> _extractHashtags(String text) {
    final tags = <String>[];
    final parts = text.split(RegExp(r'[\s,]+'));
    for (final p in parts) {
      final clean = p.replaceAll('#', '').trim();
      if (clean.isNotEmpty) {
        tags.add(clean.toLowerCase());
      }
    }
    return tags;
  }

  Future<void> _handlePublish() async {
    if (_videoFile == null || _isUploading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to publish reels.")),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.05;
      _uploadStatusMessage = "Uploading video to Firebase Storage...";
    });

    try {
      final reelId = "reel_${DateTime.now().millisecondsSinceEpoch}_${user.uid.substring(0, 5)}";
      final username = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? "Player");

      // 1. Upload video to Firebase Storage
      final uploadResult = await ReelStorageService.uploadReelMedia(
        userId: user.uid,
        reelId: reelId,
        videoFile: _videoFile!,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _uploadProgress = 0.05 + (p * 0.65);
            });
          }
        },
      );

      // 2. Run AI Analysis if selected
      ReelAiAnalysis? aiResult;
      if (_runAiAnalysis) {
        if (mounted) {
          setState(() {
            _uploadProgress = 0.75;
            _uploadStatusMessage = "CricX AI is analyzing cricket technique...";
          });
        }
        aiResult = await ReelAiService.analyzeReelVideo(_videoFile!);
      }

      // 3. Create Reel document in Firestore
      if (mounted) {
        setState(() {
          _uploadProgress = 0.95;
          _uploadStatusMessage = "Publishing to Reels feed...";
        });
      }

      final reel = ReelModel(
        reelId: reelId,
        userId: user.uid,
        username: username,
        userPhotoUrl: user.photoURL,
        videoUrl: uploadResult.reelVideoUrl,
        originalVideoUrl: uploadResult.originalVideoUrl,
        thumbnailUrl: uploadResult.thumbnailUrl,
        caption: _captionController.text.trim(),
        hashtags: _extractHashtags(_hashtagsController.text),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        visibility: _selectedVisibility,
        status: ReelStatus.ready,
        aiAnalysis: aiResult,
      );

      await ReelService.createReel(reel);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Reel published successfully!"),
            backgroundColor: CrickXColors.graphiteElevated,
          ),
        );
        Navigator.pop(context, reel);
      }
    } catch (e) {
      debugPrint("PUBLISH_REEL_ERROR: $e");
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrickXColors.graphiteBg,
      appBar: AppBar(
        backgroundColor: CrickXColors.graphiteBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "New Cricket Reel",
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_isUploading)
            TextButton(
              onPressed: _videoFile != null ? _handlePublish : null,
              child: Text(
                "Share",
                style: GoogleFonts.poppins(
                  color: _videoFile != null ? CrickXColors.limeSpark : Colors.white38,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: _isUploading
          ? _buildUploadingProgressView()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Video Preview & Change Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 100,
                          height: 150,
                          color: CrickXColors.graphiteElevated,
                          child: (_previewController != null && _isPreviewInitialized)
                              ? FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _previewController!.value.size.width,
                                    height: _previewController!.value.size.height,
                                    child: VideoPlayer(_previewController!),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.videocam_rounded, color: Colors.white38, size: 36),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Video Selected",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "Vertical cricket action videos (up to 90s) give the best AI tracking experience.",
                              style: TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: CrickXColors.graphiteBorder),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => _pickVideo(ImageSource.gallery),
                              icon: const Icon(Icons.change_circle_outlined, size: 16),
                              label: const Text("Change Video", style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Caption Input
                  Text("Caption", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: CrickXColors.graphiteBorder),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _captionController,
                      maxLines: 3,
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Share your cricket shot, delivery stride, or practice drills...",
                        hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12.5),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Hashtags Input
                  Text("Hashtags", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: CrickXColors.graphiteBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: TextField(
                      controller: _hashtagsController,
                      style: GoogleFonts.poppins(color: CrickXColors.limeSpark, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "#coverdrive #yorker #batting",
                        hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12.5),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // AI Technique Analysis Switch
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CrickXColors.graphiteBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CrickXColors.limeSpark.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: CrickXColors.limeSpark, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Analyze Technique with AI",
                                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              const Text(
                                "Estimates ball/bat speed, swing angle, and coaching feedback badge.",
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _runAiAnalysis,
                          activeColor: CrickXColors.limeSpark,
                          onChanged: (val) => setState(() => _runAiAnalysis = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Visibility Options
                  Text("Who can watch this Reel?", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: CrickXColors.graphite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CrickXColors.graphiteBorder),
                    ),
                    child: Column(
                      children: [
                        _buildVisibilityTile(
                          title: "Public",
                          subtitle: "Anyone on CricX can watch and discover",
                          value: ReelVisibility.public,
                          icon: Icons.public_rounded,
                        ),
                        Divider(color: CrickXColors.graphiteBorder, height: 1),
                        _buildVisibilityTile(
                          title: "Followers",
                          subtitle: "Only players who follow you can watch",
                          value: ReelVisibility.followers,
                          icon: Icons.people_alt_rounded,
                        ),
                        Divider(color: CrickXColors.graphiteBorder, height: 1),
                        _buildVisibilityTile(
                          title: "Private",
                          subtitle: "Only visible in your Profile",
                          value: ReelVisibility.private,
                          icon: Icons.lock_outline_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CrickXColors.limeSpark,
                        foregroundColor: CrickXColors.onLime,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _handlePublish,
                      child: Text(
                        "Share Cricket Reel",
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: CrickXColors.onLime),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildVisibilityTile({
    required String title,
    required String subtitle,
    required ReelVisibility value,
    required IconData icon,
  }) {
    final selected = _selectedVisibility == value;
    return RadioListTile<ReelVisibility>(
      value: value,
      groupValue: _selectedVisibility,
      activeColor: CrickXColors.limeSpark,
      onChanged: (val) => setState(() => _selectedVisibility = val ?? ReelVisibility.public),
      title: Row(
        children: [
          Icon(icon, size: 16, color: selected ? CrickXColors.limeSpark : Colors.white70),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    );
  }

  Widget _buildUploadingProgressView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CrickXColors.limeSpark.withOpacity(0.15),
              ),
              child: const Icon(Icons.cloud_upload_rounded, color: CrickXColors.limeSpark, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              "Publishing Reel",
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _uploadStatusMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12.5),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 6,
                backgroundColor: CrickXColors.graphiteElevated,
                valueColor: const AlwaysStoppedAnimation<Color>(CrickXColors.limeSpark),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "${(_uploadProgress * 100).toInt()}%",
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
