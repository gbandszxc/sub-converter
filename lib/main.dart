import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/app_language.dart';
import 'i18n/app_strings.dart';
import 'i18n/strings_scope.dart';
import 'platform/app_typography.dart';
import 'platform/window_close.dart';
import 'screens/app_controller.dart';
import 'screens/home_screen.dart';
import 'widgets/exit_confirm_dialog.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final WindowCloseChannel _closeChannel = WindowCloseChannel();
  bool _exitDialogOpen = false;

  /// Set once the user confirmed quitting: `close()` re-enters the close
  /// handler before the window is gone, and that must not show the
  /// confirmation dialog again.
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    // Ask before the user closes the window. Degrades to the default close
    // behavior when the plugin is unavailable (tests, headless hosts).
    _closeChannel.interceptClose(_showExitConfirm);
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever the controller changes, so picking a language updates
    // every string immediately.
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        // Use the binding's dispatcher rather than the raw
        // `PlatformDispatcher.instance`: it is the same locale at runtime and
        // it is what tests can override.
        final Locale platformLocale =
            WidgetsBinding.instance.platformDispatcher.locale;
        final AppLanguage effective = _controller.language.resolve(
          platformLocale,
        );
        return StringsScope(
          strings: AppStrings.forLanguage(effective),
          child: MaterialApp(
            // The window title stays the product name in every language.
            title: 'Subtitle Converter',
            locale: effective.locale,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[Locale('en'), Locale('zh')],
            debugShowCheckedModeBanner: false,
            theme: _themeFor(Brightness.light),
            darkTheme: _themeFor(Brightness.dark),
            navigatorKey: _navigatorKey,
            home: HomeScreen(controller: _controller),
          ),
        );
      },
    );
  }

  /// Shows the bilingual quit confirmation, then closes for real on exit.
  ///
  /// The strings resolve the same way `build` does: the user's pick, else the
  /// platform locale.
  Future<void> _showExitConfirm() async {
    if (_exitDialogOpen || _quitting) {
      return;
    }
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      // Nothing to confirm against (window torn down before the first frame);
      // honor the close request instead of leaving a zombie window.
      await _closeChannel.closeNow();
      return;
    }
    _exitDialogOpen = true;
    final Locale platformLocale =
        WidgetsBinding.instance.platformDispatcher.locale;
    final AppStrings strings = AppStrings.forLanguage(
      _controller.language.resolve(platformLocale),
    );
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (BuildContext context) => ExitConfirmDialog(
        strings: strings,
        onConfirm: () {
          _quitting = true;
          _closeChannel.closeNow();
        },
        onCancel: () {},
      ),
    );
    _exitDialogOpen = false;
  }

  /// Builds the theme around the app font: the user's pick, else the
  /// platform's default policy. The fallback chain stays in charge of
  /// scripts and weights the chosen family cannot render.
  ThemeData _themeFor(Brightness brightness) {
    final String? family = _controller.effectiveFontFamily;
    final List<String> fallback = AppTypography.fallbackChain(
      _controller.platformName,
      primary: family,
    );
    // Start from the full Material text theme, never a hand-picked const:
    // TextTheme.apply() below only rewrites non-null styles, so every style
    // left out would keep the Material default - including its missing font
    // family - and silently fall back to the engine font. That is exactly
    // what bodyLarge drives (ListTile titles, TextField text) and labelLarge
    // (button labels); those must follow the app font like everything else.
    final Typography typography = Typography.material2021();
    TextTheme textTheme =
        (brightness == Brightness.light ? typography.black : typography.white)
            .merge(
              const TextTheme(
                bodyLarge: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
                bodyMedium: TextStyle(fontSize: 13, letterSpacing: 0),
                bodySmall: TextStyle(fontSize: 12, letterSpacing: 0),
                // DropdownButton renders its closed value in titleMedium,
                // whose Material default is w500. CJK UI fonts rarely ship a
                // 500 face, so DirectWrite jumps to Bold for those runs while
                // the surrounding text stays regular - the uneven weights
                // this app must never show. Pin it to the regular weight and
                // the body size.
                titleMedium: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
                // Button labels default to w500, which hits the same trap on
                // CJK fonts that only ship regular and bold.
                labelLarge: TextStyle(
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            );
    if (family != null) {
      textTheme = textTheme.apply(
        fontFamily: family,
        fontFamilyFallback: fallback,
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B6EA5),
        brightness: brightness,
      ),
      visualDensity: VisualDensity.compact,
      textTheme: textTheme,
    );
  }
}
