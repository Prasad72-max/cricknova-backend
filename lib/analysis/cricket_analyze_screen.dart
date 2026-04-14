import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/cricket_analyze_api.dart';

class CricketAnalyzeScreen extends StatefulWidget {
  const CricketAnalyzeScreen({super.key});

  @override
  State<CricketAnalyzeScreen> createState() => _CricketAnalyzeScreenState();
}

class _CricketAnalyzeScreenState extends State<CricketAnalyzeScreen> {
  final _controller = TextEditingController();
  Future<String>? _future;

  Color _withA(Color c, double a) =>
      c.withAlpha((a * 255).round().clamp(0, 255));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _future = CricketAnalyzeApi.analyzeCricketMarkdown(query: q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050A12),
        foregroundColor: Colors.white,
        title: const Text(
          "CrickNova Coach",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Ask about your batting, bowling, mindset...",
                        hintStyle: TextStyle(color: _withA(Colors.white, 0.55)),
                        filled: true,
                        fillColor: _withA(Colors.white, 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _withA(Colors.white, 0.10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _withA(Colors.white, 0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF38BDF8),
                            width: 1.3,
                          ),
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      "Ask",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _future == null
                  ? Center(
                      child: Text(
                        "Type a cricket question and tap Ask.",
                        style: TextStyle(
                          color: _withA(Colors.white, 0.65),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : FutureBuilder<String>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF38BDF8),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Error: ${snap.error}",
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.35,
                              ),
                            ),
                          );
                        }
                        final md = (snap.data ?? "").trim();
                        if (md.isEmpty) {
                          return const Center(
                            child: Text(
                              "No reply.",
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                          decoration: BoxDecoration(
                            color: _withA(Colors.white, 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _withA(Colors.white, 0.10),
                            ),
                          ),
                          child: MarkdownBody(
                            data: md,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.45,
                              ),
                              h2: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                              strong: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
