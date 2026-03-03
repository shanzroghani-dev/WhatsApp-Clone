/// User data model (permanent, stored in Firestore)
class UserModel {
  final String uid;
  final String uniqueNumber;
  final String email;
  final String displayName;
  final String profilePic;
  final String status;
  final String publicKey;
  final DateTime lastSeen;
  final bool isOnline;
  final DateTime createdAt;
  final DateTime lastUpdated;

  UserModel({
    required this.uid,
    required this.uniqueNumber,
    required this.email,
    required this.displayName,
    this.profilePic = '',
    this.status = 'Available',
    this.publicKey = '',
    DateTime? lastSeen,
    this.isOnline = false,
    DateTime? createdAt,
    DateTime? lastUpdated,
  })  : lastSeen = lastSeen ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Convert to JSON for Firestore
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'uniqueNumber': uniqueNumber,
        'email': email,
        'displayName': displayName,
        'profilePic': profilePic,
        'status': status,
        'publicKey': publicKey,
        'lastSeen': lastSeen,
        'isOnline': isOnline,
        'createdAt': createdAt,
        'lastUpdated': lastUpdated,
      };

  /// Create from Firestore JSON
  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        uid: json['uid'] as String,
        uniqueNumber: json['uniqueNumber'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        profilePic: json['profilePic'] as String? ?? '',
        status: json['status'] as String? ?? 'Available',
        publicKey: json['publicKey'] as String? ?? '',
        lastSeen: (json['lastSeen'] as dynamic)?.toDate() ?? DateTime.now(),
        isOnline: json['isOnline'] as bool? ?? false,
        createdAt: (json['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
        lastUpdated: (json['lastUpdated'] as dynamic)?.toDate() ?? DateTime.now(),
      );

  /// Copy with modifications
  UserModel copyWith({
    String? uid,
    String? uniqueNumber,
    String? email,
    String? displayName,
    String? profilePic,
    String? status,
    String? publicKey,
    DateTime? lastSeen,
    bool? isOnline,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) =>
      UserModel(
        uid: uid ?? this.uid,
        uniqueNumber: uniqueNumber ?? this.uniqueNumber,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        profilePic: profilePic ?? this.profilePic,
        status: status ?? this.status,
        publicKey: publicKey ?? this.publicKey,
        lastSeen: lastSeen ?? this.lastSeen,
        isOnline: isOnline ?? this.isOnline,
        createdAt: createdAt ?? this.createdAt,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  @override
  String toString() => 'UserModel(uid: $uid, uniqueNumber: $uniqueNumber, displayName: $displayName)';
}
