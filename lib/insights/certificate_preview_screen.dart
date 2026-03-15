import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../widgets/premium_blur_lock.dart';
import 'performance_certificate.dart';

class CertificatePreviewScreen extends StatefulWidget {
  const CertificatePreviewScreen({
    super.key,
    required this.playerName,
    required this.topSpeed,
    required this.avgSpeed,
    required this.accuracyPercent,
    required this.sessionXp,
    required this.speedSeries,
    required this.sessionId,
    required this.appLink,
    required this.certificateSerial,
  });

  final String playerName;
  final double topSpeed;
  final double avgSpeed;
  final double accuracyPercent;
  final int sessionXp;
  final List<double> speedSeries;
  final String sessionId;
  final String appLink;
  final String certificateSerial;

  @override
  State<CertificatePreviewScreen> createState() =>
      _CertificatePreviewScreenState();
}

class _CertificatePreviewScreenState extends State<CertificatePreviewScreen> {
  final GlobalKey _certificateKey = GlobalKey();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await PremiumService.restoreOnLaunch();
      if (mounted) setState(() {});
    });
    PremiumService.premiumNotifier.addListener(_onPremiumChanged);
  }

  void _onPremiumChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    PremiumService.premiumNotifier.removeListener(_onPremiumChanged);
    super.dispose();
  }

  Future<void> _shareCertificate() async {
    if (_sharing) return;
    if (!PremiumService.isLoaded || !PremiumService.isPremiumActive) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PremiumScreen(entrySource: "certificate_lock"),
        ),
      );
      return;
    }
    setState(() => _sharing = true);
    try {
      final boundary =
          _certificateKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File(
        '${tempDir.path}/cricknova_certificate.png',
      ).create();
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '🏏 My CrickNova Certificate\nTop: ${widget.topSpeed.toStringAsFixed(1)} km/h\nAvg: ${widget.avgSpeed.toStringAsFixed(1)} km/h\nAccuracy: ${widget.accuracyPercent.toStringAsFixed(0)}%\nXP: ${widget.sessionXp}\n${widget.appLink}',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to share certificate")),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = !PremiumService.isLoaded || !PremiumService.isPremiumActive;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        foregroundColor: Colors.white,
        title: const Text("Certificate"),
        actions: [
          IconButton(
            onPressed: (_sharing || locked) ? null : _shareCertificate,
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: RepaintBoundary(
                  key: _certificateKey,
                  child: PremiumBlurLock(
                    locked: locked,
                    ctaText: "UNLOCK PREMIUM CERTIFICATE",
                    title: "Certificate Locked",
                    subtitle:
                        "Upgrade to unlock high-res certificate export and verification sharing.",
                    onUnlock: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PremiumScreen(
                            entrySource: "certificate_lock",
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(26),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: constraints.maxHeight,
                      ),
                      child: PerformanceCertificate(
                        boundaryKey: GlobalKey(),
                        playerName: widget.playerName,
                        topSpeed: widget.topSpeed,
                        avgSpeed: widget.avgSpeed,
                        accuracyPercent: widget.accuracyPercent,
                        sessionXp: widget.sessionXp,
                        speedSeries: widget.speedSeries,
                        sessionId: widget.sessionId,
                        appLink: widget.appLink,
                        darkPremium: true,
                        certificateSerial: widget.certificateSerial,
                        isPremiumUser: PremiumService.isPremiumActive,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_sharing || locked) ? null : _shareCertificate,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text("Share"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFA500),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2937),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("Close"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
