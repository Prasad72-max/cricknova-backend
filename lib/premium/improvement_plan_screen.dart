import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/improvement_plan_service.dart';

const List<String> _eliteMotivationLines = [
  'Remember every person who said you would never get selected. Train until your name makes the list.',
  'They doubted your cricket. Good. Now give them a scorecard they cannot ignore.',
  'Selection is not luck. It is proof repeated quietly when nobody is clapping.',
  'Your excuse is not stronger than your dream unless you feed it daily.',
  'A bad session is not the end. Quitting after it is.',
  'When they say you are not ready, make your preparation louder than your reply.',
  'The player who corrects one mistake daily becomes dangerous in silence.',
  'Do not chase respect. Build skill so clean that respect has to follow.',
  'Every extra rep is a vote against the people who counted you out.',
  'The nets remember who showed up when motivation was missing.',
  'Your comeback starts in the session you almost skipped.',
  'Talent opens the gate. Discipline keeps you inside the team.',
  'If selection matters, your lazy days must become rare.',
  'Make your next video look like evidence, not hope.',
  'Train like the next trial is already watching.',
  'Pressure is not your enemy. Unpreparedness is.',
  'Do not ask for a chance with average habits.',
  'A clean technique is revenge without noise.',
  'They can ignore your talk. They cannot ignore wickets and runs.',
  'Your body wants comfort. Your future wants work.',
  'Small corrections today become big match moments tomorrow.',
  'Do not wait to feel elite. Behave elite first.',
  'Every ball is a chance to delete an old weakness.',
  'If you want a jersey, stop practicing like a visitor.',
  'The scoreboard exposes what training hides.',
  'Your dream needs sweat, not sympathy.',
  'One focused hour beats three lazy hours every time.',
  'Do not fear being behind. Fear staying the same.',
  'If nobody believes in you, your routine must.',
  'Turn insult into footwork, rejection into timing, doubt into pace.',
  'A selector needs one reason. Give them ten.',
  'You are not unlucky. You are unfinished. Fix the next detail.',
  'Champions do not avoid mistakes. They hunt them.',
  'A mistake found today is a wicket saved tomorrow.',
  'Your next level is hiding inside the drill you hate.',
  'Train so your old self cannot recognize your game.',
  'The player who records, reviews, and corrects becomes hard to beat.',
  'Do not be emotional about feedback. Be ruthless with improvement.',
  'Every missed selection is a message: sharpen again.',
  'Keep receipts of doubt. Pay them back with performance.',
  'Nobody can block a player who keeps upgrading.',
  'Your name will not appear by accident. Build the case.',
  'The gap between selected and rejected is often one corrected habit.',
  'You do not need perfect. You need better every week.',
  'If your dream is serious, your warm-up cannot be casual.',
  'Make discipline your loudest announcement.',
  'A weak day still counts if you complete the drill.',
  'You cannot control politics. You can control preparation.',
  'Let them talk. You fix your seam, swing, timing, and fitness.',
  'The next trial will not care about excuses.',
  'Your work rate must make your doubt uncomfortable.',
  'The player who learns fastest plays longest.',
  'Anger is useful only when it becomes repetition.',
  'Do not carry failure. Study it, then outgrow it.',
  'Your improvement plan is not decoration. It is your comeback map.',
  'Every day you delay, another player gets sharper.',
  'The ground rewards attendance before applause.',
  'You are one honest correction away from a different game.',
  'If you want pressure moments, earn them in practice.',
  'Your future team needs the version of you that does the boring work.',
  'When confidence drops, let your routine speak.',
  'A serious player does not need perfect weather.',
  'Your weakness is not shameful. Ignoring it is.',
  'Make your basics so strong that panic has no entry.',
  'The best reply to rejection is measurable progress.',
  'Do not train to look busy. Train to become undeniable.',
  'Your next spell or innings is being built right now.',
  'A player with clarity beats a player with excuses.',
  'If you want elite results, protect your practice time like a match.',
  'One mistake fixed can change a whole season.',
  'Nobody sees your shadow practice. Everyone sees your timing later.',
  'Your hunger must be visible in your footwork.',
  'The line between average and dangerous is daily correction.',
  'Do not let one bad match become your identity.',
  'Your ceiling rises when your honesty rises.',
  'Stop waiting for someone to discover you. Build something visible.',
  'Your drill today is your confidence tomorrow.',
  'If you cannot repeat it in practice, do not expect it in pressure.',
  'A clean action, a stable head, and a strong mind travel together.',
  'You are allowed to be tired. You are not allowed to drift.',
  'Every comeback begins with one disciplined session.',
  'The player who accepts correction early avoids regret later.',
  'Make the next coach say: this player has changed.',
  'Your mistake is not permanent unless your ego protects it.',
  'Do the drill until the error gets bored and leaves.',
  'Let your improvement be so clear that debate ends.',
  'The best players are not mistake-free. They are mistake-killers.',
  'If selection hurt you, use that pain with structure.',
  'Do not dream about big matches with small habits.',
  'Skill loves repetition. Confidence loves proof.',
  'Your phone can record excuses or evidence. Choose evidence.',
  'The next upload should embarrass your old technique.',
  'Every correction is a brick in your comeback.',
  'You do not need noise. You need numbers, clips, and consistency.',
  'Train with the seriousness of someone who wants the final over.',
  'A lazy session teaches your body the wrong story.',
  'Your competition is not sleeping on your dream.',
  'If they said no once, return so improved they hesitate next time.',
  'A real player gets sharper after being exposed.',
  'Your discipline should scare your excuses.',
  'Good players practice. Selected players correct.',
  'The mistake you fix now may be the reason you get picked.',
  'You cannot fake rhythm. You build it.',
  'Your plan is simple: find error, drill error, upload proof.',
  'When doubt gets loud, make your next rep cleaner.',
  'The game respects players who keep coming back smarter.',
  'Your best answer is not a caption. It is performance.',
  'Every day inside the max window matters. Do not waste the clock.',
  'Be patient with results, ruthless with habits.',
  'The trial starts long before the trial date.',
  'Make your preparation impossible to dismiss.',
  'One honest video can save months of blind practice.',
  'Your future self is begging you to finish today’s drill.',
  'If cricket is your dream, details are your duty.',
  'They may not select your old version. Build a version they cannot ignore.',
];

