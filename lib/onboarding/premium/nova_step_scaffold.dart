import 'package:flutter/material.dart';

import 'nova_background.dart';
import 'nova_button.dart';
import 'nova_progress_header.dart';
import 'nova_reveal.dart';
import 'nova_tokens.dart';

class NovaStepScaffold extends StatelessWidget {
  final VoidCallback? onBack;
  final double progress;
  final String progressText;
  final String? stepText;

  final String categoryLabel;
  final String title;
  final String subtitle;

  final Widget body;

  final String ctaLabel;
  final bool ctaEnabled;
  final VoidCallback onCta;

  const NovaStepScaffold({
    super.key,
    required this.onBack,
    required this.progress,
    required this.progressText,
    required this.stepText,
    required this.categoryLabel,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.ctaLabel,
    required this.ctaEnabled,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    return NovaAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            NovaProgressHeader(
              progress: progress,
              progressText: progressText,
              stepText: stepText,
              onBack: onBack,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: NovaTokens.maxContentWidth,
                  ),
                  child: Padding(
                    padding: NovaTokens.contentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        NovaReveal(
                          delay: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 30),
                          child: Text(
                            categoryLabel.toUpperCase(),
                            style: NovaTypography.labelMono(
                              color: NovaColors.textMuted,
                              size: 11,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        NovaReveal(
                          delay: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 80),
                          from: const Offset(22, 0),
                          child: Text(
                            title,
                            style: NovaTypography.display(
                              size: 34,
                              weight: FontWeight.w400,
                              color: NovaColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        NovaReveal(
                          delay: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 130),
                          from: const Offset(22, 0),
                          child: Text(
                            subtitle,
                            style: NovaTypography.body(
                              size: 15,
                              color: NovaColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: NovaReveal(
                              delay: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              from: const Offset(26, 0),
                              child: body,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SafeArea(
                          top: false,
                          child: NovaPrimaryButton(
                            label: ctaLabel,
                            enabled: ctaEnabled,
                            onPressed: ctaEnabled ? onCta : null,
                          ),
                        ),
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
