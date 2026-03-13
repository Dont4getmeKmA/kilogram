import 'package:flutter/material.dart';
import 'package:kilogram/models/profile.dart';
import 'package:kilogram/pages/chat_page.dart';
import 'package:kilogram/utils/constants.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(builder: (context) => const CreateGroupPage());
  }

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final Set<Profile> _selected = {};
  List<Profile> _users = [];
  List<Profile> _filteredUsers = [];
  bool _isLoading = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final myId = supabase.auth.currentUser!.id;
      final List data = await supabase
          .from('profiles')
          .select()
          .not('id', 'eq', myId)
          .order('username');
      final rows = List<Map<String, dynamic>>.from(data);
      setState(() {
        _users = rows.map(Profile.fromMap).toList();
        _filteredUsers = _users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        context.showErrorSnackBar(
            message: 'Không thể tải danh sách người dùng');
      }
    }
  }

  void _onSearch(String query) {
    setState(() {
      _filteredUsers = query.isEmpty
          ? _users
          : _users
              .where(
                  (u) => u.username.toLowerCase().contains(query.toLowerCase()))
              .toList();
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      context.showErrorSnackBar(message: 'Vui lòng nhập tên nhóm');
      return;
    }
    if (_selected.isEmpty) {
      context.showErrorSnackBar(message: 'Hãy chọn ít nhất 1 thành viên');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final myId = supabase.auth.currentUser!.id;

      // 1. Create the room directly via Supabase
      final roomData = await supabase
          .from('rooms')
          .insert({
            'name': name,
            'is_group': true,
          })
          .select()
          .single();

      final roomId = roomData['id'] as String;

      // 2. Insert all participants (current user + selected members)
      final participants = [
        {'room_id': roomId, 'profile_id': myId},
        ..._selected.map((p) => {'room_id': roomId, 'profile_id': p.id}),
      ];
      await supabase.from('room_participants').insert(participants);

      if (mounted) {
        Navigator.of(context).pop(); // Pop Create Group page
        Navigator.of(context).push(
          ChatPage.route(
              roomId,
              Profile(
                id: roomId,
                username: name,
                createdAt: DateTime.now(),
              )),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        context.showErrorSnackBar(message: 'Không thể tạo nhóm: $e');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo nhóm mới'),
        actions: [
          if (_isCreating)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _createGroup,
              child: Text(
                'Tạo',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group name input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Tên nhóm',
                hintText: 'Nhập tên nhóm...',
                prefixIcon: const Icon(Icons.group),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Selected members chips
          if (_selected.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Đã chọn (${_selected.length})',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                scrollDirection: Axis.horizontal,
                children: _selected.map((profile) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: CircleAvatar(
                        backgroundImage: profile.avatarUrl != null
                            ? NetworkImage(profile.avatarUrl!)
                            : null,
                        child: profile.avatarUrl == null
                            ? Text(
                                profile.username.substring(0, 1).toUpperCase())
                            : null,
                      ),
                      label: Text(profile.username),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () =>
                          setState(() => _selected.remove(profile)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const Divider(),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm người dùng...',
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onSearch,
            ),
          ),

          // User list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? const Center(child: Text('Không tìm thấy người dùng'))
                    : ListView.builder(
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final isSelected = _selected.contains(user);
                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selected.remove(user);
                                } else {
                                  _selected.add(user);
                                }
                              });
                            },
                            leading: CircleAvatar(
                              backgroundImage: user.avatarUrl != null
                                  ? NetworkImage(user.avatarUrl!)
                                  : null,
                              child: user.avatarUrl == null
                                  ? Text(user.username
                                      .substring(0, 1)
                                      .toUpperCase())
                                  : null,
                            ),
                            title: Text(user.username),
                            trailing: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                border: isSelected
                                    ? null
                                    : Border.all(color: Colors.grey),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.check,
                                size: 18,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