class ImprovementPlanScreen extends StatefulWidget {
  final bool embedded;

  const ImprovementPlanScreen({super.key, this.embedded = false});

  @override
  State<ImprovementPlanScreen> createState() => _ImprovementPlanScreenState();
}

class _ImprovementPlanScreenState extends State<ImprovementPlanScreen> {
  String _selectedDiscipline = 'batting';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final body = Stack(
      children: [
        const Positioned.fill(child: _ImprovementBackdrop()),
        SafeArea(
          child: user == null
              ? const Center(
                  child: Text(
                    'Please sign in again.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : FutureBuilder<List<ImprovementPlanEntry>>(
                  future: ImprovementPlanService.entriesForUser(user.uid),
                  builder: (context, snapshot) {
                    final entries =
                        snapshot.data ?? const <ImprovementPlanEntry>[];
                    ImprovementPlanEntry? entryFor(String discipline) {
                      for (final entry in entries) {
                        if (entry.discipline == discipline &&
                            !entry.completed) {
                          return entry;
                        }
                      }
                      return null;
                    }

                    List<ImprovementPlanEntry> fixedFor(String discipline) {
                      return entries
                          .where(
                            (entry) =>
                                entry.discipline == discipline &&
                                entry.completed,
                          )
                          .take(2)
                          .toList(growable: false);
                    }

                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        widget.embedded ? 18 : 12,
                        18,
                        28,
                      ),
                      children: [
                        if (!widget.embedded) ...[
                          const _ImprovementTopBar(),
                          const SizedBox(height: 28),
                        ],
                        _HeroCard(),
                        const SizedBox(height: 14),
                        const _MotivationFuelCard(),
                        const SizedBox(height: 18),
                        if (widget.embedded) ...[
                          _ImprovementTrackCard(
                            title: 'Batting Focus',
                            accent: const Color(0xFFFFD86B),
                            icon: Icons.sports_cricket_rounded,
                            entry: entryFor('batting'),
                            fixedEntries: fixedFor('batting'),
                          ),
                          const SizedBox(height: 16),
                          _ImprovementTrackCard(
                            title: 'Bowling Focus',
                            accent: const Color(0xFF7DD3FC),
                            icon: Icons.sports_baseball_rounded,
                            entry: entryFor('bowling'),
                            fixedEntries: fixedFor('bowling'),
                          ),
                        ] else ...[
                          _SkillTabsHeader(
                            selectedDiscipline: _selectedDiscipline,
                            onChanged: (discipline) {
                              setState(() => _selectedDiscipline = discipline);
                            },
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _selectedDiscipline == 'bowling'
                                ? _ImprovementTrackCard(
                                    key: const ValueKey('bowling-plan'),
                                    title: 'Bowling Focus',
                                    accent: const Color(0xFF7DD3FC),
                                    icon: Icons.sports_baseball_rounded,
                                    entry: entryFor('bowling'),
                                    fixedEntries: fixedFor('bowling'),
                                  )
                                : _ImprovementTrackCard(
                                    key: const ValueKey('batting-plan'),
                                    title: 'Batting Focus',
                                    accent: const Color(0xFFFFD86B),
                                    icon: Icons.sports_cricket_rounded,
                                    entry: entryFor('batting'),
                                    fixedEntries: fixedFor('batting'),
                                  ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(backgroundColor: const Color(0xFF020617), body: body);
  }
}

class _ImprovementBackdrop extends StatelessWidget {
  const _ImprovementBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ImprovementBackdropPainter(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF030718),
              Color(0xFF081427),
              Color(0xFF111C35),
              Color(0xFF040A18),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}

class _ImprovementBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pathPaint = Paint()
      ..color = const Color(0xFFFFD86B).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final path = Path()
      ..moveTo(-40, size.height * 0.82)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.96,
        size.width * 0.44,
        size.height * 0.66,
        size.width * 0.68,
        size.height * 0.76,
      )
      ..cubicTo(
        size.width * 0.86,
        size.height * 0.84,
        size.width * 1.02,
        size.height * 0.70,
        size.width + 50,
        size.height * 0.83,
      );
    canvas.drawPath(path, pathPaint);

    final glowPaint = Paint()
      ..color = const Color(0xFFFFD86B).withOpacity(0.06);
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.86),
      44,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.52, size.height * 0.76),
      78,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.52, size.height * 0.76),
      76,
      Paint()
        ..color = const Color(0xFFFFE7A0).withOpacity(0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ImprovementTopBar extends StatelessWidget {
  const _ImprovementTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: Colors.white,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF111827).withOpacity(0.78),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: const Color(0xFFFFD86B).withOpacity(0.28),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'CrickNova Elite',
            style: GoogleFonts.poppins(
              color: const Color(0xFFFFE7A0),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const _ProgressDots(),
      ],
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 260 + index * 80),
          width: index == 2 ? 9 : 7,
          height: index == 2 ? 9 : 7,
          margin: const EdgeInsets.only(left: 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (index == 2 ? const Color(0xFFFFD86B) : Colors.white)
                .withOpacity(index == 2 ? 0.95 : 0.30),
          ),
        );
      }),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE08A), Color(0xFFB8860B)],
              ),
              border: Border.all(color: const Color(0xFFFFE7A0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD86B).withOpacity(0.22),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.route_rounded,
              color: Color(0xFF111827),
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Your 35-Day Fix Path',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 28,
              height: 1.12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'No player is 100% perfect. Rohit, Sachin, and every elite cricketer keep finding small errors, fixing them, and coming back sharper.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.78),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotivationFuelCard extends StatelessWidget {
  const _MotivationFuelCard();

  String get _line {
    final now = DateTime.now();
    final index =
        (now.microsecondsSinceEpoch + now.day) % _eliteMotivationLines.length;
    return _eliteMotivationLines[index];
  }

  void _showRandomLine(BuildContext context) {
    final random = math.Random();
    var currentIndex = random.nextInt(_eliteMotivationLines.length);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF080D18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final line = _eliteMotivationLines[currentIndex];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          color: Color(0xFFFFD86B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Random Elite Motivation',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Container(
                        key: ValueKey(currentIndex),
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF111827).withOpacity(0.92),
                              const Color(0xFF1C263A).withOpacity(0.84),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFFFD86B).withOpacity(0.24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              color: Color(0xFFFFD86B),
                              size: 30,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              line,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.42,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          setSheetState(() {
                            var nextIndex = random.nextInt(
                              _eliteMotivationLines.length,
                            );
                            if (_eliteMotivationLines.length > 1) {
                              while (nextIndex == currentIndex) {
                                nextIndex = random.nextInt(
                                  _eliteMotivationLines.length,
                                );
                              }
                            }
                            currentIndex = nextIndex;
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD86B),
                          foregroundColor: const Color(0xFF111827),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: Text(
                          'Next fire line',
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_eliteMotivationLines.length} lines inside. One at a time.',
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF111827).withOpacity(0.88),
                const Color(0xFF1C263A).withOpacity(0.78),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFFFD86B).withOpacity(0.26),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD86B).withOpacity(0.14),
                  border: Border.all(
                    color: const Color(0xFFFFD86B).withOpacity(0.30),
                  ),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFFD86B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Remember who doubted you',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFFFE7A0),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Shuffle motivation',
                          onPressed: () {
                            _showRandomLine(context);
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(
                              0xFFFFD86B,
                            ).withOpacity(0.12),
                            minimumSize: const Size(34, 34),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: const Color(
                                  0xFFFFD86B,
                                ).withOpacity(0.26),
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.shuffle_rounded,
                            color: Color(0xFFFFD86B),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _line,
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the side icon to shuffle',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFFFD86B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillTabsHeader extends StatelessWidget {
  final String selectedDiscipline;
  final ValueChanged<String> onChanged;

  const _SkillTabsHeader({
    required this.selectedDiscipline,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SkillTabChip(
            label: 'Batting',
            icon: Icons.sports_cricket_rounded,
            accent: const Color(0xFFFFD86B),
            selected: selectedDiscipline == 'batting',
            onTap: () => onChanged('batting'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SkillTabChip(
            label: 'Bowling',
            icon: Icons.sports_baseball_rounded,
            accent: const Color(0xFF7DD3FC),
            selected: selectedDiscipline == 'bowling',
            onTap: () => onChanged('bowling'),
          ),
        ),
      ],
    );
  }
}

