import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../../theme/crickx_colors.dart';

class ReelActions extends StatefulWidget {
  final ReelModel reel;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenMore;

  const ReelActions({
    super.key,
    required this.reel,
    required this.onOpenComments,
    required this.onOpenMore,
  });

  @override
  State<ReelActions> createState() => _ReelActionsState();
}

class _ReelActionsState extends State<ReelActions> {
  late bool _isLiked;
  late int _likesCount;
  late bool _isSaved;
  late int _savesCount;
  bool _likeLock = false;
  bool _saveLock = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.reel.isLiked;
    _likesCount = widget.reel.likesCount;
    _isSaved = widget.reel.isSaved;
    _savesCount = widget.reel.savesCount;
  }

  @override
  void didUpdateWidget(covariant ReelActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reel.reelId != widget.reel.reelId) {
      _isLiked = widget.reel.isLiked;
      _likesCount = widget.reel.likesCount;
      _isSaved = widget.reel.isSaved;
      _savesCount = widget.reel.savesCount;
    }
  }

  String _formatCount(int count) {
    if (count <= 0) return "0";
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      final k = count / 1000.0;
      return "${k.toStringAsFixed(k >= 10 ? 0 : 1)}K";
    }
    final m = count / 1000000.0;
    return "${m.toStringAsFixed(1)}M";
  }

  Future<void> _handleLike() async {
    if (_likeLock) return;
    _likeLock = true;

    final prevLiked = _isLiked;
    final prevCount = _likesCount;

    setState(() {
      _isLiked = !_isLiked;
      _likesCount = _isLiked ? _likesCount + 1 : (_likesCount > 0 ? _likesCount - 1 : 0);
    });

    try {
      final result = await ReelService.toggleLike(widget.reel.reelId);
      if (mounted && result != _isLiked) {
        setState(() {
          _isLiked = result;
          _likesCount = result ? _likesCount + 1 : (_likesCount > 0 ? _likesCount - 1 : 0);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = prevLiked;
          _likesCount = prevCount;
        });
      }
    } finally {
      _likeLock = false;
    }
  }

  Future<void> _handleSave() async {
    if (_saveLock) return;
    _saveLock = true;

    final prevSaved = _isSaved;
    final prevCount = _savesCount;

    setState(() {
      _isSaved = !_isSaved;
      _savesCount = _isSaved ? _savesCount + 1 : (_savesCount > 0 ? _savesCount - 1 : 0);
    });

    try {
      final result = await ReelService.toggleSave(widget.reel.reelId);
      if (mounted && result != _isSaved) {
        setState(() {
          _isSaved = result;
          _savesCount = result ? _savesCount + 1 : (_savesCount > 0 ? _savesCount - 1 : 0);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaved = prevSaved;
          _savesCount = prevCount;
        });
      }
    } finally {
      _saveLock = false;
    }
  }

  Future<void> _handleShare() async {
    final shareUrl = "cricknova://reel/${widget.reel.reelId}";
    final text = "Watch this cricket reel on CrickNova AI: ${widget.reel.caption}\n$shareUrl";
    await Share.share(
      text,
      subject: "CrickNova Cricket Reel",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. LIKE
        _buildActionButton(
          icon: _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          iconColor: _isLiked ? const Color(0xFFEF4444) : Colors.white,
          label: _formatCount(_likesCount),
          onTap: _handleLike,
        ),
        const SizedBox(height: 18),

        // 2. COMMENTS
        _buildActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: Colors.white,
          label: _formatCount(widget.reel.commentsCount),
          onTap: widget.onOpenComments,
        ),
        const SizedBox(height: 18),

        // 3. SHARE
        _buildActionButton(
          icon: Icons.share_outlined,
          iconColor: Colors.white,
          label: "Share",
          onTap: _handleShare,
        ),
        const SizedBox(height: 18),

        // 4. SAVE
        _buildActionButton(
          icon: _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          iconColor: _isSaved ? CrickXColors.limeSpark : Colors.white,
          label: _formatCount(_savesCount),
          onTap: _handleSave,
        ),
        const SizedBox(height: 18),

        // 5. MORE
        _buildActionButton(
          icon: Icons.more_horiz_rounded,
          iconColor: Colors.white,
          label: "",
          onTap: widget.onOpenMore,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.35),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 28,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.85),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
