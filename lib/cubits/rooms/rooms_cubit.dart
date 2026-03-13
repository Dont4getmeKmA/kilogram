import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kilogram/cubits/profiles/profiles_cubit.dart';
import 'package:kilogram/models/profile.dart';
import 'package:kilogram/models/message.dart';
import 'package:kilogram/models/room.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/utils/constants.dart';

part 'rooms_state.dart';

class RoomCubit extends Cubit<RoomState> {
  RoomCubit() : super(RoomsLoading());

  final Map<String, StreamSubscription<Message?>> _messageSubscriptions = {};

  late final String _myUserId;

  /// List of new users of the app for the user to start talking to
  List<Profile> _newUsers = [];

  /// List of rooms
  List<Room> _rooms = [];
  StreamSubscription<List<Map<String, dynamic>>>? _rawRoomsSubscription;
  bool _haveCalledGetRooms = false;

  Future<void> initializeRooms(BuildContext context) async {
    if (_haveCalledGetRooms) {
      return;
    }
    _haveCalledGetRooms = true;

    _myUserId = supabase.auth.currentUser!.id;

    // Ensure E2EE keys exist whenever we enter the main page
    unawaited(
        CryptoService.ensureKeysExistAndUploaded(_myUserId).catchError((e) {
      debugPrint('[RoomsCubit] E2EE key check failed: $e');
    }));

    late final List data;

    try {
      data = await supabase
          .from('profiles')
          .select()
          .not('id', 'eq', _myUserId)
          .order('created_at')
          .limit(12);
    } catch (e) {
      debugPrint('Error loading new users: $e');
      if (!isClosed) {
        emit(RoomsError('Error loading new users: $e'));
      }
    }

    final rows = List<Map<String, dynamic>>.from(data);
    _newUsers = rows.map(Profile.fromMap).toList();

    _rawRoomsSubscription = supabase.from('room_participants').stream(
      primaryKey: ['room_id', 'profile_id'],
    ).listen((participantMaps) async {
      if (participantMaps.isEmpty) {
        if (!isClosed) {
          emit(RoomsEmpty(newUsers: _newUsers));
        }
        return;
      }

      // Load metadata for each room (to check if it's a group)
      final roomIds =
          participantMaps.map((p) => p['room_id'] as String).toSet().toList();
      final List roomsData =
          await supabase.from('rooms').select().inFilter('id', roomIds);
      final roomsMetadata = {for (var r in roomsData) r['id']: r};

      // Group participant rows by room_id
      final Map<String, List<String>> roomParticipants = {};
      final Map<String, DateTime> roomCreatedAt = {};
      for (final map in participantMaps) {
        final roomId = map['room_id'] as String;
        final profileId = map['profile_id'] as String;
        roomParticipants.putIfAbsent(roomId, () => []).add(profileId);
        roomCreatedAt.putIfAbsent(
            roomId, () => DateTime.parse(map['created_at']));
      }

      // Build unique Room list — one entry per room_id
      _rooms = [];
      for (final roomId in roomParticipants.keys) {
        final metadata = roomsMetadata[roomId];
        final isGroup = metadata?['is_group'] == true;
        final participants = roomParticipants[roomId]!;

        if (isGroup) {
          // Group: always show once, no otherUserId
          _rooms.add(Room(
            id: roomId,
            createdAt: roomCreatedAt[roomId]!,
            name: metadata?['name'],
            isGroup: true,
          ));
        } else {
          // Private 1:1: only show if current user is a participant,
          // and use the OTHER person's ID
          if (!participants.contains(_myUserId)) continue;
          final otherId = participants.firstWhere(
            (id) => id != _myUserId,
            orElse: () => '',
          );
          if (otherId.isEmpty) continue;
          _rooms.add(Room(
            id: roomId,
            createdAt: roomCreatedAt[roomId]!,
            otherUserId: otherId,
            isGroup: false,
          ));
        }
      }

      for (final room in _rooms) {
        _getNewestMessage(context: context, roomId: room.id);
        if (!room.isGroup && room.otherUserId != null) {
          BlocProvider.of<ProfilesCubit>(context).getProfile(room.otherUserId!);
        }
      }
      if (!isClosed) {
        emit(RoomsLoaded(
          newUsers: _newUsers,
          rooms: _rooms,
        ));
      }
    }, onError: (error) {
      debugPrint('Error loading rooms: $error');
      if (!isClosed) {
        emit(RoomsError('Error loading rooms: $error'));
      }
    });
  }

  // Setup listeners to listen to the most recent message in each room
  void _getNewestMessage({
    required BuildContext context,
    required String roomId,
  }) {
    _messageSubscriptions[roomId] = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at')
        .limit(1)
        .map<Message?>(
          (data) => data.isEmpty
              ? null
              : Message.fromMap(
                  map: data.first,
                  myUserId: _myUserId,
                ),
        )
        .listen((message) {
          final index = _rooms.indexWhere((room) => room.id == roomId);
          _rooms[index] = _rooms[index].copyWith(lastMessage: message);
          _rooms.sort((a, b) {
            /// Sort according to the last message
            /// Use the room createdAt when last message is not available
            final aTimeStamp =
                a.lastMessage != null ? a.lastMessage!.createdAt : a.createdAt;
            final bTimeStamp =
                b.lastMessage != null ? b.lastMessage!.createdAt : b.createdAt;
            return bTimeStamp.compareTo(aTimeStamp);
          });
          if (!isClosed) {
            emit(RoomsLoaded(
              newUsers: _newUsers,
              rooms: _rooms,
            ));
          }
        });
  }

  /// Creates or returns an existing roomID of both participants
  Future<String> createRoom(String otherUserId) async {
    final data = await supabase
        .rpc('create_new_room', params: {'other_user_id': otherUserId});
    emit(RoomsLoaded(rooms: _rooms, newUsers: _newUsers));
    return data as String;
  }

  /// Creates a new group room
  Future<String> createGroup(String groupName,
      {List<String> memberIds = const []}) async {
    // 1. Create the room
    final roomData = await supabase
        .from('rooms')
        .insert({
          'name': groupName,
          'is_group': true,
        })
        .select()
        .single();

    final roomId = roomData['id'] as String;

    // 2. Add current user + selected members as participants
    final participants = [
      {'room_id': roomId, 'profile_id': _myUserId},
      ...memberIds.map((id) => {'room_id': roomId, 'profile_id': id}),
    ];
    await supabase.from('room_participants').insert(participants);

    return roomId;
  }

  Future<void> searchUsers(String query) async {
    try {
      final List data;
      if (query.isEmpty) {
        data = await supabase
            .from('profiles')
            .select()
            .not('id', 'eq', _myUserId)
            .order('created_at')
            .limit(12);
      } else {
        data = await supabase
            .from('profiles')
            .select()
            .not('id', 'eq', _myUserId)
            .ilike('username', '%$query%')
            .order('created_at')
            .limit(12);
      }
      final rows = List<Map<String, dynamic>>.from(data);
      _newUsers = rows.map(Profile.fromMap).toList();

      if (state is RoomsLoaded) {
        emit(RoomsLoaded(newUsers: _newUsers, rooms: _rooms));
      } else if (state is RoomsEmpty) {
        emit(RoomsEmpty(newUsers: _newUsers));
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
  }

  @override
  Future<void> close() {
    _rawRoomsSubscription?.cancel();
    return super.close();
  }
}