class _SkillTabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _SkillTabChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 46,
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.16)
                : const Color(0xFF111827).withOpacity(0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? accent.withOpacity(0.72)
                  : accent.withOpacity(0.34),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: selected ? accent : Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImprovementTrackCard extends StatelessWidget {
  final String title;
  final Color accent;
  final IconData icon;
  final ImprovementPlanEntry? entry;
  final List<ImprovementPlanEntry> fixedEntries;

  const _ImprovementTrackCard({
    super.key,
    required this.title,
    required this.accent,
    required this.icon,
    required this.entry,
    required this.fixedEntries,
  });

  @override
  Widget build(BuildContext context) {
    final activeEntry = entry;
    final completed = activeEntry?.completed == true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF121826).withOpacity(0.94),
            const Color(0xFF1C263A).withOpacity(0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: completed
              ? const Color(0xFF22C55E).withOpacity(0.55)
              : accent.withOpacity(0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.40)),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(completed: completed, hasPlan: activeEntry != null),
            ],
          ),
          const SizedBox(height: 13),
          if (activeEntry == null)
            _EmptyState(accent: accent)
          else ...[
            Text(
              activeEntry.mistake,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _MaxFixSummary(entry: activeEntry, accent: accent),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.calendar_month_rounded,
                  label: '${activeEntry.minDays} days min',
                  color: accent,
                ),
                _MetricChip(
                  icon: Icons.timer_outlined,
                  label: '${activeEntry.maxDays} days max',
                  color: const Color(0xFFF59E0B),
                ),
                _MetricChip(
                  icon: Icons.replay_rounded,
                  label: '${activeEntry.attempts} checks',
                  color: completed ? const Color(0xFF22C55E) : accent,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DeadlineNotice(entry: activeEntry),
            const SizedBox(height: 14),
            _PlanPeriodText(entry: activeEntry, accent: accent),
            const SizedBox(height: 14),
            _DailyPlanPreview(
              entry: activeEntry,
              accent: accent,
              completed: completed,
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < activeEntry.drills.take(2).length; i++) ...[
              _DrillTile(
                index: i + 1,
                text: activeEntry.drills[i],
                accent: accent,
              ),
              if (i == 0) const SizedBox(height: 8),
            ],
          ],
          if (fixedEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            _FixedMistakesList(entries: fixedEntries),
          ],
        ],
      ),
    );
  }
}

