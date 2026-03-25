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

  /// ID định danh của phòng chat
  final String id;
  /// Ngày giờ khởi tạo phòng chat
  final DateTime createdAt;
  /// ID của người dùng còn lại (chỉ dùng cho chat 1-1, sẽ là null nếu là chat nhóm)
  final String? otherUserId;
  /// Tên của phòng chat (chỉ dùng cho chat nhóm)
  final String? name;
  /// Xác định xem đây là phòng chat nhóm (true) hay chat 1-1 (false)
  final bool isGroup;
  /// Tin nhắn mới nhất trong phòng (dùng để hiển thị nổi bật ở danh sách phòng)
  final Message? lastMessage;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Tạo đối tượng Room từ dữ liệu join giữa bảng room_participants và bảng rooms
  Room.fromRoomParticipants(Map<String, dynamic> map, {String? currentUserId})
      : id = map['room_id'],
        // Lấy profile_id của người kia (phù hợp với logic lấy danh sách chat 1:1)
        otherUserId = map['profile_id'],
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
