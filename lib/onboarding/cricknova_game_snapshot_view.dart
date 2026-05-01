import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

import 'onboarding_ui_tokens.dart';

class CricknovaGameSnapshotView extends StatelessWidget {
  final Map<String, String> answers;
  final VoidCallback onContinue;
  final String ctaLabel;
  final bool showRateCta;

  const CricknovaGameSnapshotView({
    super.key,
    required this.answers,
    required this.onContinue,
    this.ctaLabel = 'Continue',
    this.showRateCta = false,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = CricknovaGameSnapshotBuilder.build(answers);
    return Stack(
      children: [
        const _EmeraldGlowBackdrop(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FadeSlideIn(
              delay: const Duration(milliseconds: 0),
              duration: const Duration(milliseconds: 320),
              offsetY: 10,
              child: Text(
                'YOUR GAME SNAPSHOT',
                style: OnboardingTextStyles.uiMono(
                  color: OnboardingColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.6,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _FadeSlideIn(
              delay: const Duration(milliseconds: 70),
              duration: const Duration(milliseconds: 360),
              offsetY: 10,
              child: Text(
                'Your Game Snapshot',
                style: OnboardingTextStyles.uiSans(
                  color: OnboardingColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              duration: const Duration(milliseconds: 320),
              offsetY: 10,
              child: Text(
                "Based on your answers, here’s your edge.",
                style: OnboardingTextStyles.uiSans(
                  color: OnboardingColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
            if (snapshot.edgeLine != null) ...[
              const SizedBox(height: 14),
              _FadeSlideIn(
                delay: const Duration(milliseconds: 160),
                duration: const Duration(milliseconds: 320),
                offsetY: 10,
                child: _EdgePill(text: snapshot.edgeLine!),
              ),
            ],
            const SizedBox(height: 22),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _FadeSlideIn(
                    delay: const Duration(milliseconds: 220),
                    duration: const Duration(milliseconds: 360),
                    offsetY: 14,
                    child: _PremiumSectionCard(
                      title: 'CURRENT ANALYSIS',
                      child: _TightBulletList(
                        items: snapshot.weaknesses,
                        accent: OnboardingColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FadeSlideIn(
                    delay: const Duration(milliseconds: 300),
                    duration: const Duration(milliseconds: 360),
                    offsetY: 14,
                    child: _PremiumSectionCard(
                      title: "WHAT WE’LL FIX",
                      child: _TightBulletList(
                        items: snapshot.improvementPath,
                        accent: OnboardingColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FadeSlideIn(
                    delay: const Duration(milliseconds: 380),
                    duration: const Duration(milliseconds: 380),
                    offsetY: 14,
                    child: _PremiumSectionCard(
                      title: 'YOUR PROGRESS TIMELINE',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snapshot.timelineLine,
                            style: OnboardingTextStyles.uiSans(
                              color: OnboardingColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _TimelineMiniBar(phases: snapshot.timelinePhases),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FadeSlideIn(
                    delay: const Duration(milliseconds: 460),
                    duration: const Duration(milliseconds: 360),
                    offsetY: 14,
                    child: _PremiumSectionCard(
                      title: 'HOW CRICKNOVA HELPS YOU',
                      child: _TightBulletList(
                        items: snapshot.aiAdvantages,
                        accent: OnboardingColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FadeSlideIn(
                    delay: const Duration(milliseconds: 540),
                    duration: const Duration(milliseconds: 340),
                    offsetY: 12,
                    child: _PremiumQuoteCard(text: snapshot.confidenceBoostLine),
                  ),
                  if (showRateCta) ...[
                    const SizedBox(height: 12),
                    _FadeSlideIn(
                      delay: const Duration(milliseconds: 590),
                      duration: const Duration(milliseconds: 320),
                      offsetY: 10,
                      child: _RateRow(),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _FadeSlideIn(
              delay: const Duration(milliseconds: 620),
              duration: const Duration(milliseconds: 320),
              offsetY: 10,
              child: Center(
                child: Text(
                  "Let’s start building your game",
                  style: OnboardingTextStyles.uiSans(
                    color: OnboardingColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _FadeSlideIn(
              delay: const Duration(milliseconds: 680),
              duration: const Duration(milliseconds: 340),
              offsetY: 12,
              child: _PrimaryCta(label: ctaLabel, onPressed: onContinue),
            ),
            const SizedBox(height: 12),
            _FadeSlideIn(
              delay: const Duration(milliseconds: 740),
              duration: const Duration(milliseconds: 300),
              offsetY: 10,
              child: Center(
                child: Text(
                  'This takes about 3 seconds',
                  style: OnboardingTextStyles.uiMono(
                    color: OnboardingColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CricknovaGameSnapshot {
  final String? edgeLine;
  final List<String> weaknesses;
  final List<String> improvementPath;
  final String timelineLine;
  final List<String> timelinePhases;
  final List<String> aiAdvantages;
  final String confidenceBoostLine;

  const CricknovaGameSnapshot({
    required this.edgeLine,
    required this.weaknesses,
    required this.improvementPath,
    required this.timelineLine,
    required this.timelinePhases,
    required this.aiAdvantages,
    required this.confidenceBoostLine,
  });
}

class CricknovaGameSnapshotBuilder {
  static CricknovaGameSnapshot build(Map<String, String> answers) {
    String? firstAnswerWhere(bool Function(String key) pred) {
      for (final e in answers.entries) {
        if (pred(e.key)) return e.value;
      }
      return null;
    }

    void addUnique(List<String> list, String? value) {
      if (value == null) return;
      final v = value.trim();
      if (v.isEmpty) return;
      if (list.contains(v)) return;
      list.add(v);
    }

    final role = answers['role'];
    final experience = firstAnswerWhere((k) => k.endsWith('_years'));
    final training =
        answers['batting_training_frequency'] ??
        answers['bowling_training_frequency'] ??
        answers['keeper_training_frequency'];
    final record =
        answers['record_sessions'] ??
        answers['record_bowling_sessions'] ??
        answers['record_keeping_sessions'];

    final battingWeakness = answers['batting_weakness'];
    final bowlingWeakness = answers['bowling_weakness'];
    final keepingWeakness = answers['keeping_weakness'] ?? answers['keeper_batting_weakness'];
    final pressure = answers['pressure'];

    final style = answers['batting_style'];
    final weaponShot = answers['strongest_shot'];
    final delivery = answers['deadly_delivery'];
    final lineLength = answers['line_length_consistency'];
    final deathOvers = answers['death_overs'];

    String? edgeLine() {
      final parts = <String>[];
      if (role != null && role.isNotEmpty) parts.add(role);
      if (weaponShot != null && weaponShot.isNotEmpty) {
        parts.add('Weapon: $weaponShot');
      } else if (delivery != null && delivery.isNotEmpty) {
        parts.add('Weapon: $delivery');
      }
      if (style != null && style.isNotEmpty) parts.add('Style: $style');
      if (training != null && training.isNotEmpty) {
        parts.add('Rhythm: $training');
      }
      if (parts.isEmpty) return null;
      return parts.take(2).join(' • ');
    }

    String? shortBatWeakness(String? raw) {
      switch (raw) {
        case 'Playing spin':
          return 'Struggling vs spin';
        case 'Playing pace':
          return 'Late vs pace';
        case 'Footwork':
          return 'Late footwork reaction';
        case 'Shot selection under pressure':
          return 'Pressure shot choices';
      }
      return null;
    }

    String? shortBowlWeakness(String? raw) {
      switch (raw) {
        case 'Speed':
          return 'Need more pace';
        case 'Accuracy':
          return 'Accuracy leaks';
        case 'Line & length':
          return 'Line/length drift';
        case 'Death bowling':
          return 'Death overs control';
      }
      return null;
    }

    String? shortKeepWeakness(String? raw) {
      switch (raw) {
        case 'Catching':
          return 'Catching clean-ups';
        case 'Stumping speed':
        case 'Stumping':
          return 'Faster stumpings';
        case 'Pressure situations':
          return 'Pressure moments';
        case 'Diving stops':
          return 'Diving stops';
      }
      return raw == null ? null : null;
    }

    final weaknesses = <String>[];
    addUnique(weaknesses, switch (role) {
      'Bowler' => shortBowlWeakness(bowlingWeakness),
      'Wicket Keeper' => shortKeepWeakness(keepingWeakness),
      _ => shortBatWeakness(battingWeakness),
    });

    if (pressure == 'I go quiet') addUnique(weaknesses, 'Pressure: go quiet');
    if (pressure == "I'm inconsistent") addUnique(weaknesses, 'Pressure: inconsistent');

    if (role == 'Bowler') {
      if (lineLength == 'Hit or miss') addUnique(weaknesses, 'Line/length: hit or miss');
      if (deathOvers == 'I struggle') addUnique(weaknesses, 'Death overs: struggle');
    }

    if (record == 'Never tried') addUnique(weaknesses, 'No video feedback');
    if (record == 'Want to start') addUnique(weaknesses, 'Video habit missing');

    if (training == 'Rarely') addUnique(weaknesses, 'Training volume low');
    if (training == 'Weekends only') addUnique(weaknesses, 'Low weekly reps');

    if (experience == 'Under 1 year') addUnique(weaknesses, 'Foundation still building');

    final currentAnalysis = weaknesses.isEmpty
        ? const <String>['Timing under pressure', 'Footwork reaction late']
        : weaknesses.take(3).toList(growable: false);

    final improvementPath = <String>[];
    for (final e in _improvementPathFor(role, battingWeakness, bowlingWeakness, keepingWeakness)) {
      addUnique(improvementPath, e);
    }
    if (record != 'Always') addUnique(improvementPath, 'Record 2 sessions/week');
    if (training == 'Rarely' || training == 'Weekends only') {
      addUnique(improvementPath, '3 sessions/week plan');
    }

    final trimmedPath = improvementPath.isEmpty
        ? const <String>[
            'Improve shot timing',
            'Better foot movement',
            'Smarter shot selection',
          ]
        : improvementPath.take(3).toList(growable: false);

    final range = _timelineRangeDays(
      training: training,
      record: record,
      experience: experience,
    );
    final timelineLine =
        'You can see visible improvement in ${range.$1}–${range.$2} days';

    final aiAdvantages = const <String>[
      'Cricknova video comparison',
      'Instant mistake detection',
      'Cricknova coaching feedback',
    ];

    final confidenceBoostLine = (training == 'Every day' ||
            training == '3–4x a week' ||
            record == 'Always' ||
            record == 'Sometimes')
        ? 'Players like you improve faster with structured feedback'
        : 'Structured feedback makes progress feel simple';

    return CricknovaGameSnapshot(
      edgeLine: edgeLine(),
      weaknesses: currentAnalysis,
      improvementPath: trimmedPath,
      timelineLine: timelineLine,
      timelinePhases: const <String>[
        'Week 1  Understanding',
        'Week 2  Correction',
        'Week 3  Confidence',
      ],
      aiAdvantages: aiAdvantages,
      confidenceBoostLine: confidenceBoostLine,
    );
  }

  static List<String> _improvementPathFor(
    String? role,
    String? battingWeakness,
    String? bowlingWeakness,
    String? keepingWeakness,
  ) {
    if (role == 'Bowler') {
      switch (bowlingWeakness) {
        case 'Speed':
          return const <String>['Run-up rhythm', 'Release speed', 'Power transfer'];
        case 'Accuracy':
          return const <String>['Target practice', 'Repeatable release', 'Better alignment'];
        case 'Line & length':
          return const <String>['Length control', 'Seam position', 'Set-up plans'];
        case 'Death bowling':
          return const <String>['Yorker reps', 'Slower balls', 'Field-aware plans'];
      }
      return const <String>['Line & length control', 'Better variations', 'Smarter plans'];
    }

    if (role == 'Wicket Keeper') {
      switch (keepingWeakness) {
        case 'Catching':
          return const <String>['Soft hands', 'Head still', 'High reps'];
        case 'Stumping speed':
        case 'Stumping':
          return const <String>['Faster gather', 'Cleaner transfer', 'Timing cues'];
        case 'Pressure situations':
          return const <String>['Calm routine', 'Decision speed', 'Ball tracking'];
        case 'Diving stops':
          return const <String>['Footwork angles', 'First dive', 'Recovery speed'];
      }
      return const <String>['Footwork first', 'Cleaner takes', 'Faster decisions'];
    }

    switch (battingWeakness) {
      case 'Playing spin':
        return const <String>['Pick spin earlier', 'Front-foot control', 'Safer shot zones'];
      case 'Playing pace':
        return const <String>['Earlier bat launch', 'Still head at contact', 'Backlift timing'];
      case 'Footwork':
        return const <String>['Faster first step', 'Balance into shots', 'Cleaner trigger moves'];
      case 'Shot selection under pressure':
        return const <String>['Smarter shot selection', 'Pre-ball routine', 'Play percentages'];
      default:
        return const <String>['Improve shot timing', 'Better foot movement', 'Smarter shot selection'];
    }
  }

  static (int, int) _timelineRangeDays({
    required String? training,
    required String? record,
    required String? experience,
  }) {
    var minDays = 21;
    var maxDays = 30;

    switch (training) {
      case 'Every day':
        minDays -= 7;
        maxDays -= 7;
      case '3–4x a week':
      case '3-4x a week':
        minDays -= 2;
        maxDays -= 2;
      case 'Weekends only':
        minDays += 7;
        maxDays += 10;
      case 'Rarely':
        minDays += 10;
        maxDays += 15;
    }

    if (record == 'Always') {
      minDays -= 2;
      maxDays -= 2;
    } else if (record == 'Never tried') {
      maxDays += 3;
    }

    if (experience == '5+ years') {
      minDays -= 2;
      maxDays -= 1;
    } else if (experience == 'Under 1 year') {
      maxDays += 3;
    }

    minDays = minDays.clamp(14, 45);
    maxDays = maxDays.clamp(minDays + 7, 45);
    return (minDays, maxDays);
  }
}

class _PrimaryCta extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryCta({required this.label, required this.onPressed});

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: _hovered ? 0.9 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          height: 58,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OnboardingColors.ctaBg,
              foregroundColor: OnboardingColors.ctaText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: OnboardingTextStyles.uiSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: widget.onPressed,
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _FadeSlideIn extends StatefulWidget {
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final Widget child;

  const _FadeSlideIn({
    required this.delay,
    required this.duration,
    required this.offsetY,
    required this.child,
  });

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, (1 - curved.value) * widget.offsetY),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _EmeraldGlowBackdrop extends StatelessWidget {
  const _EmeraldGlowBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    OnboardingColors.accent.withValues(alpha: 0.16),
                    OnboardingColors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -180,
            left: -140,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    OnboardingColors.accent.withValues(alpha: 0.10),
                    OnboardingColors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _PremiumSectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: OnboardingColors.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OnboardingColors.borderDefault, width: 1),
        boxShadow: [
          BoxShadow(
            color: OnboardingColors.accent.withValues(alpha: 0.10),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: OnboardingTextStyles.uiMono(
              color: OnboardingColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EdgePill extends StatelessWidget {
  final String text;

  const _EdgePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: OnboardingColors.bgSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: OnboardingColors.borderActive, width: 1),
        boxShadow: [
          BoxShadow(
            color: OnboardingColors.accent.withValues(alpha: 0.16),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: OnboardingColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: OnboardingTextStyles.uiSans(
                color: OnboardingColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TightBulletList extends StatelessWidget {
  final List<String> items;
  final Color accent;

  const _TightBulletList({required this.items, required this.accent});

  @override
  Widget build(BuildContext context) {
    final safeItems = items.isEmpty ? const <String>['—'] : items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List<Widget>.generate(safeItems.length, (index) {
        final text = safeItems[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == safeItems.length - 1 ? 0 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.75),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: OnboardingTextStyles.uiSans(
                    color: OnboardingColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TimelineMiniBar extends StatelessWidget {
  final List<String> phases;

  const _TimelineMiniBar({required this.phases});

  @override
  Widget build(BuildContext context) {
    final safe = phases.isEmpty
        ? const <String>[
            'Week 1  Understanding',
            'Week 2  Correction',
            'Week 3  Confidence',
          ]
        : phases;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List<Widget>.generate(3, (index) {
            final isLast = index == 2;
            final bg = OnboardingColors.progressTrack;
            final fg = index == 0
                ? OnboardingColors.accent.withValues(alpha: 0.90)
                : (index == 1
                      ? OnboardingColors.accent.withValues(alpha: 0.55)
                      : OnboardingColors.accent.withValues(alpha: 0.35));
            return Expanded(
              child: Container(
                height: 8,
                margin: EdgeInsets.only(right: isLast ? 0 : 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: OnboardingColors.borderDefault,
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(color: fg),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: safe.take(3).map((label) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: OnboardingColors.bgSelected,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: OnboardingColors.borderDefault,
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: OnboardingTextStyles.uiMono(
                  color: OnboardingColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PremiumQuoteCard extends StatelessWidget {
  final String text;

  const _PremiumQuoteCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: OnboardingColors.bgSelected,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OnboardingColors.borderDefault, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: OnboardingColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: OnboardingTextStyles.uiSans(
                color: OnboardingColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: OnboardingColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OnboardingColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Enjoying CrickNova? Rate us.',
              style: OnboardingTextStyles.uiSans(
                color: OnboardingColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final review = InAppReview.instance;
              try {
                if (await review.isAvailable()) {
                  await review.requestReview();
                }
              } catch (_) {}
            },
            style: TextButton.styleFrom(
              foregroundColor: OnboardingColors.textPrimary,
              textStyle: OnboardingTextStyles.uiSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Rate'),
          ),
        ],
      ),
    );
  }
}

