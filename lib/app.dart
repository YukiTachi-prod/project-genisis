import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_config.dart';
import 'providers/chat_provider.dart';
import 'ui/screens/glow_screen.dart';
import 'ui/screens/home_screen.dart';

class HomeAiApp extends StatefulWidget {
  final AppConfig config;
  const HomeAiApp({super.key, required this.config});

  @override
  State<HomeAiApp> createState() => _HomeAiAppState();
}

class _HomeAiAppState extends State<HomeAiApp> {
  bool _showChat = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(widget.config),
      child: MaterialApp(
        title: 'Home AI',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _showChat
              ? const HomeScreen(key: ValueKey('home'))
              : GlowScreen(
                  key: const ValueKey('glow'),
                  onComplete: () => setState(() => _showChat = true),
                ),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final seedColor = const Color(0xFF5B6EF5);
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
