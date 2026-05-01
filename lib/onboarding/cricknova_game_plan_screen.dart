import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import 'cricknova_onboarding_store.dart';
import 'onboarding_ui_tokens.dart';

class CricknovaGamePlanScreen extends StatefulWidget {
  final String userName;

  const CricknovaGamePlanScreen({super.key, required this.userName});

  @override
  State<CricknovaGamePlanScreen> createState() =>
      _CricknovaGamePlanScreenState();
}

class _CricknovaGamePlanScreenState extends State<CricknovaGamePlanScreen> {
  Map<String, dynamic> _answers = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _loadAnswers();
  }

  Future<void> _loadAnswers() async {
    final user = FirebaseAuth.instance.currentUser;
    final answers = user == null
        ? await CricknovaOnboardingStore.loadPendingAnswers()
        : await CricknovaOnboardingStore.loadAnswers(user.uid);
    if (!mounted) return;
    setState(() {
      _answers = answers;
    });
  }

  String _role() => (_answers['role'] ?? 'Player').toString();

  String _selectedGoal() {
    final value =
        (_answers['urgent_improve'] ??
                _answers['urgent_bowling_upgrade'] ??
                _answers['keeper_urgent_improve'] ??
                _answers['batting_weakness'] ??
                _answers['bowling_weakness'] ??
                _answers['keeping_weakness'] ??
                _answers['keeper_batting_weakness'])
            ?.toString()
            .trim();
    if (value == null || value.isEmpty) {
      switch (_role()) {
        case 'Batsman':
          return 'Improve timing';
        case 'Bowler':
          return 'Take more wickets';
        case 'Wicket Keeper':
          return 'Sharpen reactions';
        case 'All-Rounder':
          return 'Build complete match impact';
        default:
          return 'Improve performance';
      }
    }
    switch (value) {
      case 'Timing':
        return 'Improve timing';
      case 'Consistency':
        return 'Build consistency';
      case 'Power hitting':
        return 'Increase power hitting';
      case 'Running':
        return 'Run smarter between wickets';
      case 'Raw speed':
        return 'Increase bowling speed';
      case 'Swing & seam':
        return 'Improve swing and seam';
      case 'Accuracy':
        return 'Improve accuracy';
      case 'Variations':
        return 'Add stronger variations';
      case 'Stumping speed':
        return 'Improve stumping speed';
      case 'Catching':
        return 'Improve catching';
      case 'Batting':
        return 'Improve batting';
      case 'Reading spin':
        return 'Read spin earlier';
      default:
        return value;
    }
  }

  List<String> _insights() {
    final goal = _selectedGoal();
    final weakness =
        (_answers['batting_weakness'] ??
                _answers['bowling_weakness'] ??
                _answers['keeping_weakness'] ??
                _answers['keeper_batting_weakness'])
            ?.toString();
    final training =
        (_answers['batting_training_frequency'] ??
                _answers['bowling_training_frequency'] ??
                _answers['keeper_training_frequency'])
            ?.toString();

    final lines = <String>[
      'Strong intent to improve',
      if (weakness != null && weakness.isNotEmpty) 'Needs better $weakness',
      'Key focus: $goal',
    ];
    if (lines.length < 3 && training != null && training.isNotEmpty) {
      lines.insert(1, 'Training habit: $training');
    }
    return lines.take(3).toList();
  }

  ({String range, String skill, String performance}) _timelineData() {
    final role = _role();
    final goal = _selectedGoal().toLowerCase();
    if (role == 'Bowler') {
      return (
        range: '21-30 days',
        skill: goal.contains('accuracy') || goal.contains('line')
            ? 'accuracy'
            : 'execution',
        performance: 'pressure overs and wicket chances',
      );
    }
    if (role == 'Wicket Keeper') {
      return (
        range: '14-21 days',
        skill: goal.contains('catch') ? 'hands and reactions' : 'movement',
        performance: 'clean takes and confidence',
      );
    }
    if (role == 'All-Rounder') {
      return (
        range: '21-30 days',
        skill: 'decision-making under pressure',
        performance: 'match impact',
      );
    }
    return (
      range: goal.contains('timing') || goal.contains('consistency')
          ? '14-21 days'
          : '21-30 days',
      skill: goal.contains('timing') ? 'timing' : 'shot execution',
      performance: 'run output',
    );
  }

  List<String> _planPreview() {
    final weakness =
        (_answers['batting_weakness'] ??
                _answers['bowling_weakness'] ??
                _answers['keeping_weakness'] ??
                _answers['keeper_batting_weakness'])
            ?.toString();
    return <String>[
      'Day 1 -> Fix ${weakness == null || weakness.isEmpty ? 'core issue' : weakness}',
      'Day 7 -> Improve consistency',
      'Day 14 -> Build confidence',
      'Day 30 -> Match-ready performance',
    ];
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            const LoginScreen(postLoginTarget: LoginPostLoginTarget.app),
      ),
    );
  }

  void _goToApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigation(userName: widget.userName),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final insights = _insights();
    final identity = '${_role()} • Focus: ${_selectedGoal()}';
    final timeline = _timelineData();
    final roadmap = _planPreview();

    return Scaffold(
      backgroundColor: OnboardingColors.bgBase,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: OnboardingUiTokens.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  Text(
                    'FINAL SUMMARY',
                    style: OnboardingTextStyles.uiMono(
                      color: OnboardingColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your CrickNova Game Plan is Ready.',
                    style: OnboardingTextStyles.serif(
                      color: OnboardingColors.textPrimary,
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: OnboardingColors.bgSurface,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: OnboardingColors.borderDefault.withValues(
                          alpha: 0.58,
                        ),
                      ),
                    ),
                    child: Text(
                      identity,
                      style: OnboardingTextStyles.uiSans(
                        color: OnboardingColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "This is the first version of your AI plan. It's built from your role, your goal, and the gap holding you back right now.",
                    style: OnboardingTextStyles.uiSans(
                      color: OnboardingColors.textSecondary.withValues(
                        alpha: 0.68,
                      ),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _GamePlanSectionLabel(label: 'AI INSIGHTS'),
                  const SizedBox(height: 12),
                  _GamePlanCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List<Widget>.generate(insights.length, (index) {
                        final line = insights[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == insights.length - 1 ? 0 : 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 3,
                                height: 16,
                                margin: const EdgeInsets.only(top: 1),
                                decoration: BoxDecoration(
                                  color: OnboardingColors.accent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  line,
                                  style: OnboardingTextStyles.uiSans(
                                    color: OnboardingColors.textPrimary
                                        .withValues(alpha: 0.94),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _GamePlanSectionLabel(label: 'YOUR TIMELINE'),
                  const SizedBox(height: 12),
                  _GamePlanCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'If you consistently follow CrickNova coaching feedback...',
                          style: OnboardingTextStyles.uiSans(
                            color: OnboardingColors.textSecondary.withValues(
                              alpha: 0.72,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'In the next ${timeline.range},',
                          style: OnboardingTextStyles.serif(
                            color: OnboardingColors.textPrimary,
                            fontSize: 23,
                            fontWeight: FontWeight.w500,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'your ${timeline.skill} will improve,\nyour ${timeline.performance} will increase,\nand your results will become more consistent.',
                          style: OnboardingTextStyles.uiSans(
                            color: OnboardingColors.textPrimary.withValues(
                              alpha: 0.92,
                            ),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _GamePlanSectionLabel(label: 'PLAN PREVIEW'),
                  const SizedBox(height: 12),
                  _GamePlanCard(
                    child: Column(
                      children: List<Widget>.generate(roadmap.length, (index) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == roadmap.length - 1 ? 0 : 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: OnboardingColors.bgHover,
                                  border: Border.all(
                                    color: OnboardingColors.borderSubtle,
                                  ),
                                ),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: OnboardingColors.progressFill,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  roadmap[index],
                                  style: OnboardingTextStyles.uiSans(
                                    color: OnboardingColors.textPrimary
                                        .withValues(alpha: 0.92),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      "You're closer than you think.",
                      textAlign: TextAlign.center,
                      style: OnboardingTextStyles.serif(
                        color: OnboardingColors.textPrimary.withValues(
                          alpha: 0.94,
                        ),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: isLoggedIn ? _goToApp : _goToLogin,
                      style: FilledButton.styleFrom(
                        backgroundColor: OnboardingColors.ctaBg,
                        foregroundColor: OnboardingColors.ctaText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: OnboardingTextStyles.uiSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(
                        isLoggedIn ? 'Continue to App' : 'Continue to Login',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GamePlanSectionLabel extends StatelessWidget {
  final String label;

  const _GamePlanSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: OnboardingTextStyles.uiMono(
        color: OnboardingColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.5,
      ),
    );
  }
}

class _GamePlanCard extends StatelessWidget {
  final Widget child;

  const _GamePlanCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: OnboardingColors.bgSurface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: OnboardingColors.borderDefault.withValues(alpha: 0.58),
        ),
      ),
      child: child,
    );
  }
}
