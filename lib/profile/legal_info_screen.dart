import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum LegalDocType { privacy, terms, about }

class DocSection {
  final String heading;
  final String body;

  const DocSection({required this.heading, required this.body});
}

class LegalDocument {
  final LegalDocType type;
  final String title;
  final List<DocSection> sections;

  const LegalDocument({
    required this.type,
    required this.title,
    required this.sections,
  });

  factory LegalDocument.privacy() {
    return const LegalDocument(
      type: LegalDocType.privacy,
      title: "Privacy Policy",
      sections: [
        DocSection(
          heading: "1.0 Overview",
          body: "CrickNova AI respects your game and your privacy.",
        ),
        DocSection(
          heading: "1.1 Camera Access",
          body:
              "We use your camera only to analyze your cricket sessions and track performance.",
        ),
        DocSection(
          heading: "1.2 Data Security",
          body:
              "Your videos are processed locally or on secure servers and are never shared with third parties for ads.",
        ),
        DocSection(
          heading: "1.3 Age",
          body: "Users under 13 must use the app under parental supervision.",
        ),
        DocSection(
          heading: "1.4 Payments",
          body:
              "All transactions are handled by secure, encrypted payment partners.",
        ),
      ],
    );
  }

  factory LegalDocument.terms() {
    return const LegalDocument(
      type: LegalDocType.terms,
      title: "Terms and Conditions",
      sections: [
        DocSection(
          heading: "2.0 Agreement",
          body: "By using CrickNova, you agree:",
        ),
        DocSection(
          heading: "2.1 Elite Access",
          body: "Subscriptions are for single users only.",
        ),
        DocSection(
          heading: "2.2 Physical Safety",
          body:
              "Cricket is a physical sport. CrickNova is not liable for any injuries sustained during practice. Always play in a safe environment.",
        ),
        DocSection(
          heading: "2.3 Usage",
          body:
              "Any attempt to reverse-engineer the AI \"CrickNova Call\" will result in account termination.",
        ),
      ],
    );
  }

  factory LegalDocument.about() {
    return const LegalDocument(
      type: LegalDocType.about,
      title: "About CrickNova",
      sections: [
        DocSection(
          heading: "3.0 Breaking Barriers",
          body: "CrickNova AI: Breaking Barriers.",
        ),
        DocSection(
          heading: "3.1 Brand Story",
          body:
              "Born from a passion for the streets of India, CrickNova brings professional DRS-style technology to every gully, club, and stadium. Our mission is to make elite coaching affordable and accessible to every dreamer with a bat or a ball.",
        ),
        DocSection(heading: "3.2 Founder", body: "Founder: Prasad & Team."),
      ],
    );
  }
}

class LegalInfoScreen extends StatefulWidget {
  final LegalDocument document;

  const LegalInfoScreen({super.key, required this.document});

  @override
  State<LegalInfoScreen> createState() => _LegalInfoScreenState();
}

