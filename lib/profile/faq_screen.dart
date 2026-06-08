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
  static const Color _gold = Color(0xFFFFD86B);

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
          'If something feels off, contact support directly and include your issue clearly so support can help you faster.',
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _FaqBackButton(onTap: () => Navigator.of(context).pop()),
        ),
        title: Text(
          'FAQ',
          style: GoogleFonts.playfairDisplay(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: _bg)),
          SafeArea(
            top: false,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Text(
                  'Quick answers for CrickNova AI features, access, privacy, and support.',
                  style: GoogleFonts.montserrat(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: _glass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.montserrat(color: Colors.white),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      hintText: 'Search categories',
                      hintStyle: GoogleFonts.montserrat(
                        color: _slate.withValues(alpha: 0.75),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _gold,
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
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      'No matching FAQ found. Use support for a direct answer.',
                      style: GoogleFonts.montserrat(
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
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Support',
                        style: GoogleFonts.playfairDisplay(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Send a clear issue description and support will help you directly.',
                        style: GoogleFonts.montserrat(
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
                            backgroundColor: _gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Contact Support',
                            style: GoogleFonts.montserrat(
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
              ? _FaqScreenState._gold.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.05,
        ),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: _FaqScreenState._gold.withValues(alpha: 0.14),
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
                    color: expanded ? _FaqScreenState._gold : Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.title,
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.remove_rounded : Icons.add_rounded,
                    color: expanded ? _FaqScreenState._gold : Colors.white70,
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
                    color: _FaqScreenState._gold.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  item.answer,
                  style: GoogleFonts.montserrat(
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

class _FaqBackButton extends StatelessWidget {
  const _FaqBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF1A1A1A),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.22),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
    );
  }
}
