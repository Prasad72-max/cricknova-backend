import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/crickx_colors.dart';

/// 1000% accurate vector Google Play Store logo
class GooglePlayLogo extends StatelessWidget {
  const GooglePlayLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GooglePlayPainter(),
      ),
    );
  }
}

class _GooglePlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer rounded triangle boundary
    final clipPath = Path()
      ..moveTo(w * 0.12, h * 0.08)
      ..lineTo(w * 0.82, h * 0.46)
      ..quadraticBezierTo(w * 0.94, h * 0.50, w * 0.82, h * 0.54)
      ..lineTo(w * 0.12, h * 0.92)
      ..quadraticBezierTo(w * 0.04, h * 0.96, w * 0.04, h * 0.88)
      ..lineTo(w * 0.04, h * 0.12)
      ..quadraticBezierTo(w * 0.04, h * 0.04, w * 0.12, h * 0.08)
      ..close();

    canvas.save();
    canvas.clipPath(clipPath);

    final centerPoint = Offset(w * 0.50, h * 0.50);
    final topLeft = Offset(w * 0.04, h * 0.04);
    final bottomLeft = Offset(w * 0.04, h * 0.96);
    final rightTip = Offset(w * 0.94, h * 0.50);

    // 1. Blue base (left)
    final bluePath = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(centerPoint.dx, centerPoint.dy)
      ..close();
    canvas.drawPath(
      bluePath,
      Paint()
        ..color = const Color(0xFF0086F8)
        ..style = PaintingStyle.fill,
    );

    // 2. Green top fold
    final greenPath = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(rightTip.dx, rightTip.dy)
      ..lineTo(centerPoint.dx, centerPoint.dy)
      ..close();
    canvas.drawPath(
      greenPath,
      Paint()
        ..color = const Color(0xFF00E676)
        ..style = PaintingStyle.fill,
    );

    // 3. Red bottom fold
    final redPath = Path()
      ..moveTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(rightTip.dx, rightTip.dy)
      ..lineTo(centerPoint.dx, centerPoint.dy)
      ..close();
    canvas.drawPath(
      redPath,
      Paint()
        ..color = const Color(0xFFFF334B)
        ..style = PaintingStyle.fill,
    );

    // 4. Yellow right tip
    final yellowPath = Path()
      ..moveTo(w * 0.65, h * 0.38)
      ..lineTo(rightTip.dx, rightTip.dy)
      ..lineTo(w * 0.65, h * 0.62)
      ..lineTo(centerPoint.dx, centerPoint.dy)
      ..close();
    canvas.drawPath(
      yellowPath,
      Paint()
        ..color = const Color(0xFFFFD200)
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official NPCI UPI Chevron Painter
class _UpiChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Green left chevron
    final greenPath = Path()
      ..moveTo(w * 0.06, h * 0.86)
      ..lineTo(w * 0.40, h * 0.14)
      ..lineTo(w * 0.52, h * 0.14)
      ..lineTo(w * 0.18, h * 0.86)
      ..close();
    canvas.drawPath(
      greenPath,
      Paint()
        ..color = const Color(0xFF00833E)
        ..style = PaintingStyle.fill,
    );

    // Orange right chevron
    final orangePath = Path()
      ..moveTo(w * 0.48, h * 0.86)
      ..lineTo(w * 0.82, h * 0.14)
      ..lineTo(w * 0.94, h * 0.14)
      ..lineTo(w * 0.60, h * 0.86)
      ..close();
    canvas.drawPath(
      orangePath,
      Paint()
        ..color = const Color(0xFFF37021)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official UPI Badge
class UpiLogoBadge extends StatelessWidget {
  const UpiLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1425),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: const Color(0xFF00833E).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(compact ? 13 : 16, compact ? 13 : 16),
            painter: _UpiChevronPainter(),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            'UPI',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              fontSize: compact ? 11 : 12.5,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Official Google 4-Color 'G' Painter
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = math.min(w, h) / 2;
    final strokeWidth = radius * 0.42;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Blue arc (right top to right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -math.pi / 4, math.pi / 2, false, paint);

    // Green arc (right bottom to bottom)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, math.pi / 4, math.pi / 2, false, paint);

    // Yellow arc (bottom to left top)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 3 * math.pi / 4, math.pi / 2, false, paint);

    // Red arc (left top to top)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 5 * math.pi / 4, math.pi / 2, false, paint);

    // Crossbar for G (Blue)
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTWH(
      center.dx,
      center.dy - strokeWidth / 2,
      radius,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official Google Pay Badge
class GPayLogoBadge extends StatelessWidget {
  const GPayLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: const Color(0xFF4285F4).withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(compact ? 13 : 15, compact ? 13 : 15),
            painter: _GoogleGPainter(),
          ),
          SizedBox(width: compact ? 3 : 5),
          Text(
            'Pay',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 12.5,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Official PhonePe Logo Badge
class PhonePeLogoBadge extends StatelessWidget {
  const PhonePeLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF5F259F),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x335F259F),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 13 : 15,
            height: compact ? 13 : 15,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Text(
              'पे',
              style: TextStyle(
                color: const Color(0xFF5F259F),
                fontWeight: FontWeight.w900,
                fontSize: compact ? 9.5 : 11,
                height: 1.0,
              ),
            ),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            'PhonePe',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 10.5 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Official Paytm Logo Badge
class PaytmLogoBadge extends StatelessWidget {
  const PaytmLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF002970),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: const Color(0xFF00BAF2).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'pay',
              style: GoogleFonts.poppins(
                color: const Color(0xFF00BAF2),
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11 : 12.5,
              ),
            ),
            TextSpan(
              text: 'tm',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11 : 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Official Visa Card Logo
class VisaLogoBadge extends StatelessWidget {
  const VisaLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1434CB),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        'VISA',
        style: GoogleFonts.roboto(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          fontSize: compact ? 11 : 13,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// Official Mastercard Logo
class MastercardLogoBadge extends StatelessWidget {
  const MastercardLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final circleSize = compact ? 11.0 : 13.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1917),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: circleSize * 1.6,
            height: circleSize,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFEB001B),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF79E1B).withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(
              'mastercard',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// RuPay Chevron Painter
class _RuPayChevronsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cyan chevron
    final cyan = Path()
      ..moveTo(w * 0.05, h * 0.85)
      ..lineTo(w * 0.45, h * 0.15)
      ..lineTo(w * 0.60, h * 0.15)
      ..lineTo(w * 0.20, h * 0.85)
      ..close();
    canvas.drawPath(
      cyan,
      Paint()
        ..color = const Color(0xFF00A3E0)
        ..style = PaintingStyle.fill,
    );

    // Orange chevron
    final orange = Path()
      ..moveTo(w * 0.45, h * 0.85)
      ..lineTo(w * 0.85, h * 0.15)
      ..lineTo(w * 1.00, h * 0.15)
      ..lineTo(w * 0.60, h * 0.85)
      ..close();
    canvas.drawPath(
      orange,
      Paint()
        ..color = const Color(0xFFF47B20)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official RuPay Card Logo
class RuPayLogoBadge extends StatelessWidget {
  const RuPayLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1E36),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: const Color(0xFF00A3E0).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RuPay',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              fontSize: compact ? 11 : 12.5,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(width: compact ? 3 : 4),
          CustomPaint(
            size: Size(compact ? 8 : 10, compact ? 10 : 12),
            painter: _RuPayChevronsPainter(),
          ),
        ],
      ),
    );
  }
}

