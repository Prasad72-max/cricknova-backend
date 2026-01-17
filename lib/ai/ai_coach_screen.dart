import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/api_config.dart';
import '../premium/premium_screen.dart';
import '../services/premium_service.dart';

class AICoachScreen extends StatefulWidget {
  final Map<String, dynamic>? context;
  final String? initialQuestion;

  const AICoachScreen({super.key, this.context, this.initialQuestion});

  @override
  State<AICoachScreen> createState() => _AICoachScreenState();
}

class _AICoachScreenState extends State<AICoachScreen> {
  late final Uri uri;

  final TextEditingController controller = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool loading = false;
  bool isListening = false;

  int currentChatIndex = 0;
  List<Map<String, dynamic>> chats = [];

  // Helper to block free users after paywall
  bool _blocked = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!PremiumService.isLoaded) {
        await PremiumService.restoreOnLaunch();
      }

      // TEMP: allow AI access even if not premium (payment debug mode)
      // Premium enforcement handled server-side for now

      uri = Uri.parse("${ApiConfig.baseUrl}/coach/chat");
      await loadChats();

      if (widget.initialQuestion != null &&
          widget.initialQuestion!.isNotEmpty) {
        controller.text = widget.initialQuestion!;
        sendMessage();
      }
    });
  }

  /* ---------------- STORAGE ---------------- */

  Future<void> saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("cricknova_chats", jsonEncode(chats));
  }

  Future<void> loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString("cricknova_chats");

    if (data != null) {
      chats = List<Map<String, dynamic>>.from(jsonDecode(data));
    }

    if (chats.isEmpty) {
      createNewChat();
    }
    currentChatIndex = 0;

    setState(() {});
  }

  void createNewChat() {
    chats.insert(0, {
      "title": "New Chat",
      "messages": [],
    });
    currentChatIndex = 0;
    saveChats();
    setState(() {});
  }

  List<Map<String, dynamic>> get messages {
    if (chats.isEmpty) return [];
    if (currentChatIndex < 0 || currentChatIndex >= chats.length) return [];
    final msgs = chats[currentChatIndex]["messages"];
    if (msgs == null) return [];
    return List<Map<String, dynamic>>.from(msgs);
  }

  /* ---------------- SEND MESSAGE ---------------- */

  Future<void> sendMessage() async {
    // 🔁 Always ensure premium data is restored before checking limits
    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }

    // ✅ Premium users should NEVER be blocked by local limits
    final isPremium = PremiumService.isPremium;

    if (!isPremium) {
      final remaining = await PremiumService.getChatLimit();
      if (remaining <= 0) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Chat Limit Reached"),
              content: const Text(
                "You have used all AI Coach chats for your plan.\nUpgrade to continue.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    String userMessage = controller.text.trim();
    if (userMessage.isEmpty) return;

    controller.clear();

    if (chats[currentChatIndex]["messages"].isEmpty) {
      chats[currentChatIndex]["title"] =
          userMessage.length > 25
              ? "${userMessage.substring(0, 25)}…"
              : userMessage;
    }

    chats[currentChatIndex]["messages"].add({
      "role": "user",
      "text": userMessage,
    });

    loading = true;
    saveChats();
    setState(() {});

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }
      final idToken = await user.getIdToken(true);

      final response = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "Authorization": "Bearer ${user.uid}",
            },
            body: jsonEncode({
              "message": userMessage,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        chats[currentChatIndex]["messages"].add({
          "role": "coach",
          "text": "Session expired. Please reopen the app or login again.",
        });
        loading = false;
        saveChats();
        setState(() {});
        return;
      }

      String coachText;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        coachText = decoded["reply"]?.toString() ??
            decoded["coach_feedback"]?.toString() ??
            "No reply received";
        await PremiumService.consumeChat();
      } 
      else if (response.statusCode == 403) {
        loading = false;
        saveChats();
        setState(() {});

        // 🚫 Redirect ONLY if user is truly not premium
        final isPremium = PremiumService.isPremium;
        if (!isPremium && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PremiumScreen()),
          );
        }
        return;
      }
      else if (response.statusCode == 404 &&
               response.body.toLowerCase().contains("premium")) {
        loading = false;
        saveChats();
        setState(() {});

        final isPremium = PremiumService.isPremium;
        if (!isPremium && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PremiumScreen()),
          );
        }
        return;
      }
      else {
        coachText =
            "Server error ${response.statusCode}: ${response.body}";
      }

      chats[currentChatIndex]["messages"].add({
        "role": "coach",
        "text": coachText,
      });
    } catch (e) {
      chats[currentChatIndex]["messages"].add({
        "role": "coach",
        "text": "Session expired or authentication failed. Please login again.",
      });
    }

    loading = false;
    saveChats();
    setState(() {});
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
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin:
            const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF1E293B)  // dark slate (user)
              : const Color(0xFF0F766E), // muted cyan (coach)
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          msg["text"],
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  /* ---------------- HISTORY DRAWER ---------------- */

  Widget buildHistoryDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF020617),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            "CrickNova History",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (context, i) {
                return ListTile(
                  title: Text(
                    chats[i]["title"],
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: i == currentChatIndex,
                  onTap: () {
                    currentChatIndex = i;
                    Navigator.pop(context);
                    setState(() {});
                  },
                );
              },
            ),
          ),
          ListTile(
            leading:
                const Icon(Icons.add, color: Colors.white),
            title: const Text(
              "New Chat",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              createNewChat();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🔒 HARD BLOCK FREE USERS BEFORE UI RENDERS
    if (!PremiumService.isLoaded) {
      return const SizedBox.shrink();
    }

    // TEMP: do not block UI for non-premium during debug

    return Scaffold(
      drawer: buildHistoryDrawer(),
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
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      "Start your first AI coaching session",
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (_, i) =>
                        buildMessage(messages[i]),
                  ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: AnimatedTextKit(
                repeatForever: true,
                animatedTexts: [
                  TyperAnimatedText(
                    "CrickNova analysing...",
                    textStyle:
                        const TextStyle(color: Color(0xFF94A3B8)),
                  )
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
                      decoration: const InputDecoration(
                        hintText: "Ask CrickNova AI Coach...",
                        hintStyle: TextStyle(color: Color(0xFF64748B)),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isListening
                        ? Icons.mic
                        : Icons.mic_none,
                    color: isListening
                        ? Colors.red
                        : Colors.white,
                  ),
                  onPressed: toggleMic,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: sendMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}