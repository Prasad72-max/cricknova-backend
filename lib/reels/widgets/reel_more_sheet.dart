import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../../theme/crickx_colors.dart';

class ReelMoreSheet extends StatelessWidget {
  final ReelModel reel;
  final VoidCallback? onReelDeleted;

  const ReelMoreSheet({
    super.key,
    required this.reel,
    this.onReelDeleted,
  });

  static void show(
    BuildContext context,
    ReelModel reel, {
    VoidCallback? onReelDeleted,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReelMoreSheet(
        reel: reel,
        onReelDeleted: onReelDeleted,
      ),
    );
  }

  bool get _isOwnReel {
    final uid = ReelService.currentUserId;
    return uid != null && uid == reel.userId;
  }

  Future<void> _handleReport(BuildContext context) async {
    Navigator.pop(context);
    final reasons = [
      "Inappropriate content",
      "Not cricket-related",
      "Dangerous technique / drill",
      "Harassment or spam",
      "Other",
    ];

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: CrickXColors.graphite,
        title: Text(
          "Report Reel",
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        children: reasons
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(r, style: const TextStyle(color: Colors.white70)),
                ),
              ),
            )
            .toList(),
      ),
    );

    if (chosen != null) {
      await ReelService.reportReel(reelId: reel.reelId, reason: chosen);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Thank you. Report received for review.")),
        );
      }
    }
  }

  Future<void> _handleBlock(BuildContext context) async {
    Navigator.pop(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CrickXColors.graphite,
        title: Text("Block @${reel.username}?", style: const TextStyle(color: Colors.white)),
        content: const Text(
          "You won't see reels from this user anymore.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Block", style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ReelService.blockUser(reel.userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Blocked @${reel.username}.")),
        );
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    Navigator.pop(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CrickXColors.graphite,
        title: const Text("Delete this Reel?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This action is permanent and will remove the video and all its stats.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete Reel", style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ReelService.deleteReel(reel.reelId);
      onReelDeleted?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reel deleted successfully.")),
        );
      }
    }
  }

  void _handleCopyLink(BuildContext context) {
    Navigator.pop(context);
    Clipboard.setData(ClipboardData(text: "cricknova://reel/${reel.reelId}"));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Reel link copied to clipboard.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: CrickXColors.graphiteBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Copy Link
          _buildOptionTile(
            icon: Icons.link_rounded,
            title: "Copy link",
            onTap: () => _handleCopyLink(context),
          ),

          if (!_isOwnReel) ...[
            // Report
            _buildOptionTile(
              icon: Icons.flag_outlined,
              title: "Report Reel",
              titleColor: const Color(0xFFF87171),
              onTap: () => _handleReport(context),
            ),
            // Block
            _buildOptionTile(
              icon: Icons.block_rounded,
              title: "Block User",
              titleColor: const Color(0xFFF87171),
              onTap: () => _handleBlock(context),
            ),
          ],

          if (_isOwnReel) ...[
            // Delete Reel
            _buildOptionTile(
              icon: Icons.delete_outline_rounded,
              title: "Delete Reel",
              titleColor: const Color(0xFFEF4444),
              onTap: () => _handleDelete(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: titleColor ?? Colors.white70, size: 22),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: titleColor ?? Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
