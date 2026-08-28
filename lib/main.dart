import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'ui/main_navigation_scaffold.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive dark status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF131923),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final appState = AppState();
  await appState.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const VibeArsApp(),
    ),
  );
}

class VibeArsApp extends StatelessWidget {
  const VibeArsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vibeARS',
      debugShowCheckedModeBanner: false,
      theme: VibeTheme.darkTheme,
      home: const MainNavigationScaffold(),
    );
  }
}
