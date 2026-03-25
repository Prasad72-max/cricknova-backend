import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedTitles = <String>{};

  static const Color _bg = Color(0xFF050505);
  static const Color _slate = Color(0xFFA0A0A0);
  static const Color _glass = Color(0x14FFFFFF);
  static const Color _electricBlue = Color(0xFF2C8DFF);

  final List<_FaqCategory> _items = const [
    _FaqCategory(
      title: 'AI Precision',
      icon: Icons.blur_on_outlined,
      answer:
          'CrickNova uses motion analysis and structured video cues to keep feedback consistent, fast, and practical for real training sessions.',
    ),
    _FaqCategory(
      title: 'Subscription (Ultra)',
      icon: Icons.diamond_outlined,
      answer:
          'Ultra unlocks the premium workflow: deeper analysis, faster processing, richer AI feedback, and the most advanced cricket insights in the app.',
    ),
    _FaqCategory(
      title: 'Data Privacy',
      icon: Icons.lock_outline,
      answer:
          'Your account and training data stay tied to your profile, and the app only uses the information needed to deliver analysis and support.',
    ),
    _FaqCategory(
      title: 'Device Compatibility',
      icon: Icons.devices_outlined,
      answer:
          'CrickNova is designed for modern mobile devices and performs best when the app is updated and videos are recorded clearly in supported formats.',
    ),
    _FaqCategory(
      title: 'Support',
      icon: Icons.headset_mic_outlined,
      answer:
          'If something feels off, contact support directly and include your issue clearly so the team can help you faster.',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _contactSupport() async {
    final emailUri = Uri.parse(
      'mailto:urmiladukare0@gmail.com'
      '?subject=${Uri.encodeComponent('CrickNova Support')}',
    );
    if (!await canLaunchUrl(emailUri)) return;
    await launchUrl(emailUri);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _items.where((item) {
      if (query.isEmpty) return true;
      return item.title.toLowerCase().contains(query) ||
          item.answer.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'FAQ',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FaqGrainPainter(),
            ),
          ),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                Text(
                  'Elegant answers for the modern cricketer.',
                  style: GoogleFonts.inter(
                    color: _slate,
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: _glass,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.inter(color: Colors.white),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      hintText: 'Search categories',
                      hintStyle: GoogleFonts.inter(
                        color: _slate.withValues(alpha: 0.75),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ...filtered.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FaqAccordionTile(
                      item: item,
                      expanded: _expandedTitles.contains(item.title),
                      onToggle: () {
                        setState(() {
                          if (_expandedTitles.contains(item.title)) {
                            _expandedTitles.remove(item.title);
                          } else {
                            _expandedTitles.add(item.title);
                          }
                        });
                      },
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _glass,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Text(
                      'No matching FAQ found. Use support for a direct answer.',
                      style: GoogleFonts.inter(
                        color: _slate,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _glass,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Support',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Curated with precision for the next generation of cricketers.',
                        style: GoogleFonts.inter(
                          color: _slate,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _contactSupport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            'Contact Support',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _FaqAccordionTile extends StatelessWidget {
  const _FaqAccordionTile({
    required this.item,
    required this.expanded,
    required this.onToggle,
  });

  final _FaqCategory item;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _FaqScreenState._glass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: expanded
              ? _FaqScreenState._electricBlue.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.05,
        ),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: _FaqScreenState._electricBlue.withValues(alpha: 0.14),
                  blurRadius: 22,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.remove_rounded : Icons.add_rounded,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: expanded ? 1 : 0,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _FaqScreenState._electricBlue.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  item.answer,
                  style: GoogleFonts.inter(
                    color: _FaqScreenState._slate,
                    fontSize: 13.5,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqCategory {
  const _FaqCategory({
    required this.title,
    required this.icon,
    required this.answer,
  });

  final String title;
  final IconData icon;
  final String answer;
}

class _FaqGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: 0.018);
    for (int i = 0; i < 260; i++) {
      final x = ((((i * 37) % 100) / 100) * size.width);
      final y = ((((i * 19) % 100) / 100) * size.height);
      final r = i.isEven ? 0.75 : 0.45;
      canvas.drawCircle(Offset(x, y), r, dot);
    }

    final fade = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF081019).withValues(alpha: 0.0),
          const Color(0xFF081019).withValues(alpha: 0.35),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fade);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
