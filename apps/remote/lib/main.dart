import 'package:flutter/material.dart';

import 'controller/remote_controller.dart';
import 'screens/pairing_screen.dart';
import 'screens/remote_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CineLarkRemoteApp());
}

class CineLarkRemoteApp extends StatefulWidget {
  const CineLarkRemoteApp({super.key});

  @override
  State<CineLarkRemoteApp> createState() => _CineLarkRemoteAppState();
}

class _CineLarkRemoteAppState extends State<CineLarkRemoteApp> {
  late final RemoteController controller;

  @override
  void initState() {
    super.initState();
    controller = RemoteController();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CineLark Remote',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff51a8ff),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff080b12),
      useMaterial3: true,
    ),
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.phase == RemoteConnectionPhase.loading) {
          return const _LoadingScreen();
        }
        if (!controller.isPaired) {
          return PairingScreen(controller: controller);
        }
        return RemoteScreen(controller: controller);
      },
    ),
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flutter_dash_rounded, size: 64),
          SizedBox(height: 20),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}
