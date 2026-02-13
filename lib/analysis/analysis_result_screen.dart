import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalysisResultScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const AnalysisResultScreen({super.key, required this.data});

  @override
  State<AnalysisResultScreen> createState() => _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends State<AnalysisResultScreen> {

  @override
  Widget build(BuildContext context) {

    final Map<String, dynamic> src =
        (widget.data["data"] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(widget.data["data"])
            : (widget.data["result"] is Map<String, dynamic>)
                ? Map<String, dynamic>.from(widget.data["result"])
                : Map<String, dynamic>.from(widget.data);

    // ---------- SPEED (FULLTRACK STYLE, UI SAFE) ----------
    String speed = "Unavailable";

    final dynamic rawKmph =
        src["speed_kmph"] ??
        src["analysis"]?["speed_kmph"];

    final dynamic speedType =
        src["speed_type"] ??
        src["analysis"]?["speed_type"];

    if (rawKmph is num && rawKmph > 0) {
      if (speedType == "very_slow_estimate" ||
          speedType == "camera_normalized" ||
          speedType == "video_derived" ||
          speedType == "derived_physics") {
        speed = "~${rawKmph.toStringAsFixed(1)} km/h";
      } else {
        speed = "${rawKmph.toStringAsFixed(1)} km/h";
      }
    }

    // ---------- SWING (NORMALIZED FOR STABILITY) ----------
    String swing = "Straight";

    final rawSwing = src["swing"];
    if (rawSwing is String && rawSwing.trim().isNotEmpty) {
      final normalized = rawSwing.trim().toLowerCase();
      if (normalized.contains("in")) {
        swing = "Inswing";
      } else if (normalized.contains("out")) {
        swing = "Outswing";
      } else {
        swing = "Straight";
      }
    }

    // ---------- SPIN (NORMALIZED FOR STABILITY) ----------
    String spin = "No Spin";
    String spinStrength = "";

    final rawSpin = src["spin"];
    if (rawSpin is String && rawSpin.trim().isNotEmpty) {
      final normalized = rawSpin.trim().toLowerCase();
      if (normalized.contains("off")) {
        spin = "Off Spin";
      } else if (normalized.contains("leg")) {
        spin = "Leg Spin";
      } else if (normalized.contains("chinaman")) {
        spin = "Chinaman";
      } else {
        spin = "No Spin";
      }
    }

    final rawStrength = src["spin_strength"];
    if (rawStrength is String && rawStrength.trim().isNotEmpty) {
      spinStrength = rawStrength.trim();
    }

    // ---------- DRS 2.0 (Projection Based) ----------
    String drsDecision = "NA";
    String drsConfidenceText = "";

    final drs = src["drs"];

    if (drs is Map<String, dynamic>) {
      final decisionRaw = drs["decision"];
      final confidenceRaw = drs["stump_confidence"];

      if (decisionRaw != null) {
        final normalized =
            decisionRaw.toString().toLowerCase().trim();

        if (normalized.contains("not") &&
            normalized.contains("out")) {
          drsDecision = "NOT OUT";
        } else if (normalized.contains("out")) {
          drsDecision = "OUT";
        } else {
          drsDecision = normalized.toUpperCase();
        }
      }

      if (confidenceRaw is num) {
        final percent =
            (confidenceRaw.toDouble().clamp(0.0, 1.0)) * 100;
        drsConfidenceText =
            " (${percent.toStringAsFixed(0)}%)";
      }
    }


    final List trajectory =
        (src["trajectory"] is List) ? src["trajectory"] : [];

    final List pitchmap =
        (src["pitchmap"] is List) ? src["pitchmap"] : [];

    final Map releasePoint =
        (src["release_point"] is Map) ? src["release_point"] : {};

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          "Analysis Result",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _metric(
            "Speed",
            speed,
          ),
          _metric("Swing", swing),
          _metric(
            "Spin",
            (spinStrength.isNotEmpty)
                ? "$spin • $spinStrength"
                : spin,
          ),
          _metric(
            "DRS",
            drsDecision == "NA"
                ? "NA"
                : "$drsDecision$drsConfidenceText",
            valueColor: drsDecision == "OUT"
                ? Colors.red
                : drsDecision == "NOT OUT"
                    ? Colors.green
                    : Colors.orange,
          ),
          const SizedBox(height: 25),

          _chartTitle("Ball Trajectory"),
          _trajectoryGraph(trajectory),
          const SizedBox(height: 25),

          _chartTitle("Pitch Map"),
          _pitchMap(pitchmap),
          const SizedBox(height: 25),

          _chartTitle("Release Point Map"),
          _releaseMap(releasePoint),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            "$title: ",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: valueColor ?? Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // -------- TRAJECTORY GRAPH --------
  Widget _trajectoryGraph(List data) {
    if (data.isEmpty) return _placeholder("No trajectory data");

    return SizedBox(
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            "assets/pitch_bg.png",
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: Colors.black);
            },
          ),
          CustomPaint(
            painter: TrajectoryPainter(data),
          ),
        ],
      ),
    );
  }

  // -------- PITCH MAP --------
  Widget _pitchMap(List data) {
    if (data.isEmpty) return _placeholder("No pitch map data");
    return _scatter(data, 0, 1, 0, 1);
  }

  // -------- RELEASE POINT --------
  Widget _releaseMap(Map point) {
    if (point.isEmpty) return _placeholder("No release point");

    return SizedBox(
      height: 220,
      child: ScatterChart(
        ScatterChartData(
          minX: 0,
          maxX: 1,
          minY: 0,
          maxY: 1,
          borderData: FlBorderData(show: true),
          titlesData: FlTitlesData(show: false),
          scatterSpots: [
            ScatterSpot(
              (point["nx"] is num) ? point["nx"].toDouble() : 0.5,
              (point["ny"] is num) ? point["ny"].toDouble() : 0.5,
              dotPainter: FlDotCirclePainter(
                radius: 8,
                color: Colors.red,
                strokeWidth: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- UNIVERSAL SCATTER --------
  Widget _scatter(
      List data, double minX, double maxX, double minY, double maxY) {
    final spots = data.map<ScatterSpot>((p) {
      final x = p["x"];
      final y = p["y"];
      return ScatterSpot(
        x is num ? x.toDouble() : 0.5,
        y is num ? y.toDouble() : 0.5,
        dotPainter: FlDotCirclePainter(
          radius: 6,
          color: Colors.blueAccent,
          strokeWidth: 0,
        ),
      );
    }).toList();

    return SizedBox(
      height: 220,
      child: ScatterChart(
        ScatterChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          borderData: FlBorderData(show: true),
          titlesData: FlTitlesData(show: false),
          scatterSpots: spots,
        ),
      ),
    );
  }

  Widget _placeholder(String text) {
    return Container(
      height: 140,
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 16,
          color: Colors.black54,
        ),
      ),
    );
  }
}

class TrajectoryPainter extends CustomPainter {
  final List points;
  TrajectoryPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    return; // trajectory rendering disabled intentionally
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
      ),
      body: const Center(
        child: Text('Premium Screen'),
      ),
    );
  }
}