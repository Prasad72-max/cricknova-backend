import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/reel_model.dart';

class ReelOverlay extends StatefulWidget {
  final ReelModel reel;
  final VoidCallback? onOpenAiSheet;

  const ReelOverlay({
    super.key,
    required this.reel,
    this.onOpenAiSheet,
  });

  @override
  State<ReelOverlay> createState() => _ReelOverlayState();
}

class _ReelOverlayState extends State<ReelOverlay> {
  bool _isExpandedCaption = false;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.reel.isFollowing;
  }

  @override
  void didUpdateWidget(covariant ReelOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reel.reelId != widget.reel.reelId) {
      _isFollowing = widget.reel.isFollowing;
      _isExpandedCaption = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 85, bottom: 24, top: 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.85),
            Colors.black.withOpacity(0.35),
            Colors.transparent,
          ],
          stops: const [0.0, 0.60, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Creator Profile & Follow Button (Pure Instagram Style)
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  image: widget.reel.userPhotoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(widget.reel.userPhotoUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: const Color(0xFF1E293B),
                ),
                child: widget.reel.userPhotoUrl == null
                    ? const Icon(Icons.sports_cricket_rounded, color: Colors.white, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.reel.username.isNotEmpty ? "@${widget.reel.username.replaceAll('@', '')}" : "@cricketer",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  setState(() => _isFollowing = !_isFollowing);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isFollowing ? Colors.white.withOpacity(0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isFollowing ? Colors.white54 : Colors.white,
                      width: 1.2,
                    ),
                  ),
                  child: Text(
                    _isFollowing ? "Following" : "Follow",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 2. Caption
          if (widget.reel.caption.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _isExpandedCaption = !_isExpandedCaption),
              child: Text(
                widget.reel.caption,
                maxLines: _isExpandedCaption ? 8 : 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.9), blurRadius: 4),
                  ],
                ),
              ),
            ),

          // 3. Hashtags
          if (widget.reel.hashtags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: widget.reel.hashtags.map((tag) {
                final text = tag.startsWith('#') ? tag : '#$tag';
                return Text(
                  text,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 3),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 10),

          // 4. Instagram Audio Track Marquee
          Row(
            children: [
              const Icon(Icons.music_note_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Original audio - ${widget.reel.username.isNotEmpty ? widget.reel.username : 'cricket'}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11.5,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 3),
                    ],
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
