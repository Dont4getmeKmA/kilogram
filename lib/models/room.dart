import 'package:kilogram/models/message.dart';

class Room {
  Room({
    required this.id,
    required this.createdAt,
    this.otherUserId,
    this.name,
    this.isGroup = false,
    this.lastMessage,
  });

  /// ID of the room
  final String id;

  /// Date and time when the room was created
  final DateTime createdAt;

  /// ID of the user who the user is talking to (for 1:1)
  final String? otherUserId;

  /// Name of the room (for groups)
  final String? name;

  /// Whether it's a group room
  final bool isGroup;

  /// Latest message submitted in the room
  final Message? lastMessage;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Creates a room object from room_participants joined with rooms table
  Room.fromRoomParticipants(Map<String, dynamic> map, {String? currentUserId})
      : id = map['room_id'],
        otherUserId = map[
            'profile_id'], // This might be wrong for groups, but for 1:1 we filter it
        createdAt = DateTime.parse(map['created_at']),
        name = map['rooms']?['name'],
        isGroup = map['rooms']?['is_group'] ?? false,
        lastMessage = null;

  Room copyWith({
    String? id,
    DateTime? createdAt,
    String? otherUserId,
    String? name,
    bool? isGroup,
    Message? lastMessage,
  }) {
    return Room(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      otherUserId: otherUserId ?? this.otherUserId,
      name: name ?? this.name,
      isGroup: isGroup ?? this.isGroup,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}
