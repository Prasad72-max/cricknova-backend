import 'package:flutter/material.dart';

class AnalyseYourselfScreen extends StatelessWidget {
  const AnalyseYourselfScreen({super.key});

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