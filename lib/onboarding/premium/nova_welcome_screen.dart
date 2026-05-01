import 'dart:ui';

import 'package:flutter/material.dart';

import 'nova_background.dart';
import 'nova_button.dart';
import 'nova_progress_header.dart';
import 'nova_reveal.dart';
import 'nova_tokens.dart';

class NovaWelcomeScreen extends StatefulWidget {
  final String brandTitle;
  final String heroTitle;
  final String heroSubtitle;
  final String ctaLabel;
  final VoidCallback onStart;

  const NovaWelcomeScreen({
    super.key,
    required this.brandTitle,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.ctaLabel,
    required this.onStart,
  });

  @override
  State<NovaWelcomeScreen> createState() => _NovaWelcomeScreenState();
}

class _NovaWelcomeScreenState extends State<NovaWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);

    return NovaAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const NovaProgressHeader(
              progress: 0,
              progressText: 'Building your player profile',
              stepText: null,
              onBack: null,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: NovaTokens.maxContentWidth,
                  ),
                  child: Padding(
                    padding: NovaTokens.pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) {
                            final t = reduceMotion ? 1.0 : _c.value;
                            final opacity = CurvedAnimation(
                              parent: _c,
                              curve: Curves.easeOut,
                            ).value;
                            final scale = lerpDouble(0.96, 1.0, t)!;
                            return Opacity(
                              opacity: reduceMotion ? 1 : opacity,
                              child: Transform.scale(
                                scale: reduceMotion ? 1 : scale,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 92,
                                      height: 92,
                                      decoration: BoxDecoration(
                                        color: NovaColors.bgSurface,
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: NovaColors.borderSubtle,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: NovaColors.accentGlow(0.16),
                                            blurRadius: 24,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.sports_cricket_rounded,
                                        size: 44,
                                        color: NovaColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      widget.brandTitle,
                                      textAlign: TextAlign.center,
                                      style: NovaTypography.title(
                                        size: 22,
                                        weight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                        color: NovaColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        NovaReveal(
                          delay: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 140),
                          from: const Offset(0, 18),
                          child: Text(
                            widget.heroTitle,
                            textAlign: TextAlign.center,
                            style: NovaTypography.display(
                              size: 40,
                              weight: FontWeight.w400,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        NovaReveal(
                          delay: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          from: const Offset(0, 18),
                          child: Text(
                            widget.heroSubtitle,
                            textAlign: TextAlign.center,
                            style: NovaTypography.body(
                              size: 15,
                              color: NovaColors.textSecondary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        SafeArea(
                          top: false,
                          child: NovaPrimaryButton(
                            label: widget.ctaLabel,
                            enabled: true,
                            onPressed: widget.onStart,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Takes under a minute. Feels like a custom session.',
                          textAlign: TextAlign.center,
                          style: NovaTypography.body(
                            size: 12,
                            height: 1.35,
                            color: NovaColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
