import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../services/reel_service.dart';

class ReelVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String reelId;
  final bool isActive;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback? onDoubleTapLike;

  const ReelVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.reelId,
    required this.isActive,
    required this.isMuted,
    required this.onToggleMute,
    this.onDoubleTapLike,
  });

  @override
  State<ReelVideoPlayer> createState() => _ReelVideoPlayerState();
}

class _ReelVideoPlayerState extends State<ReelVideoPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  WebViewController? _webViewController;
  bool _isYouTube = false;
  String? _youtubeId;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = true;
  bool _showCenterIcon = false;
  Timer? _centerIconTimer;
  Timer? _viewThresholdTimer;

  // Big heart animation on double tap
  bool _showHeartAnim = false;
  late AnimationController _heartAnimController;

  static String? extractYouTubeId(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return null;

    final idRegex = RegExp(r'^[a-zA-Z0-9_-]{11}$');
    if (idRegex.hasMatch(clean)) return clean;

    final uri = Uri.tryParse(clean);
    if (uri == null) return null;

    if (uri.pathSegments.contains('shorts')) {
      final idx = uri.pathSegments.indexOf('shorts');
      if (idx + 1 < uri.pathSegments.length) {
        return uri.pathSegments[idx + 1].split('?').first;
      }
    }

    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first.split('?').first;
    }

    if (uri.queryParameters.containsKey('v')) {
      return uri.queryParameters['v'];
    }

    if (uri.pathSegments.contains('embed')) {
      final idx = uri.pathSegments.indexOf('embed');
      if (idx + 1 < uri.pathSegments.length) {
        return uri.pathSegments[idx + 1].split('?').first;
      }
    }

    return null;
  }

  String _buildYouTubeHtml(String videoId, bool isMuted) {
    final muteVal = isMuted ? 1 : 0;
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
      background: #000;
      overflow: hidden;
      -webkit-touch-callout: none;
      -webkit-user-select: none;
      user-select: none;
    }
    html, body {
      width: 100%;
      height: 100%;
      background: #000;
    }
    .video-wrapper {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000;
    }
    iframe {
      width: 100vw;
      height: 100vh;
      border: 0;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div class="video-wrapper">
    <iframe
      id="cricket-player"
      src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&mute=$muteVal&controls=0&loop=1&playlist=$videoId&playsinline=1&rel=0&modestbranding=1&enablejsapi=1&fs=0&disablekb=1&iv_load_policy=3&origin=https://www.youtube-nocookie.com"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
      allowfullscreen>
    </iframe>
  </div>
</body>
</html>
''';
  }

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final ytId = extractYouTubeId(widget.videoUrl);
    if (ytId != null) {
      _isYouTube = true;
      _youtubeId = ytId;

      try {
        late final PlatformWebViewControllerCreationParams params;
        if (WebViewPlatform.instance is WebKitWebViewPlatform) {
          params = WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }

        final controller = WebViewController.fromPlatformCreationParams(params);

        controller
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black);

        if (controller.platform is AndroidWebViewController) {
          AndroidWebViewController.enableDebugging(false);
          (controller.platform as AndroidWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        }

        final html = _buildYouTubeHtml(ytId, widget.isMuted);
        await controller.loadHtmlString(
          html,
          baseUrl: 'https://www.youtube-nocookie.com',
        );

        if (!mounted) return;
        setState(() {
          _webViewController = controller;
          _isInitialized = true;
          _hasError = false;
        });

        if (widget.isActive) {
          _startViewThresholdTimer();
        }
        return;
      } catch (e) {
        debugPrint("REEL_YOUTUBE_INIT_ERROR: $e");
        if (mounted) {
          setState(() {
            _hasError = true;
            _isInitialized = false;
          });
        }
        return;
      }
    }

    _isYouTube = false;
    _youtubeId = null;

    try {
      if (widget.videoUrl.startsWith('assets/')) {
        _controller = VideoPlayerController.asset(
          widget.videoUrl,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final uri = Uri.parse(widget.videoUrl);
        _controller = VideoPlayerController.networkUrl(
          uri,
          httpHeaders: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Accept': '*/*',
          },
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }

      await _controller!.initialize();
      if (!mounted) return;

      await _controller!.setLooping(true);
      await _controller!.setVolume(widget.isMuted ? 0.0 : 1.0);

      setState(() {
        _isInitialized = true;
        _hasError = false;
      });

      if (widget.isActive) {
        await _controller!.play();
        _startViewThresholdTimer();
      }
    } catch (e) {
      debugPrint("REEL_VIDEO_INIT_ERROR: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  void _startViewThresholdTimer() {
    _viewThresholdTimer?.cancel();
    _viewThresholdTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && widget.isActive) {
        if (_isYouTube || (_controller != null && _controller!.value.isPlaying)) {
          ReelService.recordView(widget.reelId);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReelVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isMuted != widget.isMuted) {
      if (_isYouTube && _webViewController != null) {
        final func = widget.isMuted ? "mute" : "unMute";
        _webViewController!.runJavaScript(
          'document.getElementById("cricket-player")?.contentWindow?.postMessage(JSON.stringify({event: "command", func: "$func", args: ""}), "*");',
        );
      } else if (_controller != null) {
        _controller!.setVolume(widget.isMuted ? 0.0 : 1.0);
      }
    }

    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        if (_isYouTube && _webViewController != null) {
          _webViewController!.runJavaScript(
            'document.getElementById("cricket-player")?.contentWindow?.postMessage(JSON.stringify({event: "command", func: "playVideo", args: ""}), "*");',
          );
          _isPlaying = true;
          _startViewThresholdTimer();
        } else if (_controller != null && _isInitialized) {
          _controller!.play();
          _isPlaying = true;
          _startViewThresholdTimer();
        } else if (!_isInitialized && !_hasError) {
          _initializePlayer();
        }
      } else {
        _viewThresholdTimer?.cancel();
        if (_isYouTube && _webViewController != null) {
          _webViewController!.runJavaScript(
            'document.getElementById("cricket-player")?.contentWindow?.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: ""}), "*");',
          );
          _isPlaying = false;
        } else if (_controller != null) {
          _controller?.pause();
          _isPlaying = false;
        }
      }
    }
  }

  void _togglePlayPause() {
    if (_isYouTube && _webViewController != null) {
      setState(() {
        if (_isPlaying) {
          _webViewController!.runJavaScript(
            'document.getElementById("cricket-player")?.contentWindow?.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: ""}), "*");',
          );
          _isPlaying = false;
        } else {
          _webViewController!.runJavaScript(
            'document.getElementById("cricket-player")?.contentWindow?.postMessage(JSON.stringify({event: "command", func: "playVideo", args: ""}), "*");',
          );
          _isPlaying = true;
          _startViewThresholdTimer();
        }
        _showCenterIcon = true;
      });

      _centerIconTimer?.cancel();
      _centerIconTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showCenterIcon = false);
      });
      return;
    }

    if (_controller == null || !_isInitialized) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
        _startViewThresholdTimer();
      }
      _showCenterIcon = true;
    });

    _centerIconTimer?.cancel();
    _centerIconTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showCenterIcon = false);
    });
  }

  void _handleDoubleTap() {
    widget.onDoubleTapLike?.call();
    setState(() => _showHeartAnim = true);
    _heartAnimController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeartAnim = false);
    });
  }

  @override
  void dispose() {
    _viewThresholdTimer?.cancel();
    _centerIconTimer?.cancel();
    _heartAnimController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: const Color(0xFF0D0E12),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_cricket_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            const Text(
              "Cricket Reel Unavailable",
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() => _hasError = false);
                _initializePlayer();
              },
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text("Retry", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || (_isYouTube ? _webViewController == null : _controller == null)) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayPause,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Surface (YouTube WebView or Native VideoPlayer)
          if (_isYouTube && _webViewController != null)
            IgnorePointer(
              ignoring: true,
              child: WebViewWidget(controller: _webViewController!),
            )
          else if (_controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio > 0
                    ? _controller!.value.aspectRatio
                    : 9 / 16,
                child: VideoPlayer(_controller!),
              ),
            ),

          // 2. Play/Pause Center Indicator
          if (_showCenterIcon)
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _showCenterIcon ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),

          // 3. Instagram Big Double-Tap Heart Animation
          if (_showHeartAnim)
            Center(
              child: ScaleTransition(
                scale: TweenSequence<double>([
                  TweenSequenceItem(
                    tween: Tween<double>(begin: 0.0, end: 1.25)
                        .chain(CurveTween(curve: Curves.easeOutBack)),
                    weight: 40,
                  ),
                  TweenSequenceItem(
                    tween: Tween<double>(begin: 1.25, end: 1.0)
                        .chain(CurveTween(curve: Curves.easeInOut)),
                    weight: 20,
                  ),
                  TweenSequenceItem(
                    tween: Tween<double>(begin: 1.0, end: 0.0)
                        .chain(CurveTween(curve: Curves.easeInQuad)),
                    weight: 40,
                  ),
                ]).animate(_heartAnimController),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 110,
                  shadows: [
                    Shadow(color: Colors.redAccent, blurRadius: 30),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
