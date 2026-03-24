import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/pages/register_page.dart';
import 'package:kilogram/pages/rooms_page.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  static Route<void> route() {
    return MaterialPageRoute(builder: (context) => const LoginPage());
  }

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  bool _showPassword = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session != null && mounted) {
        await _ensureKeysExist();
        if (mounted) {
          Navigator.of(context).pushReplacement(RoomsPage.route());
        }
      }
    });
  }

  Future<void> _ensureKeysExist() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await CryptoService.ensureKeysExistAndUploaded(userId);
    } catch (e) {
      debugPrint('[Login] Key setup failed: $e');
    }
  }

  void _onNext() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _showPassword = true;
      });
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        debugPrint('[Login] Đăng nhập thành công, đang đồng bộ khóa...');
        await _ensureKeysExist();
      }
    } on AuthException catch (e) {
      String message = "Mật khẩu không chính xác hoặc email không tồn tại";
      if (e.message.toLowerCase().contains('confirm')) {
        message =
            "Vui lòng xác nhận email trong hộp thư của bạn trước khi đăng nhập.";
      }
      if (!mounted) return;
      context.showErrorSnackBar(message: message);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar(message: "Đã có lỗi xảy ra: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng nhập'),
        leading: _showPassword
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showPassword = false),
              )
            : null,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: formPadding,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                height: 120,
              ),
            ),
            const SizedBox(height: 40),
            TextFormField(
              controller: _emailController,
              enabled: !_showPassword,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập email';
                }
                const pattern = r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$';
                final regExp = RegExp(pattern);
                if (!regExp.hasMatch(value)) {
                  return 'Email không đúng định dạng';
                }
                return null;
              },
            ),
            if (!_showPassword) ...[
              spacer,
              ElevatedButton(
                onPressed: _onNext,
                child: const Text('Tiếp theo'),
              ),
              spacer,
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(RegisterPage.route());
                },
                child: const Text('Đăng ký tài khoản'),
              ),
            ],
            if (_showPassword) ...[
              spacer,
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập mật khẩu';
                  }
                  return null;
                },
              ),
              spacer,
              ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Đăng nhập'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
