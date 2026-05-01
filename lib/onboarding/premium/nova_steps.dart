import 'nova_choices.dart';

enum NovaQuestionKind {
  singleChoiceCards,
  multiChoiceChips,
  slider,
  yesNo,
  role,
}

sealed class NovaStep {
  final String id;
  const NovaStep({required this.id});
}

final class NovaWelcomeStep extends NovaStep {
  final String brandTitle;
  final String heroTitle;
  final String heroSubtitle;
  final String ctaLabel;

  const NovaWelcomeStep({
    required super.id,
    required this.brandTitle,
    required this.heroTitle,
    required this.heroSubtitle,
    this.ctaLabel = 'Start',
  });
}

final class NovaQuestionStep extends NovaStep {
  final NovaQuestionKind kind;
  final String categoryLabel;
  final String title;
  final String subtitle;

  final List<NovaChoiceOption> options;
  final double sliderMin;
  final double sliderMax;
  final int? sliderDivisions;
  final String? sliderLeftLabel;
  final String? sliderRightLabel;

  /// Optional micro-feedback line shown under answers.
  final String? Function(Object? answer)? coachLine;

  const NovaQuestionStep({
    required super.id,
    required this.kind,
    required this.categoryLabel,
    required this.title,
    required this.subtitle,
    this.options = const <NovaChoiceOption>[],
    this.sliderMin = 0,
    this.sliderMax = 1,
    this.sliderDivisions,
    this.sliderLeftLabel,
    this.sliderRightLabel,
    this.coachLine,
  });
}

final class NovaMagicMomentStep extends NovaStep {
  final String categoryLabel;
  final String title;
  final String subtitle;
  final List<NovaMetric> metrics;
  final String ctaLabel;

  const NovaMagicMomentStep({
    required super.id,
    required this.categoryLabel,
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.ctaLabel = 'Continue',
  });
}

final class NovaRewardStep extends NovaStep {
  final String title;
  final String subtitle;
  final int xp;
  final String ctaLabel;

  const NovaRewardStep({
    required super.id,
    required this.title,
    required this.subtitle,
    required this.xp,
    this.ctaLabel = 'Next',
  });
}

final class NovaSummaryStep extends NovaStep {
  final String title;
  final String subtitle;
  final List<NovaSummaryItem> items;
  final String ctaLabel;

  const NovaSummaryStep({
    required super.id,
    required this.title,
    required this.subtitle,
    required this.items,
    this.ctaLabel = 'Enter CrickNova',
  });
}

final class NovaMetric {
  final String label;
  final String value;
  const NovaMetric({required this.label, required this.value});
}

final class NovaSummaryItem {
  final String label;
  final String value;
  const NovaSummaryItem({required this.label, required this.value});
}
