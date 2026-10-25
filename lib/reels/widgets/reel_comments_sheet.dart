import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../../theme/crickx_colors.dart';

class ReelCommentsSheet extends StatefulWidget {
  final String reelId;
  final String creatorId;

  const ReelCommentsSheet({
    super.key,
    required this.reelId,
    required this.creatorId,
  });

  static void show(BuildContext context, String reelId, String creatorId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReelCommentsSheet(
        reelId: reelId,
        creatorId: creatorId,
      ),
    );
  }

  @override
  State<ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<ReelCommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  bool _isPosting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handlePostComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isPosting) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to comment.")),
      );
      return;
    }

    setState(() => _isPosting = true);
    try {
      final name = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? "Cricketer");

      await ReelService.addComment(
        reelId: widget.reelId,
        text: text,
        username: name,
        userPhotoUrl: user.photoURL,
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to post comment: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _handleDeleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CrickXColors.graphite,
        title: const Text("Delete comment?", style: TextStyle(color: Colors.white)),
        content: const Text("This action cannot be undone.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ReelService.deleteComment(
        reelId: widget.reelId,
        commentId: commentId,
      );
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m";
    if (diff.inHours < 24) return "${diff.inHours}h";
    return "${diff.inDays}d";
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final currentUid = ReelService.currentUserId;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65 + keyboardHeight,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: CrickXColors.graphiteBorder, width: 1.2)),
      ),
      child: Column(
        children: [
          // 1. Drag Handle & Header
          const SizedBox(height: 12),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Comments",
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Divider(color: CrickXColors.graphiteBorder, height: 1),

          // 2. Comments List Stream
          Expanded(
            child: StreamBuilder<List<ReelComment>>(
              stream: ReelService.getCommentsStream(widget.reelId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(CrickXColors.limeSpark),
                    ),
                  );
                }

                final comments = snapshot.data ?? [];
                if (comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white24, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          "No comments yet.",
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
                        ),
                        Text(
                          "Be the first to share your thoughts!",
                          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11.5),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: comments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final c = comments[index];
                    final canDelete = currentUid != null &&
                        (currentUid == c.userId || currentUid == widget.creatorId);

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF1E222A),
                          ),
                          child: ClipOval(
                            child: (c.userPhotoUrl != null && c.userPhotoUrl!.isNotEmpty)
                                ? Image.network(
                                    c.userPhotoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _fallbackAvatar(c.username),
                                  )
                                : _fallbackAvatar(c.username),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Comment Text & Metadata
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    c.username,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatTimeAgo(c.createdAt),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                c.text,
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.88),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Delete option if allowed
                        if (canDelete)
                          IconButton(
                            onPressed: () => _handleDeleteComment(c.commentId),
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.white38),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // 3. Comment Input Box
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: CrickXColors.graphite,
              border: Border(top: BorderSide(color: CrickXColors.graphiteBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: CrickXColors.graphiteBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: CrickXColors.graphiteBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _commentController,
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Add a cricket comment...",
                        hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12.5),
                        border: InputBorder.none,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handlePostComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isPosting ? null : _handlePostComment,
                  icon: _isPosting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(CrickXColors.limeSpark),
                          ),
                        )
                      : Icon(Icons.send_rounded, color: CrickXColors.limeSpark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar(String username) {
    return Container(
      color: CrickXColors.graphiteElevated,
      alignment: Alignment.center,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : "P",
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
