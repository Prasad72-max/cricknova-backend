import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nova_tokens.dart';

class NovaPrimaryButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  const NovaPrimaryButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<NovaPrimaryButton> createState() => _NovaPrimaryButtonState();
}

class _NovaPrimaryButtonState extends State<NovaPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPulse());
  }

  @override
  void didUpdateWidget(covariant NovaPrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _syncPulse();
  }

  void _syncPulse() {
    if (!mounted) return;
    if (widget.enabled && !NovaMotion.reduceMotionOf(context)) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final enabled = widget.enabled && widget.onPressed != null;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        final glow = enabled ? lerpDouble(0.16, 0.26, t)! : 0.0;
        final scale = enabled ? lerpDouble(1.0, 1.015, t)! : 1.0;
        final pressScale = _pressed ? 0.985 : 1.0;
        return AnimatedScale(
          scale: reduceMotion ? 1.0 : (scale * pressScale),
          duration: NovaTokens.dMed,
          curve: NovaTokens.ease,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: NovaTokens.dFast,
            child: GestureDetector(
              onTap: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onPressed?.call();
                    }
                  : null,
              onTapDown: enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapCancel: enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: enabled ? NovaColors.accent : NovaColors.bgSurface2,
                  borderRadius: BorderRadius.circular(NovaTokens.rLg),
                  border: Border.all(
                    color: enabled
                        ? NovaColors.accentGlow(0.35)
                        : NovaColors.borderSubtle,
                  ),
                  boxShadow: [
                    if (enabled)
                      BoxShadow(
                        color: NovaColors.accentGlow(glow),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.label,
                  style: NovaTypography.title(
                    color: enabled
                        ? NovaColors.ctaText
                        : NovaColors.textDisabled,
                    size: 15,
                    weight: FontWeight.w700,
                    letterSpacing: -0.1,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
