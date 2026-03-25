class Message {
  Message({
    required this.id,
    required this.roomId,
    required this.profileId,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    required this.isMine,
    // E2EE fields
    this.ciphertext,
    this.encryptedKey,
    this.nonce,
    this.hmac,
    this.signature,
  });

  /// ID duy nhất của tin nhắn
  final String id;

  /// ID của người gửi tin nhắn
  final String profileId;

  /// ID của phòng chat chứa tin nhắn này
  final String roomId;

  /// Nội dung tin nhắn (Đây là văn bản gốc nếu đã giải mã, hoặc tin nhắn chưa mã hoá từ phiên bản cũ)
  final String content;

  /// Đường dẫn hình ảnh (nếu có)
  final String? imageUrl;

  /// Ngày giờ gửi tin nhắn
  final DateTime createdAt;

  /// Xác định xem đây có phải tin nhắn do chính mình gửi hay không
  final bool isMine;

  // --- Các trường dữ liệu dành riêng cho Mã hoá Đầu cuối (E2EE) ---
  /// Nội dung đã được mã hoá bằng thuật toán AES-256-GCM
  final String? ciphertext;

  /// Khóa AES đã được bọc/mã hoá (dùng thuật toán ElGamal đối với chat nhóm hoặc chỉ là cờ báo 'v2_full')
  final String? encryptedKey;

  /// Chuỗi dữ liệu ngẫu nhiên (nonce) dùng cho quá trình mã hoá/giải mã AES-GCM
  final String? nonce;

  /// Mã xác thực (HMAC) để kiểm tra tính toàn vẹn, đảm bảo tin nhắn không bị sửa đổi
  final String? hmac;

  /// Chữ ký điện tử RSA để xác minh chính xác danh tính người gửi tin
  final String? signature;

  /// Kỉểm tra xem tin nhắn này đã được mã hoá E2EE hay chưa
  bool get isEncrypted => ciphertext != null && ciphertext!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'profile_id': profileId,
      'room_id': roomId,
      'content': content,
      'image_url': imageUrl,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (encryptedKey != null) 'encrypted_key': encryptedKey,
      if (nonce != null) 'nonce': nonce,
      if (hmac != null) 'hmac': hmac,
      if (signature != null) 'signature': signature,
    };
  }

  Message.fromMap({
    required Map<String, dynamic> map,
    required String myUserId,
  })  : id = map['id'].toString(),
        roomId = map['room_id'].toString(),
        profileId = map['profile_id'].toString(),
        content = map['content']?.toString() ?? '',
        imageUrl = map['image_url']?.toString(),
        createdAt = DateTime.parse(map['created_at'].toString()),
        isMine = myUserId == map['profile_id'].toString(),
        ciphertext = map['ciphertext']?.toString(),
        encryptedKey = map['encrypted_key']?.toString(),
        nonce = map['nonce']?.toString(),
        hmac = map['hmac']?.toString(),
        signature = map['signature']?.toString();

  Message copyWith({
    String? id,
    String? userId,
    String? roomId,
    String? content,
    String? imageUrl,
    DateTime? createdAt,
    bool? isMine,
    String? ciphertext,
    String? encryptedKey,
    String? nonce,
    String? hmac,
    String? signature,
  }) {
    return Message(
      id: id ?? this.id,
      profileId: userId ?? profileId,
      roomId: roomId ?? this.roomId,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      isMine: isMine ?? this.isMine,
      ciphertext: ciphertext ?? this.ciphertext,
      encryptedKey: encryptedKey ?? this.encryptedKey,
      nonce: nonce ?? this.nonce,
      hmac: hmac ?? this.hmac,
      signature: signature ?? this.signature,
    );
  }
}
