import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kilogram/cubits/profiles/profiles_cubit.dart';
import 'package:kilogram/utils/constants.dart';

/// Widget that will display a user's avatar
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfilesCubit, ProfilesState>(
      builder: (context, state) {
        if (state is ProfilesLoaded) {
          final user = state.profiles[userId];
          return CircleAvatar(
            backgroundImage:
                user?.avatarUrl != null ? NetworkImage(user!.avatarUrl!) : null,
            child: user == null
                ? preloader
                : (user.avatarUrl == null
                    ? Text(user.username.substring(0, 2))
                    : null),
          );
        } else {
          return const CircleAvatar(child: preloader);
        }
      },
    );
  }
}
