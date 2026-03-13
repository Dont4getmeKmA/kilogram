class Profile {
  Profile({
    required this.id,
    required this.username,
    required this.createdAt,
    this.avatarUrl,
  });

  /// User ID of the profile
  final String id;

  /// Username of the profile
  final String username;

  /// Date and time when the profile was created
  final DateTime createdAt;

  /// Optional avatar URL
  final String? avatarUrl;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'created_at': createdAt.toIso8601String(),
      'avatar_url': avatarUrl,
    };
  }

  Profile.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        username = map['username'],
        createdAt = DateTime.parse(map['created_at']),
        avatarUrl = map['avatar_url'];

  Profile copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? avatarUrl,
  }) {
    return Profile(
      id: id ?? this.id,
      username: name ?? username,
      createdAt: createdAt ?? this.createdAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
