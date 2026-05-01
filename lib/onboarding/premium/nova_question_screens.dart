import 'package:flutter/material.dart';

import 'nova_answers.dart';
import 'nova_choices.dart';
import 'nova_question_template.dart';
import 'nova_slider.dart';
import 'nova_steps.dart';
import 'nova_tokens.dart';

class NovaQuestionScreen extends StatelessWidget {
  final NovaQuestionStep step;
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final ValueChanged<NovaAnswer> onAnswered;

  const NovaQuestionScreen({
    super.key,
    required this.step,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.onAnswered,
  });

  @override
  Widget build(BuildContext context) {
    return switch (step.kind) {
      NovaQuestionKind.singleChoiceCards => _SingleChoice(
        step: step,
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        onAnswered: onAnswered,
      ),
      NovaQuestionKind.multiChoiceChips => _MultiChoice(
        step: step,
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        onAnswered: onAnswered,
      ),
      NovaQuestionKind.slider => _Slider(
        step: step,
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        onAnswered: onAnswered,
      ),
      NovaQuestionKind.yesNo => _YesNo(
        step: step,
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        onAnswered: onAnswered,
      ),
      NovaQuestionKind.role => _Role(
        step: step,
        progress: progress,
        stepText: stepText,
        onBack: onBack,
        onAnswered: onAnswered,
      ),
    };
  }
}

class _SingleChoice extends StatefulWidget {
  final NovaQuestionStep step;
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final ValueChanged<NovaAnswer> onAnswered;

  const _SingleChoice({
    required this.step,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.onAnswered,
  });

  @override
  State<_SingleChoice> createState() => _SingleChoiceState();
}

class _SingleChoiceState extends State<_SingleChoice> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final ans = _selectedId == null
        ? null
        : NovaSingleChoiceAnswer(_selectedId!);
    final coach = widget.step.coachLine?.call(ans);
    return NovaQuestionTemplate(
      onBack: widget.onBack,
      progress: widget.progress,
      progressText: 'Building your player profile',
      stepText: widget.stepText,
      categoryLabel: widget.step.categoryLabel,
      title: widget.step.title,
      subtitle: widget.step.subtitle,
      answers: NovaSingleChoiceCards(
        options: widget.step.options,
        selectedId: _selectedId,
        onSelected: (id) => setState(() => _selectedId = id),
      ),
      coachLine: coach,
      continueEnabled: _selectedId != null,
      onContinue: () => widget.onAnswered(NovaSingleChoiceAnswer(_selectedId!)),
    );
  }
}

class _Role extends StatefulWidget {
  final NovaQuestionStep step;
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final ValueChanged<NovaAnswer> onAnswered;

  const _Role({
    required this.step,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.onAnswered,
  });

  @override
  State<_Role> createState() => _RoleState();
}

class _RoleState extends State<_Role> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final ans = _selectedId == null
        ? null
        : NovaSingleChoiceAnswer(_selectedId!);
    final coach = widget.step.coachLine?.call(ans);
    return NovaQuestionTemplate(
      onBack: widget.onBack,
      progress: widget.progress,
      progressText: 'Building your player profile',
      stepText: widget.stepText,
      categoryLabel: widget.step.categoryLabel,
      title: widget.step.title,
      subtitle: widget.step.subtitle,
      answers: NovaRoleGrid(
        options: widget.step.options,
        selectedId: _selectedId,
        onSelected: (id) => setState(() => _selectedId = id),
      ),
      coachLine: coach,
      continueEnabled: _selectedId != null,
      onContinue: () => widget.onAnswered(NovaSingleChoiceAnswer(_selectedId!)),
    );
  }
}

class _MultiChoice extends StatefulWidget {
  final NovaQuestionStep step;
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final ValueChanged<NovaAnswer> onAnswered;

  const _MultiChoice({
    required this.step,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.onAnswered,
  });

  @override
  State<_MultiChoice> createState() => _MultiChoiceState();
}

class _MultiChoiceState extends State<_MultiChoice> {
  Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final ans = NovaMultiChoiceAnswer(_selected);
    final coach = _selected.isEmpty ? null : widget.step.coachLine?.call(ans);
    return NovaQuestionTemplate(
      onBack: widget.onBack,
      progress: widget.progress,
      progressText: 'Building your player profile',
      stepText: widget.stepText,
      categoryLabel: widget.step.categoryLabel,
      title: widget.step.title,
      subtitle: widget.step.subtitle,
      answers: NovaMultiChoiceChips(
        options: widget.step.options,
        selectedIds: _selected,
        onChanged: (next) => setState(() => _selected = next),
      ),
      coachLine: coach,
      continueEnabled: _selected.isNotEmpty,
      continueLabel: 'Continue',
      onContinue: () =>
          widget.onAnswered(NovaMultiChoiceAnswer(Set<String>.from(_selected))),
    );
  }
}

class _YesNo extends StatefulWidget {
  final NovaQuestionStep step;
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final ValueChanged<NovaAnswer> onAnswered;

  const _YesNo({
    required this.step,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.onAnswered,
  });

  @override
  State<_YesNo> createState() => _YesNoState();
}

class _YesNoState extends State<_YesNo> {
  bool? _value;

  @override
  Widget build(BuildContext context) {
    final ans = _value == null ? null : NovaYesNoAnswer(_value!);
    final coach = _value == null ? null : widget.step.coachLine?.call(ans);
    return NovaQuestionTemplate(
      onBack: widget.onBack,
      progress: widget.progress,
      progressText: 'Building your player profile',
      stepText: widget.stepText,
      categoryLabel: widget.step.categoryLabel,
      title: widget.step.title,
      subtitle: widget.step.subtitle,
      answers: NovaYesNoChoice(
        value: _value,
        onChanged: (v) => setState(() => _value = v),
      ),
      coachLine: coach,
      continueEnabled: _value != null,
      onContinue: () => widget.onAnswered(NovaYesNoAnswer(_value!)),
    );
  }
}

class _Slider extends StatefulWidget {
  final NovaQuestionStep step;
  final double progress;
  final String? stepText;
  final VoidCallback? onBack;
  final ValueChanged<NovaAnswer> onAnswered;

  const _Slider({
    required this.step,
    required this.progress,
    required this.stepText,
    required this.onBack,
    required this.onAnswered,
  });

  @override
  State<_Slider> createState() => _SliderState();
}

class _SliderState extends State<_Slider> {
  late double _value;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _value = (widget.step.sliderMin + widget.step.sliderMax) / 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final ans = NovaSliderAnswer(_value);
    final coach = _touched ? widget.step.coachLine?.call(ans) : null;
    return NovaQuestionTemplate(
      onBack: widget.onBack,
      progress: widget.progress,
      progressText: 'Building your player profile',
      stepText: widget.stepText,
      categoryLabel: widget.step.categoryLabel,
      title: widget.step.title,
      subtitle: widget.step.subtitle,
      answers: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: NovaColors.bgSurface,
          borderRadius: BorderRadius.circular(NovaTokens.rXl),
          border: Border.all(color: NovaColors.borderSubtle),
        ),
        child: NovaGlowSlider(
          value: _value,
          min: widget.step.sliderMin,
          max: widget.step.sliderMax,
          divisions: widget.step.sliderDivisions,
          leftLabel: widget.step.sliderLeftLabel,
          rightLabel: widget.step.sliderRightLabel,
          onChanged: (v) => setState(() {
            _value = v;
            _touched = true;
          }),
        ),
      ),
      coachLine: coach,
      continueEnabled: _touched,
      onContinue: () => widget.onAnswered(NovaSliderAnswer(_value)),
    );
  }
}
