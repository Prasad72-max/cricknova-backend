import 'package:cloud_firestore/cloud_firestore.dart';

enum ReelVisibility {
  public,
  followers,
  private;

  String toValue() {
    switch (this) {
      case ReelVisibility.followers:
        return 'followers';
      case ReelVisibility.private:
        return 'private';
      case ReelVisibility.public:
      default:
        return 'public';
    }
  }

  static ReelVisibility fromValue(String? val) {
    switch (val?.toLowerCase()) {
      case 'followers':
        return ReelVisibility.followers;
      case 'private':
        return ReelVisibility.private;
      case 'public':
      default:
        return ReelVisibility.public;
    }
  }
}

enum ReelStatus {
  uploading,
  processing,
  ready,
  failed;

  String toValue() {
    switch (this) {
      case ReelStatus.uploading:
        return 'uploading';
      case ReelStatus.processing:
        return 'processing';
      case ReelStatus.failed:
        return 'failed';
      case ReelStatus.ready:
      default:
        return 'ready';
    }
  }

  static ReelStatus fromValue(String? val) {
    switch (val?.toLowerCase()) {
      case 'uploading':
        return ReelStatus.uploading;
      case 'processing':
        return ReelStatus.processing;
      case 'failed':
        return ReelStatus.failed;
      case 'ready':
      default:
        return ReelStatus.ready;
    }
  }
}

class ReelAiAnalysis {
  final String shotType;
  final double? ballSpeed;
  final double? batSpeed;
  final String swing;
  final String spin;
  final double? aiScore;
  final String? aiFeedback;
  final List<dynamic> trajectory;
  final Map<String, dynamic> rawData;

  const ReelAiAnalysis({
    this.shotType = "Cricket Shot",
    this.ballSpeed,
    this.batSpeed,
    this.swing = "Normal",
    this.spin = "None",
    this.aiScore,
    this.aiFeedback,
    this.trajectory = const [],
    this.rawData = const {},
  });

  factory ReelAiAnalysis.fromMap(Map<String, dynamic> map) {
    double? parseNum(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    return ReelAiAnalysis(
      shotType: (map['shotType'] ?? map['shot_type'] ?? map['shot'] ?? "Cricket Action").toString(),
      ballSpeed: parseNum(map['ballSpeed'] ?? map['ball_speed'] ?? map['speed_kmph']),
      batSpeed: parseNum(map['batSpeed'] ?? map['bat_speed']),
      swing: (map['swing'] ?? "Normal").toString(),
      spin: (map['spin'] ?? "None").toString(),
      aiScore: parseNum(map['aiScore'] ?? map['ai_score'] ?? map['score'] ?? map['rating']),
      aiFeedback: (map['aiFeedback'] ?? map['ai_feedback'] ?? map['feedback'] ?? map['coach_reply'] ?? map['mistake'])?.toString(),
      trajectory: (map['trajectory'] is List) ? (map['trajectory'] as List) : const [],
      rawData: map,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shotType': shotType,
      'ballSpeed': ballSpeed,
      'batSpeed': batSpeed,
      'swing': swing,
      'spin': spin,
      'aiScore': aiScore,
      'aiFeedback': aiFeedback,
      'trajectory': trajectory,
      'rawData': rawData,
    };
  }
}

class ReelComment {
  final String commentId;
  final String reelId;
  final String userId;
  final String username;
  final String? userPhotoUrl;
  final String text;
  final DateTime createdAt;
  final int likesCount;

  const ReelComment({
    required this.commentId,
    required this.reelId,
    required this.userId,
    required this.username,
    this.userPhotoUrl,
    required this.text,
    required this.createdAt,
    this.likesCount = 0,
  });

  factory ReelComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return ReelComment(
      commentId: doc.id,
      reelId: (data['reelId'] ?? '').toString(),
      userId: (data['userId'] ?? '').toString(),
      username: (data['username'] ?? 'Player').toString(),
      userPhotoUrl: data['userPhotoUrl'] as String?,
      text: (data['text'] ?? '').toString(),
      createdAt: parseDate(data['createdAt']),
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'commentId': commentId,
      'reelId': reelId,
      'userId': userId,
      'username': username,
      'userPhotoUrl': userPhotoUrl,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'likesCount': likesCount,
    };
  }
}

