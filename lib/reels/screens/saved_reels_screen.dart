import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../../theme/crickx_colors.dart';
import 'reels_screen.dart';

class SavedReelsScreen extends StatefulWidget {
  const SavedReelsScreen({super.key});

  @override
  State<SavedReelsScreen> createState() => _SavedReelsScreenState();
}

class _SavedReelsScreenState extends State<SavedReelsScreen> {
  List<ReelModel> _savedReels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedReels();
  }

  Future<void> _loadSavedReels() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final reels = await ReelService.getSavedReels(userId: uid);
      if (mounted) {
        setState(() {
          _savedReels = reels;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("LOAD_SAVED_REELS_ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openReelDetail(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReelsScreen(
          customReels: _savedReels,
          initialIndex: initialIndex,
          screenTitle: "Saved Reels",
        ),
      ),
    ).then((_) => _loadSavedReels());
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
          "Saved Reels",
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(CrickXColors.limeSpark),
              ),
            )
          : _savedReels.isEmpty
              ? Center(
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
                          child: const Icon(Icons.bookmark_outline_rounded, color: CrickXColors.limeSpark, size: 48),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No Saved Reels",
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Save your favorite batting shots and bowling masterclasses to rewatch anytime.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _savedReels.length,
                  itemBuilder: (context, index) {
                    final reel = _savedReels[index];
                    return GestureDetector(
                      onTap: () => _openReelDetail(index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: CrickXColors.graphite,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (reel.thumbnailUrl != null && reel.thumbnailUrl!.isNotEmpty)
                                Image.network(
                                  reel.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _posterFallback(),
                                )
                              else
                                _posterFallback(),

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
                                      const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444), size: 12),
                                      const SizedBox(width: 3),
                                      Text(
                                        "${reel.likesCount}",
                                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
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

  Widget _posterFallback() {
    return Container(
      color: CrickXColors.graphiteElevated,
      alignment: Alignment.center,
      child: const Icon(Icons.sports_cricket_rounded, color: Colors.white24, size: 28),
    );
  }
}
