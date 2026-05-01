import 'dart:async';
import 'dart:math' as math;

import 'package:in_app_review/in_app_review.dart';
import 'package:hive/hive.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen.dart';
import '../navigation/main_navigation.dart';
import '../services/premium_service.dart';
import '../services/pricing_location_service.dart';
import 'cricknova_onboarding_store.dart';
import 'onboarding_ui_tokens.dart';

class CricknovaOnboardingScreen extends StatefulWidget {
  final String userName;
  final bool skipGetStarted;
  final String? entryNotice;

  const CricknovaOnboardingScreen({
    super.key,
    required this.userName,
    this.skipGetStarted = false,
    this.entryNotice,
  });

  @override
  State<CricknovaOnboardingScreen> createState() =>
      _CricknovaOnboardingScreenState();
}

class _CricknovaOnboardingScreenState extends State<CricknovaOnboardingScreen> {
  static const Color _bg = Color(0xFF0C0C0C);
  static const Color _gold = Color(0xFFD4AF37);

  final Map<String, String> _answers = <String, String>{};
  final TextEditingController _nameController = TextEditingController();

  int _stepIndex = 0;
  String? _selectedOption;
  bool _isCompleting = false;
  bool _hasAdvancedPastAnalysis = false;
  Timer? _analysisTimer;

  String get _welcomeBody {
    const base =
        'You aren\'t here to just "play" anymore. You are here to win.';
    final notice = widget.entryNotice?.trim();
    if (notice == null || notice.isEmpty) {
      return base;
    }
    return '$notice\n\n$base';
  }

  String get _firstName {
    final fromAnswer = _answers['display_name']?.trim();
    if (fromAnswer != null && fromAnswer.isNotEmpty) {
      return fromAnswer.split(RegExp(r'\s+')).first;
    }
    final fromWidget = widget.userName.trim();
    if (fromWidget.isNotEmpty) {
      return fromWidget.split(RegExp(r'\s+')).first;
    }
    final fromAuth = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) {
      return fromAuth.split(RegExp(r'\s+')).first;
    }
    return 'Player';
  }

  String? get _roleValue {
    final raw = _answers['identity'];
    if (raw == null) return null;
    return raw.replaceFirst(RegExp(r'^[A-D]\.\s+'), '');
  }

  double get _weeklyAvgHours {
    final rawHours = _answers['net_hours'] ?? '';
    final hours = rawHours.replaceFirst(RegExp(r'^[A-D]\.\s+'), '');
    switch (hours) {
      case '< 5 hrs':
        return 3.0;
      case '5-12 hrs':
        return 8.5;
      case '12-25 hrs':
        return 18.5;
      case '25+ hrs':
        return 30.0;
      default:
        return 8.5;
    }
  }

  int get _decadeTotalHours => (_weeklyAvgHours * 52 * 10).round();

  int get _totalActiveDays => (_decadeTotalHours / 15).round();

  // Technical debt is still 25% of decade total for the 'wasted' metric
  int get _technicalDebtHours => (_decadeTotalHours * 0.25).round();

  int get _fullDaysWasted => (_technicalDebtHours / 24).round();

  List<_QuestionNode> get _questionNodes => _questionBankFor(_roleValue);

  List<_FlowStep> get _steps {
    final steps = <_FlowStep>[
      _FlowStep.message(
        id: 'welcome',
        kicker: 'The Welcome',
        title: 'Welcome to CrickNova AI.',
        body: _welcomeBody,
        ctaLabel: 'Continue',
        showSignIn: true,
      ),
      _FlowStep.input(
        id: 'display_name',
        kicker: 'Your Name',
        title: 'What does CrickNova call you?',
        body: 'Add the name you want us to use throughout your roadmap.',
        storageKey: 'display_name',
        ctaLabel: 'Continue',
      ),
      _FlowStep.message(
        id: 'truth',
        kicker: 'The Hard Truth',
        title: '$_firstName, be honest...',
        body:
            'After sweating for hours in the nets, why does your technique abandon you under match pressure?',
        ctaLabel: 'I need the answer',
        spotlight: true,
      ),
      _FlowStep.message(
        id: 'reality',
        kicker: 'The Solution',
        title:
            'Because wrong practice doesn\'t make you perfect; it makes your mistakes permanent.',
        body:
            'Our AI sees what the human eye misses. Every ball is now a data point for your success.',
        ctaLabel: 'Show me the system',
      ),
      _FlowStep.choice(
        id: 'identity',
        kicker: 'Identity',
        category: 'Identity',
        question: 'What is your primary identity on the field?',
        body: 'This decides how CrickNova judges your game.',
        storageKey: 'identity',
        options: _abcd('Batsman', 'Bowler', 'All-Rounder', 'Wicket-Keeper'),
      ),
      _FlowStep.choice(
        id: 'net_hours',
        kicker: 'Training Volume',
        category: 'Volume',
        question: 'How many hours a week do you spend in the nets?',
        body: 'Time is either building you, or burying you.',
        storageKey: 'net_hours',
        options: _abcd('< 5 hrs', '5-12 hrs', '12-25 hrs', '25+ hrs'),
      ),
      _FlowStep.shock(
        id: 'shock',
        kicker: 'TIME-WASTAGE REALITY',
        title: '$_firstName, Value Your Dreams in Time! ⏳',
        body:
            'In the next 10 years, you will spend ${_formatNumber(_decadeTotalHours)} Hours solely on practice. That is $_totalActiveDays FULL DAYS of your life! Practicing without CrickNova data means ${_formatNumber(_technicalDebtHours)} of these hours (${_formatNumber(_technicalDebtHours ~/ 24)} days) could be wasted on wrong habits or unoptimized drills. Choose CrickNova Premium to save these precious days.',
        footnote: '',
        ctaLabel: 'Save My $_totalActiveDays Days',
      ),
      _FlowStep.message(
        id: 'pivot',
        kicker: 'The Pivot',
        title:
            'We are here to save that time and turn every hour into a "Result".',
        body:
            "\"We are here to save that time.\"\n\n\"Every hour now becomes a Result.\"\n\n\"This is your 35-day blueprint.\"",
        ctaLabel: 'Build my blueprint',
      ),
    ];

    for (final node in _questionNodes) {
      steps.add(
        _FlowStep.choice(
          id: node.id,
          kicker: node.blockLabel,
          category: node.blockLabel,
          question: node.question,
          body: node.helper,
          storageKey: node.id,
          options: node.options,
        ),
      );
      if (node.summaryAfter != null) {
        steps.add(
          _FlowStep.summary(
            id: 'summary_${node.id}',
            kicker: node.summaryAfter!.label,
            title: node.summaryAfter!.title,
            body: node.summaryAfter!.body,
            ctaLabel: 'Continue',
            imagePath: node.summaryAfter!.imagePath,
          ),
        );
      }
      if (node.id == 'q7') {
        steps.add(
          _FlowStep.rating(
            id: 'cricknova_rating',
            kicker: 'CrickNova Boost',
            title: 'Feeling the CrickNova boost?',
            body:
                'If this flow is giving you that next-level training spark, rate CrickNova AI and help more players find it.',
            ctaLabel: 'Rate Now',
          ),
        );
      }
    }

    steps.addAll(<_FlowStep>[
      _FlowStep.analysis(
        id: 'analysis',
        kicker: 'The AI Analysis',
        title:
            'Analyzing 18 critical flaws... Designing your 35-day professional roadmap.',
      ),
      _FlowStep.review(
        id: 'trust_card',
        kicker: 'The Trust Card',
        title: "You're in the right place.",
        body:
            "Over 1,200 athletes have bridged the gap between 'Potential' and 'Performance' using this exact blueprint.",
        ctaLabel: 'See my roadmap',
      ),
      _FlowStep.finalCta(
        id: 'final_cta',
        kicker: 'The Final Verdict',
        title: 'YOUR 35-DAY ROADMAP IS READY.',
        body:
            'Based on your training volume, you are on track to waste ${_formatNumber(_technicalDebtHours)} hours (${_formatNumber(_technicalDebtHours ~/ 24)} days) on the wrong drills. Our 35-day plan will fix your 18 flaws and increase your selection probability by 30%.',
        ctaLabel: 'START MY 35-DAY TRANSFORMATION',
      ),
    ]);

    if (steps.length >= 30) {
      steps.insert(
        30,
        _FlowStep.namaste(
          id: 'namaste',
          kicker: 'GRATITUDE',
          title: 'Thanks for Trusting Us, $_firstName.',
          body:
              'Thanks for choosing CrickNova AI. From this moment on, you are no longer just a player. You are a game changer.',
          userName: _firstName,
          ctaLabel: 'Reveal My Strategy',
        ),
      );
    } else {
      steps.add(
        _FlowStep.namaste(
          id: 'namaste',
          kicker: 'GRATITUDE',
          title: 'Thanks for Trusting Us, $_firstName.',
          body:
              'Thanks for choosing CrickNova AI. From this moment on, you are no longer just a player. You are a game changer.',
          userName: _firstName,
          ctaLabel: 'Reveal My Strategy',
        ),
      );
    }

    return steps;
  }

  _FlowStep get _currentStep => _steps[_stepIndex];

  @override
  void initState() {
    super.initState();
    _stepIndex = widget.skipGetStarted ? 1 : 0;
    _restoreInputValueForCurrentStep();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
    _handleAutoAdvanceForStep();
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  bool _canPopSystem() {
    return _stepIndex == 0 && !_isCompleting;
  }

  void _handleSystemBack() {
    if (_isCompleting) {
      return;
    }
    if (_stepIndex > 0) {
      _goBack();
    }
  }

  void _handleAutoAdvanceForStep() {
    _analysisTimer?.cancel();
    if (_currentStep.kind == _FlowStepKind.analysis &&
        !_hasAdvancedPastAnalysis) {
      _analysisTimer = Timer(const Duration(milliseconds: 2600), () {
        if (!mounted || _stepIndex >= _steps.length - 1) return;
        setState(() {
          _hasAdvancedPastAnalysis = true;
          _stepIndex += 1;
          _selectedOption = null;
        });
      });
    }
  }

  void _goBack() {
    _analysisTimer?.cancel();
    if (_stepIndex == 0) return;
    setState(() {
      if (_currentStep.kind == _FlowStepKind.review) {
        _hasAdvancedPastAnalysis = false;
      }
      _stepIndex -= 1;
      _restoreInputValueForCurrentStep();
    });
    _handleAutoAdvanceForStep();
  }

  void _goNext() {
    _analysisTimer?.cancel();
    if (_stepIndex >= _steps.length - 1) return;
    setState(() {
      _stepIndex += 1;
      _restoreInputValueForCurrentStep();
    });
    _handleAutoAdvanceForStep();
  }

  void _restoreInputValueForCurrentStep() {
    final step = _currentStep;
    if (step.kind == _FlowStepKind.input) {
      final restored = step.storageKey == null
          ? ''
          : (_answers[step.storageKey!] ?? '');
      _nameController.text = restored;
      _nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _nameController.text.length),
      );
      _selectedOption = restored.isEmpty ? null : restored;
      return;
    }
    _selectedOption = step.storageKey == null
        ? null
        : _answers[step.storageKey!];
  }

  void _onOptionSelected(String value) {
    if (_isCompleting) return;
    setState(() {
      _selectedOption = value;
    });
  }

  Future<void> _rateCricknovaAndContinue() async {
    if (_isCompleting) return;
    final inAppReview = InAppReview.instance;
    try {
      await inAppReview.openStoreListing(
        appStoreId: null,
        microsoftStoreId: null,
      );
    } catch (_) {
      // If the store cannot open, keep the onboarding moving.
    }
    if (!mounted) return;
    _goNext();
  }

  Future<void> _onContinue() async {
    if (_isCompleting) return;

    switch (_currentStep.kind) {
      case _FlowStepKind.message:
      case _FlowStepKind.shock:
      case _FlowStepKind.summary:
      case _FlowStepKind.review:
      case _FlowStepKind.namaste:
        _goNext();
        return;
      case _FlowStepKind.rating:
        _goNext();
        return;
      case _FlowStepKind.input:
        final step = _currentStep;
        final name = _nameController.text.trim();
        if (step.storageKey == null || name.isEmpty) return;
        setState(() {
          _answers[step.storageKey!] = name;
          _selectedOption = name;
        });
        if (step.storageKey == 'display_name') {
          await _saveProfileName(name);
        }
        _goNext();
        return;
      case _FlowStepKind.analysis:
        return;
      case _FlowStepKind.finalCta:
        await _completeOnboarding();
        return;
      case _FlowStepKind.choice:
        final step = _currentStep;
        final selected = _selectedOption;
        if (step.storageKey == null || selected == null) return;
        setState(() {
          _answers[step.storageKey!] = selected;
        });
        _goNext();
        return;
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isCompleting = true;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await CricknovaOnboardingStore.savePendingProgress(
        _answers,
        completed: true,
      );
    } else {
      await CricknovaOnboardingStore.saveProgress(
        uid,
        _answers,
        completed: true,
      );
    }

    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    final user = FirebaseAuth.instance.currentUser;
    final enteredName = _answers['display_name']?.trim();
    final displayName = user?.displayName?.trim();
    final resolvedName = (enteredName != null && enteredName.isNotEmpty)
        ? enteredName
        : (displayName != null && displayName.isNotEmpty)
        ? displayName
        : widget.userName.trim().isEmpty
        ? 'Player'
        : widget.userName.trim();

    await _saveProfileName(resolvedName);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _RoadmapScreen(
          userName: resolvedName,
          roleValue: _roleValue,
          weeklyHours: _weeklyAvgHours.round(),
          dataPointCount: 35,
          technicalDebtHours: _technicalDebtHours,
          fullDaysWasted: _fullDaysWasted,
        ),
      ),
    );
  }

  Future<void> _saveProfileName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    final box = await Hive.openBox('local_stats_$uid');
    await box.put('profileName', trimmed);
    await prefs.setString('profileName', trimmed);
    await prefs.setString('userName', trimmed);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep.id == 'truth') {
      return HardTruthScreen(
        playerName: _firstName,
        onContinue: _onContinue,
        onBack: _goBack,
      );
    }
    if (_currentStep.id == 'summary_q3') {
      return _RealityMirrorScreen(
        key: const ValueKey('summary_q3'),
        onBack: _goBack,
        onContinue: _onContinue,
      );
    }

    final progress = ((_stepIndex + 1) / _steps.length).clamp(0.0, 1.0);
    final displayedProgress = _stepIndex == 0 ? 0.03 : progress;

    return PopScope(
      canPop: _canPopSystem(),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: <Widget>[
            const RepaintBoundary(child: _CinematicBackdrop()),
            SafeArea(
              child: Column(
                children: <Widget>[
                  RepaintBoundary(
                    child: _CinematicTopBar(
                      title: 'CrickNova AI',
                      progressLabel: '${_stepIndex + 1} / ${_steps.length}',
                      progress: displayedProgress,
                      onBack: _stepIndex == 0 ? null : _goBack,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 480),
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              final step = _currentStep;
                              if (step.kind == _FlowStepKind.choice) {
                                final offset = Tween<Offset>(
                                  begin: const Offset(0.14, 0),
                                  end: Offset.zero,
                                ).animate(animation);
                                return SlideTransition(
                                  position: offset,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              }
                              final offset = Tween<Offset>(
                                begin: const Offset(0, 0.08),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offset,
                                  child: child,
                                ),
                              );
                            },
                        child: _isCompleting
                            ? _CompletionPane(key: const ValueKey('done'))
                            : _buildStep(context, _currentStep),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, _FlowStep step) {
    switch (step.kind) {
      case _FlowStepKind.message:
        if (step.id == 'welcome') {
          return _WelcomePane(
            key: ValueKey(step.id),
            onContinue: _onContinue,
            onSignIn: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(
                    postLoginTarget: LoginPostLoginTarget.signInCheck,
                    skipOnboardingGetStarted: true,
                  ),
                ),
              );
            },
          );
        }
        if (step.id == 'truth') {
          return HardTruthScreen(
            key: ValueKey(step.id),
            playerName: _firstName,
            onContinue: _onContinue,
            onBack: _goBack,
          );
        }
        final footerNote = switch (step.id) {
          'welcome' => 'Every answer personalizes your cricket roadmap',
          'truth' => 'Your technique is fixable. Your time is not unlimited.',
          'reality' => 'Wrong repetition is harder to fix than no repetition.',
          'pivot' => 'Your 35-day blueprint is being assembled right now.',
          _ => null,
        };
        return _MessagePane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          bodyWidget: step.id == 'pivot' ? const _PivotBodyCopy() : null,
          ctaLabel: step.ctaLabel!,
          onContinue: _onContinue,
          showSignIn: step.showSignIn,
          spotlight: step.spotlight,
          footerNote: footerNote,
          onSignIn: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LoginScreen(
                  postLoginTarget: LoginPostLoginTarget.signInCheck,
                  skipOnboardingGetStarted: true,
                ),
              ),
            );
          },
        );
      case _FlowStepKind.shock:
        return _ShockPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          footnote: step.footnote!,
          ctaLabel: step.ctaLabel!,
          userName: _firstName,
          totalActiveDays: _totalActiveDays,
          bodyWidget: _OpportunityCostWidget(
            userName: _firstName,
            decadeTotalHours: _decadeTotalHours,
            totalActiveDays: _totalActiveDays,
          ),
          onContinue: _onContinue,
        );
      case _FlowStepKind.choice:
        final saved = step.storageKey == null
            ? null
            : _answers[step.storageKey!];
        return _ChoicePane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          category: step.category!,
          question: step.question!,
          body: step.body!,
          options: step.options!,
          selectedValue: _selectedOption ?? saved,
          onSelect: _onOptionSelected,
          onContinue: _onContinue,
        );
      case _FlowStepKind.input:
        return _NameInputPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          ctaLabel: step.ctaLabel!,
          controller: _nameController,
          onChanged: (String value) {
            final nextValue = value.trim().isEmpty ? null : value.trim();
            if ((_selectedOption == null) == (nextValue == null)) {
              return;
            }
            setState(() {
              _selectedOption = nextValue;
            });
          },
          onContinue: _onContinue,
        );
      case _FlowStepKind.summary:
        if (step.id == 'summary_q6') {
          return _TechnicalBlindnessPane(
            key: ValueKey(step.id),
            kicker: step.kicker!,
            title: step.title!,
            ctaLabel: step.ctaLabel!,
            onContinue: _onContinue,
          );
        }
        if (step.id == 'summary_q3') {
          return _RealityMirrorPane(
            key: ValueKey(step.id),
            kicker: step.kicker!,
            title: step.title!,
            onContinue: _onContinue,
          );
        }
        return _SummaryPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          ctaLabel: step.ctaLabel!,
          onContinue: _onContinue,
        );
      case _FlowStepKind.analysis:
        return _AnalysisPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
        );
      case _FlowStepKind.review:
        return _ReviewPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          ctaLabel: step.ctaLabel!,
          onContinue: _onContinue,
        );
      case _FlowStepKind.rating:
        return _RatingStepPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          ctaLabel: step.ctaLabel!,
          onRate: _rateCricknovaAndContinue,
          onContinue: _onContinue,
        );
      case _FlowStepKind.namaste:
        return _NamastePane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          userName: step.userName!,
          ctaLabel: step.ctaLabel!,
          onContinue: _onContinue,
        );
      case _FlowStepKind.finalCta:
        return _FinalCtaPane(
          key: ValueKey(step.id),
          kicker: step.kicker!,
          title: step.title!,
          body: step.body!,
          ctaLabel: step.ctaLabel!,
          technicalDebtHours: _technicalDebtHours,
          onContinue: _onContinue,
        );
    }
  }
}

