// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/db_service.dart';
import 'services/llm_service.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_shell.dart';

import 'screens/library/scanning_screen.dart';
import 'services/notification_service.dart';
import 'providers/player_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // ── Open Isar database FIRST ──────────────────────────────────
  // Must happen before initAudioService() — AudioService.init() binds
  // to the Android service via IPC which can disrupt the Pigeon
  // BinaryMessenger, causing channel-error on path_provider calls.
  await DbService.instance.open();

  // Initialize LLM if model path exists (fire and forget to not block startup)
  unawaited(LlmService.instance.loadModel());

  // Initialize notifications
  await NotificationService.instance.init();
  await NotificationService.instance.scheduleMonthlyRecapReminder();

  // Audio service AFTER DB and other plugins are ready
  await initAudioService();

  // Request permissions (fire-and-forget, never crash the app)
  unawaited(_requestPermissions());

  final prefs = await SharedPreferences.getInstance();
  final hasOnboarded = prefs.getBool('onboarded') ?? false;

  // ── Global Image Cache Limits ─────────────────────────
  // Prevents RAM bloat from large libraries of album art.
  PaintingBinding.instance.imageCache.maximumSize = 1000; // Limit by # of images
  PaintingBinding.instance.imageCache.maximumSizeBytes = 250 * 1024 * 1024; // Limit to 250MB

  runApp(ProviderScope(child: BopApp(hasOnboarded: hasOnboarded)));
}

Future<void> _requestPermissions() async {
  if (Platform.isAndroid) {
    // Android 13+ (SDK 33+)
    await Permission.audio.request();
    await Permission.notification.request();
    // Fallback for older
    await Permission.storage.request();
  }
}

class BopApp extends StatelessWidget {
  final bool hasOnboarded;
  const BopApp({super.key, required this.hasOnboarded});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bop v2',
      debugShowCheckedModeBanner: false,
      theme: BopTheme.dark,
      // ── Route table ───────────────────────────
      initialRoute: hasOnboarded ? '/home' : '/onboarding',
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/scan': (_) => const ScanningScreen(),
        '/home': (_) => const MainShell(),
      },
      // ── Deep link: /wrapped/:id ───────────────
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith('/wrapped') == true) {
          return MaterialPageRoute(builder: (_) => const MainShell());
        }
        return null;
      },
    );
  }
}
