import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/crickx_colors.dart';

class EliteSupportChatScreen extends StatefulWidget {
  const EliteSupportChatScreen({super.key});

  @override
  State<EliteSupportChatScreen> createState() => _EliteSupportChatScreenState();
}

class _EliteSupportChatScreenState extends State<EliteSupportChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  String? _uid;

  CollectionReference<Map<String, dynamic>>? _messagesRef;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid;
    if (_uid != null) {
      _messagesRef = FirebaseFirestore.instance
          .collection("support_chats")
          .doc(_uid)
          .collection("messages");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _uid == null || _messagesRef == null) return;

    setState(() => _sending = true);
    _controller.clear();

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : "CrickNova Player";
    final docRef = FirebaseFirestore.instance
        .collection("support_chats")
        .doc(_uid);

    try {
      await docRef.set({
        "uid": _uid,
        "displayName": displayName,
        "lastMessage": text,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _messagesRef!.add({
        "text": text,
        "sender": _uid,
        "displayName": displayName,
        "clientAt": Timestamp.now(),
        "createdAt": FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null || _messagesRef == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text("Elite Coach Support"),
        ),
        body: Center(
          child: Text(
            "Please sign in to reach Elite Support.",
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          "Elite Coach Support",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesRef!
                  .orderBy("clientAt", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Failed to load messages",
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: CrickXColors.limeSpark),
                  );
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "Elite 24/7 dedicated support is ready.\nAsk any technical or cricket coaching question.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final text = data["text"]?.toString() ?? "";
                    final sender = data["sender"]?.toString();
                    final isMe = sender == _uid;
                    return _MessageBubble(text: text, isMe: isMe);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            decoration: const BoxDecoration(
              color: CrickXColors.graphite,
              border: Border(
                top: BorderSide(color: CrickXColors.graphiteBorder),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: GoogleFonts.poppins(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: "Type your message",
                      hintStyle: GoogleFonts.poppins(color: Colors.white54),
                      filled: true,
                      fillColor: CrickXColors.graphiteBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: CrickXColors.graphiteBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: CrickXColors.graphiteBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: CrickXColors.limeSpark),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _sending ? null : _sendMessage,
                  icon: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: CrickXColors.limeSpark),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: CrickXColors.limeSpark,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;

  const _MessageBubble({required this.text, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe
        ? CrickXColors.limeSpark.withValues(alpha: 0.18)
        : CrickXColors.graphiteElevated;
    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final radius = isMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          );

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
