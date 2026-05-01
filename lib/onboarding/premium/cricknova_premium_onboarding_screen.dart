import 'package:flutter/material.dart';

import 'nova_answers.dart';
import 'nova_choices.dart';
import 'nova_flow.dart';
import 'nova_steps.dart';

/// Premium onboarding UI shell.
/// Note: question text/options are intentionally placeholders here.
/// Provide your real question content by supplying [steps] from your data layer.
class CricknovaPremiumOnboardingScreen extends StatelessWidget {
  final List<NovaStep>? steps;
  final void Function(Map<String, NovaAnswer> answers)? onFinished;

  const CricknovaPremiumOnboardingScreen({
    super.key,
    this.steps,
    this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    final flowSteps = steps ?? _placeholderSteps();
    return NovaOnboardingFlow(
      steps: flowSteps,
      onExit: () => Navigator.maybePop(context),
      onFinished: (answers) => onFinished?.call(answers),
    );
  }
}

List<NovaStep> _placeholderSteps() {
  return <NovaStep>[
    const NovaWelcomeStep(
      id: 'welcome',
      brandTitle: 'CrickNova AI',
      heroTitle: 'Your AI coach,\nbuilt for cricket.',
      heroSubtitle:
          'A fast profile build that unlocks a personalized training journey.',
      ctaLabel: 'Build my profile',
    ),
    const NovaQuestionStep(
      id: 'q_role',
      kind: NovaQuestionKind.role,
      categoryLabel: 'Profile',
      title: 'Question title goes here',
      subtitle: 'Helper subtitle goes here.',
      options: [
        NovaChoiceOption(id: 'opt1', label: 'Option 1', hint: 'Short hint.'),
        NovaChoiceOption(id: 'opt2', label: 'Option 2', hint: 'Short hint.'),
        NovaChoiceOption(id: 'opt3', label: 'Option 3', hint: 'Short hint.'),
        NovaChoiceOption(id: 'opt4', label: 'Option 4', hint: 'Short hint.'),
      ],
    ),
    const NovaQuestionStep(
      id: 'q_multi',
      kind: NovaQuestionKind.multiChoiceChips,
      categoryLabel: 'Preferences',
      title: 'Question title goes here',
      subtitle: 'Pick any that apply.',
      options: [
        NovaChoiceOption(id: 'm1', label: 'Chip 1'),
        NovaChoiceOption(id: 'm2', label: 'Chip 2'),
        NovaChoiceOption(id: 'm3', label: 'Chip 3'),
        NovaChoiceOption(id: 'm4', label: 'Chip 4'),
        NovaChoiceOption(id: 'm5', label: 'Chip 5'),
      ],
    ),
    const NovaMagicMomentStep(
      id: 'magic',
      categoryLabel: 'AI Preview',
      title: 'Watch CrickNova adapt.',
      subtitle: 'A quick glimpse of what your profile unlocks.',
      metrics: [
        NovaMetric(label: 'Swing', value: '—'),
        NovaMetric(label: 'Timing', value: '—'),
        NovaMetric(label: 'Control', value: '—'),
        NovaMetric(label: 'Consistency', value: '—'),
      ],
      ctaLabel: 'Continue',
    ),
    const NovaRewardStep(
      id: 'reward',
      title: 'Nice.',
      subtitle: 'Profile progress locked in.',
      xp: 120,
      ctaLabel: 'See summary',
    ),
    const NovaSummaryStep(
      id: 'summary',
      title: 'Your profile is ready.',
      subtitle: 'CrickNova will tune coaching around this.',
      items: [
        NovaSummaryItem(label: 'Role', value: '—'),
        NovaSummaryItem(label: 'Focus', value: '—'),
        NovaSummaryItem(label: 'Intensity', value: '—'),
      ],
      ctaLabel: 'Enter CrickNova',
    ),
  ];
}
