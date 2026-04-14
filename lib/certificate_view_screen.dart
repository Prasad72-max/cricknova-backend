import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'insights/performance_certificate.dart';

class CertificateViewScreen extends StatefulWidget {
  const CertificateViewScreen({
    super.key,
    required this.playerName,
    required this.topSpeed,
    required this.accuracyPercent,
    required this.sessionXp,
    required this.sessionId,
    required this.appLink,
    required this.darkPremium,
  });

  final String playerName;
  final double topSpeed;
  final double accuracyPercent;
  final int sessionXp;
  final String sessionId;
  final String appLink;
  final bool darkPremium;

  @override
  State<CertificateViewScreen> createState() => _CertificateViewScreenState();
}

class _CertificateViewScreenState extends State<CertificateViewScreen> {
  final GlobalKey _certKey = GlobalKey();
  bool _saving = false;
  bool _sharing = false;

  Future<Uint8List?> _capturePng() async {
    final boundary =
        _certKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    if (boundary.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 20));
      await WidgetsBinding.instance.endOfFrame;
    }

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) throw Exception("capture_failed");
      final result = await ImageGallerySaver.saveImage(
        bytes,
        quality: 100,
        name: "cricknova_certificate_${DateTime.now().millisecondsSinceEpoch}",
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (result['isSuccess'] == true) ? "Saved to gallery" : "Save failed",
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Could not save image.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) throw Exception("capture_failed");
      final tempDir = await getTemporaryDirectory();
      final file = await File(
        "${tempDir.path}/cricknova_certificate.png",
      ).create();
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            "My CrickNova AI Certificate\nTop: ${widget.topSpeed.toStringAsFixed(1)} km/h\nAccuracy: ${widget.accuracyPercent.toStringAsFixed(0)}%\n${widget.appLink}",
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not share certificate.")),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serial = buildCertificateSerial(widget.sessionId);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E19),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Performance Certificate",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: RepaintBoundary(
            key: _certKey,
            child: PerformanceCertificate(
              boundaryKey: GlobalKey(), // internal key unused here
              playerName: widget.playerName,
              topSpeed: widget.topSpeed,
              avgSpeed: widget.topSpeed,
              accuracyPercent: widget.accuracyPercent,
              sessionXp: widget.sessionXp,
              sessionId: widget.sessionId,
              appLink: widget.appLink,
              darkPremium: widget.darkPremium,
              certificateSerial: serial,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveToGallery,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: const Text("Download PNG"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _shareImage,
                  icon: _sharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.share_rounded),
                  label: const Text("Share with Friends"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
