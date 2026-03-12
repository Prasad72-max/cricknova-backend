import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import 'chat_sessions_provider.dart';

class AICoachScreen extends StatefulWidget {
  final Map<String, dynamic>? payloadContext;
  final String? initialQuestion;

  const AICoachScreen({super.key, this.payloadContext, this.initialQuestion});

  @override
  State<AICoachScreen> createState() => _AICoachScreenState();
}

class _AICoachScreenState extends State<AICoachScreen> {
  bool _redirectedToPremium = false;

  late Uri uri;
  late final ChatSessionsProvider _chatProvider;

  final TextEditingController controller = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ScrollController _scrollController = ScrollController();

  bool loading = false;
  bool isListening = false;

  @override
  void initState() {
    super.initState();

    uri = Uri.parse("${ApiConfig.baseUrl}/coach/chat");
    _chatProvider = ChatSessionsProvider()..init();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.initialQuestion != null &&
          widget.initialQuestion!.isNotEmpty) {
        controller.text = widget.initialQuestion!;
        sendMessage();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _chatProvider.dispose();
    controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _redirectToPremiumWithReason() async {
    if (_redirectedToPremium) return;
    _redirectedToPremium = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF020617),
        title: const Text(
          "Premium Feature",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "AI Coach is a premium feature.\n\nUpgrade to unlock personalised cricket coaching, mistake analysis, and match-level insights.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              "Upgrade",
              style: TextStyle(color: Color(0xFF38BDF8)),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const PremiumScreen(entrySource: "ai_coach"),
      ),
    );
  }

  /* ---------------- SEND MESSAGE ---------------- */

  Future<void> sendMessage() async {
    String userMessage = controller.text.trim();
    if (userMessage.isEmpty) return;
    controller.clear();

    // 🔒 Real-time premium gate (single source of truth)
    if (!PremiumService.isPremiumActive) {
      await _redirectToPremiumWithReason();
      return;
    }

    await _chatProvider.addUserMessage(userMessage);
    loading = true;
    setState(() {});

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        loading = false;
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You are logged out. Please sign in again."),
            ),
          );
        }
        return;
      }
      final String? idToken = await user.getIdToken();

      if (idToken == null || idToken.isEmpty) {
        loading = false;
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Authentication failed. Please log in again."),
            ),
          );
        }
        return;
      }

      debugPrint(
        "🔥 FIREBASE ID TOKEN (AI COACH) PREFIX → ${idToken.substring(0, 30)}",
      );

      http.Response response = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "authorization": "Bearer ${idToken.trim()}",
            },
            body: jsonEncode({"message": userMessage}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        loading = false;
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Session expired. Please reopen the app."),
            ),
          );
        }
        return;
      } else if (response.statusCode == 403) {
        loading = false;
        setState(() {});

        try {
          final decoded = jsonDecode(response.body);
          if (decoded["detail"] == "CHAT_LIMIT_REACHED") {
            await _redirectToPremiumWithReason();
            return;
          }
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Usage limit reached.")));
        }
        return;
      } else if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        debugPrint("AI COACH RESPONSE => $decoded");

        // ❌ Any other unexpected failure
        if (decoded["success"] != true && decoded["status"] != "success") {
          throw Exception("AI failed");
        }

        final coachText =
            decoded["reply"]?.toString() ??
            decoded["coach_feedback"]?.toString() ??
            "No reply received from AI.";

        await _chatProvider.addCoachMessage(coachText);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        debugPrint("AI COACH ERROR ${response.statusCode} => ${response.body}");
        loading = false;
        setState(() {});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Server error. Please try again.")),
          );
        }
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Network error. Please try again.")),
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      return;
    } finally {
      // 🔥 Universal XP reward (AI attempt — success or fail)
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final uid = user.uid;
          final box = await Hive.openBox("local_stats_$uid");

          int currentXp = box.get('xp', defaultValue: 0);
          int newXp = currentXp + 500000; // 🔥 5 Lakh XP Boost

          await box.put('xp', newXp);

          debugPrint("🔥 +5 LAKH XP ADDED → TOTAL: $newXp");
        }
      } catch (e) {
        debugPrint("XP update failed: $e");
      }
      if (mounted) {
        loading = false;
        setState(() {});
      }
    }

    // (final loading reset and saveChats removed as per instructions)
  }

  /* ---------------- MIC ---------------- */

  Future<void> toggleMic() async {
    if (isListening) {
      await _speech.stop();
      isListening = false;
    } else {
      bool ok = await _speech.initialize();
      if (!ok) return;

      isListening = true;
      _speech.listen(
        onResult: (res) {
          controller.text = res.recognizedWords;
        },
      );
    }
    setState(() {});
  }

  /* ---------------- UI ---------------- */

  Widget buildMessage(Map<String, dynamic> msg) {
    bool isUser = msg["role"] == "user";

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF1E293B) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: isUser
              ? null
              : Border.all(color: const Color(0xFF38BDF8), width: 1.2),
        ),
        child: Text(
          msg["content"] ?? msg["text"] ?? "",
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // ---------------- USER NAME HELPER ----------------
  String getUserName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      return user.displayName!.split(" ").first;
    }
    return "Player";
  }

  // ---------------- QUICK CHIP + SUGGESTION WIDGETS ----------------
  Widget quickChip(String text) {
    return ActionChip(
      backgroundColor: const Color(0xFF0F172A),
      label: Text(text, style: const TextStyle(color: Colors.white)),
      onPressed: () {
        controller.text = text;
        sendMessage();
      },
    );
  }

  Widget suggestionTile(String text) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      onTap: () {
        controller.text = text;
        sendMessage();
      },
    );
  }

  /* ---------------- HISTORY DRAWER ---------------- */

  Widget buildHistoryDrawer(ChatSessionsProvider provider) {
    return Drawer(
      backgroundColor: const Color(0xFF020617),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  const Text(
                    "Chat History",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: "New Chat",
                    icon: const Icon(Icons.add_circle, color: Colors.white),
                    onPressed: () async {
                      await provider.startNewChat();
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Expanded(
              child: provider.loadingList
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF38BDF8),
                      ),
                    )
                  : provider.sessions.isEmpty
                  ? const Center(
                      child: Text(
                        "No previous chats",
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: provider.sessions.length,
                      itemBuilder: (context, i) {
                        final session = provider.sessions[i];
                        final selected = session.id == provider.currentChatId;
                        return ListTile(
                          title: Text(
                            session.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          selected: selected,
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white54,
                            ),
                            onPressed: () async {
                              await provider.deleteChat(session.id);
                            },
                          ),
                          onTap: () async {
                            await provider.openChat(session.id);
                            if (mounted) Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _chatProvider,
      child: Consumer<ChatSessionsProvider>(
        builder: (context, provider, _) {
          final hasMessages = provider.messages.isNotEmpty;
          return Scaffold(
            drawer: buildHistoryDrawer(provider),
            backgroundColor: const Color(0xFF020617),
            appBar: AppBar(
              backgroundColor: const Color(0xFF020617),
              elevation: 0,
              title: const Text(
                "CrickNova AI Coach",
                style: TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            body: Column(
              children: [
                Flexible(
                  fit: FlexFit.tight,
                  child: !hasMessages
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 👤 Coach Greeting
                              Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Color(0xFF0F172A),
                                    child: Icon(
                                      Icons.sports_cricket,
                                      color: Color(0xFF38BDF8),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "Hello ${getUserName()}!\nI am your CrickNova AI. How can I help you improve your game today?",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // ⚡ Quick Action Chips
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  quickChip("🏏 Batting Tips"),
                                  quickChip("🥎 Bowling Tips"),
                                  quickChip("🧠 Match Mindset"),
                                  quickChip("📉 My Mistakes"),
                                ],
                              ),

                              const SizedBox(height: 28),

                              // 🏆 Suggested Questions
                              const Text(
                                "Suggested Questions",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              suggestionTile(
                                "How to play a perfect cover drive?",
                              ),
                              suggestionTile(
                                "What is the ideal release point for an outswinger?",
                              ),
                              suggestionTile(
                                "Show me drills for better footwork.",
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: provider.messages.length,
                          itemBuilder: (_, i) =>
                              buildMessage(provider.messages[i]),
                        ),
                ),
                // Clean AI analyzing indicator
                if (loading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 28,
                          width: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(
                              Color(0xFF38BDF8),
                            ),
                            backgroundColor: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(seconds: 2),
                          builder: (context, value, child) {
                            int dots = (value * 3).floor();
                            return Text(
                              "Analyzing${"." * dots}",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                          onEnd: () {
                            if (mounted && loading) {
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: false,
                          child: TextField(
                            controller: controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "Ask CrickNova AI Coach...",
                              hintStyle: const TextStyle(
                                color: Color(0xFF64748B),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isListening ? Icons.mic : Icons.mic_none,
                          color: isListening ? Colors.red : Colors.white,
                        ),
                        onPressed: toggleMic,
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