enum _FlowStepKind {
  message,
  input,
  choice,
  shock,
  summary,
  rating,
  analysis,
  review,
  finalCta,
  namaste,
}

class _FlowStep {
  final _FlowStepKind kind;
  final String id;
  final String? kicker;
  final String? category;
  final String? title;
  final String? question;
  final String? body;
  final String? footnote;
  final String? ctaLabel;
  final String? storageKey;
  final String? imagePath;
  final String? userName;
  final List<_OptionChoice>? options;
  final bool showSignIn;
  final bool spotlight;

  const _FlowStep._({
    required this.kind,
    required this.id,
    this.kicker,
    this.category,
    this.title,
    this.question,
    this.body,
    this.footnote,
    this.ctaLabel,
    this.storageKey,
    this.imagePath,
    this.userName,
    this.options,
    this.showSignIn = false,
    this.spotlight = false,
  });

  factory _FlowStep.message({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String ctaLabel,
    bool showSignIn = false,
    bool spotlight = false,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.message,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      ctaLabel: ctaLabel,
      showSignIn: showSignIn,
      spotlight: spotlight,
    );
  }

  factory _FlowStep.choice({
    required String id,
    required String kicker,
    required String category,
    required String question,
    required String body,
    required String storageKey,
    required List<_OptionChoice> options,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.choice,
      id: id,
      kicker: kicker,
      category: category,
      question: question,
      body: body,
      storageKey: storageKey,
      options: options,
    );
  }

  factory _FlowStep.input({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String storageKey,
    required String ctaLabel,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.input,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      storageKey: storageKey,
      ctaLabel: ctaLabel,
    );
  }

  factory _FlowStep.shock({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String footnote,
    required String ctaLabel,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.shock,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      footnote: footnote,
      ctaLabel: ctaLabel,
    );
  }

  factory _FlowStep.summary({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String ctaLabel,
    String? imagePath,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.summary,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      ctaLabel: ctaLabel,
      imagePath: imagePath,
    );
  }

  factory _FlowStep.rating({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String ctaLabel,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.rating,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      ctaLabel: ctaLabel,
    );
  }

  factory _FlowStep.analysis({
    required String id,
    required String kicker,
    required String title,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.analysis,
      id: id,
      kicker: kicker,
      title: title,
    );
  }
  factory _FlowStep.namaste({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String userName,
    required String ctaLabel,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.namaste,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      userName: userName,
      ctaLabel: ctaLabel,
    );
  }
  factory _FlowStep.review({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String ctaLabel,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.review,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      ctaLabel: ctaLabel,
    );
  }

  factory _FlowStep.finalCta({
    required String id,
    required String kicker,
    required String title,
    required String body,
    required String ctaLabel,
  }) {
    return _FlowStep._(
      kind: _FlowStepKind.finalCta,
      id: id,
      kicker: kicker,
      title: title,
      body: body,
      ctaLabel: ctaLabel,
    );
  }
}

class _OptionChoice {
  final String label;
  final String? emoji;

  const _OptionChoice(this.label, {this.emoji});
}

class _QuestionNode {
  final String id;
  final String blockLabel;
  final String question;
  final String helper;
  final List<_OptionChoice> options;
  final _SummaryBeat? summaryAfter;

  const _QuestionNode({
    required this.id,
    required this.blockLabel,
    required this.question,
    required this.helper,
    required this.options,
    this.summaryAfter,
  });
}

class _SummaryBeat {
  final String label;
  final String title;
  final String body;
  final String? imagePath;

  const _SummaryBeat({
    required this.label,
    required this.title,
    required this.body,
    this.imagePath,
  });
}

List<_QuestionNode> _questionBankFor(String? role) {
  switch (role) {
    case 'Bowler':
      return _bowlerQuestions;
    case 'All-Rounder':
      return _allRounderQuestions;
    case 'Wicket-Keeper':
      return _wicketKeeperQuestions;
    case 'Batsman':
    default:
      return _batsmanQuestions;
  }
}

List<_OptionChoice> _abcd(String a, String b, String c, String d) {
  return <_OptionChoice>[
    _OptionChoice('A. $a'),
    _OptionChoice('B. $b'),
    _OptionChoice('C. $c'),
    _OptionChoice('D. $d'),
  ];
}

List<_OptionChoice> _abcdEmoji(
  String a,
  String ae,
  String b,
  String be,
  String c,
  String ce,
  String d,
  String de,
) {
  return <_OptionChoice>[
    _OptionChoice('A. $a', emoji: ae),
    _OptionChoice('B. $b', emoji: be),
    _OptionChoice('C. $c', emoji: ce),
    _OptionChoice('D. $d', emoji: de),
  ];
}

const _SummaryBeat _summary1 = _SummaryBeat(
  label: 'The Reality Mirror',
  title: 'Insight: Stagnation Detected.',
  body:
      "\"You are training for Duration, not Domination.\"\n\n\"You are repeating mistakes, not building a career.\"\n\n\"This is your Reality Mirror.\"",
);

const _SummaryBeat _summary2 = _SummaryBeat(
  label: 'The Technical Gap',
  title: 'Insight: Technical Blindness.',
  body:
      'You are perfecting your flaws.\n\nWithout data, you are running fast.\n\nIn a dark room.',
);

const _SummaryBeat _summary3 = _SummaryBeat(
  label: 'The Direction Crisis',
  title: 'Insight: Directionless Grind.',
  body:
      'Hard work without a professional blueprint is a waste of your peak years.',
  imagePath: 'assets/images/direction_crisis.png',
);

const _SummaryBeat _summary4 = _SummaryBeat(
  label: 'The Mental Wall',
  title: 'Insight: Mental Fragility.',
  body:
      'Pressure is exposing the parts of your game you still cannot trust. Confidence without proof disappears under lights.',
);

const _SummaryBeat _summary5 = _SummaryBeat(
  label: 'The Skill Gap',
  title: 'Insight: Incomplete Skill Set.',
  body:
      'You are not a bad player. You are an unfinished one, and unfinished players get exposed when the level rises.',
);

const _SummaryBeat _summary6 = _SummaryBeat(
  label: 'The Final Commitment',
  title: 'Insight: Decision Time.',
  body:
      "\"It is time to decide.\"\n\n\"Does this dream get structure, data, and urgency?\"\n\n\"Or does it stay a story you keep repeating?\"",
);

final List<_QuestionNode> _batsmanQuestions = <_QuestionNode>[
  _QuestionNode(
    id: 'q1',
    blockLabel: 'Match Psychology',
    question:
        'Does your footwork move instinctively or freeze under match-day pressure?',
    helper: 'Pressure exposes the first movement.',
    options: _abcd(
      'Fluid',
      'Freezes slightly',
      'Moves too late',
      'I have no footwork',
    ),
  ),
  _QuestionNode(
    id: 'q2',
    blockLabel: 'Match Psychology',
    question:
        'When you fail, do you know the technical reason or do you blame "bad luck"?',
    helper: 'Great batters can name the mistake.',
    options: _abcd('Know exactly', 'Guessing', 'Blame pitch', 'Clueless'),
  ),
  _QuestionNode(
    id: 'q3',
    blockLabel: 'Match Psychology',
    question:
        'Are you a "Net Hero" who struggles in games, or a true "Match Winner"?',
    helper: 'The scoreboard tells the truth.',
    options: _abcd('Match Winner', 'Net Hero', 'Average', 'Struggling'),
    summaryAfter: _summary1,
  ),
  _QuestionNode(
    id: 'q4',
    blockLabel: 'Technical Precision',
    question:
        'Does your bat-pad gap open up as soon as you face dot-ball pressure?',
    helper: 'Tiny gaps become big dismissals.',
    options: _abcd(
      'Stays closed',
      'Opens often',
      'Always open',
      'I do not know my gap',
    ),
  ),
  _QuestionNode(
    id: 'q5',
    blockLabel: 'Technical Precision',
    question:
        'Can you hit a boundary on-demand, or is it just "Slog and Hope"?',
    helper: 'Finishing is a repeatable skill.',
    options: _abcd(
      'Calculated',
      'Wild slog',
      'Struggle to middle',
      'Panic and get out',
    ),
  ),
  _QuestionNode(
    id: 'q6',
    blockLabel: 'Technical Precision',
    question:
        'Do you have a single data point about your bat-speed or swing path?',
    helper: 'If it is not measured, it is guessed.',
    options: _abcd(
      'Use tech',
      'Use video',
      'Purely on feel',
      'No tracking at all',
    ),
    summaryAfter: _summary2,
  ),
  _QuestionNode(
    id: 'q7',
    blockLabel: 'Selection Gap',
    question:
        'If a scout watches you today, would they find a reason to pick you or reject you?',
    helper: 'Selection starts before the trial does.',
    options: _abcd('Pick me', 'Reject me', 'Not ready', 'Too early to say'),
  ),
  _QuestionNode(
    id: 'q8',
    blockLabel: 'Selection Gap',
    question:
        'Why should a team pick you over a rival who is 10% more consistent?',
    helper: 'Effort is not an edge. Value is.',
    options: _abcd(
      'I am elite',
      "I'm trying hard",
      'No real reason',
      'I do not know',
    ),
  ),
  _QuestionNode(
    id: 'q9',
    blockLabel: 'Selection Gap',
    question:
        'Is your current grind leading to the IPL or just the local park?',
    helper: 'Movement without direction is just noise.',
    options: _abcd('Professional path', 'Local hero', 'Nowhere', 'I\'m lost'),
    summaryAfter: _summary3,
  ),
  _QuestionNode(
    id: 'q10',
    blockLabel: 'Mental Fragility',
    question:
        'Does one bad performance destroy your confidence for the next 3 matches?',
    helper: 'Confidence without proof disappears quickly.',
    options: _abcd('Never', 'Sometimes', 'Always', 'I have no confidence left'),
  ),
  _QuestionNode(
    id: 'q11',
    blockLabel: 'Mental Fragility',
    question: 'Do you play safe because you are terrified of making mistakes?',
    helper: 'Fear turns talent into hesitation.',
    options: _abcd(
      'Play to win',
      'Play safe',
      'Terrified',
      'No winning mindset',
    ),
  ),
  _QuestionNode(
    id: 'q12',
    blockLabel: 'Mental Fragility',
    question:
        'Would you bet your entire career on the technique you have right now?',
    helper: 'Belief is expensive when technique is weak.',
    options: _abcd('Yes', 'No', 'Maybe', 'No chance'),
    summaryAfter: _summary4,
  ),
  _QuestionNode(
    id: 'q13',
    blockLabel: 'Skill Assessment',
    question:
        'Do you know how much your head falls over while playing a cover drive?',
    helper: 'Body control decides ball control.',
    options: _abcd('Perfectly still', 'Falls often', 'Always falls', 'No idea'),
  ),
  _QuestionNode(
    id: 'q14',
    blockLabel: 'Skill Assessment',
    question:
        'Can you dominate a professional pacer, or will you be exposed in 5 balls?',
    helper: 'Level jumps punish unfinished players.',
    options: _abcd('Dominate', 'Survive', 'Exposed', 'Terrified'),
  ),
  _QuestionNode(
    id: 'q15',
    blockLabel: 'Skill Assessment',
    question: 'Are you making excuses about facilities or finding ways to win?',
    helper: 'Excuses never make selection lists.',
    options: _abcd(
      'No excuses',
      'Some excuses',
      'Many excuses',
      "Always someone else's fault",
    ),
    summaryAfter: _summary5,
  ),
  _QuestionNode(
    id: 'q16',
    blockLabel: 'Final Commitment',
    question:
        'How many more years are you willing to try before you finally get professional help?',
    helper: 'Delay has a cost.',
    options: _abcd(
      'This is the last year',
      '1-2 years',
      'Many years',
      "I'm quitting",
    ),
  ),
  _QuestionNode(
    id: 'q17',
    blockLabel: 'Final Commitment',
    question:
        'Is your dream of playing at the top a real goal or just a lie you tell yourself?',
    helper: 'Dreams become goals only after commitment.',
    options: _abcd(
      'Real goal',
      'Just a dream',
      'Not sure anymore',
      "I'm confused",
    ),
  ),
  _QuestionNode(
    id: 'q18',
    blockLabel: 'Final Commitment',
    question:
        'Are you ready to see the ugly truth through CrickNova AI and fix it forever?',
    helper:
        'The truth is painful for one moment. Staying average hurts for years.',
    options: _abcd('I\'m ready', 'Scared', 'Maybe', 'No'),
    summaryAfter: _summary6,
  ),
];

