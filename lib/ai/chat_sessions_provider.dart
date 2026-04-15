import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime? timestamp;

  const ChatSession({
    required this.id,
    required this.title,
    required this.timestamp,
  });

  factory ChatSession.fromMap(Map<String, dynamic> data) {
    final ts = data["timestamp"];
    return ChatSession(
      id: (data["chat_id"] as String?) ?? "",
      title: (data["title"] as String?)?.trim().isNotEmpty == true
          ? data["title"] as String
          : "New Chat",
      timestamp: ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
    );
  }
}

class ChatSessionsProvider extends ChangeNotifier {
  ChatSessionsProvider({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  StreamSubscription<User?>? _authSub;
  String? _uid;
  Box? _box;
  final _rng = Random();

  bool loadingList = false;
  bool loadingChat = false;

  List<ChatSession> sessions = [];
  String? currentChatId;
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> _sessionStore = [];

  static const int _maxMessagesPerChat = 20; // 10 chats (user+coach)

  void _trimMessagesInPlace() {
    if (messages.length <= _maxMessagesPerChat) return;
    final overflow = messages.length - _maxMessagesPerChat;
    messages.removeRange(0, overflow);
  }

  void init() {
    _uid = _auth.currentUser?.uid;
    _loadSessions();
    _authSub = _auth.authStateChanges().listen((user) {
      if (user?.uid != _uid) {
        _uid = user?.uid;
        startNewChat(notify: false);
        _loadSessions();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    sessions = [];
    currentChatId = null;
    messages = [];
    loadingList = _uid != null;
    notifyListeners();

    if (_uid == null) {
      loadingList = false;
      return;
    }

    _box = await Hive.openBox("chat_sessions_${_uid!}");
    final raw = (_box!.get("sessions") as List?)?.cast<Map>() ?? const <Map>[];
    _sessionStore = raw
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: true);
    _rebuildSessions();
    loadingList = false;
    notifyListeners();
  }

  Future<void> startNewChat({bool notify = true}) async {
    currentChatId = null;
    messages = [];
    if (notify) notifyListeners();
  }

  Future<void> openChat(String chatId) async {
    if (_uid == null) return;
    loadingChat = true;
    notifyListeners();

    try {
      final session = _sessionStore.firstWhere((e) => e["chat_id"] == chatId);
      currentChatId = chatId;
      messages = _normalizeMessages(session["messages"]);
    } catch (_) {
      await startNewChat();
    } finally {
      loadingChat = false;
      notifyListeners();
    }
  }

  Future<void> deleteChat(String chatId) async {
    if (_uid == null) return;
    _sessionStore.removeWhere((e) => e["chat_id"] == chatId);
    await _persistSessions();
    if (chatId == currentChatId) {
      await startNewChat();
    }
  }

  Future<void> addUserMessage(String text) async {
    if (_uid == null) return;
    final message = {"role": "user", "content": text};

    if (currentChatId == null) {
      final chatId =
          "${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(9999)}";
      final title = _titleFrom(text);
      currentChatId = chatId;
      messages = [message];
      _sessionStore.insert(0, {
        "chat_id": chatId,
        "user_id": _uid,
        "title": title,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        "messages": List<Map<String, dynamic>>.from(messages),
      });
      await _persistSessions();
      notifyListeners();
      return;
    }

    messages.add(message);
    _trimMessagesInPlace();
    notifyListeners();
    await _updateMessages();
  }

  Future<void> addCoachMessage(String text) async {
    if (_uid == null || currentChatId == null) return;
    final message = {"role": "coach", "content": text};
    messages.add(message);
    _trimMessagesInPlace();
    notifyListeners();
    await _updateMessages();
  }

  Future<void> _updateMessages() async {
    if (_uid == null || currentChatId == null) return;
    final idx = _sessionStore.indexWhere((e) => e["chat_id"] == currentChatId);
    if (idx == -1) return;
    _sessionStore[idx]["messages"] = List<Map<String, dynamic>>.from(messages);
    _sessionStore[idx]["timestamp"] = DateTime.now().millisecondsSinceEpoch;
    await _persistSessions();
  }

  List<Map<String, dynamic>> _normalizeMessages(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final role = item["role"]?.toString() ?? "user";
      final content = item["content"] ?? item["text"] ?? "";
      out.add({"role": role, "content": content.toString()});
    }
    return out;
  }

  List<Map<String, String>> recentMessagesForApi({int maxItems = 8}) {
    if (messages.isEmpty) return const <Map<String, String>>[];
    final start = messages.length > maxItems ? messages.length - maxItems : 0;
    return messages
        .sublist(start)
        .map((item) {
          return <String, String>{
            "role": (item["role"] ?? "user").toString(),
            "content": (item["content"] ?? item["text"] ?? "").toString(),
          };
        })
        .toList(growable: false);
  }

  Future<void> _persistSessions() async {
    if (_box == null) return;
    await _box!.put("sessions", _sessionStore);
    _rebuildSessions();
  }

  void _rebuildSessions() {
    sessions = _sessionStore
        .map((e) => ChatSession.fromMap(e))
        .toList(growable: false);
    sessions.sort((a, b) {
      final at = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final bt = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
  }

  String _titleFrom(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return "New Chat";
    return trimmed.length > 28 ? "${trimmed.substring(0, 28)}…" : trimmed;
  }
}
