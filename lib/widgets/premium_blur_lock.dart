import 'dart:ui';

import 'package:flutter/material.dart';

class PremiumBlurLock extends StatelessWidget {
  const PremiumBlurLock({
    super.key,
    required this.locked,
    required this.child,
    required this.ctaText,
    required this.onUnlock,
    this.title = "Unlock Elite Insights",
    this.subtitle,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blurSigma = 12.0,
    this.tint,
  });

  final bool locked;
  final Widget child;
  final String ctaText;
  final VoidCallback onUnlock;

  final String title;
  final String? subtitle;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          AbsorbPointer(absorbing: true, child: child),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(
                decoration: BoxDecoration(
                  color: tint ?? Colors.black.withOpacity(0.30),
                  border: Border.all(color: Colors.white.withOpacity(0.20)),
                  borderRadius: borderRadius,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: _LockCta(
                  title: title,
                  subtitle: subtitle,
                  ctaText: ctaText,
                  onUnlock: onUnlock,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockCta extends StatelessWidget {
  const _LockCta({
    required this.title,
    required this.subtitle,
    required this.ctaText,
    required this.onUnlock,
  });

  final String title;
  final String? subtitle;
  final String ctaText;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFB45309)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.38),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Colors.black,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 0.6,
              fontFamily: "serif",
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _PremiumCtaButton(text: ctaText, onTap: onUnlock),
        ],
      ),
    );
  }
}

class _PremiumCtaButton extends StatelessWidget {
  const _PremiumCtaButton({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF22D3EE)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22D3EE).withOpacity(0.26),
                blurRadius: 22,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFF8B5CF6).withOpacity(0.22),
                blurRadius: 26,
                spreadRadius: 1,
              ),
            ],
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}