final List<_QuestionNode> _bowlerQuestions = <_QuestionNode>[
  _QuestionNode(
    id: 'q1',
    blockLabel: 'Match Psychology',
    question:
        'In a high-pressure spell, does your run-up stay committed or break under pressure?',
    helper: 'A broken run-up usually means a broken ball.',
    options: _abcdEmoji(
      'Fluid',
      '🏃',
      'Breaks slightly',
      '🌪️',
      'Late to gather',
      '📉',
      'No rhythm at all',
      '🛑',
    ),
  ),
  _QuestionNode(
    id: 'q2',
    blockLabel: 'Match Psychology',
    question:
        'When you get hit, do you know exactly why, or do you blame the pitch and luck?',
    helper: 'Elite bowlers diagnose the release instantly.',
    options: _abcd('Know exactly', 'Guessing', 'Blame pitch', 'Clueless'),
  ),
  _QuestionNode(
    id: 'q3',
    blockLabel: 'Match Psychology',
    question:
        'Are you a net bowler who looks sharp in drills, or a match winner when the game turns?',
    helper: 'Pressure overs reveal the truth.',
    options: _abcd('Match Winner', 'Net Hero', 'Average', 'Struggling'),
    summaryAfter: _summary1,
  ),
  _QuestionNode(
    id: 'q4',
    blockLabel: 'Technical Precision',
    question:
        'Does your seam position or wrist control break down as soon as dot-ball pressure rises?',
    helper: 'Control under stress is the whole job.',
    options: _abcdEmoji(
      'Stays strong',
      '⚾',
      'Breaks often',
      '🩹',
      'Always collapses',
      '🏚️',
      'I do not know',
      '❓',
    ),
  ),
  _QuestionNode(
    id: 'q5',
    blockLabel: 'Technical Precision',
    question:
        'In the death overs, can you execute yorkers on demand, or is it spray and pray?',
    helper: 'Death bowling is measurement, not emotion.',
    options: _abcd(
      'Calculated',
      'Wild miss',
      'Rarely nail it',
      'Panic and feed boundaries',
    ),
  ),
  _QuestionNode(
    id: 'q6',
    blockLabel: 'Technical Precision',
    question:
        'Do you have a single data point about your release speed, seam angle, or length map?',
    helper: 'Guessing pace is not pace science.',
    options: _abcd(
      'Use tech',
      'Use video',
      'Purely on feel',
      'No tracking at all',
    ),
    summaryAfter: _summary2,
  ),
  _QuestionNode(
    id: 'q7',
    blockLabel: 'Selection Gap',
    question:
        'If a scout watches you today, would they see a wicket-taker or just another hopeful bowler?',
    helper: 'Selection starts with standout repeatability.',
    options: _abcd('Pick me', 'Reject me', 'Not ready', 'They would be bored'),
  ),
  _QuestionNode(
    id: 'q8',
    blockLabel: 'Selection Gap',
    question:
        'Why should a team pick you over a rival who lands 10% more balls in the right area?',
    helper: 'Intent is not an edge. Execution is.',
    options: _abcd(
      'I am elite',
      "I'm trying hard",
      'No real reason',
      'I do not know',
    ),
  ),
  _QuestionNode(
    id: 'q9',
    blockLabel: 'Selection Gap',
    question:
        'Is your blind grind taking you toward elite cricket, or keeping you stuck as a local bowler?',
    helper: 'Volume without direction becomes wasted overs.',
    options: _abcd('Professional path', 'Local hero', 'Nowhere', 'I\'m lost'),
    summaryAfter: _summary3,
  ),
  _QuestionNode(
    id: 'q10',
    blockLabel: 'Mental Fragility',
    question:
        'Does one expensive over destroy your confidence for the next 3 spells?',
    helper: 'A bowler without reset skills unravels fast.',
    options: _abcd('Never', 'Sometimes', 'Always', 'I have no confidence left'),
  ),
  _QuestionNode(
    id: 'q11',
    blockLabel: 'Mental Fragility',
    question: 'Do you bowl safe because you are terrified of getting hit?',
    helper: 'Fear makes bowlers aim small and miss big.',
    options: _abcd(
      'Always precise',
      'Breaks under heat',
      'Varies too much',
      'Purely on instinct',
    ),
  ),
  _QuestionNode(
    id: 'q12',
    blockLabel: 'Mental Fragility',
    question:
        'Would you bet your bowling future on the release and control you have right now?',
    helper: 'Belief without proof does not survive under lights.',
    options: _abcd('Yes', 'No', 'Maybe', 'No chance'),
    summaryAfter: _summary4,
  ),
  _QuestionNode(
    id: 'q13',
    blockLabel: 'Skill Assessment',
    question:
        'Do you know exactly what your front arm and landing leg do at release?',
    helper: 'Biomechanics decide repeatability.',
    options: _abcd(
      'Know exactly',
      'Breaks often',
      'Always unstable',
      'No idea',
    ),
  ),
  _QuestionNode(
    id: 'q14',
    blockLabel: 'Skill Assessment',
    question:
        'Can you challenge a professional batter, or will they expose your plan in 5 balls?',
    helper: 'Level changes punish unfinished bowlers.',
    options: _abcd('Dominate', 'Compete', 'Exposed', 'Terrified'),
  ),
  _QuestionNode(
    id: 'q15',
    blockLabel: 'Skill Assessment',
    question:
        'Are you making excuses about the pitch and facilities, or finding ways to take wickets anyway?',
    helper: 'Conditions matter less than adaptation.',
    options: _abcd(
      'No excuses',
      'Some excuses',
      'Many excuses',
      'Just complaining',
    ),
    summaryAfter: _summary5,
  ),
  _QuestionNode(
    id: 'q16',
    blockLabel: 'Final Commitment',
    question:
        'How many more years are you willing to guess before you finally get professional feedback?',
    helper: 'Every season of delay has a price.',
    options: _abcd(
      'This is the last year',
      '1-2 years',
      'Many years',
      "I'm quitting",
    ),
  ),
  _QuestionNode(
    id: 'q17',
    blockLabel: 'Final Commitment',
    question:
        'Is your dream of bowling at the top level a real goal or just a comforting story?',
    helper: 'Ambition without action expires.',
    options: _abcd('Real goal', 'Just a dream', 'A lie', "I'm confused"),
  ),
  _QuestionNode(
    id: 'q18',
    blockLabel: 'Final Commitment',
    question:
        'Are you ready to see the ugly truth in your bowling and fix it forever?',
    helper: 'Truth hurts once. Wasted years hurt longer.',
    options: _abcd("I'm ready", 'Scared', 'Maybe', 'No'),
    summaryAfter: _summary6,
  ),
];

final List<_QuestionNode> _allRounderQuestions = <_QuestionNode>[
  _QuestionNode(
    id: 'q1',
    blockLabel: 'Match Psychology',
    question:
        'In a high-pressure match, does your game stay balanced or do both skills collapse together?',
    helper: 'All-rounders must stay stable twice.',
    options: _abcd(
      'Balanced',
      'Shakes slightly',
      'Breaks late',
      'Everything freezes',
    ),
  ),
  _QuestionNode(
    id: 'q2',
    blockLabel: 'Match Psychology',
    question:
        'When you fail, do you know whether batting or bowling caused it, or do you just blame luck?',
    helper: 'Split-role players need precise diagnosis.',
    options: _abcd('Know exactly', 'Guessing', 'Blame luck', 'Clueless'),
  ),
  _QuestionNode(
    id: 'q3',
    blockLabel: 'Match Psychology',
    question:
        'Are you a training all-rounder, or a true match winner in both disciplines?',
    helper: 'Versatility only matters when it survives pressure.',
    options: _abcd('Match Winner', 'Training Hero', 'Average', 'Struggling'),
    summaryAfter: _summary1,
  ),
  _QuestionNode(
    id: 'q4',
    blockLabel: 'Technical Precision',
    question:
        'When pressure rises, does your batting shape or bowling release lose discipline first?',
    helper: 'Weak links show first under stress.',
    options: _abcd(
      'Neither',
      'Batting breaks',
      'Bowling breaks',
      'I do not know',
    ),
  ),
  _QuestionNode(
    id: 'q5',
    blockLabel: 'Technical Precision',
    question:
        'Can you deliver impact late in the game with bat or ball, or do you hope something works?',
    helper: 'Impact players are intentional, not lucky.',
    options: _abcd(
      'Calculated impact',
      'Wild attempts',
      'Struggle to influence',
      'Panic',
    ),
  ),
  _QuestionNode(
    id: 'q6',
    blockLabel: 'Technical Precision',
    question:
        'Do you track even one data point that proves both sides of your game are improving?',
    helper: 'Without evidence, balance is just a feeling.',
    options: _abcd(
      'Use tech',
      'Use video',
      'Purely on feel',
      'No tracking at all',
    ),
    summaryAfter: _summary2,
  ),
  _QuestionNode(
    id: 'q7',
    blockLabel: 'Selection Gap',
    question:
        'If a scout watches you today, do they see a genuine all-rounder or a player stuck between roles?',
    helper: 'Versatility must still be selectable.',
    options: _abcd('Pick me', 'Reject me', 'Not ready', 'They would be bored'),
  ),
  _QuestionNode(
    id: 'q8',
    blockLabel: 'Selection Gap',
    question:
        'Why should a team pick you over a specialist who is 10% better in one role?',
    helper: 'Your edge must be obvious.',
    options: _abcd(
      'I am elite',
      "I'm trying hard",
      'No real reason',
      "I do not know",
    ),
  ),
  _QuestionNode(
    id: 'q9',
    blockLabel: 'Selection Gap',
    question:
        'Is your blind grind taking you toward elite cricket, or leaving you undefined?',
    helper: 'Undefined players are easy to ignore.',
    options: _abcd('Professional path', 'Local hero', 'Nowhere', 'I\'m lost'),
    summaryAfter: _summary3,
  ),
  _QuestionNode(
    id: 'q10',
    blockLabel: 'Mental Fragility',
    question:
        'Does one bad outing with bat or ball damage your confidence in both skills?',
    helper: 'Double-role players need double resilience.',
    options: _abcd('Never', 'Sometimes', 'Always', 'I have no confidence left'),
  ),
  _QuestionNode(
    id: 'q11',
    blockLabel: 'Mental Fragility',
    question:
        'Do you play safe because you are scared of failing in both roles at once?',
    helper: 'Safety can shrink your impact on both sides.',
    options: _abcd(
      'Play to win',
      'Play safe',
      'Terrified',
      'No winning mindset',
    ),
  ),
  _QuestionNode(
    id: 'q12',
    blockLabel: 'Mental Fragility',
    question:
        'Would you bet your cricket future on the complete all-round game you have right now?',
    helper: 'Incomplete balance gets exposed quickly.',
    options: _abcd('Yes', 'No', 'Maybe', 'No chance'),
    summaryAfter: _summary4,
  ),
  _QuestionNode(
    id: 'q13',
    blockLabel: 'Skill Assessment',
    question:
        'Do you know exactly where your game leaks more: movement, release, or decision-making?',
    helper: 'Clarity decides where progress starts.',
    options: _abcd('Know exactly', 'Leak often', 'Leak everywhere', 'No idea'),
  ),
  _QuestionNode(
    id: 'q14',
    blockLabel: 'Skill Assessment',
    question:
        'Can you compete against professional players in both roles, or does one side get exposed immediately?',
    helper: 'Top-level cricket punishes half-built all-rounders.',
    options: _abcd(
      'Compete in both',
      'One side survives',
      'Exposed',
      'Terrified',
    ),
  ),
  _QuestionNode(
    id: 'q15',
    blockLabel: 'Skill Assessment',
    question:
        'Are you making excuses about role confusion, or finding ways to become undeniable?',
    helper: 'Your role becomes clear when your value becomes obvious.',
    options: _abcd(
      'No excuses',
      'Some excuses',
      'Many excuses',
      'Just complaining',
    ),
    summaryAfter: _summary5,
  ),
  _QuestionNode(
    id: 'q16',
    blockLabel: 'Final Commitment',
    question:
        'How many more years are you willing to stay undefined before you finally get professional help?',
    helper: 'Undefined talent fades fast.',
    options: _abcd(
      'This is the last year',
      '1-2 years',
      'Many years',
      "I'm quitting",
    ),
  ),
  _QuestionNode(
    id: 'q17',
    blockLabel: 'Final Commitment',
    question:
        'Is your dream of being a true all-rounder a real goal or just a convenient label?',
    helper: 'A label is not a legacy.',
    options: _abcd('Real goal', 'Just a dream', 'A lie', "I'm confused"),
  ),
  _QuestionNode(
    id: 'q18',
    blockLabel: 'Final Commitment',
    question:
        'Are you ready to see the ugly truth in both parts of your game and fix it forever?',
    helper: 'You cannot dominate what you refuse to measure.',
    options: _abcd("I'm ready", 'Scared', 'Maybe', 'No'),
    summaryAfter: _summary6,
  ),
];

