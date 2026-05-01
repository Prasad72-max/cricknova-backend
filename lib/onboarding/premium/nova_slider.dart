import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nova_tokens.dart';

class NovaGlowSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? leftLabel;
  final String? rightLabel;

  const NovaGlowSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.leftLabel,
    this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: NovaColors.accent,
            inactiveTrackColor: NovaColors.progressTrack,
            overlayColor: NovaColors.accentGlow(0.18),
            thumbColor: NovaColors.accent,
            valueIndicatorColor: NovaColors.bgElevated,
            valueIndicatorTextStyle: NovaTypography.title(
              size: 12,
              weight: FontWeight.w700,
              color: NovaColors.textPrimary,
              height: 1.0,
              letterSpacing: 0.0,
            ),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) {
              if (!reduceMotion) HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ),
        if (leftLabel != null || rightLabel != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  leftLabel ?? '',
                  style: NovaTypography.body(
                    size: 12,
                    height: 1.2,
                    color: NovaColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  rightLabel ?? '',
                  textAlign: TextAlign.right,
                  style: NovaTypography.body(
                    size: 12,
                    height: 1.2,
                    color: NovaColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
