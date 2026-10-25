import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../widgets/reel_video_player.dart';
import '../widgets/reel_overlay.dart';
import '../widgets/reel_actions.dart';
import '../widgets/reel_comments_sheet.dart';
import '../widgets/reel_more_sheet.dart';
import '../widgets/ai_result_reel_sheet.dart';
import '../../theme/crickx_colors.dart';

enum CricketCategory {
  all,
  highlights,
  coaching,
}

class ReelsScreen extends StatefulWidget {
  final List<ReelModel>? customReels;
  final int initialIndex;
  final String? screenTitle;

  const ReelsScreen({
    super.key,
    this.customReels,
    this.initialIndex = 0,
    this.screenTitle,
  });

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isMuted = false;
  CricketCategory _selectedCategory = CricketCategory.all;

  List<ReelModel> _reels = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    if (widget.customReels != null) {
      _reels = List.from(widget.customReels!);
      _isLoading = false;
      _hasMore = false;
    } else {
      _fetchInitialReels();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause videos when app goes to background
      if (mounted) setState(() {});
    }
  }

  List<ReelModel> get _displayReels {
    switch (_selectedCategory) {
      case CricketCategory.highlights:
        return _reels.where((r) {
          final tags = r.hashtags.map((t) => t.toLowerCase()).toList();
          return tags.contains('highlights') ||
              tags.contains('international') ||
              tags.contains('match') ||
              r.caption.toLowerCase().contains('highlight') ||
              r.caption.toLowerCase().contains('cover drive') ||
              r.caption.toLowerCase().contains('pull shot') ||
              r.caption.toLowerCase().contains('yorker') ||
              r.caption.toLowerCase().contains('stumping') ||
              r.caption.toLowerCase().contains('run out') ||
              r.reelId.startsWith('crick_intl_');
        }).toList();

      case CricketCategory.coaching:
        return _reels.where((r) {
          final tags = r.hashtags.map((t) => t.toLowerCase()).toList();
          return tags.contains('coaching') ||
              tags.contains('drill') ||
              tags.contains('drills') ||
              tags.contains('technique') ||
              tags.contains('coach') ||
              r.caption.toLowerCase().contains('coach') ||
              r.caption.toLowerCase().contains('drill') ||
              r.caption.toLowerCase().contains('technique') ||
              r.caption.toLowerCase().contains('tip') ||
              r.reelId.startsWith('crick_coach_');
        }).toList();

      case CricketCategory.all:
      default:
        return _reels;
    }
  }

  Future<void> _fetchInitialReels() async {
    setState(() {
      _isLoading = true;
      _lastDoc = null;
    });

    try {
      final fetched = await ReelService.getOtherUsersVideoResults(limit: 10);

      if (mounted) {
        setState(() {
          _reels = fetched;
          _isLoading = false;
          _hasMore = fetched.length >= 10;
        });
      }
    } catch (e) {
      debugPrint("FETCH_REELS_ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreReels() async {
    if (_isLoadingMore || !_hasMore || widget.customReels != null) return;

    setState(() => _isLoadingMore = true);
    try {
      final fetched = await ReelService.getOtherUsersVideoResults(startAfterDoc: _lastDoc, limit: 10);

      if (mounted) {
        setState(() {
          _reels.addAll(fetched);
          _isLoadingMore = false;
          _hasMore = fetched.length >= 10;
        });
      }
    } catch (e) {
      debugPrint("FETCH_MORE_REELS_ERROR: $e");
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustomFeed = widget.customReels != null;
    final displayList = _displayReels;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full-Screen Vertical Video PageView
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (displayList.isEmpty)
            _buildEmptyState()
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: displayList.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                if (index >= displayList.length - 2) {
                  _fetchMoreReels();
                }
              },
              itemBuilder: (context, index) {
                final reel = displayList[index];
                final isActive = index == _currentIndex;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Full Screen Cricket Video Player
                    ReelVideoPlayer(
                      videoUrl: reel.videoUrl,
                      reelId: reel.reelId,
                      isActive: isActive,
                      isMuted: _isMuted,
                      onToggleMute: () => setState(() => _isMuted = !_isMuted),
                    ),

                    // 2. Left Information Overlay (Creator, Caption, Audio)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ReelOverlay(
                        reel: reel,
                        onOpenAiSheet: () {
                          if (reel.aiAnalysis != null) {
                            AiResultReelSheet.show(context, reel.aiAnalysis!, reel.caption);
                          }
                        },
                      ),
                    ),

                    // 3. Right Action Bar (Like, Comment, Share, Save, More)
                    Positioned(
                      right: 12,
                      bottom: 24,
                      child: ReelActions(
                        reel: reel,
                        onOpenComments: () {
                          ReelCommentsSheet.show(context, reel.reelId, reel.userId);
                        },
                        onOpenMore: () {
                          ReelMoreSheet.show(
                            context,
                            reel,
                            onReelDeleted: () {
                              setState(() {
                                _reels.removeWhere((r) => r.reelId == reel.reelId);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),

          // 2. Top Header (Header, Category Filter Tabs & Mute Button)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCustomFeed) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.screenTitle ?? "Cricket Reels",
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: CrickXColors.graphite,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: CrickXColors.graphiteBorder,
                                  width: 1.2,
                                ),
                              ),
                              child: const Icon(Icons.sports_cricket_rounded, color: CrickXColors.limeSpark, size: 18),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Cricket Reels",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.9),
                                    blurRadius: 8,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],

                      const Spacer(),

                      // Mute / Unmute Button
                      IconButton(
                        icon: Icon(
                          _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () => setState(() => _isMuted = !_isMuted),
                      ),
                    ],
                  ),

                  // Category Filter Pills
                  if (!isCustomFeed) ...[
                    const SizedBox(height: 6),
                    _buildCategoryTabs(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCategoryTabItem("All Cricket", CricketCategory.all),
          const SizedBox(width: 4),
          _buildCategoryTabItem("Highlights", CricketCategory.highlights),
          const SizedBox(width: 4),
          _buildCategoryTabItem("Coaching Drills", CricketCategory.coaching),
        ],
      ),
    );
  }

  Widget _buildCategoryTabItem(String title, CricketCategory category) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () {
        if (_selectedCategory == category) return;
        setState(() {
          _selectedCategory = category;
          _currentIndex = 0;
        });
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? CrickXColors.limeSpark : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          title,
          style: GoogleFonts.poppins(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String emptyTitle = "No Reels Available";
    String emptySubtitle = "Latest cricket reels will appear here automatically.";

    if (_selectedCategory == CricketCategory.highlights) {
      emptyTitle = "No Highlights Available";
      emptySubtitle = "International cricket highlights will appear here shortly.";
    } else if (_selectedCategory == CricketCategory.coaching) {
      emptyTitle = "No Coaching Drills Available";
      emptySubtitle = "Cricket coaching advice and training drills will appear here shortly.";
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF161922),
                shape: BoxShape.circle,
                border: Border.all(
                  color: CrickXColors.limeSpark.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.sports_cricket_rounded,
                color: CrickXColors.limeSpark,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              emptyTitle,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              emptySubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_selectedCategory != CricketCategory.all)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedCategory = CricketCategory.all;
                        _currentIndex = 0;
                      });
                    },
                    child: Text(
                      "Show All Cricket",
                      style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _fetchInitialReels,
                  icon: const Icon(Icons.refresh_rounded, color: CrickXColors.limeSpark, size: 18),
                  label: Text(
                    "Refresh Feed",
                    style: GoogleFonts.poppins(color: CrickXColors.limeSpark, fontWeight: FontWeight.w600, fontSize: 13),
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
