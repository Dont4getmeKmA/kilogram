import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';
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

  late final String _roomId;
  late final String _myUserId;

  /// Public keys of the other participant (for encryption + decryption).
  RemotePublicKeys? _recipientKeys;

  /// Cache: profile_id → RemotePublicKeys (for incoming messages)
  final Map<String, RemotePublicKeys> _keysCache = {};

  // ─────────────────────────────────────────────────────────────────────────
  // SETUP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> setMessagesListener(String roomId) async {
    _roomId = roomId;
    _myUserId = supabase.auth.currentUser!.id;

    // 1. Initial load via REST API (always reliable)
    await _loadMessages();

    // 2. Realtime: subscribe to new inserts via channel
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

            // Remove optimistic placeholder for my own messages
            _messages
                .removeWhere((m) => m.id == 'new' && m.isMine && msg.isMine);

            // Avoid duplicates
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
      debugPrint('Load messages error: $e');
      if (!isClosed) emit(ChatError('Không thể tải tin nhắn: $e'));
    }
  }

  /// Called after key fetch completes — triggers re-decrypt of cached messages.
  Future<void> setRecipientKeys(RemotePublicKeys keys) async {
    _recipientKeys = keys;
    // Re-decrypt any messages that failed before keys were available
    if (_messages.isNotEmpty) {
      _messages = await _decryptAll(_messages);
      if (!isClosed) emit(ChatLoaded(List.from(_messages)));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND MESSAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
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
      debugPrint('Send message error: $e');
      _messages.removeWhere((m) => m.id == 'new');
      emit(ChatLoaded(List.from(_messages)));
      emit(ChatError('Không thể gửi: $e'));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND IMAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendImage(
      {required Uint8List imageBytes, required String fileName}) async {
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
      debugPrint('Send image error: $e');
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
          '[ChatCubit] First decrypt failed, retrying with fresh keys...');
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
        debugPrint('[ChatCubit] Retry decrypt failed: $e2');
      }
      return msg.copyWith(content: '🔒 [Lỗi giải mã]');
    }
  }

  Future<Message> _attemptDecrypt(Message msg) async {
    RemotePublicKeys? otherPartyKeys;
    CryptoRole role;

    if (msg.isMine) {
      // I am SENDER: To decrypt my own message, I need the RECIPIENT'S public key
      otherPartyKeys = _recipientKeys;
      role = CryptoRole.sender;

      if (otherPartyKeys == null) {
        // Try to find the other person's ID from the room/cache if possible
        // For simplicity, if _recipientKeys is null, we can't decrypt our own old messages yet
        throw Exception('Recipient keys not loaded in Cubit');
      }
    } else {
      // I am RECIPIENT: To decrypt an incoming message, I need the SENDER'S public key
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
