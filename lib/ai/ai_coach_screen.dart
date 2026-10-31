import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../services/xp_service.dart';
import 'chat_sessions_provider.dart';
import '../widgets/premium_blur_lock.dart';
import '../navigation/main_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/crickx_colors.dart';
import '../services/analysis_credit_service.dart';

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
  int _charCount = 0;
  int _lastMessageCount = 0;
  bool _scrollScheduled = false;
  bool _lastPremiumState = PremiumService.isPremiumActive;
  String _resolvedUserName = "Player";


  @override
  void initState() {
    super.initState();

    uri = Uri.parse("${ApiConfig.baseUrl}/coach/chat");
    _chatProvider = ChatSessionsProvider()..init();
    _loadResolvedUserName();
    MainNavigation.userNameNotifier.addListener(_onUserNameChanged);

    Future.microtask(() async {
      if (!PremiumService.isLoaded) {
        await PremiumService.restoreOnLaunch();
      }
      if (mounted) setState(() {});
    });
    AnalysisCreditService.instance.loadCredits();
    AnalysisCreditService.instance.chatCreditsNotifier.addListener(_onChatCreditsChanged);
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
    AnalysisCreditService.instance.chatCreditsNotifier.removeListener(_onChatCreditsChanged);
    PremiumService.premiumNotifier.removeListener(_onPremiumChanged);
    MainNavigation.userNameNotifier.removeListener(_onUserNameChanged);
    _chatProvider.dispose();
    controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChatCreditsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onUserNameChanged() {
    if (!mounted) return;
    _loadResolvedUserName();
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    final next = PremiumService.isPremiumActive;
    if (next == _lastPremiumState) return;
    _lastPremiumState = next;
    setState(() {});
  }

  Future<void> _awardAiCoachXp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await XpService.award(uid: user.uid, amount: 10, source: 'AI COACH');
  }

  Future<void> _loadResolvedUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    String nextName = "Player";
    if (user != null) {
      String? name;
      try {
        final box = await Hive.openBox("local_stats_${user.uid}");
        name = (box.get("profileName") as String?)?.trim();
      } catch (_) {}

      if (name == null || name.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          name = prefs.getString("profileName_${user.uid}")?.trim();
        } catch (_) {}
      }

      if (name == null || name.isEmpty) {
        name = user.displayName?.trim();
      }

      // Removed global fallback to prevent name leak

      if (name != null && name.isNotEmpty && name.toLowerCase() != "player") {
        nextName = name.split(" ").first;
      } else if ((user.email ?? "").contains("@")) {
        nextName = user.email!.split("@").first;
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

  /* ---------------- DIRECT NVIDIA NEMOTRON CLIENT ---------------- */

  Future<String?> _callNvidiaDirect(
    String userMessage,
    List<Map<String, dynamic>> history,
  ) async {
    try {
      final key = ApiConfig.nvidiaApiKey.trim();
      if (key.isEmpty) return null;

      final url = Uri.parse(
        "https://integrate.api.nvidia.com/v1/chat/completions",
      );

      final messages = <Map<String, dynamic>>[
        {
          "role": "system",
          "content":
              "You are a universal cricket coach. Keep your responses focused on cricket.",
        }
      ];

      for (final msg in history.take(8)) {
        final role = msg["role"] == "user" ? "user" : "assistant";
        final text = (msg["content"] ?? msg["text"] ?? "").toString().trim();
        if (text.isNotEmpty) {
          messages.add({
            "role": role,
            "content": text,
          });
        }
      }

      messages.add({
        "role": "user",
        "content": userMessage,
      });

      final response = await http
          .post(
            url,
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $key",
            },
            body: jsonEncode({
              "model": "nvidia/nemotron-3.5-super-vl-120b-a12b",
              "messages": messages,
              "temperature": 0.6,
              "max_tokens": 4096,
              "chat_template_kwargs": {"enable_thinking": false},
            }),
          )
          .timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final choices = data["choices"] as List?;
        if (choices != null && choices.isNotEmpty) {
          final text = choices[0]?["message"]?["content"]?.toString().trim();
          if (text != null && text.isNotEmpty) {
            return text;
          }
        }
      }
    } catch (e) {
      debugPrint("Direct NVIDIA Nemotron error: $e");
    }
    return null;
  }

  Future<bool> _showWatchAdForChatDialog() async {
    bool unlocked = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: CrickXColors.graphiteBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
        title: Text(
          '🎬 Watch Ad to Unlock CricX Chat',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Watch a short video ad to unlock 5 free CricX Coach messages, or upgrade to Premium for unlimited chats.',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                label: const Text(
                  'Watch Ad (5 Free Chats)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CrickXColors.limeSpark,
                  foregroundColor: CrickXColors.onLime,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  Navigator.of(dialogCtx).pop();
                  final result =
                      await AnalysisCreditService.instance.watchAdForChatCredit();
                  if (result == AdWatchResult.rewardEarned ||
                      result == AdWatchResult.premiumUser) {
                    unlocked = true;
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎉 5 CricX Chat messages added!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      setState(() {});
                    }
                  } else if (result == AdWatchResult.adNotAvailable) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              "Ad isn't available right now. Please try again."),
                        ),
                      );
                    }
                  } else if (result == AdWatchResult.adClosedEarly) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text("Watch the complete ad to get your 5 chats."),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const PremiumScreen(entrySource: "ai_coach"),
                  ),
                );
              },
              child: const Text(
                'Get Premium (Unlimited Chats)',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
    return unlocked;
  }

  /* ---------------- SEND MESSAGE ---------------- */

  Future<void> sendMessage() async {
    final raw = controller.text;
    String userMessage = raw.trim();
    if (userMessage.isEmpty) return;

    // Check premium or ad credits
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }
    final isPremium = PremiumService.isPremiumActive;
    if (!isPremium) {
      final currentCredits = AnalysisCreditService.instance.chatCredits;
      if (currentCredits <= 0) {
        final earned = await _showWatchAdForChatDialog();
        if (!earned && AnalysisCreditService.instance.chatCredits <= 0) {
          return;
        }
      }
      final consumed = await AnalysisCreditService.instance.consumeChatCredit();
      if (!consumed && !PremiumService.isPremiumActive) {
        await _showWatchAdForChatDialog();
        return;
      }
    }

    controller.clear();
    await _chatProvider.addUserMessage(userMessage);
    _scheduleScrollToBottomRobust(animated: true);
    loading = true;
    setState(() {});

    try {
      // ⚡ FAST DIRECT NVIDIA NEMOTRON ATTEMPT (Instant response if client key set)
      final directReply = await _callNvidiaDirect(
        userMessage,
        _chatProvider.recentMessagesForApi(),
      );
      if (directReply != null && directReply.trim().isNotEmpty) {
        await _chatProvider.addCoachMessage(directReply.trim());
        await _awardAiCoachXp();
        try {
          await PremiumService.consumeChat();
        } catch (_) {}
        _scheduleScrollToBottomRobust(animated: true);
        return;
      }

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
              "X-USER-ID": user.uid,
            },
            body: jsonEncode({
              "user_id": user.uid,
              "message": userMessage,
              "history": _chatProvider.recentMessagesForApi(),
            }),
          )
          .timeout(const Duration(seconds: 60));

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
          if (decoded["detail"] == "PREMIUM_REQUIRED" ||
              decoded["detail"] == "ACCESS_DENIED") {
            await PremiumService.ensureFreshState();
            if (!PremiumService.isPremiumActive) {
              await _redirectToPremiumWithReason();
              return;
            }
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

        String coachText = "No reply received from AI.";
        bool isSuccess = true;
        if (decoded is String && decoded.trim().isNotEmpty) {
          coachText = decoded.trim();
        } else if (decoded is Map) {
          final s = decoded["status"]?.toString().toLowerCase();
          if (s != null && s.isNotEmpty && s != "success") {
            isSuccess = false;
          }
          for (final key in [
            "reply",
            "coach_feedback",
            "difference",
            "message",
          ]) {
            final value = decoded[key]?.toString().trim();
            if (value != null && value.isNotEmpty) {
              coachText = value;
              break;
            }
          }
        }

        await _chatProvider.addCoachMessage(coachText.trim());
        // Only award XP / consume usage when the backend confirms success.
        if (isSuccess) {
          await _awardAiCoachXp();
          await PremiumService.consumeChat();
        }
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
    final rawContent = (msg["content"] ?? msg["text"] ?? "").toString().trim();
    // 🧹 Clean markdown symbols (*, #, _, `) so chat reads in crystal-clean natural text
    final content = isUser
        ? rawContent
        : rawContent
            .replaceAll(RegExp(r'[*#_`~]'), '')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Copied to clipboard"),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.80,
          ),
          decoration: BoxDecoration(
            color: CrickXColors.graphiteElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: CrickXColors.graphiteBorder,
              width: 1.1,
            ),
          ),
          child: SelectableText(
            content,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // 🤖 ChatGPT-Style Reply (Direct on page, NO enclosing box/container)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: CrickXColors.limeSpark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    "X",
                    style: GoogleFonts.poppins(
                      color: CrickXColors.onLime,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "CrickX",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  content,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFECECF1),
                    fontSize: 15,
                    height: 1.6,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.15,
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: copy,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: Color(0xFF8E8EA0),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "Copy",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF8E8EA0),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- USER NAME HELPER ----------------
  String getUserName() {
    return _resolvedUserName;
  }

  // ---------------- QUICK CHIP + SUGGESTION WIDGETS ----------------
  Widget quickChip(String text) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          controller.text = text;
          sendMessage();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: CrickXColors.graphite,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget suggestionTile(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CrickXColors.graphite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: CrickXColors.graphiteElevated,
          onTap: () {
            controller.text = text;
            sendMessage();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CrickXColors.graphiteElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CrickXColors.graphiteBorder),
                  ),
                  child: const Icon(
                    Icons.sports_cricket_rounded,
                    color: CrickXColors.limeSpark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Tap to get instant coaching analysis",
                        style: GoogleFonts.poppins(
                          color: Colors.white38,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: CrickXColors.graphiteElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: CrickXColors.graphiteBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: CrickXColors.textSecondary,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /* ---------------- HISTORY DRAWER ---------------- */

  Widget buildHistoryDrawer(ChatSessionsProvider provider) {
    return Drawer(
      backgroundColor: CrickXColors.graphiteBg,
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
                  Text(
                    "Chat History",
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: "New Chat",
                    icon: const Icon(Icons.add_circle, color: CrickXColors.limeSpark),
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
              color: CrickXColors.graphiteBorder,
            ),
            Expanded(
              child: provider.loadingList
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: CrickXColors.limeSpark,
                      ),
                    )
                  : provider.sessions.isEmpty
                  ? Center(
                      child: Text(
                        "No previous chats",
                        style: GoogleFonts.poppins(color: CrickXColors.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: provider.sessions.length,
                      itemBuilder: (context, i) {
                        final session = provider.sessions[i];
                        final selected = session.id == provider.currentChatId;
                        return ListTile(
                          tileColor: selected ? CrickXColors.graphiteElevated : null,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          title: Text(
                            session.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: selected ? CrickXColors.limeSpark : Colors.white,
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
                              color: CrickXColors.textMuted,
                            ),
                            onPressed: () async {
                              await provider.deleteChat(session.id);
                            },
                          ),
                          onTap: () async {
                            await provider.openChat(session.id);
                            if (!context.mounted) return;
                            Navigator.pop(context);
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
          final isPremium =
              PremiumService.isLoaded && PremiumService.isPremiumActive;
          final chatCredits = AnalysisCreditService.instance.chatCredits;
          final locked = !isPremium && chatCredits <= 0;

          void unlock() {
            _showWatchAdForChatDialog();
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
            backgroundColor: CrickXColors.graphiteBg,
            appBar: AppBar(
              backgroundColor: CrickXColors.graphiteBg,
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
              title: Text(
                "CricX Coach",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable:
                      AnalysisCreditService.instance.chatCreditsNotifier,
                  builder: (context, credits, _) {
                    final premium =
                        PremiumService.isLoaded && PremiumService.isPremiumActive;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: InkWell(
                          onTap: premium ? null : () => _showWatchAdForChatDialog(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: premium
                                  ? CrickXColors.limeSpark.withValues(alpha: 0.2)
                                  : (credits > 0
                                      ? CrickXColors.limeSpark
                                          .withValues(alpha: 0.15)
                                      : Colors.orange.withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: premium
                                    ? CrickXColors.limeSpark
                                    : (credits > 0
                                        ? CrickXColors.limeSpark
                                        : Colors.orangeAccent),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  premium
                                      ? Icons.star_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  size: 14,
                                  color: premium
                                      ? CrickXColors.limeSpark
                                      : (credits > 0
                                          ? CrickXColors.limeSpark
                                          : Colors.orangeAccent),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  premium ? "PRO" : "$credits left",
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                if (!premium) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.add_circle,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
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
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: CrickXColors.graphite,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: CrickXColors.graphiteBorder,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    "CricX Coach: Your action plan is simple—fix your head position, shorten your run-up, and focus on one seam drill daily for 10 minutes...",
                                    maxLines: 2,
                                    overflow: TextOverflow.fade,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      height: 1.45,
                                    ),
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
                                  ctaText: "WATCH AD (5 CHATS) OR GO PRO",
                                  title: "CricX Coach Locked",
                                  subtitle:
                                      "Watch an ad to get 5 free CricX Coach messages, or upgrade to Premium.",
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
                                  horizontal: 18,
                                  vertical: 18,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 👤 Coach Greeting Card (Upload Screen Luxury Style)
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: CrickXColors.graphite,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: CrickXColors.graphiteBorder,
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.7),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: CrickXColors.graphiteElevated,
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(
                                                    color: CrickXColors.graphiteBorder,
                                                    width: 1.2,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.sports_cricket_rounded,
                                                  color: CrickXColors.limeSpark,
                                                  size: 26,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          "CRICKX COACH",
                                                          style: GoogleFonts.poppins(
                                                            color: const Color(0xFFE2E8F0),
                                                            fontSize: 11.5,
                                                            fontWeight: FontWeight.w700,
                                                            letterSpacing: 1.1,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: CrickXColors.limeSpark.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            "ONLINE",
                                                            style: GoogleFonts.poppins(
                                                              color: CrickXColors.limeSpark,
                                                              fontSize: 9.5,
                                                              fontWeight: FontWeight.w700,
                                                              letterSpacing: 0.5,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      "Hello, ${getUserName()}! 👋",
                                                      style: GoogleFonts.poppins(
                                                        color: Colors.white,
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            "I am your personal AI cricket coach. Ask me anything about your batting stance, seam release, bowling action, or tactical match strategy.",
                                            style: GoogleFonts.poppins(
                                              color: Colors.white.withValues(alpha: 0.72),
                                              fontSize: 13.5,
                                              height: 1.45,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 22),

                                    // ⚡ Quick Action Chips
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        quickChip("🏏 Batting Tips"),
                                        quickChip("🥎 Bowling Tips"),
                                        quickChip("🧠 Match Mindset"),
                                      ],
                                    ),

                                    const SizedBox(height: 26),

                                    // 🏆 Suggested Questions
                                    Text(
                                      "Suggested Questions",
                                      style: GoogleFonts.poppins(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
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
                            : Builder(
                                builder: (_) {
                                  final messages =
                                      List<Map<String, dynamic>>.from(
                                        provider.messages,
                                      );
                                  return ListView.builder(
                                    controller: _scrollController,
                                    itemCount: messages.length,
                                    itemBuilder: (_, i) =>
                                        buildMessage(messages[i]),
                                  );
                                },
                              )),
                ),
                // ChatGPT-style unboxed AI thinking indicator
                if (loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: CrickXColors.limeSpark,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              "X",
                              style: GoogleFonts.poppins(
                                color: CrickXColors.onLime,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "CricX is thinking...",
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF8E8EA0),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation(CrickXColors.limeSpark),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 🚀 ChatGPT-Style Big Input Bar with Mic & Send Inside It
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                      decoration: BoxDecoration(
                        color: CrickXColors.graphite,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: CrickXColors.graphiteBorder,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 16,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: AbsorbPointer(
                              absorbing: locked,
                              child: TextField(
                                controller: controller,
                                minLines: 1,
                                maxLines: 5,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                ),
                                cursorColor: CrickXColors.limeSpark,
                                decoration: InputDecoration(
                                  hintText: "Message CricX...",
                                  hintStyle: GoogleFonts.poppins(
                                    color: CrickXColors.textMuted,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // 🎙️ Mic Icon (Inside the Bar)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: locked ? unlock : toggleMic,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isListening
                                        ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: isListening
                                        ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
                                        : null,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                                      color: isListening
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF94A3B8),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // ⬆️ Send Button (ChatGPT Round Upward Arrow Inside the Bar)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: locked ? unlock : sendMessage,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _charCount > 0
                                        ? CrickXColors.limeSpark
                                        : CrickXColors.graphiteElevated,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.arrow_upward_rounded,
                                      color: _charCount > 0
                                          ? CrickXColors.onLime
                                          : CrickXColors.textMuted,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

