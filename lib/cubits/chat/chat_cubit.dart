import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/models/message.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  ChatCubit() : super(ChatInitial());

  StreamSubscription<List<Message>>? _messagesSubscription;
  RealtimeChannel? _channel;
  List<Message> _messages = [];

  ///Khoá công khai (Public Keys) của người đang chat cùng (dùng cho chat 1-1)
  RemotePublicKeys? _recipientKeys;

  /// Bộ nhớ tạm (Cache) lưu khóa công khai thiết bị của nhiều người dùng khác (hữu dụng trong chat nhóm)
  final Map<String, RemotePublicKeys> _keysCache = {};
  late final String _roomId;
  late final String _myUserId;

  // ─────────────────────────────────────────────────────────────────────────
  // SETUP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> setMessagesListener(
    String roomId,
  ) async {
    _roomId = roomId;
    _myUserId = supabase.auth.currentUser!.id;

    // 1. Tải tin nhắn cũ (Lịch sử chat) thông qua REST API (đảm bảo không bị sót tin nhắn)
    await _loadMessages();

    // 2. Bật kết nối Realtime WebSockets: Lắng nghe liên tục ngay khi có tin nhắn mới được thêm (insert) vào DB
    _channel = supabase
        .channel('room_chat_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) async {
            final newRow = payload.newRecord;
            if (newRow.isEmpty) return;
            final msg = Message.fromMap(map: newRow, myUserId: _myUserId);
            _messages
                .removeWhere((m) => m.id == 'new' && m.isMine && msg.isMine);
            if (_messages.any((m) => m.id == msg.id)) return;

            final decrypted = await _decryptOne(msg);
            _messages.insert(0, decrypted);
            _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            if (!isClosed) emit(ChatLoaded(List.from(_messages)));
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await supabase
          .from('messages')
          .select()
          .eq('room_id', _roomId)
          .order('created_at', ascending: false);

      final messages = (data as List)
          .map<Message>((row) => Message.fromMap(map: row, myUserId: _myUserId))
          .toList();

      _messages = await _decryptAll(messages);

      if (!isClosed) {
        if (_messages.isEmpty) {
          emit(ChatEmpty());
        } else {
          emit(ChatLoaded(List.from(_messages)));
        }
      }
    } catch (e) {
      debugPrint('Lỗi tải tin nhắn: $e');
      if (!isClosed) emit(ChatError('Không thể tải tin nhắn: $e'));
    }
  }

  Future<void> setRecipientKeys(
    RemotePublicKeys keys,
  ) async {
    _recipientKeys = keys;
    if (_messages.isNotEmpty) {
      _messages = await _decryptAll(_messages);
      if (!isClosed) emit(ChatLoaded(List.from(_messages)));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND MESSAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    // 1. Giao diện lạc quan (Optimistic UI): Cập nhật thẳng màn hình trước khi gửi thật để tạo cảm giác mượt mà
    final optimistic = Message(
      id: 'new',
      roomId: _roomId,
      profileId: _myUserId,
      content: text,
      createdAt: DateTime.now(),
      isMine: true,
    );
    _messages.insert(0, optimistic);
    emit(ChatLoaded(List.from(_messages)));

    try {
      Map<String, dynamic> insertMap;

      if (_recipientKeys != null &&
          await CryptoService.hasKeyBundle(_myUserId)) {
        final encrypted = await CryptoService.encryptMessage(
          plaintext: text,
          recipient: _recipientKeys!,
        );
        insertMap = {
          'profile_id': _myUserId,
          'room_id': _roomId,
          'content': '',
          ...encrypted.toMap(),
        };
      } else {
        insertMap = optimistic.toMap();
      }

      await supabase.from('messages').insert(insertMap);
    } catch (e) {
      debugPrint('Lỗi gửi tin nhắn: $e');
      _messages.removeWhere((m) => m.id == 'new');
      emit(ChatLoaded(List.from(_messages)));
      emit(ChatError('Không thể gửi: $e'));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND IMAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendImage({
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    final imagePath = '/$_roomId/$fileName';
    try {
      await supabase.storage
          .from('chat_images')
          .uploadBinary(imagePath, imageBytes);
      final imageUrl =
          supabase.storage.from('chat_images').getPublicUrl(imagePath);
      final message = Message(
        id: 'new',
        roomId: _roomId,
        profileId: _myUserId,
        content: '',
        imageUrl: imageUrl,
        createdAt: DateTime.now(),
        isMine: true,
      );
      _messages.insert(0, message);
      emit(ChatLoaded(List.from(_messages)));
      await supabase.from('messages').insert(message.toMap());
    } catch (e) {
      debugPrint('Lỗi gửi ảnh: $e');
      _messages.removeWhere((m) => m.id == 'new');
      emit(ChatLoaded(List.from(_messages)));
      String errorMessage = 'Lỗi tải ảnh: $e';
      if (e.toString().contains('violates row-level security policy')) {
        errorMessage =
            'Lỗi bảo mật: Cần cấu hình RLS cho bucket "chat_images".';
      }
      emit(ChatError(errorMessage));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DECRYPT HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<Message>> _decryptAll(List<Message> messages) async {
    final result = <Message>[];
    for (final msg in messages) {
      result.add(await _decryptOne(msg));
    }
    return result;
  }

  Future<Message> _decryptOne(Message msg) async {
    if (msg.ciphertext == null || msg.ciphertext!.isEmpty) return msg;
    if (msg.imageUrl != null) return msg;

    try {
      return await _attemptDecrypt(msg);
    } catch (e) {
      debugPrint(
          '[ChatCubit] Giải mã lần đầu thất bại, đang thử lại với khóa mới...');
      try {
        final freshKeys = await _fetchPublicKeys(msg.profileId);
        if (freshKeys != null) {
          _keysCache[msg.profileId] = freshKeys;
          if (msg.profileId != _myUserId) {
            _recipientKeys = freshKeys;
          }
          return await _attemptDecrypt(msg);
        }
      } catch (e2) {
        debugPrint('[ChatCubit] Thử giải mã lại thất bại: $e2');
      }
      return msg.copyWith(content: '[Lỗi giải mã]');
    }
  }

  Future<Message> _attemptDecrypt(Message msg) async {
    RemotePublicKeys? otherPartyKeys;
    CryptoRole role;

    if (msg.isMine) {
      // TRƯỜNG HỢP MÌNH VỪA GỬI TIN: Để giải mã tin nhắn hiển thị lại máy mình, mình cần Public Key của ĐỐI TÁC đã dùng để mã hoá cho họ
      otherPartyKeys = _recipientKeys;
      role = CryptoRole.sender;

      if (otherPartyKeys == null) {
        throw Exception('Recipient keys not loaded in Cubit');
      }
    } else {
      // TRƯỜNG HỢP NHẬN TIN NHẮN TỪ NGƯỜI KHÁC: Để giải mã được, mình cần Public Key của chính NGƯỜI GỬI ĐÓ
      otherPartyKeys = _keysCache[msg.profileId];
      if (otherPartyKeys == null) {
        otherPartyKeys = await _fetchPublicKeys(msg.profileId);
        if (otherPartyKeys != null) _keysCache[msg.profileId] = otherPartyKeys;
      }
      role = CryptoRole.recipient;
    }

    if (otherPartyKeys == null) {
      throw Exception('Could not find public keys for other party');
    }

    final payload = EncryptedPayload.fromMap(msg.toMap());
    final decryptedText = await CryptoService.decryptMessage(
      payload: payload,
      otherParty: otherPartyKeys,
      signerRsaPublicKey: otherPartyKeys.rsaPublicKey,
      role: role,
    );

    return msg.copyWith(content: decryptedText);
  }

  Future<RemotePublicKeys?> _fetchPublicKeys(String profileId) async {
    try {
      final data = await supabase
          .from('profiles')
          .select('rsa_public_key, elgamal_public_key, ecdh_public_key')
          .eq('id', profileId)
          .single();
      if (data['ecdh_public_key'] == null) return null;
      return RemotePublicKeys(
        rsaPublicKey: data['rsa_public_key'] as String,
        elgamalPublicKey: data['elgamal_public_key'] as String,
        ecdhPublicKey: data['ecdh_public_key'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    _channel?.unsubscribe();
    return super.close();
  }
}