final List<_QuestionNode> _wicketKeeperQuestions = <_QuestionNode>[
  _QuestionNode(
    id: 'q1',
    blockLabel: 'Match Psychology',
    question:
        'In a high-pressure match, do your hands stay soft and reactive or do they freeze behind the stumps?',
    helper: 'One stiff moment can cost the innings.',
    options: _abcd(
      'Fluid',
      'Freeze slightly',
      'React too late',
      'No timing at all',
    ),
  ),
  _QuestionNode(
    id: 'q2',
    blockLabel: 'Match Psychology',
    question:
        'When you miss a take or stumping, do you know why, or do you blame the pitch and bounce?',
    helper: 'Keepers need honest feedback faster than anyone.',
    options: _abcd('Know exactly', 'Guessing', 'Blame pitch', 'Clueless'),
  ),
  _QuestionNode(
    id: 'q3',
    blockLabel: 'Match Psychology',
    question:
        'Are you sharp in practice but shaky in matches, or a true game-changing keeper?',
    helper: 'Real keepers change games under noise.',
    options: _abcd('Match Winner', 'Net Hero', 'Average', 'Struggling'),
    summaryAfter: _summary1,
  ),
  _QuestionNode(
    id: 'q4',
    blockLabel: 'Technical Precision',
    question:
        'Does your head position and glove line stay disciplined under pressure, or does it drift?',
    helper: 'Tiny technical leaks create big keeping errors.',
    options: _abcd(
      'Stays stable',
      'Drifts often',
      'Always drifts',
      'I do not know',
    ),
  ),
  _QuestionNode(
    id: 'q5',
    blockLabel: 'Technical Precision',
    question:
        'Can you create a dismissal chance on demand late in the innings, or do you just hope for an error?',
    helper: 'Elite keepers manufacture pressure too.',
    options: _abcd(
      'Calculated',
      'Hope and react',
      'Struggle to influence',
      'Panic',
    ),
  ),
  _QuestionNode(
    id: 'q6',
    blockLabel: 'Technical Precision',
    question:
        'Do you track even one data point about your takes, footwork speed, or glove path?',
    helper: 'Keeping without data is blind repetition.',
    options: _abcd(
      'Use tech',
      'Use video',
      'Purely on feel',
      'No tracking at all',
    ),
    summaryAfter: _summary2,
  ),
  _QuestionNode(
    id: 'q7',
    blockLabel: 'Selection Gap',
    question:
        'If a scout watches you today, would they see a keeper who saves runs and creates dismissals?',
    helper: 'Selection favors impact, not just effort.',
    options: _abcd('Pick me', 'Reject me', 'Not ready', 'They would be bored'),
  ),
  _QuestionNode(
    id: 'q8',
    blockLabel: 'Selection Gap',
    question:
        'Why should a team pick you over a rival who is 10% cleaner behind the stumps?',
    helper: 'Being busy is not the same as being valuable.',
    options: _abcd(
      'I am elite',
      "I'm trying hard",
      'No real reason',
      'I do not know',
    ),
  ),
  _QuestionNode(
    id: 'q9',
    blockLabel: 'Selection Gap',
    question:
        'Is your blind grind taking you to elite keeping, or just making you look active at the local ground?',
    helper: 'Activity is not progress.',
    options: _abcd('Professional path', 'Local hero', 'Nowhere', 'I\'m lost'),
    summaryAfter: _summary3,
  ),
  _QuestionNode(
    id: 'q10',
    blockLabel: 'Mental Fragility',
    question:
        'Does one dropped chance damage your confidence for the next 3 matches?',
    helper: 'A shaken keeper spreads fear through the field.',
    options: _abcd('Never', 'Sometimes', 'Always', 'I have no confidence left'),
  ),
  _QuestionNode(
    id: 'q11',
    blockLabel: 'Mental Fragility',
    question:
        'Do you play safe with your movement because you are terrified of making mistakes?',
    helper: 'Fear makes keepers late.',
    options: _abcd(
      'Play to win',
      'Play safe',
      'Terrified',
      'No winning mindset',
    ),
  ),
  _QuestionNode(
    id: 'q12',
    blockLabel: 'Mental Fragility',
    question:
        'Would you bet your future as a keeper on the technique you have right now?',
    helper: 'Trust without evidence evaporates fast.',
    options: _abcd('Yes', 'No', 'Maybe', 'No chance'),
    summaryAfter: _summary4,
  ),
  _QuestionNode(
    id: 'q13',
    blockLabel: 'Skill Assessment',
    question:
        'Do you know exactly how your head, hips, and gloves move on a low take?',
    helper: 'Mechanics decide consistency.',
    options: _abcd('Know exactly', 'Break often', 'Always unstable', 'No idea'),
  ),
  _QuestionNode(
    id: 'q14',
    blockLabel: 'Skill Assessment',
    question:
        'Can you keep cleanly to professional bowlers, or will the pace and movement expose you immediately?',
    helper: 'Higher levels punish untidy movement.',
    options: _abcd('Dominate', 'Survive', 'Exposed', 'Terrified'),
  ),
  _QuestionNode(
    id: 'q15',
    blockLabel: 'Skill Assessment',
    question:
        'Are you making excuses about conditions, or finding ways to save runs anyway?',
    helper: 'Adaptability keeps players selected.',
    options: _abcd(
      'No excuses',
      'Some excuses',
      'Many excuses',
      'Just complaining',
    ),
    summaryAfter: _summary5,
  ),
  _QuestionNode(
    id: 'q16',
    blockLabel: 'Final Commitment',
    question:
        'How many more years are you willing to guess behind the stumps before getting professional help?',
    helper: 'Delay quietly becomes habit.',
    options: _abcd(
      'This is the last year',
      '1-2 years',
      'Many years',
      "I'm quitting",
    ),
  ),
  _QuestionNode(
    id: 'q17',
    blockLabel: 'Final Commitment',
    question:
        'Is your dream of being a top wicket-keeper a real goal or just a story you keep repeating?',
    helper: 'Real goals leave evidence.',
    options: _abcd('Real goal', 'Just a dream', 'A lie', "I'm confused"),
  ),
  _QuestionNode(
    id: 'q18',
    blockLabel: 'Final Commitment',
    question:
        'Are you ready to see the ugly truth in your keeping and fix it forever?',
    helper: 'Measured truth is the start of elite hands.',
    options: _abcd("I'm ready", 'Scared', 'Maybe', 'No'),
    summaryAfter: _summary6,
  ),
];

class _CinematicBackdrop extends StatelessWidget {
  const _CinematicBackdrop();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: _CricknovaOnboardingScreenState._bg);
  }
}

class _LuxuryTypography {
  static TextStyle headline({
    Color color = Colors.white,
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w700,
    double height = 1.15,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.cormorantGaramond(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: FontStyle.italic,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle body({
    Color color = const Color(0xCCFFFFFF),
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w300,
    double height = 1.55,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.inter(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle label({
    Color color = const Color(0xCCFFFFFF),
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 1.4,
  }) {
    return GoogleFonts.inter(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }
}

class _CinematicTopBar extends StatelessWidget {
  final String title;
  final String progressLabel;
  final double progress;
  final VoidCallback? onBack;

  const _CinematicTopBar({
    required this.title,
    required this.progressLabel,
    required this.progress,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 36,
            child: Row(
              children: <Widget>[
                if (onBack != null) ...<Widget>[
                  _BackChrome(onBack: onBack),
                  const SizedBox(width: 10),
                ],
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF444444),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                    height: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF222222)),
                  ),
                  child: Text(
                    progressLabel,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF555555),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              height: 2,
              width: double.infinity,
              decoration: const BoxDecoration(color: Color(0xFF161616)),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: _CricknovaOnboardingScreenState._gold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackChrome extends StatelessWidget {
  final VoidCallback? onBack;

  const _BackChrome({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onBack,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onBack == null ? Colors.transparent : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: onBack == null
                ? Colors.transparent
                : const Color(0x22FFFFFF),
          ),
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 16,
          color: onBack == null ? Colors.transparent : Colors.white,
        ),
      ),
    );
  }
}

class _PaneShell extends StatelessWidget {
  final String kicker;
  final String title;
  final String body;
  final Widget? bodyWidget;
  final Widget? child;
  final Widget footer;
  final bool spotlight;
  final bool compactLayout;

  const _PaneShell({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    this.bodyWidget,
    this.child,
    required this.footer,
    this.spotlight = false,
    this.compactLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortestSide = size.shortestSide;
    final titleSize = _fluidType(value: shortestSide * 0.095, min: 32, max: 44);
    final bodySize = _fluidType(value: shortestSide * 0.048, min: 18, max: 23);
    final kickerSize = _fluidType(
      value: shortestSide * 0.028,
      min: 12,
      max: 14,
    );
    final topBottomPadding = _fluidType(
      value: size.height * 0.02,
      min: 14,
      max: 18,
    );
    final kickerTitleGap = 20.0;
    final titleBodyGap = 24.0;
    final bodyChildGap = 20.0;
    final childTopGap = 24.0;
    final contentBottomGap = 20.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, topBottomPadding, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _FadeInUp(
                    child: Text(
                      kicker.toUpperCase(),
                      style: _LuxuryTypography.label(
                        color: const Color(0x99D4AF37),
                        fontSize: kickerSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.6,
                      ),
                    ),
                  ),
                  SizedBox(height: kickerTitleGap),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 70),
                    child: _HighlightedCopy(
                      text: title,
                      style: _LuxuryTypography.headline(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                      highlightStyle: _LuxuryTypography.headline(
                        color: const Color(0xFFD4AF37),
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                  ),
                  SizedBox(height: titleBodyGap),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 140),
                    child:
                        bodyWidget ??
                        _HighlightedCopy(
                          text: body,
                          style: _LuxuryTypography.body(
                            color: const Color(0xE6FFFFFF),
                            fontSize: compactLayout ? bodySize : bodySize + 3,
                            fontWeight: FontWeight.w400,
                            height: compactLayout ? 1.35 : 1.7,
                          ),
                          highlightStyle: _LuxuryTypography.body(
                            color: const Color(0xFFD4AF37),
                            fontSize: compactLayout
                                ? bodySize + 1
                                : bodySize + 4,
                            fontWeight: FontWeight.w600,
                            height: compactLayout ? 1.35 : 1.7,
                          ),
                        ),
                  ),
                  SizedBox(height: bodyChildGap),
                  if (child != null) ...<Widget>[
                    SizedBox(height: childTopGap),
                    _FadeInUp(
                      delay: const Duration(milliseconds: 210),
                      child: child!,
                    ),
                  ],
                  SizedBox(height: contentBottomGap),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            0,
            compactLayout ? 6 : 12,
            0,
            topBottomPadding,
          ),
          child: _FadeInUp(
            delay: const Duration(milliseconds: 260),
            child: footer,
          ),
        ),
      ],
    );
  }
}

double _fluidType({
  required double value,
  required double min,
  required double max,
}) {
  return value.clamp(min, max).toDouble();
}

String _formatNumber(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (Match match) => ',',
  );
}

class _HighlightedCopy extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle highlightStyle;

  const _HighlightedCopy({
    required this.text,
    required this.style,
    required this.highlightStyle,
  });

  static final RegExp _importantPattern = RegExp(
    '"[^"]+"'
    r'|\b\d+(?:,\d{3})*(?:\+)?(?:\.\d+)?%?\b'
    r'|\bAI\b|\bData\b|\bResult\b|\bResults\b|\bLegacy\b|\bPotential\b|\bPerformance\b'
    r'|\bBlueprint\b|\bRoadmap\b|\bTransformation\b|\bPressure\b|\bTruth\b|\bSelection\b'
    r'|\bDomination\b|\bDuration\b|\bAverage\b|\bProfessional\b|\bCritical\b|\bFlaws\b'
    r'|\bProblem\b|\bSolution\b|\bReality\b|\bMirror\b|\bCommitment\b|\bCareer\b'
    r'|\bAthletes\b|\bFix\b|\bProbability\b|\bTrack\b|\bWaste\b|\bUsed\b|\bVerified\b'
    r'|\bDominate\b|\bCoach\b|\bGeneric\b|\bSkip\b|\bGreats\b|\bStarted\b|\bPersonalizes\b'
    r'|\bReady\b|\bDream\b|\bGoal\b|\bHelp\b|\bUgly\b|\bForever\b|\bPainful\b|\bYears\b|\bDark Room\b',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in _importantPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: highlightStyle,
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _MessagePane extends StatelessWidget {
  final String kicker;
  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onContinue;
  final Widget? bodyWidget;
  final bool showSignIn;
  final bool spotlight;
  final String? footerNote;
  final VoidCallback onSignIn;

  const _MessagePane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    this.bodyWidget,
    required this.ctaLabel,
    required this.onContinue,
    required this.showSignIn,
    required this.spotlight,
    this.footerNote,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: title,
      body: body,
      bodyWidget: bodyWidget,
      spotlight: spotlight,
      footer: Column(
        children: <Widget>[
          _PulseButton(
            label: ctaLabel,
            onPressed: onContinue,
            color: _CricknovaOnboardingScreenState._gold,
            textColor: Colors.black,
          ),
          if (footerNote != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              footerNote!,
              textAlign: TextAlign.center,
              style: _LuxuryTypography.body(
                color: const Color(0xFF888888),
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
          if (showSignIn) ...<Widget>[
            const SizedBox(height: 14),
            TextButton(
              onPressed: onSignIn,
              child: Text(
                'Already have an account? Sign in',
                style: _LuxuryTypography.body(
                  color: _CricknovaOnboardingScreenState._gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ],
        ],
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 56),
          child: _MessageInfoText(
            text:
                'CrickNova AI onboarding built to pressure-test commitment before the roadmap begins.',
          ),
        ),
      ),
    );
  }
}

class _PivotBodyCopy extends StatelessWidget {
  const _PivotBodyCopy();

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final bodySize = _fluidType(value: shortestSide * 0.048, min: 18, max: 23);
    final baseStyle = _LuxuryTypography.body(
      color: const Color(0xE6FFFFFF),
      fontSize: bodySize + 3,
      fontWeight: FontWeight.w400,
      height: 1.7,
    );
    final highlightStyle = _LuxuryTypography.body(
      color: const Color(0xFFD4AF37),
      fontSize: bodySize + 4,
      fontWeight: FontWeight.w600,
      height: 1.7,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: <InlineSpan>[
          const TextSpan(text: '"We are here to save that time."\n\n'),
          TextSpan(
            text: '"Every hour now becomes a Result."',
            style: highlightStyle,
          ),
          const TextSpan(text: '\n\n"This is your 35-day blueprint."'),
        ],
      ),
    );
  }
}

