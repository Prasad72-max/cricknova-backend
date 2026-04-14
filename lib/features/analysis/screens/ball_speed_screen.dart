import 'package:flutter/material.dart';

class BallSpeedScreen extends StatelessWidget {
  const BallSpeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ball Speed Analysis")),
      body: const Center(
        child: Text(
          "Ball Speed Screen",
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
