import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/reel_model.dart';
import '../../analysis/analysis_result_screen.dart';
import '../../theme/crickx_colors.dart';

class AiResultReelSheet extends StatelessWidget {
  final ReelAiAnalysis aiAnalysis;
  final String reelCaption;

  const AiResultReelSheet({
    super.key,
    required this.aiAnalysis,
    required this.reelCaption,
  });

  static void show(BuildContext context, ReelAiAnalysis analysis, String caption) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AiResultReelSheet(
        aiAnalysis: analysis,
        reelCaption: caption,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBowling = aiAnalysis.shotType.toLowerCase().contains("bowl") ||
        aiAnalysis.shotType.toLowerCase().contains("pitch");

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: CrickXColors.graphiteBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: CrickXColors.graphiteBorder, width: 1.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CrickXColors.graphiteElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CrickXColors.graphiteBorder,
                    width: 1.2,
                  ),
                ),
                child: const Icon(
                  Icons.sports_cricket_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aiAnalysis.shotType,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hasBowling ? "Bowling Biomechanics" : "Batting Technique Analysis",
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (aiAnalysis.aiScore != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: CrickXColors.limeSpark.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: CrickXColors.limeSpark.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: CrickXColors.limeSpark, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        "${aiAnalysis.aiScore!.toStringAsFixed(1)} / 10",
                        style: GoogleFonts.poppins(
                          color: CrickXColors.limeSpark,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Stat Grid
          Row(
            children: [
              if (aiAnalysis.ballSpeed != null)
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.speed_rounded,
                    label: "Ball Speed",
                    value: "${aiAnalysis.ballSpeed!.toStringAsFixed(1)} km/h",
                    accent: CrickXColors.limeSpark,
                  ),
                ),
              if (aiAnalysis.ballSpeed != null && (aiAnalysis.batSpeed != null || hasBowling))
                const SizedBox(width: 10),
              if (aiAnalysis.batSpeed != null)
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.flash_on_rounded,
                    label: "Bat Speed",
                    value: "${aiAnalysis.batSpeed!.toStringAsFixed(1)} km/h",
                    accent: CrickXColors.limeSpark,
                  ),
                )
              else if (hasBowling)
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.swap_calls_rounded,
                    label: "Swing Deviation",
                    value: aiAnalysis.swing,
                    accent: CrickXColors.limeSpark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.radar_rounded,
                  label: "Spin / Seam",
                  value: aiAnalysis.spin,
                  accent: CrickXColors.limeSpark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.timeline_rounded,
                  label: "Bat / Release Angle",
                  value: aiAnalysis.swing,
                  accent: CrickXColors.limeSpark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // AI Feedback Quote
          if (aiAnalysis.aiFeedback != null && aiAnalysis.aiFeedback!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CrickXColors.graphiteElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CrickXColors.graphiteBorder, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: CrickXColors.limeSpark, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        "AI Coach Feedback",
                        style: GoogleFonts.poppins(
                          color: CrickXColors.limeSpark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    aiAnalysis.aiFeedback!,
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // "View Full AI Analysis" Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CrickXColors.limeSpark,
                foregroundColor: CrickXColors.onLime,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnalysisResultScreen(
                      data: aiAnalysis.rawData.isNotEmpty
                          ? aiAnalysis.rawData
                          : {
                              "status": "success",
                              "speed_kmph": aiAnalysis.ballSpeed,
                              "bat_speed": aiAnalysis.batSpeed,
                              "swing": aiAnalysis.swing,
                              "spin": aiAnalysis.spin,
                              "shot": aiAnalysis.shotType,
                              "trajectory": aiAnalysis.trajectory,
                              "rating": aiAnalysis.aiScore,
                              "feedback": aiAnalysis.aiFeedback,
                            },
                    ),
                  ),
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "View Full AI Analysis",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: CrickXColors.onLime,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: CrickXColors.onLime),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CrickXColors.graphiteBorder, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