class HardTruthScreen extends StatelessWidget {
  final String playerName;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const HardTruthScreen({
    super.key,
    required this.playerName,
    required this.onContinue,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 440),
      curve: OnboardingUiTokens.motionEaseOut,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          onBack();
        },
        child: Scaffold(
          backgroundColor: _CricknovaOnboardingScreenState._bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: <Widget>[
                                      _BackChrome(onBack: onBack),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E1E),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFF333333),
                                          ),
                                        ),
                                        child: Text(
                                          '4 / 37',
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFF9C9C9C),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'CrickNova AI',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF8A8A8A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: 0.085,
                                  minHeight: 3,
                                  backgroundColor: const Color(0xFF222222),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFFD4AF37),
                                      ),
                                ),
                              ),
                              const SizedBox(height: 44),
                              Text(
                                'THE HARD TRUTH',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFD4AF37),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.2,
                                ),
                              ),
                              const SizedBox(height: 34),
                              Text(
                                '$playerName, be honest...',
                                style: GoogleFonts.playfairDisplay(
                                  color: const Color(0xFFF4F1EA),
                                  fontSize: 50,
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                  height: 1.02,
                                ),
                              ),
                              const SizedBox(height: 34),
                              Text.rich(
                                TextSpan(
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFFE7E1D5),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w400,
                                    height: 1.55,
                                  ),
                                  children: <InlineSpan>[
                                    const TextSpan(
                                      text:
                                          'After sweating for hours in the nets, why does your technique abandon you under match ',
                                    ),
                                    TextSpan(
                                      text: 'pressure',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFFD4AF37),
                                        fontSize: 21,
                                        fontWeight: FontWeight.w700,
                                        height: 1.55,
                                      ),
                                    ),
                                    const TextSpan(text: '?'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 44),
                              Row(
                                children: const <Widget>[
                                  Expanded(
                                    child: SizedBox(
                                      height: 150,
                                      child: _HardTruthStatCard(
                                        value: '73%',
                                        label: 'players choke under pressure',
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: SizedBox(
                                      height: 150,
                                      child: _HardTruthStatCard(
                                        value: '8 weeks',
                                        label: 'avg. time to fix without AI',
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: SizedBox(
                                      height: 150,
                                      child: _HardTruthStatCard(
                                        value: '2 weeks',
                                        label: 'avg. with CrickNova',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 34),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(30),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF13120C),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF2E2C20),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFFD4AF37),
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.black,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          style: GoogleFonts.inter(
                                            color: const Color(0xFFE8E1D4),
                                            fontSize: 17.5,
                                            fontWeight: FontWeight.w400,
                                            height: 1.5,
                                          ),
                                          children: <InlineSpan>[
                                            const TextSpan(
                                              text: 'CrickNova AI ',
                                            ),
                                            TextSpan(
                                              text: 'pressure-tests',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFFD4AF37),
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.w700,
                                                height: 1.5,
                                              ),
                                            ),
                                            const TextSpan(
                                              text:
                                                  ' your commitment before your ',
                                            ),
                                            TextSpan(
                                              text: 'roadmap',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFFD4AF37),
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.w700,
                                                height: 1.5,
                                              ),
                                            ),
                                            const TextSpan(
                                              text:
                                                  ' begins — so the plan actually sticks.',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: onContinue,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4AF37),
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: Text(
                                    'I need the answer',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Center(
                                child: Text(
                                  'Want to know the solution? Continue to see it.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF8A8A8A),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w400,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HardTruthStatCard extends StatelessWidget {
  final String value;
  final String label;

  const _HardTruthStatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF13120C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A281F), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFFD4AF37),
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: const Color(0xFF8C8A80),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.22,
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomePane extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onSignIn;

  const _WelcomePane({
    super.key,
    required this.onContinue,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: 10),
                        Text(
                          'THE WELCOME',
                          style: GoogleFonts.inter(
                            color: const Color(0xBFD4AF37),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _HighlightedCopy(
                          text: 'Welcome to\nCrickNova AI.',
                          style: _LuxuryTypography.headline(
                            color: const Color(0xFFEFEFEF),
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1.08,
                            letterSpacing: -0.5,
                          ),
                          highlightStyle: _LuxuryTypography.headline(
                            color: _CricknovaOnboardingScreenState._gold,
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1.08,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _HighlightedCopy(
                          text:
                              "You're not here to play. You're here to dominate.",
                          style: _LuxuryTypography.body(
                            color: const Color(0xFFF0F0F0),
                            fontSize: 19,
                            fontWeight: FontWeight.w400,
                            height: 1.6,
                          ),
                          highlightStyle: _LuxuryTypography.body(
                            color: _CricknovaOnboardingScreenState._gold,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 30),
                        const Row(
                          children: <Widget>[
                            Expanded(
                              child: _WelcomeStatCard(
                                value: '3.2x',
                                label: 'faster skill growth',
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: _WelcomeStatCard(
                                value: '89%',
                                label: 'better form in 30 days',
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: _WelcomeStatCard(
                                value: '35',
                                label: 'steps to your roadmap',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Divider(
                          color: Color(0xFF161616),
                          thickness: 0.5,
                          height: 0.5,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 36,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF1E1E1E),
                              width: 0.5,
                            ),
                          ),
                          child: _HighlightedCopy(
                            text:
                                "Every answer shapes your AI coach. Skip a step — your plan stays generic. Takes 4 minutes. Don't waste them.",
                            style: _LuxuryTypography.body(
                              color: const Color(0xFFF0F0F0),
                              fontSize: 19,
                              fontWeight: FontWeight.w400,
                              height: 1.75,
                            ),
                            highlightStyle: _LuxuryTypography.body(
                              color: _CricknovaOnboardingScreenState._gold,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.75,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: Color(0xFFE8E8E8),
                            fontFamily: 'Georgia',
                            fontSize: 19,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                          children: const <InlineSpan>[
                            TextSpan(text: '"The '),
                            TextSpan(
                              text: 'greats',
                              style: TextStyle(color: Color(0xFFD4AF37)),
                            ),
                            TextSpan(
                              text: ' didn\'t start great. They started."',
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: onContinue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _CricknovaOnboardingScreenState._gold,
                              foregroundColor: const Color(0xFF0C0C0C),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 21),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            child: Text(
                              'BEGIN YOUR JOURNEY',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF0C0C0C),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Every answer personalizes your cricket roadmap',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: const Color(0xFFE8E8E8),
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.5,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: onSignIn,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text.rich(
                            TextSpan(
                              style: GoogleFonts.inter(
                                color: const Color(0xFFE8E8E8),
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                              children: const <InlineSpan>[
                                TextSpan(text: 'Already have an account? '),
                                TextSpan(
                                  text: 'Sign in',
                                  style: TextStyle(color: Color(0xFFD4AF37)),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeStatCard extends StatelessWidget {
  final String value;
  final String label;

  const _WelcomeStatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 23),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E1E), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD4AF37),
              fontFamily: 'Georgia',
              fontSize: 37,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: const Color(0xFFF0F0F0),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageInfoText extends StatelessWidget {
  final String text;

  const _MessageInfoText({required this.text});

  @override
  Widget build(BuildContext context) {
    final aiIndex = text.indexOf('AI');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x14141414),
              border: Border.all(
                color: _CricknovaOnboardingScreenState._gold,
                width: 0.8,
              ),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: _CricknovaOnboardingScreenState._gold,
              size: 19,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: _LuxuryTypography.body(
                  color: const Color(0xFFBBBBBB),
                  fontSize: 19,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  letterSpacing: 0.2,
                ),
                children: <InlineSpan>[
                  if (aiIndex < 0)
                    TextSpan(text: text)
                  else ...<InlineSpan>[
                    TextSpan(text: text.substring(0, aiIndex)),
                    TextSpan(
                      text: 'AI',
                      style: _LuxuryTypography.body(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                    TextSpan(text: text.substring(aiIndex + 2)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameInputPane extends StatelessWidget {
  final String kicker;
  final String title;
  final String body;
  final String ctaLabel;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onContinue;

  const _NameInputPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.controller,
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final canContinue = controller.text.trim().isNotEmpty;
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: title,
      body: body,
      footer: _PulseButton(
        label: ctaLabel,
        onPressed: canContinue ? onContinue : null,
        color: _CricknovaOnboardingScreenState._gold,
        textColor: Colors.black,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x10FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x26FFFFFF)),
          ),
          child: TextField(
            controller: controller,
            autofocus: false,
            onChanged: onChanged,
            style: _LuxuryTypography.body(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
            textInputAction: TextInputAction.done,
            cursorColor: _CricknovaOnboardingScreenState._gold,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Enter your name',
              hintStyle: _LuxuryTypography.body(
                color: const Color(0x66FFFFFF),
                fontSize: 20,
                fontWeight: FontWeight.w300,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShockPane extends StatefulWidget {
  final String kicker;
  final String title;
  final String body;
  final String footnote;
  final String ctaLabel;
  final String userName;
  final int totalActiveDays;
  final Widget bodyWidget;
  final VoidCallback onContinue;

  const _ShockPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.footnote,
    required this.ctaLabel,
    required this.userName,
    required this.totalActiveDays,
    required this.bodyWidget,
    required this.onContinue,
  });

  @override
  State<_ShockPane> createState() => _ShockPaneState();
}

class _ShockPaneState extends State<_ShockPane> {
  bool _showThanks = false;

  @override
  Widget build(BuildContext context) {
    if (_showThanks) {
      return _PaneShell(
        key: const ValueKey('time_wastage_thanks'),
        kicker: 'NAMASTE',
        title: '',
        body: '',
        bodyWidget: null,
        footer: _PulseButton(
          label: 'Continue',
          onPressed: widget.onContinue,
          color: _CricknovaOnboardingScreenState._gold,
          textColor: Colors.black,
        ),
        child: _TimeWastageThanksCard(
          userName: widget.userName,
          totalActiveDays: widget.totalActiveDays,
        ),
      );
    }

    return _PaneShell(
      key: widget.key,
      kicker: widget.kicker,
      title: widget.title,
      body: widget.body,
      bodyWidget: null,
      footer: Column(
        children: [
          _PulseButton(
            label: widget.ctaLabel,
            onPressed: () => setState(() => _showThanks = true),
            color: _CricknovaOnboardingScreenState._gold,
            textColor: Colors.black,
          ),
          const SizedBox(height: 14),
          Text(
            widget.footnote,
            textAlign: TextAlign.center,
            style: _LuxuryTypography.body(
              color: const Color(0x66FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
      child: widget.bodyWidget,
    );
  }
}

class _OpportunityCostWidget extends StatefulWidget {
  final String userName;
  final int decadeTotalHours;
  final int totalActiveDays;

  const _OpportunityCostWidget({
    required this.userName,
    required this.decadeTotalHours,
    required this.totalActiveDays,
  });

  @override
  State<_OpportunityCostWidget> createState() => _OpportunityCostWidgetState();
}

class _OpportunityCostWidgetState extends State<_OpportunityCostWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x22FFF06A)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1FFFF06A),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final pulse = 0.6 + 0.4 * math.sin(_motion.value * 4 * math.pi);
              return Opacity(
                opacity: pulse,
                child: Text(
                  '⏳ TIME IS RUNNING',
                  style: _LuxuryTypography.label(
                    color: const Color(0xFFFF4500),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 132,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, _) {
                return CustomPaint(
                  painter: _HourglassTrajectoryPainter(progress: _motion.value),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatNumber(widget.totalActiveDays),
            textAlign: TextAlign.center,
            style:
                _LuxuryTypography.body(
                  color: const Color(0xFFFFF06A),
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                  height: 0.92,
                ).copyWith(
                  shadows: const <Shadow>[
                    Shadow(color: Color(0xAAFFF06A), blurRadius: 26),
                    Shadow(color: Color(0x66D4AF37), blurRadius: 42),
                  ],
                ),
          ),
          const SizedBox(height: 6),
          _HighlightedCopy(
            text: 'DAYS AT STAKE',
            style: _LuxuryTypography.label(
              color: const Color(0xCCFFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
            highlightStyle: _LuxuryTypography.label(
              color: const Color(0xFFFFF06A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Every unstructured net session drains your potential. Stop guessing.',
            textAlign: TextAlign.center,
            style: _LuxuryTypography.body(
              color: const Color(0xFFFF4500),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: _RealityStatCard(
                  label: '10-YEAR HOURS',
                  value: _formatNumber(widget.decadeTotalHours),
                  suffix: 'hrs',
                  accent: const Color(0xFFFFF06A),
                  highlight: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RealityStatCard(
                  label: 'ACTIVE DAYS',
                  value: _formatNumber(widget.totalActiveDays),
                  suffix: 'days',
                  accent: const Color(0xFFD4AF37),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x24FFF06A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'In the next 10 years, you will spend ${_formatNumber(widget.decadeTotalHours)} Hours solely on practice. That is ${_formatNumber(widget.totalActiveDays)} FULL DAYS of your life! Practicing without CrickNova data means ${_formatNumber((widget.decadeTotalHours * 0.25).round())} of these hours (${_formatNumber(((widget.decadeTotalHours * 0.25) / 24).round())} days) could be wasted on wrong habits or unoptimized drills. Choose CrickNova Premium to save these precious days.',
                  style: _LuxuryTypography.body(
                    color: const Color(0xEFFFFFFF),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.58,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeWastageThanksCard extends StatefulWidget {
  final String userName;
  final int totalActiveDays;

  const _TimeWastageThanksCard({
    required this.userName,
    required this.totalActiveDays,
  });

  @override
  State<_TimeWastageThanksCard> createState() => _TimeWastageThanksCardState();
}

class _TimeWastageThanksCardState extends State<_TimeWastageThanksCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final scale = 0.94 + (_controller.value * 0.08);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 180,
                  height: 180,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x14FFF06A),
                    border: Border.all(color: const Color(0x55FFF06A)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFFFFF06A,
                        ).withValues(alpha: 0.16 + (_controller.value * 0.12)),
                        blurRadius: 44,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/namaste_icon.png',
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Thanks for Trusting Us, ${widget.userName}.',
                textAlign: TextAlign.center,
                style: _LuxuryTypography.body(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Let\'s make these ${_formatNumber(widget.totalActiveDays)} days count!',
                textAlign: TextAlign.center,
                style: _LuxuryTypography.body(
                  color: const Color(0xFFD4AF37),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HourglassTrajectoryPainter extends CustomPainter {
  final double progress;

  const _HourglassTrajectoryPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glassPaint = Paint()
      ..color = const Color(0x55FFF06A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final glowPaint = Paint()
      ..color = const Color(0x33FFF06A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final topLeft = Offset(center.dx - 42, 10);
    final topRight = Offset(center.dx + 42, 10);
    final bottomLeft = Offset(center.dx - 42, size.height - 10);
    final bottomRight = Offset(center.dx + 42, size.height - 10);
    final neck = Offset(center.dx, center.dy);
    final glass = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..quadraticBezierTo(center.dx - 18, center.dy - 18, neck.dx, neck.dy)
      ..quadraticBezierTo(
        center.dx + 18,
        center.dy - 18,
        topRight.dx,
        topRight.dy,
      )
      ..moveTo(bottomLeft.dx, bottomLeft.dy)
      ..quadraticBezierTo(center.dx - 18, center.dy + 18, neck.dx, neck.dy)
      ..quadraticBezierTo(
        center.dx + 18,
        center.dy + 18,
        bottomRight.dx,
        bottomRight.dy,
      )
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..moveTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy);

    canvas.drawPath(glass, glowPaint);
    canvas.drawPath(glass, glassPaint);

    final sandPaint = Paint()..color = const Color(0xFFFFF06A);
    final dropY = 22 + ((size.height - 44) * progress);
    canvas.drawCircle(Offset(center.dx, dropY), 2.3, sandPaint);
    canvas.drawLine(
      Offset(center.dx, center.dy - 28),
      Offset(center.dx, center.dy + 28),
      Paint()
        ..color = const Color(0xAAFFF06A)
        ..strokeWidth = 1.2,
    );

    for (var i = 0; i < 4; i++) {
      final t = (progress + i * 0.18) % 1.0;
      final path = Path()
        ..moveTo(center.dx + 10, center.dy + 18 + i * 5)
        ..quadraticBezierTo(
          center.dx + 48 + i * 9,
          center.dy - 18 + i * 2,
          size.width - 18,
          24 + i * 24,
        );
      final metric = path.computeMetrics().first;
      final extract = metric.extractPath(0, metric.length * t);
      canvas.drawPath(
        extract,
        Paint()
          ..color = const Color(0x99FFF06A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final tangent = metric.getTangentForOffset(metric.length * t);
      if (tangent != null) {
        canvas.drawCircle(tangent.position, 4.5, sandPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourglassTrajectoryPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _RealityStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  final Color accent;
  final bool highlight;

  const _RealityStatCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.accent,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x14FFFFFF) : const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: _LuxuryTypography.label(
              color: const Color(0x99FFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: _LuxuryTypography.body(
              color: accent,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            suffix,
            style: _LuxuryTypography.body(
              color: const Color(0x99FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w300,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RealityStatementCard extends StatelessWidget {
  final String text;

  const _RealityStatementCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Text(
        text,
        style: _LuxuryTypography.body(
          color: const Color(0xE6FFFFFF),
          fontSize: 17,
          fontWeight: FontWeight.w300,
          height: 1.65,
        ),
      ),
    );
  }
}

class _SummaryPane extends StatelessWidget {
  final String kicker;
  final String title;
  final String body;
  final String ctaLabel;
  final String? imagePath;
  final VoidCallback onContinue;

  const _SummaryPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.ctaLabel,
    this.imagePath,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: title,
      body: body,
      footer: _PulseButton(
        label: ctaLabel,
        onPressed: onContinue,
        color: _CricknovaOnboardingScreenState._gold,
        textColor: Colors.black,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (imagePath != null) ...<Widget>[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  imagePath!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x14D4AF37),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x44D4AF37)),
            ),
            child: _HighlightedCopy(
              text:
                  'This is your reality mirror. What CrickNova reveals next becomes your roadmap.',
              style: _LuxuryTypography.body(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.7,
                letterSpacing: 0.2,
              ),
              highlightStyle: _LuxuryTypography.body(
                color: const Color(0xFFD4AF37),
                fontSize: 21,
                fontWeight: FontWeight.w700,
                height: 1.7,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingStepPane extends StatefulWidget {
  final String kicker;
  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onRate;
  final VoidCallback onContinue;

  const _RatingStepPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onRate,
    required this.onContinue,
  });

  @override
  State<_RatingStepPane> createState() => _RatingStepPaneState();
}

class _RatingStepPaneState extends State<_RatingStepPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: widget.key,
      kicker: widget.kicker,
      title: widget.title,
      body: widget.body,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _PulseButton(
            label: widget.ctaLabel,
            onPressed: widget.onRate,
            color: _CricknovaOnboardingScreenState._gold,
            textColor: Colors.black,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: widget.onContinue,
            child: Text(
              'Maybe later',
              style: _LuxuryTypography.body(
                color: const Color(0xFFBEBEBE),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final pulse = 0.5 + (0.5 * math.sin(_controller.value * math.pi));
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.35),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(
                    0xFFD4AF37,
                  ).withOpacity(0.12 + (pulse * 0.12)),
                  blurRadius: 28 + (pulse * 14),
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 104,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Transform.scale(
                        scale: 0.92 + (pulse * 0.1),
                        child: Container(
                          width: 94,
                          height: 94,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: <Color>[
                                const Color(
                                  0xFFD4AF37,
                                ).withOpacity(0.26 + (pulse * 0.12)),
                                const Color(0x00D4AF37),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFD4AF37).withOpacity(0.1),
                          border: Border.all(
                            color: const Color(0xFFD4AF37).withOpacity(0.48),
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFFD4AF37),
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(5, (int index) {
                    final phase = (_controller.value + (index * 0.09)) % 1;
                    final lift = math.sin(phase * math.pi) * 7;
                    final scale = 0.92 + (math.sin(phase * math.pi) * 0.14);
                    return Transform.translate(
                      offset: Offset(0, -lift),
                      child: Transform.scale(
                        scale: scale,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Icon(
                            Icons.star_rounded,
                            color: Color.lerp(
                              const Color(0xFF8E7424),
                              const Color(0xFFFFD86B),
                              math.sin(phase * math.pi).clamp(0.0, 1.0),
                            ),
                            size: 34,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),
                Text(
                  'Players build CrickNova with us.',
                  textAlign: TextAlign.center,
                  style: _LuxuryTypography.body(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your rating tells serious cricketers this AI roadmap is worth their time.',
                  textAlign: TextAlign.center,
                  style: _LuxuryTypography.body(
                    color: const Color(0xFFBDBDBD),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RealityMirrorPane extends StatelessWidget {
  final String kicker;
  final String title;
  final VoidCallback onContinue;

  const _RealityMirrorPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 24),
                  Text(
                    kicker.toUpperCase(),
                    style: _LuxuryTypography.label(
                      color: const Color(0xFFD4AF37),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: _LuxuryTypography.headline(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      height: 1.08,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 34),
                  const _RealityMirrorInsightLine(
                    leading: 'You are training for duration, not ',
                    highlight: 'domination.',
                  ),
                  const SizedBox(height: 18),
                  const _RealityMirrorInsightLine(
                    leading: 'You are repeating mistakes, not building a ',
                    highlight: 'career.',
                  ),
                  const SizedBox(height: 18),
                  const _RealityMirrorInsightLine(
                    leading: 'This is not a setback. This is your ',
                    highlight: 'turning point.',
                  ),
                  const SizedBox(height: 24),
                  const _RealityMirrorInsightCard(),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Built from your answers. Unique to you.',
                      textAlign: TextAlign.center,
                      style: _LuxuryTypography.body(
                        color: const Color(0xFF888888),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _PulseButton(
                label: 'Show me my roadmap',
                onPressed: onContinue,
                color: const Color(0xFFD4AF37),
                textColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RealityMirrorInsightLine extends StatelessWidget {
  final String leading;
  final String highlight;

  const _RealityMirrorInsightLine({
    required this.leading,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: _LuxuryTypography.body(
          color: Colors.white,
          fontSize: 21.5,
          fontWeight: FontWeight.w400,
          height: 1.58,
          letterSpacing: 0,
        ),
        children: <TextSpan>[
          TextSpan(text: leading),
          TextSpan(
            text: highlight,
            style: _LuxuryTypography.body(
              color: const Color(0xFFD4AF37),
              fontSize: 21.5,
              fontWeight: FontWeight.w700,
              height: 1.58,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RealityMirrorInsightCard extends StatelessWidget {
  const _RealityMirrorInsightCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: const Border(
          left: BorderSide(color: Color(0xFFD4AF37), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'WHAT HAPPENS NEXT',
            style: _LuxuryTypography.label(
              color: const Color(0xFFD4AF37),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: _LuxuryTypography.body(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w400,
                height: 1.58,
                letterSpacing: 0,
              ),
              children: <TextSpan>[
                const TextSpan(text: 'CrickNova now builds your '),
                TextSpan(
                  text: 'personal roadmap',
                  style: _LuxuryTypography.body(
                    color: const Color(0xFFD4AF37),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.58,
                    letterSpacing: 0,
                  ),
                ),
                const TextSpan(
                  text:
                      ' based on everything you just revealed. No generic advice. No guesswork. Just ',
                ),
                TextSpan(
                  text: 'precision',
                  style: _LuxuryTypography.body(
                    color: const Color(0xFFD4AF37),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.58,
                    letterSpacing: 0,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RealityMirrorScreen extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _RealityMirrorScreen({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0C0C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _FadeInUp(child: _RealityMirrorNav(onBack: onBack)),
                const SizedBox(height: 14),
                const _FadeInUp(
                  delay: Duration(milliseconds: 600),
                  child: _RealityMirrorProgressBar(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: 24),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 90),
                          child: Row(
                            children: const <Widget>[
                              _RealityMirrorDot(),
                              SizedBox(width: 12),
                              Text(
                                'THE REALITY MIRROR',
                                style: TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 3,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 160),
                          child: Text(
                            'Stagnation',
                            style: GoogleFonts.playfairDisplay(
                              color: const Color(0xFFEFEFEF),
                              fontSize: 56,
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                              height: 1.02,
                            ),
                          ),
                        ),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 240),
                          child: Text(
                            'Detected.',
                            style: GoogleFonts.playfairDisplay(
                              color: _CricknovaOnboardingScreenState._gold,
                              fontSize: 56,
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                              height: 1.02,
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 320),
                          child: const _RealityMirrorInsightRow(
                            icon: Icons.layers_rounded,
                            leading: 'Training for duration, not ',
                            highlight: 'domination.',
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: Color(0xFF161616),
                        ),
                        const SizedBox(height: 18),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 440),
                          child: const _RealityMirrorInsightRow(
                            icon: Icons.close_rounded,
                            leading: 'Repeating mistakes, not building a ',
                            highlight: 'career.',
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: Color(0xFF161616),
                        ),
                        const SizedBox(height: 18),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 560),
                          child: const _RealityMirrorInsightRow(
                            icon: Icons.bolt_rounded,
                            leading: 'This is not a setback. This is your ',
                            highlight: 'turning point.',
                          ),
                        ),
                        const SizedBox(height: 26),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 680),
                          child: const _RealityMirrorInfoCard(),
                        ),
                        const SizedBox(height: 16),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 780),
                          child: const Row(
                            children: <Widget>[
                              Expanded(
                                child: _RealityMirrorStatCard(
                                  value: '72%',
                                  label:
                                      'of cricketers plateau without a structured plan',
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _RealityMirrorStatCard(
                                  value: 'Day 1',
                                  label: "is the hardest. You're already here.",
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _FadeInUp(
                          delay: const Duration(milliseconds: 840),
                          child: const Text(
                            '"Awareness is the first step to dominance."',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFF4F1EA),
                              fontFamily: 'Georgia',
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w400,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                _FadeInUp(
                  delay: const Duration(milliseconds: 900),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: ElevatedButton(
                      onPressed: onContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _CricknovaOnboardingScreenState._gold,
                        foregroundColor: const Color(0xFF0C0C0C),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: Text(
                        'SHOW ME MY ROADMAP',
                        style: GoogleFonts.dmSans(
                          color: const Color(0xFF0C0C0C),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RealityMirrorStatCard extends StatelessWidget {
  final String value;
  final String label;

  const _RealityMirrorStatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD4AF37),
              fontFamily: 'Georgia',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              color: const Color(0xFFF4F1EA),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RealityMirrorNav extends StatelessWidget {
  final VoidCallback onBack;

  const _RealityMirrorNav({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFFE9E3D4),
              size: 16,
            ),
          ),
        ),
        Text(
          'CrickNova AI',
          style: GoogleFonts.dmSans(
            color: const Color(0xFFF4F1EA),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF222222)),
          ),
          child: Text(
            '5 / 37',
            style: GoogleFonts.dmSans(
              color: const Color(0xFFF4F1EA),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RealityMirrorDot extends StatelessWidget {
  const _RealityMirrorDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFFD4AF37),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _RealityMirrorProgressBar extends StatefulWidget {
  const _RealityMirrorProgressBar();

  @override
  State<_RealityMirrorProgressBar> createState() =>
      _RealityMirrorProgressBarState();
}

class _RealityMirrorProgressBarState extends State<_RealityMirrorProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _controller.forward();
      }
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget? child) {
        return Container(
          height: 2,
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(999),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.34 * _animation.value,
                child: Container(
                  decoration: const BoxDecoration(color: Color(0xFFD4AF37)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RealityMirrorInsightRow extends StatelessWidget {
  final IconData icon;
  final String leading;
  final String highlight;

  const _RealityMirrorInsightRow({
    required this.icon,
    required this.leading,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF222222)),
          ),
          child: Icon(icon, color: const Color(0xFFD4AF37), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: GoogleFonts.dmSans(
                color: const Color(0xFFF4F1EA),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
              children: <InlineSpan>[
                TextSpan(text: leading),
                TextSpan(
                  text: highlight,
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFFD4AF37),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
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

class _RealityMirrorInfoCard extends StatelessWidget {
  const _RealityMirrorInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 156),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.5),
      ),
      foregroundDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFD4AF37), width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 28, 30, 28),
        child: Text.rich(
          TextSpan(
            style: GoogleFonts.dmSans(
              color: const Color(0xFFF4F1EA),
              fontSize: 17,
              fontWeight: FontWeight.w400,
              height: 1.7,
            ),
            children: <InlineSpan>[
              const TextSpan(text: 'CrickNova builds your personal '),
              TextSpan(
                text: 'roadmap',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFFD4AF37),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.7,
                ),
              ),
              const TextSpan(
                text:
                    ' from everything you just revealed. No generic advice. No guesswork. Just ',
              ),
              TextSpan(
                text: 'precision',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFFD4AF37),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.7,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechnicalBlindnessPane extends StatelessWidget {
  final String kicker;
  final String title;
  final String ctaLabel;
  final VoidCallback onContinue;

  const _TechnicalBlindnessPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.ctaLabel,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 6),
                  _FadeInUp(
                    child: Text(
                      kicker.toUpperCase(),
                      style: _LuxuryTypography.label(
                        color: const Color(0xFFD4AF37),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 70),
                    child: Text(
                      title,
                      style: GoogleFonts.playfairDisplay(
                        color: const Color(0xFFF5F0E0),
                        fontSize: 31,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        height: 1.06,
                      ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 300),
                    child: const _TechnicalBlindnessQuote(
                      text: 'You are perfecting your flaws.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 800),
                    child: const _TechnicalBlindnessQuote(
                      text: 'Without data, you are running fast.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 1300),
                    child: const _TechnicalBlindnessQuote(
                      text: 'In a dark room.',
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: Color(0xFF1E1E16),
                  ),
                  const SizedBox(height: 28),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 1600),
                    child: const _TechnicalBlindnessFeatureCard(
                      icon: _TechnicalBlindnessIcon.target,
                      title: 'AI Mistake Detection',
                      desc:
                          'AI watches your game and pinpoints every technical error - grip, stance, follow-through',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 1720),
                    child: const _TechnicalBlindnessFeatureCard(
                      icon: _TechnicalBlindnessIcon.compare,
                      title: '2-Video Self Analysis',
                      desc:
                          'Compare your before vs after - see exactly how much you have improved',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 1840),
                    child: const _TechnicalBlindnessFeatureCard(
                      icon: _TechnicalBlindnessIcon.chat,
                      title: 'AI Chat Coach',
                      desc:
                          'Ask anything - your personal cricket coach available 24/7, always in your corner',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FadeInUp(
                    delay: const Duration(milliseconds: 1960),
                    child: const _TechnicalBlindnessInfoCard(),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'Your reality check is ready',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: const Color(0xFFF4F1EA),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            child: _PulseButton(
              label: ctaLabel,
              onPressed: onContinue,
              color: const Color(0xFFD4AF37),
              textColor: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}

class _TechnicalBlindnessQuote extends StatelessWidget {
  final String text;

  const _TechnicalBlindnessQuote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: const Color(0xFFD4AF37),
        fontSize: 16.5,
        fontWeight: FontWeight.w600,
        height: 1.5,
      ),
    );
  }
}

class _TechnicalBlindnessFeatureCard extends StatelessWidget {
  final _TechnicalBlindnessIcon icon;
  final String title;
  final String desc;

  const _TechnicalBlindnessFeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF13120C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A1E), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _TechnicalBlindnessIconBox(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFD4AF37),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFF4F1EA),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalBlindnessIconBox extends StatelessWidget {
  final _TechnicalBlindnessIcon icon;

  const _TechnicalBlindnessIconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1C10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(child: _TechnicalBlindnessIconGlyph(icon: icon)),
    );
  }
}

class _TechnicalBlindnessIconGlyph extends StatelessWidget {
  final _TechnicalBlindnessIcon icon;

  const _TechnicalBlindnessIconGlyph({required this.icon});

  @override
  Widget build(BuildContext context) {
    switch (icon) {
      case _TechnicalBlindnessIcon.target:
        return const Icon(
          Icons.center_focus_strong_rounded,
          color: Color(0xFFD4AF37),
          size: 21,
        );
      case _TechnicalBlindnessIcon.compare:
        return const Icon(
          Icons.view_column_rounded,
          color: Color(0xFFD4AF37),
          size: 21,
        );
      case _TechnicalBlindnessIcon.chat:
        return const Icon(
          Icons.chat_bubble_outline_rounded,
          color: Color(0xFFD4AF37),
          size: 20,
        );
    }
  }
}

enum _TechnicalBlindnessIcon { target, compare, chat }

class _TechnicalBlindnessInfoCard extends StatelessWidget {
  const _TechnicalBlindnessInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF13120C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A1E), width: 0.5),
      ),
      child: Text.rich(
        TextSpan(
          style: GoogleFonts.inter(
            color: const Color(0xFFF4F1EA),
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            height: 1.6,
          ),
          children: <InlineSpan>[
            const TextSpan(text: 'This is your '),
            TextSpan(
              text: 'reality mirror',
              style: GoogleFonts.inter(
                color: const Color(0xFFD4AF37),
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
            const TextSpan(text: '. What CrickNova reveals next becomes your '),
            TextSpan(
              text: 'roadmap',
              style: GoogleFonts.inter(
                color: const Color(0xFFD4AF37),
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
            const TextSpan(text: ' - so you stop practicing blind.'),
          ],
        ),
      ),
    );
  }
}

class _ChoicePane extends StatelessWidget {
  final String kicker;
  final String category;
  final String question;
  final String body;
  final List<_OptionChoice> options;
  final String? selectedValue;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;

  const _ChoicePane({
    super.key,
    required this.kicker,
    required this.category,
    required this.question,
    required this.body,
    required this.options,
    required this.selectedValue,
    required this.onSelect,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final canContinue = selectedValue != null;
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: question,
      body: body,
      footer: _PulseButton(
        label: 'Continue',
        onPressed: canContinue ? onContinue : null,
        color: _CricknovaOnboardingScreenState._gold,
        textColor: Colors.black,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x14D4AF37),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x33D4AF37)),
              ),
              child: Text(
                category.toUpperCase(),
                style: _LuxuryTypography.label(
                  color: const Color(0xCCD4AF37),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...options.map(
            (_OptionChoice option) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: _OptionCard(
                label: option.label,
                emoji: option.emoji,
                selected: selectedValue == option.label,
                onTap: () => onSelect(option.label),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: Text(
              'Every answer personalizes your cricket roadmap',
              textAlign: TextAlign.center,
              style: _LuxuryTypography.body(
                color: const Color(0xFF888888),
                fontSize: 13,
                fontWeight: FontWeight.w300,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String label;
  final String? emoji;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.label,
    this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Extract prefix (A., B., C., D.) if present
    final hasPrefix = label.length >= 3 && label[1] == '.' && label[2] == ' ';
    final prefix = hasPrefix ? label.substring(0, 1) : '';
    final cleanLabel = hasPrefix ? label.substring(3) : label;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutQuart,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          transform: Matrix4.identity()..scale(selected ? 1.01 : 1.0),
          decoration: BoxDecoration(
            color: selected ? const Color(0x1AD4AF37) : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? const Color(0xBFD4AF37)
                  : const Color(0x1AFFFFFF),
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFD4AF37).withOpacity(0.15),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: <Widget>[
              // Custom Alphanumeric Indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? const Color(0xFFD4AF37)
                      : const Color(0x12FFFFFF),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFD4AF37)
                        : const Color(0x22FFFFFF),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  prefix,
                  style: _LuxuryTypography.body(
                    color: selected ? Colors.black : const Color(0xFFD4AF37),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  cleanLabel,
                  style: _LuxuryTypography.body(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    height: 1.3,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFFD4AF37),
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisPane extends StatelessWidget {
  final String kicker;
  final String title;

  const _AnalysisPane({Key? key, required this.kicker, required this.title});

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: title,
      body:
          'Rotating scanning HUD engaged. Your blueprint is being assembled now.',
      footer: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          _HighlightedCopy(
            text:
                'Scanning movement patterns, decision pressure, technical risk, and long-term growth leaks.',
            style: _LuxuryTypography.body(
              color: const Color(0xB3FFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w300,
              height: 1.45,
            ),
            highlightStyle: _LuxuryTypography.body(
              color: const Color(0xFFD4AF37),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
      child: const Center(child: _ScanningHud()),
    );
  }
}

class _ReviewPane extends StatelessWidget {
  final String kicker;
  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onContinue;

  const _ReviewPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: title,
      body: body,
      footer: _PulseButton(
        label: ctaLabel,
        onPressed: onContinue,
        color: _CricknovaOnboardingScreenState._gold,
        textColor: Colors.black,
      ),
      child: const Column(children: <Widget>[_TrustStatsCard()]),
    );
  }
}

class _TrustStatsCard extends StatelessWidget {
  const _TrustStatsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: List<Widget>.generate(
              5,
              (int index) => const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.star_rounded,
                  color: Color(0xFFD4AF37),
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _HighlightedCopy(
            text:
                'Over 1,200 athletes have already used this blueprint to close the gap between raw potential and measurable performance.',
            style: _LuxuryTypography.body(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w300,
              height: 1.58,
            ),
            highlightStyle: _LuxuryTypography.body(
              color: const Color(0xFFD4AF37),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.58,
            ),
          ),
          const SizedBox(height: 14),
          _HighlightedCopy(
            text: 'Verified by players chasing selection, not just motivation.',
            style: _LuxuryTypography.label(
              color: const Color(0xB3FFFFFF),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
            highlightStyle: _LuxuryTypography.label(
              color: const Color(0xFFD4AF37),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalCtaPane extends StatelessWidget {
  final String kicker;
  final String title;
  final String body;
  final String ctaLabel;
  final int technicalDebtHours;
  final VoidCallback onContinue;

  const _FinalCtaPane({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.technicalDebtHours,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: title,
      body: body,
      footer: _PulseButton(
        label: ctaLabel,
        onPressed: onContinue,
        color: _CricknovaOnboardingScreenState._gold,
        textColor: Colors.black,
      ),
      child: Column(
        children: <Widget>[
          _VerdictCard(
            title: 'The Problem',
            body:
                'You are on track to waste ${_formatNumber(technicalDebtHours)} hours (${_formatNumber(technicalDebtHours ~/ 24)} days) on the wrong drills.',
            accent: const Color(0xFFE34234),
          ),
          const SizedBox(height: 14),
          _VerdictCard(
            title: 'The Solution',
            body:
                'Our 35-day plan will fix your 18 flaws and increase your selection probability by 30%.',
            accent: const Color(0xFFD4AF37),
            highlight: true,
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final String title;
  final String body;
  final Color accent;
  final bool highlight;

  const _VerdictCard({
    required this.title,
    required this.body,
    required this.accent,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x18D4AF37) : const Color(0x10FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.45)),
        boxShadow: highlight
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33D4AF37),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HighlightedCopy(
            text: title,
            style: _LuxuryTypography.label(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.9,
            ),
            highlightStyle: _LuxuryTypography.label(
              color: const Color(0xFFD4AF37),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.9,
            ),
          ),
          const SizedBox(height: 12),
          _HighlightedCopy(
            text: body,
            style: _LuxuryTypography.body(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w300,
              height: 1.52,
            ),
            highlightStyle: _LuxuryTypography.body(
              color: const Color(0xFFD4AF37),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.52,
            ),
          ),
        ],
      ),
    );
  }
}

class _NamastePane extends StatelessWidget {
  final String kicker;
  final String title;
  final String userName; // Added userName
  final String ctaLabel;
  final VoidCallback onContinue;

  const _NamastePane({
    super.key,
    required this.kicker,
    required this.title,
    required this.userName,
    required this.ctaLabel,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _PaneShell(
      key: key,
      kicker: kicker,
      title: '', // Custom layout
      body: '', // Custom layout
      footer: _PulseButton(
        label: ctaLabel,
        onPressed: onContinue,
        color: _CricknovaOnboardingScreenState._gold,
        textColor: Colors.black,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedEliteIndicator(userName: userName),
            const SizedBox(height: 40),
            Text(
              'Thanks for Trusting Us,\n$userName.',
              textAlign: TextAlign.center,
              style: _LuxuryTypography.body(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: _LuxuryTypography.body(
                    color: const Color(0xFFD4AF37),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'From this moment on, you are no longer just a player. You are a ',
                    ),
                    TextSpan(
                      text: 'Game Changer.',
                      style: _LuxuryTypography.body(
                        color: const Color(0xFFD4AF37),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ).copyWith(decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _AnimatedEliteIndicator extends StatefulWidget {
  final String userName;
  const _AnimatedEliteIndicator({required this.userName});

  @override
  State<_AnimatedEliteIndicator> createState() =>
      _AnimatedEliteIndicatorState();
}

class _AnimatedEliteIndicatorState extends State<_AnimatedEliteIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.04);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Circular Gradient Ring
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    const Color(0xFFD4AF37).withOpacity(0.2),
                    const Color(0xFFD4AF37).withOpacity(0.05),
                    const Color(0xFFD4AF37).withOpacity(0.2),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                  transform: GradientRotation(_controller.value * 2 * 3.14159),
                ),
              ),
              child: Center(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF09090B),
                  ),
                ),
              ),
            ),
            // Glow
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFFD4AF37,
                    ).withOpacity(0.15 * _controller.value),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // Custom Made Crown and Name
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: scale,
                  child: CustomPaint(
                    size: const Size(80, 60),
                    painter: _CrownPainter(),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.userName.toUpperCase(),
                  style: _LuxuryTypography.body(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final goldPaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.fill;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // Elegant, minimalist crown silhouette
    path.moveTo(w * 0.1, h); // Base start
    path.lineTo(w * 0.9, h); // Base end
    path.lineTo(w, h * 0.3); // Right spike outer
    path.lineTo(w * 0.75, h * 0.6); // Right valley
    path.lineTo(w * 0.5, 0); // Center spike
    path.lineTo(w * 0.25, h * 0.6); // Left valley
    path.lineTo(0, h * 0.3); // Left spike outer
    path.close();

    // Subtle curve to the base
    final rect = Rect.fromLTWH(w * 0.1, h * 0.85, w * 0.8, h * 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      goldPaint,
    );

    canvas.drawPath(path, goldPaint);

    // Decorative peaks (jewels)
    canvas.drawCircle(Offset(w * 0.5, -4), 5, goldPaint); // Center peak
    canvas.drawCircle(Offset(0, h * 0.25), 3.5, goldPaint); // Left peak
    canvas.drawCircle(Offset(w, h * 0.25), 3.5, goldPaint); // Right peak
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoadmapScreen extends StatefulWidget {
  final String userName;
  final String? roleValue;
  final int weeklyHours;
  final int dataPointCount;
  final int technicalDebtHours;
  final int fullDaysWasted;

  const _RoadmapScreen({
    required this.userName,
    required this.roleValue,
    required this.weeklyHours,
    required this.dataPointCount,
    required this.technicalDebtHours,
    required this.fullDaysWasted,
  });

  @override
  State<_RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<_RoadmapScreen> {
  int _loadingPercent = 0;
  bool _showRoadmap = false;
  bool _isContinuing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runLoadingSequence());
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _runLoadingSequence() async {
    final pauses = <Duration>[
      Duration(milliseconds: 1000 + math.Random().nextInt(501)),
      Duration(milliseconds: 1000 + math.Random().nextInt(501)),
      Duration(milliseconds: 1000 + math.Random().nextInt(501)),
    ];

    await _animateLoadingTo(32, const Duration(milliseconds: 1100));
    if (!mounted) return;
    await Future<void>.delayed(pauses[0]);
    if (!mounted) return;

    await _animateLoadingTo(67, const Duration(milliseconds: 1200));
    if (!mounted) return;
    await Future<void>.delayed(pauses[1]);
    if (!mounted) return;

    await _animateLoadingTo(89, const Duration(milliseconds: 900));
    if (!mounted) return;
    await Future<void>.delayed(pauses[2]);
    if (!mounted) return;

    await _animateLoadingTo(100, const Duration(milliseconds: 600));
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    setState(() {
      _showRoadmap = true;
    });
  }

  Future<void> _animateLoadingTo(int target, Duration duration) async {
    final start = _loadingPercent;
    final steps = math.max(1, (duration.inMilliseconds / 24).round());
    for (var step = 1; step <= steps; step++) {
      if (!mounted) return;
      final progress = step / steps;
      final nextValue = start + ((target - start) * progress).round();
      setState(() {
        _loadingPercent = nextValue.clamp(0, 100);
      });
      await Future<void>.delayed(
        Duration(milliseconds: (duration.inMilliseconds / steps).round()),
      );
    }
    if (!mounted) return;
    setState(() {
      _loadingPercent = target.clamp(0, 100);
    });
  }

  Future<void> _continue() async {
    if (_isContinuing) return;
    setState(() {
      _isContinuing = true;
    });

    // Removed _RatingScreen navigation

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && PremiumService.isPremiumActive) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigation(userName: widget.userName),
        ),
      );
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            const LoginScreen(postLoginTarget: LoginPostLoginTarget.paywall),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CricknovaOnboardingScreenState._bg,
      body: Stack(
        children: <Widget>[
          const RepaintBoundary(child: _CinematicBackdrop()),
          SafeArea(
            child: Column(
              children: <Widget>[
                const RepaintBoundary(
                  child: _CinematicTopBar(
                    title: 'CrickNova AI',
                    progressLabel: '37 / 37',
                    progress: 1,
                    onBack: null,
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: OnboardingUiTokens.motionEaseOut,
                    switchOutCurve: OnboardingUiTokens.motionEaseIn,
                    child: _showRoadmap
                        ? _RoadmapContent(
                            key: const ValueKey('roadmap'),
                            userName: widget.userName,
                            roleValue: widget.roleValue,
                            weeklyHours: widget.weeklyHours,
                            dataPointCount: widget.dataPointCount,
                            technicalDebtHours: widget.technicalDebtHours,
                            fullDaysWasted: widget.fullDaysWasted,
                            onContinue: _continue,
                          )
                        : _RoadmapLoadingPanel(
                            key: const ValueKey('loading'),
                            loadingPercent: _loadingPercent,
                            dataPointCount: widget.dataPointCount,
                            weeklyHours: widget.weeklyHours,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapLoadingPanel extends StatelessWidget {
  final int loadingPercent;
  final int dataPointCount;
  final int weeklyHours;

  const _RoadmapLoadingPanel({
    super.key,
    required this.loadingPercent,
    required this.dataPointCount,
    required this.weeklyHours,
  });

  @override
  Widget build(BuildContext context) {
    final analyzedCount = ((loadingPercent / 100) * dataPointCount).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'BUILDING YOUR ROADMAP',
              style: _LuxuryTypography.label(
                color: const Color(0xFFD4AF37),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.8,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '$loadingPercent%',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 54,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: loadingPercent / 100,
                minHeight: 8,
                backgroundColor: const Color(0xFF222222),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFD4AF37),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Analyzing $analyzedCount of $dataPointCount answers from your assessment.',
              textAlign: TextAlign.center,
              style: _LuxuryTypography.body(
                color: const Color(0xFFE0E0E0),
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Applying $weeklyHours hrs/week into your 90-day roadmap.',
              textAlign: TextAlign.center,
              style: _LuxuryTypography.body(
                color: const Color(0xFF9D9D9D),
                fontSize: 14,
                fontWeight: FontWeight.w300,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoadmapContent extends StatelessWidget {
  final String userName;
  final String? roleValue;
  final int weeklyHours;
  final int dataPointCount;
  final int technicalDebtHours;
  final int fullDaysWasted;
  final VoidCallback onContinue;

  const _RoadmapContent({
    super.key,
    required this.userName,
    required this.roleValue,
    required this.weeklyHours,
    required this.dataPointCount,
    required this.technicalDebtHours,
    required this.fullDaysWasted,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final recommendedPlan = _recommendedPlanLabel;
    final upgradePlan = _upgradePlanLabel;
    final planReason = _recommendedPlanReason;
    final featureCards = _featureCardsForRole(roleValue);
    final mistakeCards = _mistakeCardsForRole(roleValue);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'PERSONALIZED TRANSFORMATION ROADMAP',
              style: _LuxuryTypography.label(
                color: const Color(0xFFD4AF37),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.6,
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                style: _LuxuryTypography.body(
                  color: const Color(0xFFEDEDED),
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  height: 1.55,
                ),
                children: <InlineSpan>[
                  const TextSpan(
                    text:
                        'We\'ve analyzed your 35 data points. Your dedication is clear, but your trajectory needs correction. At ',
                  ),
                  TextSpan(
                    text: 'CrickNova',
                    style: _LuxuryTypography.body(
                      color: const Color(0xFFD4AF37),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.55,
                    ),
                  ),
                  const TextSpan(
                    text:
                        ', we hate seeing pure talent wasted on unguided practice.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: _RoadmapMetricChip(
                    label: 'Data Points',
                    value: '$dataPointCount',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RoadmapMetricChip(
                    label: 'Volume',
                    value: '$weeklyHours hrs/wk',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _RoadmapMetricChip(
              label: 'Technical Debt',
              value:
                  '${_formatNumber(technicalDebtHours)} hrs (${_formatNumber(technicalDebtHours ~/ 24)} days) at risk',
              fullWidth: true,
              accent: const Color(0xFFE34234),
            ),
            const SizedBox(height: 20),
            Text(
              'How CrickNova Helps You',
              style: _LuxuryTypography.body(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 14),
            ...featureCards.map(
              (_RoadmapInfoCard card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RoadmapInfoCardView(card: card),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF5A3A00), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Best Plan For You',
                    style: _LuxuryTypography.label(
                      color: const Color(0xFFD4AF37),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recommendedPlan,
                    style: _LuxuryTypography.body(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    planReason,
                    style: _LuxuryTypography.body(
                      color: const Color(0xFFE0E0E0),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Next tier: $upgradePlan',
                    style: _LuxuryTypography.body(
                      color: const Color(0xFF9D9D9D),
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE34234), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Your Biggest Mistakes',
                    style: _LuxuryTypography.label(
                      color: const Color(0xFFE34234),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...mistakeCards.map(
                    (_RoadmapMistakeLine line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RoadmapMistakeLineView(line: line),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Your 90-Day Elite Transformation',
              style: _LuxuryTypography.body(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 18),
            _RoadmapTimelineItem(
              dayLabel: 'DAY 1-7',
              title: 'Biomechanical Alignment',
              body: 'AI identifies your "Power Leak" points.',
              accent: const Color(0xFFD4AF37),
            ),
            _RoadmapTimelineItem(
              dayLabel: 'DAY 30',
              title: 'Muscle Memory Reset',
              body:
                  'Eliminating the ${_formatNumber(technicalDebtHours)} hours (${_formatNumber(technicalDebtHours ~/ 24)} days) we calculated.',
              accent: const Color(0xFFE34234),
            ),
            _RoadmapTimelineItem(
              dayLabel: 'DAY 90',
              title: 'Technical Mastery',
              body: 'Projected 15% increase in accuracy/pace.',
              accent: const Color(0xFFD4AF37),
              isLast: true,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2A2A00), width: 0.5),
              ),
              child: Text(
                'Commit to 90 days of purposeful training. Don\'t just practice, evolve.',
                style: _LuxuryTypography.body(
                  color: const Color(0xFFE0E0E0),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PulseButton(
              label: 'Start My Guided Journey',
              onPressed: onContinue,
              color: const Color(0xFFD4AF37),
              textColor: Colors.black,
            ),
            const SizedBox(height: 10),
            Text(
              'Built for $userName. $fullDaysWasted full days are on the line if the path stays generic.',
              textAlign: TextAlign.center,
              style: _LuxuryTypography.body(
                color: const Color(0xFF777777),
                fontSize: 12,
                fontWeight: FontWeight.w300,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _recommendedPlanLabel {
    return _isIndiaPricing
        ? 'Yearly Access • ₹499 /yr'
        : 'Yearly Access • \$69.99 /yr';
  }

  String get _recommendedPlanReason {
    return _isIndiaPricing
        ? 'India pricing detected. Yearly Access gives you the strongest value for long-term correction and includes 3 days free.'
        : 'International pricing detected. Yearly Access gives you the strongest value for long-term correction and includes 3 days free.';
  }

  String get _upgradePlanLabel {
    return _isIndiaPricing
        ? 'Ultra Pro • ₹1999'
        : 'Ultra International • \$169.99';
  }

  bool get _isIndiaPricing =>
      PricingLocationService.currentRegion == PricingRegion.india;

  List<_RoadmapInfoCard> _featureCardsForRole(String? role) {
    final roleLabel = switch (role) {
      'Bowler' => 'Bowling speed, line, length, and release feedback',
      'All-Rounder' => 'Batting + bowling correction in one plan',
      'Wicket-Keeper' => 'Footwork, glove path, and reaction analysis',
      _ => 'Batting posture, swing path, and timing analysis',
    };

    return <_RoadmapInfoCard>[
      const _RoadmapInfoCard(
        title: 'Mistake Detection',
        body:
            'Shows where your technique leaks so you stop repeating the same error.',
        accent: Color(0xFFD4AF37),
      ),
      _RoadmapInfoCard(
        title: 'AI Coaching',
        body:
            'Gives you real-time correction instead of generic training advice.',
        accent: const Color(0xFFD4AF37),
      ),
      _RoadmapInfoCard(
        title: 'Role-Specific Analysis',
        body: roleLabel,
        accent: const Color(0xFFE34234),
      ),
    ];
  }

  List<_RoadmapMistakeLine> _mistakeCardsForRole(String? role) {
    final roleMistake = switch (role) {
      'Bowler' =>
        'Your release point and length control are not stable under pressure.',
      'All-Rounder' =>
        'Your batting and bowling need separate correction, not more blind reps.',
      'Wicket-Keeper' =>
        'Your footwork and glove timing drift when the speed increases.',
      _ => 'Your bat path and timing need correction, not more repetition.',
    };

    return <_RoadmapMistakeLine>[
      const _RoadmapMistakeLine(
        text: 'Too much practice volume without live correction.',
      ),
      _RoadmapMistakeLine(text: roleMistake),
      const _RoadmapMistakeLine(
        text: 'No structured system to turn work into measurable progress.',
      ),
    ];
  }
}

class _RoadmapMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final bool fullWidth;
  final Color accent;

  const _RoadmapMetricChip({
    required this.label,
    required this.value,
    this.fullWidth = false,
    this.accent = const Color(0xFFD4AF37),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.35), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: _LuxuryTypography.label(
              color: const Color(0x99FFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: _LuxuryTypography.body(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapTimelineItem extends StatelessWidget {
  final String dayLabel;
  final String title;
  final String body;
  final Color accent;
  final bool isLast;

  const _RoadmapTimelineItem({
    required this.dayLabel,
    required this.title,
    required this.body,
    required this.accent,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Column(
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 72,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    dayLabel,
                    style: _LuxuryTypography.label(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: _LuxuryTypography.body(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: _LuxuryTypography.body(
                      color: const Color(0xFFE0E0E0),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapInfoCard {
  final String title;
  final String body;
  final Color accent;

  const _RoadmapInfoCard({
    required this.title,
    required this.body,
    required this.accent,
  });
}

class _RoadmapInfoCardView extends StatelessWidget {
  final _RoadmapInfoCard card;

  const _RoadmapInfoCardView({Key? key, required this.card}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: card.accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            card.title,
            style: _LuxuryTypography.label(
              color: card.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            card.body,
            style: _LuxuryTypography.body(
              color: const Color(0xFFE0E0E0),
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoadmapMistakeLine {
  final String text;

  const _RoadmapMistakeLine({required this.text});
}

class _RoadmapMistakeLineView extends StatelessWidget {
  final _RoadmapMistakeLine line;

  const _RoadmapMistakeLineView({Key? key, required this.line})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE34234),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            line.text,
            style: _LuxuryTypography.body(
              color: const Color(0xFFE0E0E0),
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompletionPane extends StatefulWidget {
  const _CompletionPane({Key? key}) : super(key: key);

  @override
  State<_CompletionPane> createState() => _CompletionPaneState();
}

class _CompletionPaneState extends State<_CompletionPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RotationTransition(
            turns: _controller,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x55D4AF37), width: 3),
              ),
              child: const Center(
                child: Icon(
                  Icons.radar_rounded,
                  color: Color(0xFFD4AF37),
                  size: 38,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Locking in your blueprint...',
            style: _LuxuryTypography.headline(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Saving your answers and preparing the next stage.',
            textAlign: TextAlign.center,
            style: _LuxuryTypography.body(
              color: const Color(0xCCFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;

  const _PulseButton({
    required this.label,
    required this.onPressed,
    required this.color,
    required this.textColor,
  });

  @override
  State<_PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<_PulseButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _isPressed = false) : null,
        child: AnimatedScale(
          scale: (enabled && _isPressed) ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: double.infinity,
            height: 62,
            child: ElevatedButton(
              onPressed: widget.onPressed,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: enabled
                    ? widget.color
                    : const Color(0x22FFFFFF),
                foregroundColor: enabled
                    ? widget.textColor
                    : const Color(0x66FFFFFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: enabled
                        ? widget.color.withOpacity(0.75)
                        : const Color(0x22FFFFFF),
                  ),
                ),
              ),
              child: _HighlightedCopy(
                text: widget.label,
                style: _LuxuryTypography.body(
                  color: enabled ? widget.textColor : const Color(0x66FFFFFF),
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
                highlightStyle: _LuxuryTypography.body(
                  color: enabled ? widget.textColor : const Color(0x66FFFFFF),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeInUp({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<_FadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
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
    final animation = CurvedAnimation(
      parent: _controller,
      curve: OnboardingUiTokens.motionEaseOut,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final value = Curves.easeOutQuart.transform(animation.value);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child!,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ScanningHud extends StatefulWidget {
  const _ScanningHud();

  @override
  State<_ScanningHud> createState() => _ScanningHudState();
}

class _ScanningHudState extends State<_ScanningHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Transform.rotate(
            angle: _controller.value * math.pi * 2,
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x33D4AF37)),
              ),
            ),
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
            ),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x44E34234)),
              ),
            ),
            Positioned(
              top: 18,
              child: Container(
                width: 3,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x44D4AF37),
                      blurRadius: 18,
                      offset: Offset(0, 0),
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.radar_rounded, color: Color(0xFFD4AF37), size: 36),
          ],
        ),
      ),
    );
  }
}

// Full-screen rating prompt widget
class _RatingScreen extends StatelessWidget {
  const _RatingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CricknovaOnboardingScreenState._bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),

              Icon(Icons.star_rounded, color: Color(0xFFD4AF37), size: 64),
              const SizedBox(height: 24),

              Text(
                "Enjoying CrickNova AI?",
                textAlign: TextAlign.center,
                style: GoogleFonts.cormorantGaramond(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                "Your feedback helps us improve and reach more athletes like you.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFD4AF37),
                    size: 28,
                  ),
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    "Rate Now",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Maybe later",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
