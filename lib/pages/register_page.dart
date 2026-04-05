import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/pages/login_page.dart';
import 'package:kilogram/pages/rooms_page.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.isRegistering});

  static Route<void> route({bool isRegistering = false}) {
    return MaterialPageRoute(
      builder: (context) => RegisterPage(isRegistering: isRegistering),
    );
  }

  final bool isRegistering;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();

    bool haveNavigated = false;
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session != null &&
          !haveNavigated &&
          data.event == AuthChangeEvent.signedIn) {
        haveNavigated = true;
        // Generate crypto keys after successful sign-up
        await _generateAndUploadKeys();
        if (mounted) {
          Navigator.of(context).pushReplacement(RoomsPage.route());
        }
      }
    });
  }

  Future<void> _generateAndUploadKeys() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await CryptoService.ensureKeysExistAndUploaded(userId);
    } catch (e) {
      debugPrint('[Register] Thiết lập khóa thất bại: $e');
      rethrow; // Re-throw so the caller knows it failed
    }
  }

  @override
  void dispose() {
    super.dispose();

    // Dispose subscription when no longer needed
    _authSubscription.cancel();
  }

  Future<void> _signUp() async {
    final isValid = _formKey.currentState!.validate();
    if (!isValid) {
      return;
    }
    final email = _emailController.text;
    final password = _passwordController.text;
    final username = _usernameController.text;
    setState(() => _isLoading = true); // Set loading to true
    try {
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
        emailRedirectTo: 'io.supabase.chat://login',
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận Email'),
            content: const Text(
                'Một email xác nhận đã được gửi đến hộp thư của bạn. Vui lòng nhấn vào liên kết trong email để kích hoạt tài khoản.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(LoginPage.route());
                },
                child: const Text('OK, Đăng nhập'),
              ),
            ],
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        context.showErrorSnackBar(message: error.message);
      }
    } catch (error) {
      debugPrint('Lỗi đăng ký: ${error.toString()}');
      if (mounted) {
        context.showErrorSnackBar(message: unexpectedErrorMessage);
      }
    } finally {
      if (mounted) {
        setState(
            () => _isLoading = false); // Set loading to false in finally block
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: formPadding,
          children: [
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                label: Text('Email'),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Required';
                }
                return null;
              },
              keyboardType: TextInputType.emailAddress,
            ),
            spacer,
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                label: Text('Password'),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Required';
                }
                if (val.length < 6) {
                  return '6 characters minimum';
                }
                return null;
              },
            ),
            spacer,
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                label: Text('Username'),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Required';
                }
                final isValid = RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(val);
                if (!isValid) {
                  return '3-24 long with alphanumeric or underscore';
                }
                return null;
              },
            ),
            spacer,
            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Register'),
            ),
            spacer,
            TextButton(
                onPressed: () {
                  Navigator.of(context).push(LoginPage.route());
                },
                child: const Text('Đăng nhập'))
          ],
        ),
      ),
    );
  }
}
