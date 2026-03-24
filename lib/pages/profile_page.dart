import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/cubits/profiles/profiles_cubit.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:kilogram/utils/theme_provider.dart';
import 'package:provider/provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  static Route<void> route() {
    return MaterialPageRoute(builder: (context) => const ProfilePage());
  }

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _picker = ImagePicker();
  bool _isLoading = false;
  bool _isKeysOk = true;

  @override
  void initState() {
    super.initState();
    final myUserId = supabase.auth.currentUser!.id;
    context.read<ProfilesCubit>().getProfile(myUserId);
    _checkKeys();
  }

  Future<void> _checkKeys() async {
    final userId = supabase.auth.currentUser!.id;
    final hasLocal = await CryptoService.hasKeyBundle(userId);
    final row = await supabase
        .from('profiles')
        .select('ecdh_public_key')
        .eq('id', userId)
        .maybeSingle();
    final hasServer = row != null && row['ecdh_public_key'] != null;
    if (mounted) {
      setState(() {
        _isKeysOk = hasLocal && hasServer;
      });
    }
  }

  Future<void> _repairKeys() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await CryptoService.ensureKeysExistAndUploaded(userId, force: true);
      await _checkKeys();
      if (mounted) {
        context.showSnackBar(
            message: 'Khóa bảo mật đã được cập nhật thành công!',
            backgroundColor: Colors.green);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(message: 'Lỗi sửa khóa: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final myUserId = supabase.auth.currentUser!.id;
      final Uint8List imageBytes = await image.readAsBytes();
      final String fileExt = image.path.split('.').last;
      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final String filePath = '$myUserId/$fileName';

      await supabase.storage.from('avatars').uploadBinary(
            filePath,
            imageBytes,
          );

      final String imageUrl =
          supabase.storage.from('avatars').getPublicUrl(filePath);

      await context.read<ProfilesCubit>().updateProfile(
            userId: myUserId,
            avatarUrl: imageUrl,
          );

      if (mounted) {
        context.showSnackBar(
            message: 'Avatar updated successfully',
            backgroundColor: Colors.green);
      }
    } catch (error) {
      if (mounted) {
        context.showErrorSnackBar(message: 'Error updating avatar: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = supabase.auth.currentUser!.id;
    final themeProvider = Provider.of<ThemeCubit>(context);

    return Scaffold(
      body: BlocBuilder<ProfilesCubit, ProfilesState>(
        builder: (context, state) {
          if (state is ProfilesLoaded) {
            final profile = state.profiles[myUserId];
            if (profile == null) {
              return preloader;
            }

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: profile.avatarUrl != null
                            ? NetworkImage(profile.avatarUrl!)
                            : null,
                        child: profile.avatarUrl == null
                            ? Text(
                                profile.username.substring(0, 2).toUpperCase(),
                                style: const TextStyle(fontSize: 40))
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: FloatingActionButton.small(
                          onPressed: _isLoading ? null : _uploadAvatar,
                          child: const Icon(Icons.camera_alt),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Thông tin tài khoản',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Username'),
                        subtitle: Text(profile.username),
                      ),
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Email'),
                        subtitle: Text(supabase.auth.currentUser?.email ?? ''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Cài đặt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dark_mode_outlined),
                        title: const Text('Chế độ tối'),
                        trailing: Switch(
                          value: themeProvider.themeMode == ThemeMode.dark,
                          onChanged: (value) {
                            themeProvider.toggleTheme();
                          },
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.language_outlined),
                        title: const Text('Ngôn ngữ'),
                        subtitle: const Text('Tiếng Việt'),
                        onTap: () {
                          context.showSnackBar(
                              message: 'Tính năng đang được phát triển');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Bảo mật & Mã hoá (E2EE)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          _isKeysOk
                              ? Icons.enhanced_encryption
                              : Icons.no_encryption,
                          color: _isKeysOk ? Colors.green : Colors.red,
                        ),
                        title: Text(_isKeysOk
                            ? 'Đã bật mã hóa đầu cuối'
                            : 'Lỗi mã hóa đầu cuối'),
                        subtitle: Text(_isKeysOk
                            ? 'Tài khoản của bạn an toàn'
                            : 'Khóa của bạn chưa được đồng bộ'),
                        trailing: _isKeysOk
                            ? null
                            : TextButton(
                                onPressed: _isLoading ? null : _repairKeys,
                                child: const Text('Sửa ngay'),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            );
          }
          return preloader;
        },
      ),
    );
  }
}
