import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nova_tokens.dart';

class NovaChoiceOption {
  final String id;
  final String label;
  final String? hint;
  final IconData? icon;

  const NovaChoiceOption({
    required this.id,
    required this.label,
    this.hint,
    this.icon,
  });
}

class NovaCoachLine extends StatelessWidget {
  final String? text;

  const NovaCoachLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    return AnimatedSwitcher(
      duration: NovaMotion.maybe(NovaTokens.dMed, reduceMotion: reduceMotion),
      switchInCurve: NovaTokens.ease,
      switchOutCurve: NovaTokens.easeIn,
      child: text == null
          ? const SizedBox(height: 20)
          : Padding(
              key: ValueKey<String>(text!),
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                text!,
                style: NovaTypography.body(
                  color: NovaColors.textMuted,
                  size: 13,
                  height: 1.35,
                ),
              ),
            ),
    );
  }
}

class NovaSingleChoiceCards extends StatelessWidget {
  final List<NovaChoiceOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const NovaSingleChoiceCards({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final o in options) ...[
          NovaSelectableCard(
            title: o.label,
            subtitle: o.hint,
            icon: o.icon,
            selected: o.id == selectedId,
            onTap: () => onSelected(o.id),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class NovaMultiChoiceChips extends StatelessWidget {
  final List<NovaChoiceOption> options;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const NovaMultiChoiceChips({
    super.key,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final o in options)
          _Chip(
            label: o.label,
            selected: selectedIds.contains(o.id),
            onTap: () {
              final next = Set<String>.from(selectedIds);
              if (!next.add(o.id)) next.remove(o.id);
              HapticFeedback.selectionClick();
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class NovaYesNoChoice extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool> onChanged;
  final String yesLabel;
  final String noLabel;

  const NovaYesNoChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.yesLabel = 'Yes',
    this.noLabel = 'No',
  });

  @override
  Widget build(BuildContext context) {
    final selected = value;
    return Row(
      children: [
        Expanded(
          child: _Chip(
            label: yesLabel,
            selected: selected == true,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(true);
            },
            leading: Icons.check_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Chip(
            label: noLabel,
            selected: selected == false,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(false);
            },
            leading: Icons.close_rounded,
          ),
        ),
      ],
    );
  }
}

class NovaRoleGrid extends StatelessWidget {
  final List<NovaChoiceOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const NovaRoleGrid({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final crossAxisCount = width >= 380 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: options.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossAxisCount == 2 ? 1.90 : 3.2,
          ),
          itemBuilder: (context, i) {
            final o = options[i];
            return NovaSelectableCard(
              title: o.label,
              subtitle: o.hint,
              icon: o.icon,
              selected: o.id == selectedId,
              onTap: () => onSelected(o.id),
              dense: crossAxisCount == 2,
            );
          },
        );
      },
    );
  }
}

class NovaSelectableCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  const NovaSelectableCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  @override
  State<NovaSelectableCard> createState() => _NovaSelectableCardState();
}

class _NovaSelectableCardState extends State<NovaSelectableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final selected = widget.selected;

    final bg = selected ? NovaColors.bgElevated : NovaColors.bgSurface;
    final borderColor = selected
        ? NovaColors.accentGlow(0.55)
        : NovaColors.borderSubtle;
    final shadow = selected
        ? [
            BoxShadow(
              color: NovaColors.accentGlow(0.22),
              blurRadius: 22,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ]
        : [
            const BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.28),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ];

    final baseScale = selected ? 1.01 : 1.0;
    final pressedScale = _pressed ? 0.985 : 1.0;
    final scale = reduceMotion ? 1.0 : baseScale * pressedScale;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: scale,
        duration: NovaMotion.maybe(
          NovaTokens.dFast,
          reduceMotion: reduceMotion,
        ),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: NovaMotion.maybe(
            NovaTokens.dMed,
            reduceMotion: reduceMotion,
          ),
          curve: NovaTokens.easeInOut,
          constraints: const BoxConstraints(minHeight: 76),
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: widget.dense ? 18 : 20,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(NovaTokens.rXl),
            border: Border.all(color: borderColor),
            boxShadow: shadow,
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                _IconHalo(icon: widget.icon!, selected: selected),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: NovaTypography.title(
                        size: 16,
                        weight: FontWeight.w700,
                        color: NovaColors.textPrimary,
                        height: 1.15,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle!,
                        style: NovaTypography.body(
                          size: 13,
                          height: 1.35,
                          color: NovaColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: NovaMotion.maybe(
                  NovaTokens.dMed,
                  reduceMotion: reduceMotion,
                ),
                curve: NovaTokens.easeInOut,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected ? NovaColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? NovaColors.accentGlow(0.8)
                        : NovaColors.borderSubtle,
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: NovaColors.accentGlow(0.28),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: NovaColors.ctaText,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconHalo extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _IconHalo({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: selected ? NovaColors.accentGlow(0.12) : NovaColors.bgSurface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? NovaColors.accentGlow(0.55)
              : NovaColors.borderSubtle,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: NovaColors.accentGlow(0.18),
              blurRadius: 16,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Icon(
        icon,
        color: selected ? NovaColors.accent : NovaColors.textPrimary,
        size: 22,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leading;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    final bg = selected ? NovaColors.accentGlow(0.14) : NovaColors.bgSurface;
    final border = selected
        ? NovaColors.accentGlow(0.55)
        : NovaColors.borderSubtle;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: NovaMotion.maybe(NovaTokens.dMed, reduceMotion: reduceMotion),
        curve: NovaTokens.easeInOut,
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: NovaColors.accentGlow(0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              Icon(
                leading,
                size: 18,
                color: selected ? NovaColors.accent : NovaColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: NovaTypography.title(
                size: 14,
                weight: FontWeight.w600,
                color: selected
                    ? NovaColors.textPrimary
                    : NovaColors.textSecondary,
                height: 1.0,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
