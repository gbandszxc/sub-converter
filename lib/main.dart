import 'package:flutter/material.dart';

import 'screens/app_controller.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SubtitleConverterApp());
}

/// Root widget: wires the controller, theme and single window together.
class SubtitleConverterApp extends StatefulWidget {
  const SubtitleConverterApp({super.key, this.controller});

  /// Injectable for tests; a default controller is created when omitted.
  final AppController? controller;

  @override
  State<SubtitleConverterApp> createState() => _SubtitleConverterAppState();
}

class _SubtitleConverterAppState extends State<SubtitleConverterApp> {
  late final AppController _controller = widget.controller ?? AppController();
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Subtitle Converter',
      debugShowCheckedModeBanner: false,
      theme: _themeFor(Brightness.light),
      darkTheme: _themeFor(Brightness.dark),
      home: HomeScreen(controller: _controller),
    );
  }

  ThemeData _themeFor(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B6EA5),
        brightness: brightness,
      ),
      visualDensity: VisualDensity.compact,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13),
        bodySmall: TextStyle(fontSize: 12),
      ),
    );
  }
}
