import 'dart:async';

import 'package:flutter/material.dart';

import 'nova_tokens.dart';

/// Fade + slight horizontal slide in, with an optional delay.
/// Uses a minimal state/timer so it works inside any layout.
class NovaReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset from;

  const NovaReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = const Offset(18, 0),
  });

  @override
  State<NovaReveal> createState() => _NovaRevealState();
}

class _NovaRevealState extends State<NovaReveal> {
  bool _on = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant NovaReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay != widget.delay) _schedule();
  }

  void _schedule() {
    _t?.cancel();
    _on = false;
    _t = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => _on = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = NovaMotion.reduceMotionOf(context);
    if (reduceMotion) return widget.child;
    final d = NovaMotion.maybe(NovaTokens.dMed, reduceMotion: reduceMotion);
    return AnimatedOpacity(
      opacity: _on ? 1 : 0,
      duration: d,
      curve: NovaTokens.ease,
      child: AnimatedSlide(
        offset: _on ? Offset.zero : widget.from / 120.0,
        duration: d,
        curve: NovaTokens.ease,
        child: widget.child,
      ),
    );
  }
}