class _PlanPeriodText extends StatelessWidget {
  final ImprovementPlanEntry entry;
  final Color accent;

  const _PlanPeriodText({required this.entry, required this.accent});

  String _fmt(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final end = entry.createdAt.add(Duration(days: entry.maxDays));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Text(
        'Real plan period: ${_fmt(entry.createdAt)} - ${_fmt(end)}',
        style: GoogleFonts.poppins(
          color: Colors.white70,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MaxFixSummary extends StatelessWidget {
  final ImprovementPlanEntry entry;
  final Color accent;

  const _MaxFixSummary({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    final primaryDrill = entry.drills.isNotEmpty
        ? entry.drills.first
        : 'Repeat the correction drill with clean video feedback.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF59E0B).withOpacity(0.16),
              border: Border.all(
                color: const Color(0xFFF59E0B).withOpacity(0.34),
              ),
            ),
            child: Text(
              '${entry.maxDays}',
              style: GoogleFonts.orbitron(
                color: const Color(0xFFFFD86B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Max days to fix: ${entry.maxDays}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFFE7A0),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Main drill for this window: $primaryDrill',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 11.6,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class _FixedMistakesList extends StatelessWidget {
  final List<ImprovementPlanEntry> entries;

  const _FixedMistakesList({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withOpacity(0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recently fixed',
            style: GoogleFonts.poppins(
              color: const Color(0xFF86EFAC),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF22C55E),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.mistake,
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 11.8,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
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

class _DeadlineNotice extends StatelessWidget {
  final ImprovementPlanEntry entry;

  const _DeadlineNotice({required this.entry});

  @override
  Widget build(BuildContext context) {
    final deadline = entry.createdAt.add(Duration(days: entry.maxDays));
    final remaining = deadline.difference(DateTime.now()).inDays;
    final overdue = remaining < 0;
    final color = overdue ? const Color(0xFFE34234) : const Color(0xFFFFD86B);
    final text = overdue
        ? 'Max window crossed. Upload a fresh ${entry.discipline} clip to check if it is fixed.'
        : '$remaining day${remaining == 1 ? '' : 's'} left before max fix window.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Icon(
            overdue
                ? Icons.notification_important_rounded
                : Icons.alarm_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool completed;
  final bool hasPlan;

  const _StatusPill({required this.completed, required this.hasPlan});

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? const Color(0xFF22C55E)
        : hasPlan
        ? const Color(0xFFF59E0B)
        : Colors.white38;
    final label = completed
        ? 'FIXED'
        : hasPlan
        ? 'ACTIVE'
        : 'WAITING';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : Icons.bolt_rounded,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.orbitron(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color accent;

  const _EmptyState({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: accent.withOpacity(0.85),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No mistake saved yet. Run Mistake Detection on this skill.',
              style: GoogleFonts.poppins(
                color: Colors.white60,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyPlanPreview extends StatelessWidget {
  final ImprovementPlanEntry entry;
  final Color accent;
  final bool completed;

  const _DailyPlanPreview({
    required this.entry,
    required this.accent,
    required this.completed,
  });

  void _showAllDays(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF080D18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Full ${entry.maxDays}-Day Plan',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: entry.maxDays,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final day = index + 1;
                      return _DayTile(
                        day: day,
                        text: _dayText(day),
                        accent: accent,
                        completed: completed,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _dayText(int day) {
    final drill = entry.drills.isEmpty
        ? 'Repeat the correction drill with clean video feedback.'
        : entry.drills[(day - 1) % entry.drills.length];
    if (day % 7 == 0) {
      return 'Review video, compare the mistake, then adjust the next week.';
    }
    return drill;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(entry.maxDays < 4 ? entry.maxDays : 4, (
            index,
          ) {
            final day = index + 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
                child: _DayTile(
                  day: day,
                  text: _dayText(day),
                  accent: accent,
                  completed: completed,
                  compact: true,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => _showAllDays(context),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              backgroundColor: accent.withOpacity(0.10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: accent.withOpacity(0.24)),
              ),
            ),
            icon: const Icon(Icons.visibility_rounded, size: 16),
            label: Text(
              'See all ${entry.maxDays} days',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  final int day;
  final String text;
  final Color accent;
  final bool completed;
  final bool compact;

  const _DayTile({
    required this.day,
    required this.text,
    required this.accent,
    required this.completed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: compact
          ? const BoxConstraints(minHeight: 72)
          : const BoxConstraints(),
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: completed
              ? const Color(0xFF22C55E).withOpacity(0.42)
              : accent.withOpacity(0.22),
        ),
      ),
      child: compact
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  completed ? Icons.check_circle_rounded : Icons.flag_rounded,
                  color: completed ? const Color(0xFF22C55E) : accent,
                  size: 18,
                ),
                const SizedBox(height: 6),
                Text(
                  'Day $day',
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.12),
                    border: Border.all(color: accent.withOpacity(0.32)),
                  ),
                  child: Text(
                    '$day',
                    style: GoogleFonts.orbitron(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day $day',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text,
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 11.6,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
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

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrillTile extends StatelessWidget {
  final int index;
  final String text;
  final Color accent;

  const _DrillTile({
    required this.index,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.18),
              border: Border.all(color: accent.withOpacity(0.42)),
            ),
            child: Text(
              '$index',
              style: GoogleFonts.orbitron(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 12.2,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
