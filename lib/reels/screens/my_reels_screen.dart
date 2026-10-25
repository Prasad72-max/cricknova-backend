import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../../theme/crickx_colors.dart';
import 'reel_upload_screen.dart';
import 'reels_screen.dart';

class MyReelsScreen extends StatefulWidget {
  const MyReelsScreen({super.key});

  @override
  State<MyReelsScreen> createState() => _MyReelsScreenState();
}

class _MyReelsScreenState extends State<MyReelsScreen> {
  List<ReelModel> _myReels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyReels();
  }

  Future<void> _loadMyReels() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final reels = await ReelService.getMyReels(userId: uid);
      if (mounted) {
        setState(() {
          _myReels = reels;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("LOAD_MY_REELS_ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openReelDetail(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReelsScreen(
          customReels: _myReels,
          initialIndex: initialIndex,
          screenTitle: "My Cricket Reels",
        ),
      ),
    ).then((_) => _loadMyReels());
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
          "My Reels",
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: CrickXColors.limeSpark, size: 28),
            onPressed: () async {
              final created = await Navigator.push<ReelModel?>(
                context,
                MaterialPageRoute(builder: (_) => const ReelUploadScreen()),
              );
              if (created != null) _loadMyReels();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(CrickXColors.limeSpark),
              ),
            )
          : _myReels.isEmpty
              ? _buildEmptyView()
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _myReels.length,
                  itemBuilder: (context, index) {
                    final reel = _myReels[index];
                    return GestureDetector(
                      onTap: () => _openReelDetail(index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: CrickXColors.graphite,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Background poster or dark fallback
                              if (reel.thumbnailUrl != null && reel.thumbnailUrl!.isNotEmpty)
                                Image.network(
                                  reel.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _posterFallback(reel),
                                )
                              else
                                _posterFallback(reel),

                              // Bottom info bar (views + likes)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.85),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.play_arrow_outlined, color: Colors.white70, size: 14),
                                      const SizedBox(width: 2),
                                      Text(
                                        "${reel.viewsCount}",
                                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // AI Badge if analyzed
                              if (reel.aiAnalysis != null)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: CrickXColors.limeSpark,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.auto_awesome_rounded, color: CrickXColors.onLime, size: 10),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _posterFallback(ReelModel reel) {
    return Container(
      color: CrickXColors.graphiteElevated,
      alignment: Alignment.center,
      child: const Icon(Icons.sports_cricket_rounded, color: Colors.white24, size: 28),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CrickXColors.graphite,
                shape: BoxShape.circle,
                border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
              ),
              child: const Icon(Icons.video_library_outlined, color: CrickXColors.limeSpark, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              "No Reels Yet",
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              "Be the first to upload your cricket journey, shots, and bowling technique.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CrickXColors.limeSpark,
                foregroundColor: CrickXColors.onLime,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              ),
              onPressed: () async {
                final created = await Navigator.push<ReelModel?>(
                  context,
                  MaterialPageRoute(builder: (_) => const ReelUploadScreen()),
                );
                if (created != null) _loadMyReels();
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text("Upload First Reel", style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: CrickXColors.onLime)),
            ),
          ],
        ),
      ),
    );
  }
}
