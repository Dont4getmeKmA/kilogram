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

  final String id;
  final String profileId;
  final String roomId;

  /// Plaintext content (after decryption, or original for legacy messages)
  final String content;

  final String? imageUrl;
  final DateTime createdAt;
  final bool isMine;

  // ── E2EE fields (null = legacy plaintext message) ──
  final String? ciphertext;
  final String? encryptedKey;
  final String? nonce;
  final String? hmac;
  final String? signature;

  /// True if this message has been E2EE encrypted
  bool get isEncrypted => ciphertext != null && ciphertext!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'profile_id': profileId,
      'room_id': roomId,
      'content': content,
      'image_url': imageUrl,
      // E2EE fields (only included if set)
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
