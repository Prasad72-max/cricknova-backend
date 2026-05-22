import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PremiumVideoBackground extends StatelessWidget {
  const PremiumVideoBackground({
    super.key,
    required this.controller,
    required this.isReady,
    this.focalAlignment = Alignment.center,
    this.placeholder,
    this.overlayOpacity = 1,
  });

  final VideoPlayerController? controller;
  final bool isReady;
  final Alignment focalAlignment;
  final Widget? placeholder;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    final videoController = controller;
    final canPaintVideo =
        isReady &&
        videoController != null &&
        videoController.value.isInitialized &&
        !videoController.value.hasError &&
        videoController.value.size.width > 0 &&
        videoController.value.size.height > 0;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (canPaintVideo)
            _AspectSafeVideo(
              controller: videoController,
              focalAlignment: focalAlignment,
            )
          else
            placeholder ?? const ColoredBox(color: Colors.black),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color.lerp(
                      const Color(0xCC000000),
                      Colors.transparent,
                      1 - overlayOpacity,
                    )!,
                    Color.lerp(
                      const Color(0x66000000),
                      Colors.transparent,
                      1 - overlayOpacity,
                    )!,
                    Color.lerp(
                      const Color(0xEE000000),
                      Colors.transparent,
                      1 - overlayOpacity,
                    )!,
                  ],
                  stops: const <double>[0, 0.48, 1],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.08,
                  colors: <Color>[
                    Colors.transparent,
                    Color.lerp(
                      const Color(0x99000000),
                      Colors.transparent,
                      1 - overlayOpacity,
                    )!,
                  ],
                  stops: const <double>[0.45, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumVideoSurface extends StatelessWidget {
  const PremiumVideoSurface({
    super.key,
    required this.controller,
    required this.isReady,
    this.borderRadius = 28,
    this.placeholder,
  });

  final VideoPlayerController? controller;
  final bool isReady;
  final double borderRadius;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final videoController = controller;
    final canPaintVideo =
        isReady &&
        videoController != null &&
        videoController.value.isInitialized &&
        !videoController.value.hasError &&
        videoController.value.size.width > 0 &&
        videoController.value.size.height > 0;
    const aspectRatio = 9.0 / 16.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 42,
            offset: Offset(0, 26),
          ),
          BoxShadow(
            color: Color(0x33D4AF37),
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (canPaintVideo)
                VideoPlayer(videoController)
              else
                placeholder ?? const ColoredBox(color: Color(0xFF050505)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0x40D4AF37), width: 0.8),
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

class PremiumPhoneMockup extends StatelessWidget {
  const PremiumPhoneMockup({
    super.key,
    required this.controller,
    required this.isReady,
    this.borderRadius = 38,
    this.placeholder,
  });

  final VideoPlayerController? controller;
  final bool isReady;
  final double borderRadius;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final videoController = controller;
    final canPaintVideo =
        isReady &&
        videoController != null &&
        videoController.value.isInitialized &&
        !videoController.value.hasError &&
        videoController.value.size.width > 0 &&
        videoController.value.size.height > 0;
    const aspectRatio = 9.0 / 16.0;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth;
        final height = width / aspectRatio;

        // Proportional sizing for inner UI elements so it scales perfectly
        final actionBtnTop = height * 0.17;
        final volUpBtnTop = height * 0.23;
        final volDownBtnTop = height * 0.30;
        final powerBtnTop = height * 0.25;

        final actionBtnHeight = height * 0.035;
        final volBtnHeight = height * 0.065;
        final powerBtnHeight = height * 0.095;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // 1. PHYSICAL BUTTONS (Left Side)
                // Action Button
                Positioned(
                  left: -2,
                  top: actionBtnTop,
                  child: Container(
                    width: 2,
                    height: actionBtnHeight.clamp(8, 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF5A5852),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(2),
                        bottomLeft: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Volume Up
                Positioned(
                  left: -2,
                  top: volUpBtnTop,
                  child: Container(
                    width: 2,
                    height: volBtnHeight.clamp(16, 32),
                    decoration: const BoxDecoration(
                      color: Color(0xFF4C4A45),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(2),
                        bottomLeft: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Volume Down
                Positioned(
                  left: -2,
                  top: volDownBtnTop,
                  child: Container(
                    width: 2,
                    height: volBtnHeight.clamp(16, 32),
                    decoration: const BoxDecoration(
                      color: Color(0xFF4C4A45),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(2),
                        bottomLeft: Radius.circular(2),
                      ),
                    ),
                  ),
                ),

                // 2. PHYSICAL BUTTONS (Right Side)
                // Power / Side Button
                Positioned(
                  right: -2,
                  top: powerBtnTop,
                  child: Container(
                    width: 2,
                    height: powerBtnHeight.clamp(24, 48),
                    decoration: const BoxDecoration(
                      color: Color(0xFF4C4A45),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                ),

                // 3. MAIN DEVICE FRAME WITH DUAL-TONE METALLIC METALLURGY & AMBIENT GLOW
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: Border.all(
                        color: const Color(0xFF3A3833), // Outer polished rim
                        width: 1.2,
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFF5A5852), // Titanium Gold/Gray Highlight
                          Color(0xFF1E1D1B), // Dark Titanium
                          Color(0xFF2D2B27), // Mid Gold-Titanium
                          Color(0xFF121210), // Shadow Titanium
                        ],
                        stops: <double>[0.0, 0.35, 0.75, 1.0],
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0xE6000000), // Realistic deep drop shadow
                          blurRadius: 46,
                          offset: Offset(0, 24),
                        ),
                        BoxShadow(
                          color: Color(0x33D4AF37), // Subtle golden brand ambient glow
                          blurRadius: 36,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5.5), // Elegant Bezel spacing (black rim)
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF090909), // Perfect OLED Deep Black Bezel
                          borderRadius: BorderRadius.circular(borderRadius - 5.5),
                        ),
                        padding: const EdgeInsets.all(1.0), // Outer bezel to screen divider
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(borderRadius - 6.5),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              // A. Video screen player content
                              if (canPaintVideo)
                                VideoPlayer(videoController)
                              else
                                placeholder ?? const ColoredBox(color: Color(0xFF030303)),

                              // B. High-end glass reflections & subtle vignette
                              const IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: <Color>[
                                        Color(0x1F000000),
                                        Color(0x00000000),
                                        Color(0x3D000000),
                                      ],
                                      stops: <double>[0.0, 0.5, 1.0],
                                    ),
                                  ),
                                ),
                              ),

                              // C. Classy screen-wide light reflection (diagonal shine)
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: const Alignment(-1.6, -1.0),
                                      end: const Alignment(1.6, 1.0),
                                      colors: <Color>[
                                        Colors.white.withOpacity(0.0),
                                        Colors.white.withOpacity(0.02),
                                        Colors.white.withOpacity(0.09), // Sleek metallic stripe reflection
                                        Colors.white.withOpacity(0.02),
                                        Colors.white.withOpacity(0.0),
                                      ],
                                      stops: const <double>[0.0, 0.38, 0.44, 0.50, 1.0],
                                    ),
                                  ),
                                ),
                              ),

                              // D. Ultra-realistic iOS Status Bar Overlay
                              Positioned(
                                top: height * 0.024,
                                left: 16,
                                right: 16,
                                child: IgnorePointer(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // iOS time
                                      Text(
                                        '9:41',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: (width * 0.038).clamp(8.0, 11.0),
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.15,
                                        ),
                                      ),
                                      // Status icons (Cellular signal, WiFi, Battery)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Cellular Bars
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: List.generate(4, (index) {
                                              return Container(
                                                margin: const EdgeInsets.only(left: 1),
                                                width: 1.8,
                                                height: (index + 1) * 1.5 + 1,
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(
                                                    index < 3 ? 0.95 : 0.35,
                                                  ),
                                                  borderRadius: BorderRadius.circular(0.4),
                                                ),
                                              );
                                            }),
                                          ),
                                          const SizedBox(width: 3.5),
                                          // WiFi Wave Icon
                                          Icon(
                                            Icons.wifi,
                                            color: Colors.white.withOpacity(0.95),
                                            size: (width * 0.036).clamp(8.0, 10.5),
                                          ),
                                          const SizedBox(width: 3.5),
                                          // Battery container
                                          Container(
                                            width: 15.5,
                                            height: 8.0,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(2.2),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.95),
                                                width: 0.7,
                                              ),
                                            ),
                                            padding: const EdgeInsets.all(0.7),
                                            child: Stack(
                                              children: [
                                                Positioned.fill(
                                                  child: FractionallySizedBox(
                                                    alignment: Alignment.centerLeft,
                                                    widthFactor: 0.85,
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.95),
                                                        borderRadius: BorderRadius.circular(1.0),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 0.8),
                                          // Battery Tip
                                          Container(
                                            width: 1.0,
                                            height: 2.6,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.95),
                                              borderRadius: const BorderRadius.only(
                                                topRight: Radius.circular(0.6),
                                                bottomRight: Radius.circular(0.6),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // E. Highly Realistic Dynamic Island pill (camera dot & glass reflections)
                              Positioned(
                                top: height * 0.016,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      width: width * 0.28,
                                      height: (height * 0.045).clamp(14, 21),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF000000),
                                        borderRadius: BorderRadius.circular(999),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 3,
                                            offset: const Offset(0, 0.5),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Camera lens sensor reflection
                                          Positioned(
                                            right: width * 0.038,
                                            child: Container(
                                              width: 4.5,
                                              height: 4.5,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: RadialGradient(
                                                  colors: [
                                                    Color(0xFF0E1820),
                                                    Color(0xFF030507),
                                                  ],
                                                ),
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 1.2,
                                                  height: 1.2,
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Color(0x664FACFE), // Blue lens flare
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Proximity dot
                                          Positioned(
                                            left: width * 0.05,
                                            child: Container(
                                              width: 2.8,
                                              height: 2.8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white.withOpacity(0.06),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // F. iOS bottom Home Indicator capsule
                              Positioned(
                                bottom: 6,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      width: width * 0.35,
                                      height: 3.5,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AspectSafeVideo extends StatelessWidget {
  const _AspectSafeVideo({
    required this.controller,
    required this.focalAlignment,
  });

  final VideoPlayerController controller;
  final Alignment focalAlignment;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final viewport = constraints.biggest;
          final videoSize = controller.value.size;
          final viewportAspect = viewport.width / viewport.height;
          final videoAspect = videoSize.width / videoSize.height;

          final Size paintedSize;
          if (videoAspect > viewportAspect) {
            paintedSize = Size(viewport.height * videoAspect, viewport.height);
          } else {
            paintedSize = Size(viewport.width, viewport.width / videoAspect);
          }

          final scaleX = paintedSize.width / videoSize.width;
          final scaleY = paintedSize.height / videoSize.height;

          return Align(
            alignment: focalAlignment,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              filterQuality: FilterQuality.low,
              child: SizedBox(
                width: videoSize.width,
                height: videoSize.height,
                child: VideoPlayer(controller),
              ),
            ),
          );
        },
      ),
    );
  }
}
