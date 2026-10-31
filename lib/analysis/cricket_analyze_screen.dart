import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cricket_analyze_api.dart';
import '../theme/crickx_colors.dart';

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
      backgroundColor: CrickXColors.graphiteBg,
      appBar: AppBar(
        backgroundColor: CrickXColors.graphiteBg,
        foregroundColor: Colors.white,
        title: Text(
          "CricX Coach",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
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
                      style: GoogleFonts.poppins(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Ask about your batting, bowling, mindset...",
                        hintStyle: GoogleFonts.poppins(color: Colors.white38),
                        filled: true,
                        fillColor: CrickXColors.graphiteElevated,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: CrickXColors.graphiteBorder,
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: CrickXColors.graphiteBorder,
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: CrickXColors.limeSpark,
                            width: 1.2,
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
                      backgroundColor: CrickXColors.limeSpark,
                      foregroundColor: CrickXColors.onLime,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      "Ask",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: CrickXColors.onLime,
                      ),
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
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
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
                              color: CrickXColors.limeSpark,
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              "Error: ${snap.error}",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                height: 1.35,
                              ),
                            ),
                          );
                        }
                        final md = (snap.data ?? "").trim();
                        if (md.isEmpty) {
                          return Center(
                            child: Text(
                              "No reply.",
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: CrickXColors.graphite,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: CrickXColors.graphiteBorder,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: MarkdownBody(
                            data: md,
                            styleSheet: MarkdownStyleSheet(
                              p: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 14.5,
                                height: 1.5,
                              ),
                              h2: GoogleFonts.poppins(
                                color: CrickXColors.limeSpark,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              strong: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
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
