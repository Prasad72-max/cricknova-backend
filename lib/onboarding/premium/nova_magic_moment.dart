import 'package:flutter/material.dart';

import 'nova_shimmer.dart';
import 'nova_step_scaffold.dart';
import 'nova_steps.dart';
import 'nova_tokens.dart';

class NovaMagicMomentScreen extends StatelessWidget {
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final String categoryLabel;
  final String title;
  final String subtitle;
  final List<NovaMetric> metrics;
  final String ctaLabel;
  final VoidCallback onContinue;

  const NovaMagicMomentScreen({
    super.key,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.categoryLabel,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.ctaLabel,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return NovaStepScaffold(
      onBack: onBack,
      progress: progress,
      progressText: 'Building your player profile',
      stepText: stepText,
      categoryLabel: categoryLabel,
      title: title,
      subtitle: subtitle,
      body: _MagicMetrics(metrics: metrics),
      ctaLabel: ctaLabel,
      ctaEnabled: true,
      onCta: onContinue,
    );
  }
}

class _MagicMetrics extends StatelessWidget {
  final List<NovaMetric> metrics;

  const _MagicMetrics({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Preview',
          style: NovaTypography.labelMono(
            color: NovaColors.textMuted,
            size: 11,
            letterSpacing: 2.1,
          ),
        ),
        const SizedBox(height: 10),
        NovaShimmer(
          enabled: true,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NovaColors.bgElevated,
              borderRadius: BorderRadius.circular(NovaTokens.rXl),
              border: Border.all(color: NovaColors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: NovaColors.accentGlow(0.14),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final m in metrics)
                      _MetricTile(label: m.label, value: m.value),
                  ],
                ),
                const SizedBox(height: 14),
                AnimatedOpacity(
                  opacity: 1,
                  duration: NovaMotion.maybe(
                    NovaTokens.dSlow,
                    reduceMotion: reduceMotion,
                  ),
                  curve: NovaTokens.ease,
                  child: Text(
                    'Your answers shape these. CrickNova adapts in real time.',
                    textAlign: TextAlign.center,
                    style: NovaTypography.body(
                      size: 12,
                      height: 1.35,
                      color: NovaColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: NovaColors.bgSurface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NovaColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: NovaTypography.labelMono(
                size: 10,
                letterSpacing: 1.9,
                color: NovaColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: NovaTypography.title(
                size: 18,
                weight: FontWeight.w800,
                color: NovaColors.textPrimary,
                height: 1.05,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
