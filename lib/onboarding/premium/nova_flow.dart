import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nova_answers.dart';
import 'nova_magic_moment.dart';
import 'nova_question_screens.dart';
import 'nova_reward_screen.dart';
import 'nova_steps.dart';
import 'nova_summary_screen.dart';
import 'nova_tokens.dart';
import 'nova_welcome_screen.dart';

class NovaOnboardingFlow extends StatefulWidget {
  final List<NovaStep> steps;
  final void Function(Map<String, NovaAnswer> answers) onFinished;
  final VoidCallback? onExit;

  const NovaOnboardingFlow({
    super.key,
    required this.steps,
    required this.onFinished,
    this.onExit,
  });

  @override
  State<NovaOnboardingFlow> createState() => _NovaOnboardingFlowState();
}

class _NovaOnboardingFlowState extends State<NovaOnboardingFlow> {
  late final PageController _pc = PageController();
  int _index = 0;
  final Map<String, NovaAnswer> _answers = <String, NovaAnswer>{};

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int next) {
    if (!mounted) return;
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final dur = NovaMotion.maybe(
      const Duration(milliseconds: 360),
      reduceMotion: reduceMotion,
    );
    _pc.animateToPage(next, duration: dur, curve: NovaTokens.easeInOut);
    setState(() => _index = next);
  }

  void _next() {
    final last = widget.steps.length - 1;
    if (_index >= last) {
      widget.onFinished(Map<String, NovaAnswer>.unmodifiable(_answers));
      return;
    }
    _go(_index + 1);
  }

  void _back() {
    if (_index <= 0) {
      widget.onExit?.call();
      Navigator.maybePop(context);
      return;
    }
    _go(_index - 1);
  }

  double _progressFor(int i) {
    final n = widget.steps.length;
    if (n <= 1) return 0;
    return (i / (n - 1)).clamp(0.0, 1.0);
  }

  String? _stepTextFor(int i) {
    if (i == 0) return null;
    final n = widget.steps.length;
    return 'Step ${math.min(i + 1, n)} of $n';
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pc,
      itemCount: widget.steps.length,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, i) {
        final child = _buildStep(widget.steps[i], i);
        return _FlowTransition(controller: _pc, index: i, child: child);
      },
    );
  }

  Widget _buildStep(NovaStep step, int i) {
    final progress = _progressFor(i);
    final stepText = _stepTextFor(i);
    final onBack = i == 0 ? null : _back;

    return switch (step) {
      NovaWelcomeStep s => NovaWelcomeScreen(
        brandTitle: s.brandTitle,
        heroTitle: s.heroTitle,
        heroSubtitle: s.heroSubtitle,
        ctaLabel: s.ctaLabel,
        onStart: _next,
      ),
      NovaQuestionStep s => NovaQuestionScreen(
        step: s,
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        onAnswered: (a) {
          _answers[s.id] = a;
          _next();
        },
      ),
      NovaMagicMomentStep s => NovaMagicMomentScreen(
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        categoryLabel: s.categoryLabel,
        title: s.title,
        subtitle: s.subtitle,
        metrics: s.metrics,
        ctaLabel: s.ctaLabel,
        onContinue: _next,
      ),
      NovaRewardStep s => NovaRewardScreen(
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        title: s.title,
        subtitle: s.subtitle,
        xp: s.xp,
        ctaLabel: s.ctaLabel,
        onContinue: _next,
      ),
      NovaSummaryStep s => NovaSummaryScreen(
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        title: s.title,
        subtitle: s.subtitle,
        items: s.items,
        ctaLabel: s.ctaLabel,
        onContinue: () =>
            widget.onFinished(Map<String, NovaAnswer>.unmodifiable(_answers)),
      ),
    };
  }
}

class _FlowTransition extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;

  const _FlowTransition({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    if (reduceMotion) return child;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients
            ? (controller.page ?? controller.initialPage.toDouble())
            : 0.0;
        final delta = (page - index).clamp(-1.0, 1.0);
        final fade = (1.0 - delta.abs() * 0.22).clamp(0.0, 1.0);
        final dx = delta * -36;
        final scale = 1.0 - (delta.abs() * 0.02);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}
