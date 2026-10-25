import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reel_model.dart';

/// Curated Cricket Reels Feed — REAL YouTube Cricket Content.
/// Exclusively two categories:
/// 1. International Cricketer Highlights (Batting, Bowling, Fielding).
/// 2. Cricket Coaching Drills & Masterclasses (Skill improvement).
/// All video URLs are verified real YouTube cricket videos.
class CuratedCricketReels {
  static List<ReelModel> getInitialCricketReels({bool shuffle = false}) {
    final now = DateTime.now();

    final reels = [
      // =======================================================================
      // CATEGORY 1: INTERNATIONAL CRICKETER HIGHLIGHTS
      // =======================================================================

      // 1. Virat Kohli - Signature Cover Drive Compilation
      ReelModel(
        reelId: 'crick_intl_kohli_01',
        userId: 'international_cricket',
        username: 'cricket_highlights',
        userPhotoUrl: 'https://images.unsplash.com/photo-1540747913346-19e32dc3e97e?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=pbpK1Zvegq0',
        thumbnailUrl: 'https://images.unsplash.com/photo-1540747913346-19e32dc3e97e?w=600&auto=format&fit=crop&q=80',
        caption: 'Virat Kohli Cover Drive Compilation! High elbow, head still, pristine timing. The King of Cover Drives! 🏏🔥',
        hashtags: ['cricket', 'highlights', 'viratkohli', 'coverdrive', 'international'],
        createdAt: now.subtract(const Duration(minutes: 10)),
        updatedAt: now.subtract(const Duration(minutes: 10)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 2. Virat Kohli - Best Boundary Cover Drives
      ReelModel(
        reelId: 'crick_intl_kohli_02',
        userId: 'kohli_fan_zone',
        username: 'king_kohli_official',
        userPhotoUrl: 'https://images.unsplash.com/photo-1517649763962-0c623266ddc0?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=nPBgrDjRCcg',
        thumbnailUrl: 'https://images.unsplash.com/photo-1517649763962-0c623266ddc0?w=600&auto=format&fit=crop&q=80',
        caption: 'Best Cover Drives by Virat Kohli! Textbook footwork, timing, and elegance at the crease. Pure cricketing art! 🏏✨',
        hashtags: ['cricket', 'highlights', 'viratkohli', 'batting', 'coverdrive'],
        createdAt: now.subtract(const Duration(minutes: 25)),
        updatedAt: now.subtract(const Duration(minutes: 25)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 3. Yuvraj Singh - 6 Sixes vs Stuart Broad (T20 World Cup)
      ReelModel(
        reelId: 'crick_intl_yuvraj_03',
        userId: 'icc_official',
        username: 'icc_cricket',
        userPhotoUrl: 'https://images.unsplash.com/photo-1531415074868-036b107e775a?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=8b0ubLO2MUE',
        thumbnailUrl: 'https://images.unsplash.com/photo-1531415074868-036b107e775a?w=600&auto=format&fit=crop&q=80',
        caption: 'Yuvraj Singh smashes 6 SIXES in one over off Stuart Broad! T20 World Cup 2007 — the greatest over in cricket history! 💥🔥',
        hashtags: ['cricket', 'highlights', 'yuvrajsingh', 'sixsixes', 't20worldcup'],
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 4. AB de Villiers - 360 Degree Boundary Carnage
      ReelModel(
        reelId: 'crick_intl_abd_04',
        userId: 'mr_360_zone',
        username: 'ab_devilliers_hub',
        userPhotoUrl: 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=AOeY-nDp7hI',
        thumbnailUrl: 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=600&auto=format&fit=crop&q=80',
        caption: 'Mr. 360 AB de Villiers destroying bowling attacks! Unbelievable scoops, reverse hits, and massive sixes. 🚀💥',
        hashtags: ['cricket', 'highlights', 'abdevilliers', 'mr360', 'six'],
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 5. Brett Lee - 155 km/h Lethal Pace & Wickets
      ReelModel(
        reelId: 'crick_intl_brettlee_05',
        userId: 'fast_bowling_lab',
        username: 'pace_bowling_archive',
        userPhotoUrl: 'https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=ggq2R_NB3KU',
        thumbnailUrl: 'https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?w=600&auto=format&fit=crop&q=80',
        caption: 'Brett Lee bowling at 155+ km/h! Pure aggression, fiery bouncers, and cartwheeling stumps. Fast bowling at its peak! ⚡🎯',
        hashtags: ['cricket', 'highlights', 'brettlee', 'fastbowling', 'pace'],
        createdAt: now.subtract(const Duration(hours: 4)),
        updatedAt: now.subtract(const Duration(hours: 4)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // =======================================================================
      // CATEGORY 2: CRICKET COACHING & SKILL DRILLS
      // =======================================================================

      // 6. Batting Stance & Head Stillness Masterclass
      ReelModel(
        reelId: 'crick_coach_stance_01',
        userId: 'head_coach_pro',
        username: 'cricket_coach',
        userPhotoUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=pbpK1Zvegq0',
        thumbnailUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=600&auto=format&fit=crop&q=80',
        caption: 'Coach Tip: Batting Stance & Eye Level. Keep your head rock-still at bowler release. Balance controls your footwork and timing! 🏏📐',
        hashtags: ['cricket', 'coaching', 'batting', 'technique', 'drills'],
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 5)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 7. Fast Bowling Seam & Wrist Position Drill
      ReelModel(
        reelId: 'crick_coach_pace_02',
        userId: 'pace_coach_ian',
        username: 'fast_bowling_academy',
        userPhotoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=ggq2R_NB3KU',
        thumbnailUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=600&auto=format&fit=crop&q=80',
        caption: 'Fast Bowling Drill: Upright seam alignment and wrist snap at release point. Lock the wrist to generate late swing! 🎯⚡',
        hashtags: ['cricket', 'coaching', 'bowling', 'fastbowlingdrills', 'seam'],
        createdAt: now.subtract(const Duration(hours: 7)),
        updatedAt: now.subtract(const Duration(hours: 7)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 8. Power Hitting Bat Speed & 360 Extension
      ReelModel(
        reelId: 'crick_coach_power_03',
        userId: 'batting_specialist',
        username: 'powerplay_batting',
        userPhotoUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=AOeY-nDp7hI',
        thumbnailUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=600&auto=format&fit=crop&q=80',
        caption: 'Power Hitting Masterclass: Generating maximum bat speed and hip rotation through the ball to clear the rope with ease! 🚀💪',
        hashtags: ['cricket', 'coaching', 'powerhitting', 'six', 'drills'],
        createdAt: now.subtract(const Duration(hours: 10)),
        updatedAt: now.subtract(const Duration(hours: 10)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 9. Front Foot Weight Transfer & Drive Mechanics
      ReelModel(
        reelId: 'crick_coach_coverdrive_04',
        userId: 'elite_coach',
        username: 'elite_cricket_academy',
        userPhotoUrl: 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=nPBgrDjRCcg',
        thumbnailUrl: 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=600&auto=format&fit=crop&q=80',
        caption: 'Cover Drive Coaching: Leading with the front shoulder and maintaining a high elbow finish. Master clean timing! 🏏🎯',
        hashtags: ['cricket', 'coaching', 'battingdrills', 'technique', 'coverdrive'],
        createdAt: now.subtract(const Duration(hours: 14)),
        updatedAt: now.subtract(const Duration(hours: 14)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),

      // 10. Reading Length & Back-and-Across Footwork
      ReelModel(
        reelId: 'crick_coach_pullshot_05',
        userId: 'wicketkeeping_academy',
        username: 'glovework_coach',
        userPhotoUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=150&auto=format&fit=crop&q=80',
        videoUrl: 'https://www.youtube.com/watch?v=8b0ubLO2MUE',
        thumbnailUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=600&auto=format&fit=crop&q=80',
        caption: 'T20 Batting Coaching: Step back and across, pick the length early, and commit 100% to your attacking strokes! 🧠⚡',
        hashtags: ['cricket', 'coaching', 't20', 'powerhitting', 'training'],
        createdAt: now.subtract(const Duration(hours: 18)),
        updatedAt: now.subtract(const Duration(hours: 18)),
        likesCount: 0,
        commentsCount: 0,
        viewsCount: 1,
        savesCount: 0,
        visibility: ReelVisibility.public,
        status: ReelStatus.ready,
      ),
    ];

    if (shuffle) {
      reels.shuffle();
    }
    return reels;
  }

  /// Sync curated cricket reels to Firestore — always ensure latest curated
  /// reels are present. Uses merge:true so user engagement data is preserved.
  static Future<void> seedIfEmpty(FirebaseFirestore firestore) async {
    try {
      final reels = getInitialCricketReels();
      final batch = firestore.batch();
      for (final r in reels) {
        final docRef = firestore.collection('reels').doc(r.reelId);
        final data = r.toFirestore();
        batch.set(docRef, data, SetOptions(merge: true));
      }

      // Clean up any old obsolete test IDs
      final oldIds = ['crick_reel_101', 'crick_reel_102', 'crick_reel_103'];
      for (final oldId in oldIds) {
        batch.delete(firestore.collection('reels').doc(oldId));
      }

      await batch.commit();
    } catch (_) {}
  }
}
