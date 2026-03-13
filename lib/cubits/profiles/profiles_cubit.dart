import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:kilogram/models/profile.dart';
import 'package:kilogram/utils/constants.dart';

part 'profiles_state.dart';

class ProfilesCubit extends Cubit<ProfilesState> {
  ProfilesCubit() : super(ProfilesInitial());

  /// Map of app users cache in memory with profile_id as the key
  final Map<String, Profile?> _profiles = {};

  Future<void> getProfile(String userId) async {
    if (_profiles[userId] != null) {
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .match({'id': userId}).maybeSingle();

      if (data != null) {
        _profiles[userId] = Profile.fromMap(data);
      } else {
        _profiles[userId] = null;
      }
    } catch (e) {
      _profiles[userId] = null;
    }

    emit(ProfilesLoaded(profiles: Map.from(_profiles)));
  }

  Future<void> updateProfile(
      {required String userId, String? username, String? avatarUrl}) async {
    final updateData = <String, dynamic>{};
    if (username != null) updateData['username'] = username;
    if (avatarUrl != null) updateData['avatar_url'] = avatarUrl;

    if (updateData.isNotEmpty) {
      await supabase.from('profiles').update(updateData).eq('id', userId);
      final profile = _profiles[userId];
      if (profile != null) {
        _profiles[userId] =
            profile.copyWith(name: username, avatarUrl: avatarUrl);
        emit(ProfilesLoaded(profiles: Map.from(_profiles)));
      }
    }
  }
}
