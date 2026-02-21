import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyseYourselfScreen extends StatefulWidget {
  const AnalyseYourselfScreen({super.key});

  @override
  State<AnalyseYourselfScreen> createState() => _AnalyseYourselfScreenState();
}

class _AnalyseYourselfScreenState extends State<AnalyseYourselfScreen> {

  @override
  void initState() {
    super.initState();
    _incrementTotalVideos();
  }

  Future<void> _incrementTotalVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt("totalVideos") ?? 0;
    await prefs.setInt("totalVideos", current + 1);
    debugPrint("TOTAL VIDEOS UPDATED (COMPARE): ${current + 1}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Analyse Yourself",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: const Center(
        child: Text(
          "Compare two videos (Coming Next)",
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
      ),
    );
  }
}