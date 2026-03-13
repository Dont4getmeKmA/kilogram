import 'package:flutter/material.dart';
import 'package:kilogram/crypto/crypto_service.dart';
import 'package:kilogram/pages/login_page.dart';
import 'package:kilogram/pages/rooms_page.dart';
import 'package:kilogram/utils/constants.dart';

/// Page to redirect users to the appropreate page depending on the initial auth state
class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  SplashPageState createState() => SplashPageState();
}

class SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    getInitialSession();
    super.initState();
  }

  Future<void> getInitialSession() async {
    // quick and dirty way to wait for the widget to mount
    await Future.delayed(Duration.zero);

    try {
      final session = supabase.auth.currentSession;
      if (session == null) {
        Navigator.of(context)
            .pushAndRemoveUntil(LoginPage.route(), (_) => false);
      } else {
        // Ensure keys exist before proceeding to rooms
        await _ensureKeysExist();
        if (mounted) {
          Navigator.of(context)
              .pushAndRemoveUntil(RoomsPage.route(), (_) => false);
        }
      }
    } catch (_) {
      context.showErrorSnackBar(
        message: 'Error occured during session refresh',
      );
      Navigator.of(context)
          .pushAndRemoveUntil(LoginPage.route(), (_) => false);
    }
  }

  Future<void> _ensureKeysExist() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await CryptoService.ensureKeysExistAndUploaded(userId);
    } catch (e) {
      debugPrint('[Splash] Key setup failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1500),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.5 + (0.5 * value),
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 150,
                height: 150,
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
