import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/reel_model.dart';
import 'curated_cricket_reels.dart';

class ReelService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CollectionReference _reelsRef = _firestore.collection('reels');
  static final CollectionReference _reportsRef = _firestore.collection('reel_reports');

  // In-memory view deduplication per session to prevent spamming viewsCount
  static final Set<String> _viewedReelsThisSession = <String>{};

  static String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // =========================================================================
  // 1. REEL CREATION & STATUS
  // =========================================================================

  /// Creates a new Reel document in Firestore.
  static Future<void> createReel(ReelModel reel) async {
    await _reelsRef.doc(reel.reelId).set(reel.toFirestore());
  }

  /// Updates status and optional AI analysis of a Reel.
  static Future<void> updateReelStatus({
    required String reelId,
    required ReelStatus status,
    ReelAiAnalysis? aiAnalysis,
  }) async {
    final updateData = <String, dynamic>{
      'status': status.toValue(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (aiAnalysis != null) {
      updateData['aiAnalysis'] = aiAnalysis.toMap();
    }
    await _reelsRef.doc(reelId).update(updateData);
  }

  /// Updates Reel caption or visibility (by creator).
  static Future<void> updateReelDetails({
    required String reelId,
    String? caption,
    ReelVisibility? visibility,
  }) async {
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (caption != null) updateData['caption'] = caption.trim();
    if (visibility != null) updateData['visibility'] = visibility.toValue();

    await _reelsRef.doc(reelId).update(updateData);
  }

  // =========================================================================
  // 2. REEL FEEDS & PAGINATION
  // =========================================================================

  /// Fetches public reels uploaded by other users with AI technique results.
  static Future<List<ReelModel>> getOtherUsersVideoResults({
    DocumentSnapshot? startAfterDoc,
    int limit = 10,
    bool fallbackToAllIfEmpty = true,
  }) async {
    try {
      // Trigger background auto-seed if firestore has no reels
      CuratedCricketReels.seedIfEmpty(_firestore);

      Query query = _reelsRef
          .where('visibility', isEqualTo: 'public')
          .where('status', isEqualTo: 'ready')
          .orderBy('createdAt', descending: true)
          .limit(limit * 2);

      if (startAfterDoc != null) {
        query = query.startAfterDocument(startAfterDoc);
      }

      final snapshot = await query.get();
      final uid = currentUserId;

      final reels = <ReelModel>[];
      final ownReelsFallback = <ReelModel>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final creatorId = data['userId']?.toString() ?? '';

        // Fetch all valid ready public reels (with or without AI)
        bool isLiked = false;
        bool isSaved = false;
        bool isFollowing = false;

        if (uid != null) {
          isLiked = await isReelLiked(doc.id, uid);
          isSaved = await isReelSaved(doc.id, uid);
          if (creatorId.isNotEmpty && creatorId != uid) {
            isFollowing = await isFollowingUser(creatorId);
          }
        }

        final model = ReelModel.fromFirestore(
          doc,
          isLiked: isLiked,
          isSaved: isSaved,
          isFollowing: isFollowing,
        );

        // Separate other users vs own reels
        if (uid == null || creatorId != uid) {
          reels.add(model);
        } else {
          ownReelsFallback.add(model);
        }

        if (reels.length >= limit) break;
      }

      // If other users haven't posted yet, show user's own uploaded reels
      if (reels.isEmpty && fallbackToAllIfEmpty && ownReelsFallback.isNotEmpty) {
        return ownReelsFallback.take(limit).toList();
      }

      if (reels.isEmpty) {
        return CuratedCricketReels.getInitialCricketReels(shuffle: true);
      }

      // If feed has few reels, append curated cricket reels so feed is rich
      if (reels.length < 8) {
        final existingIds = reels.map((r) => r.reelId).toSet();
        for (final curated in CuratedCricketReels.getInitialCricketReels(shuffle: true)) {
          if (!existingIds.contains(curated.reelId)) {
            reels.add(curated);
            existingIds.add(curated.reelId);
          }
        }
      }

      return reels;
    } catch (e) {
      debugPrint("FIRESTORE_REELS_ERROR: $e");
      return CuratedCricketReels.getInitialCricketReels(shuffle: true);
    }
  }

  /// Fetches public, ready reels for the feed with pagination.
  static Future<List<ReelModel>> getForYouReels({
    DocumentSnapshot? startAfterDoc,
    int limit = 10,
  }) async {
    return getOtherUsersVideoResults(
      startAfterDoc: startAfterDoc,
      limit: limit,
    );
  }

  /// Fetches reels from creators the current user follows.
  static Future<List<ReelModel>> getFollowingReels({
    DocumentSnapshot? startAfterDoc,
    int limit = 10,
  }) async {
    final uid = currentUserId;
    if (uid == null) return const [];

    // 1. Get followed creators
    final followingSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('following')
        .limit(30)
        .get();

    final followedIds = followingSnap.docs.map((d) => d.id).toList();
    if (followedIds.isEmpty) return const [];

    // 2. Query reels where userId in followedIds
    Query query = _reelsRef
        .where('userId', whereIn: followedIds.take(10).toList())
        .where('status', isEqualTo: 'ready')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfterDoc != null) {
      query = query.startAfterDocument(startAfterDoc);
    }

    final snapshot = await query.get();
    final reels = <ReelModel>[];
    for (final doc in snapshot.docs) {
      final isLiked = await isReelLiked(doc.id, uid);
      final isSaved = await isReelSaved(doc.id, uid);

      reels.add(
        ReelModel.fromFirestore(
          doc,
          isLiked: isLiked,
          isSaved: isSaved,
          isFollowing: true,
        ),
      );
    }
    return reels;
  }

  /// Fetches reels uploaded by the current user.
  static Future<List<ReelModel>> getMyReels({
    required String userId,
    DocumentSnapshot? startAfterDoc,
    int limit = 20,
  }) async {
    Query query = _reelsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfterDoc != null) {
      query = query.startAfterDocument(startAfterDoc);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => ReelModel.fromFirestore(doc))
        .toList();
  }

  /// Fetches reels bookmarked by the current user.
  static Future<List<ReelModel>> getSavedReels({
    required String userId,
    int limit = 20,
  }) async {
    final savedSnap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('savedReels')
        .orderBy('savedAt', descending: true)
        .limit(limit)
        .get();

    final reelIds = savedSnap.docs.map((d) => d.id).toList();
    if (reelIds.isEmpty) return const [];

    final reels = <ReelModel>[];
    for (final id in reelIds) {
      try {
        final doc = await _reelsRef.doc(id).get();
        if (doc.exists) {
          reels.add(ReelModel.fromFirestore(doc, isSaved: true));
        }
      } catch (_) {}
    }
    return reels;
  }

  // =========================================================================
  // 3. LIKES SYSTEM
  // =========================================================================

  static Future<bool> isReelLiked(String reelId, String userId) async {
    try {
      final doc = await _reelsRef.doc(reelId).collection('likes').doc(userId).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Toggles like/unlike atomically on the Reel document.
  static Future<bool> toggleLike(String reelId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("Please sign in to like reels.");

    final likeDocRef = _reelsRef.doc(reelId).collection('likes').doc(uid);
    final reelDocRef = _reelsRef.doc(reelId);

    return await _firestore.runTransaction<bool>((tx) async {
      final likeSnap = await tx.get(likeDocRef);
      if (likeSnap.exists) {
        // Unlike
        tx.delete(likeDocRef);
        tx.update(reelDocRef, {'likesCount': FieldValue.increment(-1)});
        return false;
      } else {
        // Like
        tx.set(likeDocRef, {
          'userId': uid,
          'likedAt': FieldValue.serverTimestamp(),
        });
        tx.update(reelDocRef, {'likesCount': FieldValue.increment(1)});
        return true;
      }
    });
  }

  // =========================================================================
  // 4. SAVED REELS
  // =========================================================================

  static Future<bool> isReelSaved(String reelId, String userId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('savedReels')
          .doc(reelId)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Toggles saving a Reel to the user's savedReels collection.
  static Future<bool> toggleSave(String reelId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("Please sign in to save reels.");

    final userSavedRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('savedReels')
        .doc(reelId);
    final reelDocRef = _reelsRef.doc(reelId);

    return await _firestore.runTransaction<bool>((tx) async {
      final snap = await tx.get(userSavedRef);
      if (snap.exists) {
        tx.delete(userSavedRef);
        tx.update(reelDocRef, {'savesCount': FieldValue.increment(-1)});
        return false;
      } else {
        tx.set(userSavedRef, {
          'reelId': reelId,
          'savedAt': FieldValue.serverTimestamp(),
        });
        tx.update(reelDocRef, {'savesCount': FieldValue.increment(1)});
        return true;
      }
    });
  }

  // =========================================================================
  // 5. VIEW TRACKING
  // =========================================================================

  /// Records a view if watched past the threshold, deduplicated per session.
  static Future<void> recordView(String reelId) async {
    final key = "${currentUserId ?? 'guest'}_$reelId";
    if (_viewedReelsThisSession.contains(key)) return;
    _viewedReelsThisSession.add(key);

    try {
      await _reelsRef.doc(reelId).update({
        'viewsCount': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint("RECORD_VIEW_ERROR: $e");
    }
  }

  // =========================================================================
  // 6. FOLLOW SYSTEM
  // =========================================================================

  static Future<bool> isFollowingUser(String targetUserId) async {
    final uid = currentUserId;
    if (uid == null || uid == targetUserId) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('following')
          .doc(targetUserId)
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Toggles follow/unfollow for a creator.
  static Future<bool> toggleFollow(String targetUserId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("Please sign in to follow creators.");
    if (uid == targetUserId) return false;

    final myFollowingRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(targetUserId);

    final theirFollowersRef = _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('followers')
        .doc(uid);

    final snap = await myFollowingRef.get();
    if (snap.exists) {
      // Unfollow
      final batch = _firestore.batch();
      batch.delete(myFollowingRef);
      batch.delete(theirFollowersRef);
      await batch.commit();
      return false;
    } else {
      // Follow
      final batch = _firestore.batch();
      batch.set(myFollowingRef, {
        'targetUserId': targetUserId,
        'followedAt': FieldValue.serverTimestamp(),
      });
      batch.set(theirFollowersRef, {
        'userId': uid,
        'followedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return true;
    }
  }

  // =========================================================================
  // 7. COMMENTS SYSTEM
  // =========================================================================

  /// Real-time stream of comments for a specific Reel.
  static Stream<List<ReelComment>> getCommentsStream(String reelId) {
    return _reelsRef
        .doc(reelId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ReelComment.fromFirestore(doc))
              .toList(),
        );
  }

  /// Adds a new comment to a Reel.
  static Future<void> addComment({
    required String reelId,
    required String text,
    required String username,
    String? userPhotoUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("Please sign in to post a comment.");
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final commentDocRef = _reelsRef.doc(reelId).collection('comments').doc();

    final comment = ReelComment(
      commentId: commentDocRef.id,
      reelId: reelId,
      userId: uid,
      username: username,
      userPhotoUrl: userPhotoUrl,
      text: cleanText,
      createdAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(commentDocRef, comment.toMap());
    batch.update(_reelsRef.doc(reelId), {
      'commentsCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Deletes a comment from a Reel (own comment or reel creator).
  static Future<void> deleteComment({
    required String reelId,
    required String commentId,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_reelsRef.doc(reelId).collection('comments').doc(commentId));
    batch.update(_reelsRef.doc(reelId), {
      'commentsCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  // =========================================================================
  // 8. DELETION & MODERATION
  // =========================================================================

  /// Deletes a Reel document from Firestore.
  static Future<void> deleteReel(String reelId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception("Unauthorized.");

    final reelDoc = await _reelsRef.doc(reelId).get();
    if (!reelDoc.exists) return;

    final ownerId = (reelDoc.data() as Map<String, dynamic>?)?['userId'];
    if (ownerId != uid) {
      throw Exception("You can only delete your own Reels.");
    }

    await _reelsRef.doc(reelId).delete();
  }

  /// Submits a moderation report for a Reel.
  static Future<void> reportReel({
    required String reelId,
    required String reason,
  }) async {
    final uid = currentUserId ?? 'anonymous';
    await _reportsRef.add({
      'reelId': reelId,
      'reportedBy': uid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Blocks a user to hide their content.
  static Future<void> blockUser(String targetUserId) async {
    final uid = currentUserId;
    if (uid == null || uid == targetUserId) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('blockedUsers')
        .doc(targetUserId)
        .set({
      'blockedUserId': targetUserId,
      'blockedAt': FieldValue.serverTimestamp(),
    });
  }
}