/// American Express Logo Badge
class AmexLogoBadge extends StatelessWidget {
  const AmexLogoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF006FCF),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Text(
        'AMEX',
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: compact ? 10 : 11.5,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// NetBanking Badge
class NetBankingBadge extends StatelessWidget {
  const NetBankingBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: CrickXColors.graphiteElevated,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: CrickXColors.limeSpark.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_rounded,
            size: compact ? 12 : 14,
            color: CrickXColors.limeSpark,
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            'NetBanking',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10.5 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Google Play Balance / Redeem Code Badge
class PlayBalanceBadge extends StatelessWidget {
  const PlayBalanceBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF13201B),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GooglePlayLogo(size: compact ? 12 : 14),
          SizedBox(width: compact ? 4 : 5),
          Text(
            'Play Balance',
            style: GoogleFonts.poppins(
              color: const Color(0xFF86EFAC),
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10.5 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary row showing compact payment logos
class PaymentLogosStrip extends StatelessWidget {
  const PaymentLogosStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        UpiLogoBadge(compact: true),
        GPayLogoBadge(compact: true),
        PhonePeLogoBadge(compact: true),
        PaytmLogoBadge(compact: true),
        VisaLogoBadge(compact: true),
        MastercardLogoBadge(compact: true),
        RuPayLogoBadge(compact: true),
        NetBankingBadge(compact: true),
      ],
    );
  }
}
