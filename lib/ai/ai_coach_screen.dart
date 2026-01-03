import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    uri = Uri.parse("${ApiConfig.baseUrl}/coach/chat");
    loadChats();

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  List<Map<String, dynamic>> get messages =>
      List<Map<String, dynamic>>.from(chats[currentChatIndex]["messages"]);

  /* ---------------- SEND MESSAGE ---------------- */

  Future<void> sendMessage() async {
    // 🔒 Premium Gate
    final isPremium = await PremiumService.isPremium();
    if (!isPremium) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
      }
      return;
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
      final response = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({
              "message": userMessage,
            }),
          )
          .timeout(const Duration(seconds: 8));

      String coachText;
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        coachText = decoded["reply"]?.toString() ??
            decoded["coach_feedback"]?.toString() ??
            "No reply received";
      } else {
        coachText =
            "Server error ${response.statusCode}: ${response.body}";
      }

      chats[currentChatIndex]["messages"].add({
        "role": "coach",
        "text": coachText,
      });
    } catch (_) {
      chats[currentChatIndex]["messages"].add({
        "role": "coach",
        "text": "AI Coach not reachable. Check server & WiFi.",
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
          color:
              isUser ? const Color(0xFF2563EB) : const Color(0xFF16A34A),
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
                    style: const TextStyle(color: Colors.white),
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
    return Scaffold(
      drawer: buildHistoryDrawer(),
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        elevation: 0,
        title: const Text(
          "CrickNova AI Coach",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
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
                        const TextStyle(color: Colors.white70),
                  )
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style:
                        const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText:
                          "Ask CrickNova AI Coach...",
                      hintStyle:
                          TextStyle(color: Colors.white54),
                      border: InputBorder.none,
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
                  icon: const Icon(Icons.send,
                      color: Colors.white),
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