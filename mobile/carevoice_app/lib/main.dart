import 'package:flutter/material.dart';
import 'core/constants.dart';
import 'core/firebase_service.dart';
import 'core/notification_service.dart';
import 'core/tts_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConstants.loadCustomUrl();
  FirebaseService.instance.configure(
    projectId: 'carevoice-health-app',
    apiKey: 'AIzaSyCxfMCcN5NA6qm6iKsAeH5G19reTjRuxZU',
  );
  await TtsService.init();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  await NotificationService.instance.syncAllSchedules();
  NotificationService.instance.startRealtimeMonitoring();
  runApp(const CareVoiceApp());
}

class CareVoiceApp extends StatelessWidget {
  const CareVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CareVoice App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const LoginScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}
