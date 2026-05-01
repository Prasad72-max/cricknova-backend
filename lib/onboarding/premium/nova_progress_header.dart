import 'package:flutter/material.dart';

import 'nova_tokens.dart';

class NovaProgressHeader extends StatelessWidget {
  final VoidCallback? onBack;
  final double progress; // 0..1
  final String progressText;
  final String? stepText;

  const NovaProgressHeader({
    super.key,
    required this.progress,
    required this.progressText,
    this.stepText,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final clamped = progress.clamp(0.0, 1.0);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: NovaTokens.topBarHeight - 10,
              child: Row(
                children: [
                  _BackPill(onTap: onBack),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progressText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaTypography.labelMono(
                            color: NovaColors.textMuted,
                            size: 11,
                            letterSpacing: 2.0,
                          ),
                        ),
                        if (stepText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            stepText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaTypography.body(
                              color: NovaColors.textSecondary,
                              size: 13,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: NovaTokens.progressBarHeight,
                color: NovaColors.progressTrack,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: clamped),
                    duration: NovaMotion.maybe(
                      NovaTokens.dMed,
                      reduceMotion: reduceMotion,
                    ),
                    curve: NovaTokens.easeInOut,
                    builder: (context, t, _) {
                      return FractionallySizedBox(
                        widthFactor: t.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: NovaColors.progressFill,
                          ),
                        ),
                      );
                    },
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

class _BackPill extends StatelessWidget {
  final VoidCallback? onTap;

  const _BackPill({this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.35,
        duration: NovaTokens.dFast,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NovaColors.bgSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: NovaColors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: NovaColors.accentGlow(0.10),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: NovaColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