class _LegalInfoScreenState extends State<LegalInfoScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0);
  late final List<GlobalKey> _sectionKeys;
  String _query = "";

  @override
  void initState() {
    super.initState();
    _sectionKeys = List.generate(
      widget.document.sections.length,
      (_) => GlobalKey(),
    );
    _scrollController.addListener(_updateProgress);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateProgress);
    _scrollController.dispose();
    _scrollProgress.dispose();
    super.dispose();
  }

  void _updateProgress() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final progress = max <= 0
        ? 0.0
        : (_scrollController.offset / max).clamp(0.0, 1.0);
    _scrollProgress.value = progress;
  }

  Future<void> _openSearch() async {
    final controller = TextEditingController(text: _query);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            "Search",
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: GoogleFonts.montserrat(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search keywords (e.g., Refund, Safety)",
              hintStyle: GoogleFonts.montserrat(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD86B),
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Find"),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final query = result.trim();
    if (!mounted) return;
    setState(() => _query = query);

    if (query.isEmpty) return;
    final lower = query.toLowerCase();
    final index = widget.document.sections.indexWhere(
      (section) =>
          section.heading.toLowerCase().contains(lower) ||
          section.body.toLowerCase().contains(lower),
    );

    if (index == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No results found."),
          backgroundColor: Color(0xFF0B1220),
        ),
      );
      return;
    }

    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  TextSpan _highlightedText(String text, TextStyle style) {
    if (_query.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final lower = text.toLowerCase();
    final query = _query.toLowerCase();
    if (!lower.contains(query)) {
      return TextSpan(text: text, style: style);
    }

    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(query, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: style.copyWith(
            color: const Color(0xFFFFD86B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + query.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final isAbout = doc.type == LegalDocType.about;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          const _LogoWatermark(),
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                toolbarHeight: 64,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _GoldBackButton(
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                title: Text(
                  doc.title,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search, color: Color(0xFFFFD86B)),
                  ),
                ],
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollProgress,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 2.5,
                        color: const Color(0xFFFFD86B),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                      );
                    },
                  ),
                ),
              ),
              if (isAbout) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _AboutHero(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      "\"Empowering every gully cricketer with the power of AI.\"",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        color: const Color(0xFFFFE7A0),
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: _TimelineCard(),
                  ),
                ),
              ],
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + bottomInset),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final section = doc.sections[index];
                    return _FadeInSection(
                      delay: Duration(milliseconds: 120 * index),
                      child: _SectionCard(
                        key: _sectionKeys[index],
                        heading: section.heading,
                        body: section.body,
                        headingSpan: _highlightedText(
                          section.heading,
                          GoogleFonts.playfairDisplay(
                            color: const Color(0xFFFFD86B),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        bodySpan: _highlightedText(
                          section.body,
                          GoogleFonts.montserrat(
                            color: Colors.white70,
                            fontSize: 13.5,
                            height: 1.6,
                          ),
                        ),
                      ),
                    );
                  }, childCount: doc.sections.length),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoldBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GoldBackButton({required this.onTap});

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
            border: Border.all(color: const Color(0xFFFFD86B), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD86B).withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back, color: Color(0xFFFFD86B)),
        ),
      ),
    );
  }
}

class _LogoWatermark extends StatelessWidget {
  const _LogoWatermark();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.08,
          child: Center(
            child: Transform.rotate(
              angle: -0.35,
              child: Text(
                "CRICKNOVA",
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 80,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0B1220),
                  const Color(0xFF1E293B).withValues(alpha: 0.9),
                  const Color(0xFF0F172A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Opacity(
                opacity: 0.45,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0xFF0EA5E9), Colors.transparent],
                      radius: 1.2,
                      center: Alignment(-0.2, -0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: Text(
              "CrickNova Arena",
              style: GoogleFonts.playfairDisplay(
                color: const Color(0xFFFFE7A0),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: Icon(
              Icons.stadium_outlined,
              color: Colors.white.withValues(alpha: 0.6),
              size: 44,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final List<_TimelineItem> _items = const [
    _TimelineItem("Idea Spark", "Local nets insight"),
    _TimelineItem("Prototype", "First DRS-style demo"),
    _TimelineItem("CrickNova Call", "AI decision engine"),
    _TimelineItem("Elite Hub", "Personalized growth"),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Founding Story",
            style: GoogleFonts.playfairDisplay(
              color: const Color(0xFFFFD86B),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(
            _items.length,
            (index) => _TimelineRow(
              item: _items[index],
              isLast: index == _items.length - 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _TimelineItem item;
  final bool isLast;

  const _TimelineRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFD86B),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 26,
                color: Colors.white.withValues(alpha: 0.18),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.montserrat(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: GoogleFonts.montserrat(
                    color: Colors.white70,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineItem {
  final String title;
  final String subtitle;

  const _TimelineItem(this.title, this.subtitle);
}

class _SectionCard extends StatelessWidget {
  final String heading;
  final String body;
  final TextSpan headingSpan;
  final TextSpan bodySpan;

  const _SectionCard({
    super.key,
    required this.heading,
    required this.body,
    required this.headingSpan,
    required this.bodySpan,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFD86B).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(text: headingSpan),
                const SizedBox(height: 8),
                RichText(text: bodySpan),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeInSection extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeInSection({required this.child, required this.delay});

  @override
  State<_FadeInSection> createState() => _FadeInSectionState();
}

class _FadeInSectionState extends State<_FadeInSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(_opacity);
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
