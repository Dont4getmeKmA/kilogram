import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kilogram/cubits/profiles/profiles_cubit.dart';
import 'package:kilogram/pages/create_group_page.dart';
import 'package:kilogram/pages/profile_page.dart';

import 'package:kilogram/cubits/rooms/rooms_cubit.dart';
import 'package:kilogram/models/profile.dart';
import 'package:kilogram/pages/chat_page.dart';
import 'package:kilogram/pages/login_page.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:timeago/timeago.dart';

/// Displays the list of chat threads
class RoomsPage extends StatefulWidget {
  const RoomsPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => BlocProvider<RoomCubit>(
        create: (context) => RoomCubit()..initializeRooms(context),
        child: const RoomsPage(),
      ),
    );
  }

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Kilogram' : (_currentIndex == 1 ? 'Nhóm' : 'Hồ sơ')),
        automaticallyImplyLeading: false,
        actions: [
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.group_add),
              tooltip: 'Tạo nhóm',
              onPressed: () => Navigator.of(context).push(CreateGroupPage.route()),
            ),
          if (_currentIndex == 2)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () async {
                await supabase.auth.signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  LoginPage.route(),
                  (route) => false,
                );
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const _RoomsList(isGroup: false),
          const _RoomsList(isGroup: true),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            activeIcon: Icon(Icons.group),
            label: 'Nhóm',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }

}

class _RoomsList extends StatelessWidget {
  final bool isGroup;
  const _RoomsList({Key? key, required this.isGroup}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoomCubit, RoomState>(
      builder: (context, state) {
        if (state is RoomsLoading) {
          return preloader;
        } else if (state is RoomsLoaded) {
          final newUsers = state.newUsers;
          final rooms = state.rooms.where((room) => room.isGroup == isGroup).toList();
          
          if (rooms.isEmpty && isGroup) {
            return const Center(child: Text('Bạn chưa tham gia nhóm nào'));
          }

          return BlocBuilder<ProfilesCubit, ProfilesState>(
            builder: (context, state) {
              if (state is ProfilesLoaded) {
                final profiles = state.profiles;
                return Column(
                  children: [
                    if (!isGroup) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Tìm kiếm người dùng...',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (val) {
                            BlocProvider.of<RoomCubit>(context).searchUsers(val);
                          },
                        ),
                      ),
                      _NewUsers(newUsers: newUsers),
                      const Divider(),
                    ],
                    Expanded(
                      child: ListView.builder(
                        itemCount: rooms.length,
                        itemBuilder: (context, index) {
                          final room = rooms[index];
                          final otherUser = isGroup ? null : (room.otherUserId != null ? profiles[room.otherUserId] : null);

                          return ListTile(
                            onTap: () {
                              if (isGroup) {
                                Navigator.of(context).push(
                                  ChatPage.route(room.id, Profile(
                                    id: room.id,
                                    username: room.name ?? 'Group Chat',
                                    createdAt: room.createdAt,
                                  )),
                                );
                              } else if (otherUser != null) {
                                Navigator.of(context).push(
                                  ChatPage.route(room.id, otherUser),
                                );
                              }
                            },
                            leading: CircleAvatar(
                              backgroundImage: isGroup 
                                ? null 
                                : (otherUser?.avatarUrl != null ? NetworkImage(otherUser!.avatarUrl!) : null),
                              child: isGroup 
                                ? const Icon(Icons.group)
                                : (otherUser == null ? preloader : (otherUser.avatarUrl == null ? Text(otherUser.username.substring(0, 2)) : null)),
                            ),
                            title: Text(isGroup 
                              ? (room.name ?? 'Group Chat') 
                              : (otherUser == null ? 'Loading...' : otherUser.username)),
                            subtitle: room.lastMessage != null
                                ? Text(
                                    room.lastMessage!.content,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : const Text('Bắt đầu trò chuyện'),
                            trailing: Text(format(
                                room.lastMessage?.createdAt ?? room.createdAt,
                                locale: 'en_short')),
                          );
                        },
                      ),
                    ),
                  ],
                );
              } else {
                return preloader;
              }
            },
          );
        } else if (state is RoomsEmpty) {
          if (isGroup) return const Center(child: Text('Bạn chưa tham gia nhóm nào'));
          final newUsers = state.newUsers;
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm người dùng...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (val) {
                    BlocProvider.of<RoomCubit>(context).searchUsers(val);
                  },
                ),
              ),
              _NewUsers(newUsers: newUsers, state: state),
              const Expanded(
                child: Center(
                  child: Text('Hãy bắt đầu cuộc trò chuyện đầu tiên'),
                ),
              ),
            ],
          );
        } else if (state is RoomsError) {
          return Center(child: Text(state.message));
        }
        return const SizedBox();
      },
    );
  }
}

class _NewUsers extends StatelessWidget {
  const _NewUsers({
    Key? key,
    required this.newUsers,
    this.state,
  }) : super(key: key);

  final List<Profile> newUsers;
  final RoomState? state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: newUsers
            .map<Widget>((user) => InkWell(
                  onTap: () async {
                    try {
                      final roomId = await BlocProvider.of<RoomCubit>(context)
                          .createRoom(user.id);
                      if (context.mounted) {
                        Navigator.of(context)
                            .push(ChatPage.route(roomId, user));
                      }
                    } catch (_) {
                      context.showErrorSnackBar(
                          message: 'Failed creating a new room');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 60,
                      child: Column(
                        children: [
                          CircleAvatar(
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.username.substring(0, 2))
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