class ReelModel {
  final String reelId;
  final String userId;
  final String username;
  final String? userPhotoUrl;
  final String videoUrl;
  final String? originalVideoUrl;
  final String? thumbnailUrl;
  final String caption;
  final List<String> hashtags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final int savesCount;
  final ReelVisibility visibility;
  final ReelStatus status;
  final ReelAiAnalysis? aiAnalysis;

  // Local client-side engagement states
  final bool isLiked;
  final bool isSaved;
  final bool isFollowing;

  const ReelModel({
    required this.reelId,
    required this.userId,
    required this.username,
    this.userPhotoUrl,
    required this.videoUrl,
    this.originalVideoUrl,
    this.thumbnailUrl,
    required this.caption,
    this.hashtags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.viewsCount = 0,
    this.savesCount = 0,
    this.visibility = ReelVisibility.public,
    this.status = ReelStatus.ready,
    this.aiAnalysis,
    this.isLiked = false,
    this.isSaved = false,
    this.isFollowing = false,
  });

  factory ReelModel.fromFirestore(
    DocumentSnapshot doc, {
    bool isLiked = false,
    bool isSaved = false,
    bool isFollowing = false,
  }) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<String> parseTags(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    ReelAiAnalysis? ai;
    if (data['aiAnalysis'] is Map<String, dynamic>) {
      ai = ReelAiAnalysis.fromMap(data['aiAnalysis'] as Map<String, dynamic>);
    }

    return ReelModel(
      reelId: doc.id,
      userId: (data['userId'] ?? '').toString(),
      username: (data['username'] ?? 'Player').toString(),
      userPhotoUrl: data['userPhotoUrl'] as String?,
      videoUrl: (data['videoUrl'] ?? '').toString(),
      originalVideoUrl: data['originalVideoUrl'] as String?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      caption: (data['caption'] ?? '').toString(),
      hashtags: parseTags(data['hashtags']),
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      likesCount: (data['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (data['commentsCount'] as num?)?.toInt() ?? 0,
      viewsCount: (data['viewsCount'] as num?)?.toInt() ?? 0,
      savesCount: (data['savesCount'] as num?)?.toInt() ?? 0,
      visibility: ReelVisibility.fromValue(data['visibility'] as String?),
      status: ReelStatus.fromValue(data['status'] as String?),
      aiAnalysis: ai,
      isLiked: isLiked,
      isSaved: isSaved,
      isFollowing: isFollowing,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reelId': reelId,
      'userId': userId,
      'username': username,
      'userPhotoUrl': userPhotoUrl,
      'videoUrl': videoUrl,
      'originalVideoUrl': originalVideoUrl,
      'thumbnailUrl': thumbnailUrl,
      'caption': caption,
      'hashtags': hashtags,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'viewsCount': viewsCount,
      'savesCount': savesCount,
      'visibility': visibility.toValue(),
      'status': status.toValue(),
      if (aiAnalysis != null) 'aiAnalysis': aiAnalysis!.toMap(),
    };
  }

  ReelModel copyWith({
    String? caption,
    List<String>? hashtags,
    int? likesCount,
    int? commentsCount,
    int? viewsCount,
    int? savesCount,
    ReelVisibility? visibility,
    ReelStatus? status,
    ReelAiAnalysis? aiAnalysis,
    bool? isLiked,
    bool? isSaved,
    bool? isFollowing,
  }) {
    return ReelModel(
      reelId: reelId,
      userId: userId,
      username: username,
      userPhotoUrl: userPhotoUrl,
      videoUrl: videoUrl,
      originalVideoUrl: originalVideoUrl,
      thumbnailUrl: thumbnailUrl,
      caption: caption ?? this.caption,
      hashtags: hashtags ?? this.hashtags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      viewsCount: viewsCount ?? this.viewsCount,
      savesCount: savesCount ?? this.savesCount,
      visibility: visibility ?? this.visibility,
      status: status ?? this.status,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}
