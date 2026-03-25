import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../services/weekly_stats_service.dart';
import 'elite_coach_prompt.dart';
import 'chat_sessions_provider.dart';
import '../widgets/premium_blur_lock.dart';

class AICoachScreen extends StatefulWidget {
  final Map<String, dynamic>? payloadContext;
  final String? initialQuestion;

  const AICoachScreen({super.key, this.payloadContext, this.initialQuestion});

  @override
  State<AICoachScreen> createState() => _AICoachScreenState();
}

class _AICoachScreenState extends State<AICoachScreen> {
  static const int _maxChars = 120;
  bool _redirectedToPremium = false;

  late Uri uri;
  late final ChatSessionsProvider _chatProvider;

  final TextEditingController controller = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ScrollController _scrollController = ScrollController();

  bool loading = false;
  bool isListening = false;
  int _charCount = 0;
  int _lastMessageCount = 0;
  bool _scrollScheduled = false;
  bool _lastPremiumState = PremiumService.isPremiumActive;
  String _resolvedUserName = "Player";

  String _formatCoachReply(String raw) {
    final cleaned = raw.replaceAll('\r', '').trim();
    final lines = cleaned
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final compact = (lines.isNotEmpty ? lines : [cleaned]).join('\n');
    final words = compact.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 280) return compact;
    return '${words.take(280).join(' ')}...';
  }

  @override
  void initState() {
    super.initState();

    uri = Uri.parse("${ApiConfig.baseUrl}/coach/chat");
    _chatProvider = ChatSessionsProvider()..init();
    _loadResolvedUserName();

    Future.microtask(() async {
      await PremiumService.restoreOnLaunch();
      if (mounted) setState(() {});
    });
    PremiumService.premiumNotifier.addListener(_onPremiumChanged);

    controller.addListener(() {
      final next = controller.text.characters.length;
      if (next == _charCount) return;
      if (!mounted) return;
      setState(() => _charCount = next);
    });

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
    PremiumService.premiumNotifier.removeListener(_onPremiumChanged);
    _chatProvider.dispose();
    controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    final next = PremiumService.isPremiumActive;
    if (next == _lastPremiumState) return;
    _lastPremiumState = next;
    setState(() {});
  }

  Future<void> _loadResolvedUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    String nextName = "Player";
    if (user != null) {
      try {
        final box = await Hive.openBox("local_stats_${user.uid}");
        final profileName = box.get("profileName") as String?;
        if (profileName != null && profileName.trim().isNotEmpty) {
          nextName = profileName.trim();
        } else if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
          nextName = user.displayName!.trim().split(" ").first;
        } else if ((user.email ?? "").contains("@")) {
          nextName = user.email!.split("@").first;
        }
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        final profileName = prefs.getString("profileName");
        if (profileName != null && profileName.trim().isNotEmpty) {
          nextName = profileName.trim();
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _resolvedUserName = nextName;
    });
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (!animated) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scheduleScrollToBottomRobust({bool animated = true}) {
    _scheduleScrollToBottom(animated: animated);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _scheduleScrollToBottom(animated: animated);
    });
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _scheduleScrollToBottom(animated: animated);
    });
  }

  Future<void> _redirectToPremiumWithReason() async {
    if (_redirectedToPremium) return;
    _redirectedToPremium = true;
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
    final raw = controller.text;
    if (raw.characters.length > _maxChars) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Message too long. Limit is 120 characters."),
          ),
        );
      }
      return;
    }

    String userMessage = raw.trim();
    if (userMessage.isEmpty) return;

    // 🔒 Real-time premium gate (single source of truth)
    if (!PremiumService.isLoaded || !PremiumService.isPremiumActive) {
      return;
    }

    controller.clear();
    await _chatProvider.addUserMessage(userMessage);
    _scheduleScrollToBottomRobust(animated: true);
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

      try {
        await WeeklyStatsService.recordAiChat(user.uid);
      } catch (_) {}

      http.Response response = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "authorization": "Bearer ${idToken.trim()}",
            },
            body: jsonEncode({
              "message": EliteCoachPrompt.forChat(userMessage: userMessage),
            }),
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

        await _chatProvider.addCoachMessage(_formatCoachReply(coachText));
        await PremiumService.consumeChat();
        _scheduleScrollToBottomRobust(animated: true);
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

      _scheduleScrollToBottomRobust(animated: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Network error. Please try again.")),
        );
      }

      _scheduleScrollToBottomRobust(animated: true);

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
        _scheduleScrollToBottomRobust(animated: true);
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
    return _resolvedUserName;
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
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: 18,
                          height: 1.6,
                          margin: const EdgeInsets.symmetric(vertical: 1.8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
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
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.34),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
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
          final locked =
              !PremiumService.isLoaded || !PremiumService.isPremiumActive;
          void unlock() {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => const PremiumScreen(entrySource: "ai_coach"),
              ),
            );
          }

          final hasMessages = provider.messages.isNotEmpty;
          if (hasMessages && provider.messages.length != _lastMessageCount) {
            _lastMessageCount = provider.messages.length;
            _scheduleScrollToBottomRobust(animated: false);
          } else if (!hasMessages) {
            _lastMessageCount = 0;
          }
          return Scaffold(
            drawer: buildHistoryDrawer(provider),
            backgroundColor: const Color(0xFF020617),
            appBar: AppBar(
              backgroundColor: const Color(0xFF020617),
              elevation: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: "Chat History",
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(
                    Icons.drag_handle_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
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
                  child: locked
                      ? Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111827),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFF38BDF8),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: const Text(
                                    "CrickNova AI: Your action plan is simple—fix your head position, shorten your run-up, and focus on one seam drill daily for 10 minutes...",
                                    maxLines: 2,
                                    overflow: TextOverflow.fade,
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                child: PremiumBlurLock(
                                  locked: true,
                                  ctaText: "TALK TO CRICKNOVA AI",
                                  title: "AI Coach Locked",
                                  subtitle:
                                      "See full AI coaching, personalised mistakes and drills with Premium.",
                                  onUnlock: unlock,
                                  child: ListView(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.only(top: 6),
                                    children: [
                                      buildMessage({
                                        "role": "user",
                                        "content":
                                            "Why am I losing pace in the last 5 overs?",
                                      }),
                                      buildMessage({
                                        "role": "coach",
                                        "content":
                                            "You're dropping your elbow at release and your front foot is landing too wide, which kills energy transfer. Fix: 1) 3x10 wrist snaps, 2) one-step bowl drill, 3) target a straight run-up line. Also track your follow-through and keep your head still through impact.",
                                      }),
                                      buildMessage({
                                        "role": "user",
                                        "content":
                                            "Give me a 7-day drill plan.",
                                      }),
                                      buildMessage({
                                        "role": "coach",
                                        "content":
                                            "Day 1–2: Seam control + release point. Day 3–4: Front-foot alignment + balance. Day 5: Pace build with controlled run-up. Day 6: Accuracy challenge with targets. Day 7: Match simulation with variations and recovery routines.",
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : (!hasMessages
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
                              )),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AbsorbPointer(
                              absorbing: locked,
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
                            onPressed: locked ? unlock : toggleMic,
                          ),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: (_charCount > _maxChars)
                                ? null
                                : (locked ? unlock : sendMessage),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "${_charCount.toString()}/$_maxChars",
                          style: TextStyle(
                            color: _charCount > _maxChars
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF22C55E),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
