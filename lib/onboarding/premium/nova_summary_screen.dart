import 'dart:ui';

import 'package:flutter/material.dart';

import 'nova_step_scaffold.dart';
import 'nova_steps.dart';
import 'nova_tokens.dart';

class NovaSummaryScreen extends StatefulWidget {
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final String title;
  final String subtitle;
  final List<NovaSummaryItem> items;
  final String ctaLabel;
  final VoidCallback onContinue;

  const NovaSummaryScreen({
    super.key,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.ctaLabel,
    required this.onContinue,
  });

  @override
  State<NovaSummaryScreen> createState() => _NovaSummaryScreenState();
}

class _NovaSummaryScreenState extends State<NovaSummaryScreen>
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
    return NovaStepScaffold(
      onBack: widget.onBack,
      progress: widget.progress,
      progressText: 'Building your player profile',
      stepText: widget.stepText,
      categoryLabel: 'Summary',
      title: widget.title,
      subtitle: widget.subtitle,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = reduceMotion
              ? 1.0
              : Curves.easeOutCubic.transform(_c.value);
          final opacity = t;
          final scale = lerpDouble(0.96, 1.0, t)!;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: _ProfileCard(items: widget.items),
            ),
          );
        },
      ),
      ctaLabel: widget.ctaLabel,
      ctaEnabled: true,
      onCta: widget.onContinue,
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final List<NovaSummaryItem> items;

  const _ProfileCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: NovaColors.bgElevated,
        borderRadius: BorderRadius.circular(NovaTokens.rXl),
        border: Border.all(color: NovaColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: NovaColors.accentGlow(0.14),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: NovaColors.accentGlow(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NovaColors.accentGlow(0.55)),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: NovaColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Player profile ready',
                  style: NovaTypography.title(
                    size: 16,
                    weight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final it in items) ...[
            _RowItem(label: it.label, value: it.value),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Text(
            'Next: your first AI coaching plan.',
            style: NovaTypography.body(
              size: 12,
              height: 1.35,
              color: NovaColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  final String label;
  final String value;

  const _RowItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: NovaTypography.labelMono(
              size: 10,
              letterSpacing: 1.9,
              color: NovaColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: NovaTypography.title(
            size: 14,
            weight: FontWeight.w700,
            height: 1.0,
            letterSpacing: -0.1,
            color: NovaColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
