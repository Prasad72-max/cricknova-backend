import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/api_config.dart';
import '../premium/premium_screen.dart';


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

  final TextEditingController controller = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ScrollController _scrollController = ScrollController();

  bool loading = false;
  bool isListening = false;
  bool _chatsLoadedOnce = false;

  int currentChatIndex = 0;
  List<Map<String, dynamic>> chats = [];

  @override
  void initState() {
    super.initState();

    uri = Uri.parse("${ApiConfig.baseUrl}/coach/chat");

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadChats();

      if (widget.initialQuestion != null &&
          widget.initialQuestion!.isNotEmpty) {
        controller.text = widget.initialQuestion!;
        sendMessage();
      }
    });
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

  /* ---------------- STORAGE ---------------- */

  Future<void> saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("cricknova_chats", jsonEncode(chats));
  }

  Future<void> loadChats() async {
    if (_chatsLoadedOnce) return;

    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString("cricknova_chats");

    if (data != null) {
      chats = List<Map<String, dynamic>>.from(jsonDecode(data));
    }

    if (chats.isEmpty) {
      createNewChat();
    }

    currentChatIndex = 0;
    _chatsLoadedOnce = true;

    if (mounted) {
      setState(() {});
    }
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


  /* ---------------- SEND MESSAGE ---------------- */

  Future<void> sendMessage() async {
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

      debugPrint("🔥 FIREBASE ID TOKEN (AI COACH) PREFIX → ${idToken.substring(0, 30)}");

      http.Response response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "authorization": "Bearer ${idToken.trim()}",
        },
        body: jsonEncode({
          "message": userMessage,
        }),
      ).timeout(const Duration(seconds: 30));

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
      }
      else if (response.statusCode == 403) {
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Usage limit reached."),
            ),
          );
        }
        return;
      }
      else if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        debugPrint("AI COACH RESPONSE => $decoded");

        // ❌ Any other unexpected failure
        if (decoded["success"] != true &&
            decoded["status"] != "success") {
          throw Exception("AI failed");
        }

        final coachText =
            decoded["reply"]?.toString() ??
            decoded["coach_feedback"]?.toString() ??
            "No reply received from AI.";

        chats[currentChatIndex]["messages"].add({
          "role": "coach",
          "text": coachText,
        });

        saveChats();

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
            const SnackBar(
              content: Text("Server error. Please try again."),
            ),
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
          const SnackBar(
            content: Text("Network error. Please try again."),
          ),
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

      saveChats();
      return;
    }
    finally {
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
          msg["text"] ?? "",
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
            child: chats.isEmpty ||
                    chats[currentChatIndex]["messages"].isEmpty
                ? const Center(
                    child: Text(
                      "Start your first AI coaching session",
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount:
                        chats[currentChatIndex]["messages"].length,
                    itemBuilder: (_, i) =>
                        buildMessage(
                          chats[currentChatIndex]["messages"][i],
                        ),
                  ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "CrickNova analysing...",
                  style: TextStyle(color: Colors.white54),
                ),
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