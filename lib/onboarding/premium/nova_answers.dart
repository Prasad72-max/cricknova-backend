sealed class NovaAnswer {
  const NovaAnswer();
}

final class NovaSingleChoiceAnswer extends NovaAnswer {
  final String id;
  const NovaSingleChoiceAnswer(this.id);
}

final class NovaMultiChoiceAnswer extends NovaAnswer {
  final Set<String> ids;
  const NovaMultiChoiceAnswer(this.ids);
}

final class NovaSliderAnswer extends NovaAnswer {
  final double value;
  const NovaSliderAnswer(this.value);
}

final class NovaYesNoAnswer extends NovaAnswer {
  final bool value;
  const NovaYesNoAnswer(this.value);
}
