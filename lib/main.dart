import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kilogram/cubits/profiles/profiles_cubit.dart';
import 'package:kilogram/utils/constants.dart';
import 'package:kilogram/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kilogram/pages/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // url và key của supabase có thư viện supabase_flutter để hỗ trợ tích hợp
  await Supabase.initialize(
    url: 'https://utpxubagugeyuxmhxedk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0cHh1YmFndWdleXV4bWh4ZWRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxMTg5NzEsImV4cCI6MjA4ODY5NDk3MX0.leDX4fO3XrbA9wl2r6Ez4v_j7jOexkuJdvTf9zrv6ms',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeCubit(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfilesCubit>(
      create: (context) => ProfilesCubit(),
      child: Consumer<ThemeCubit>(
        builder: (context, themeCubit, child) {
          return MaterialApp(
            title: 'KILOGRAM',
            debugShowCheckedModeBanner: false,
            theme: appTheme,
            darkTheme: darkTheme,
            themeMode: themeCubit.themeMode,
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}
