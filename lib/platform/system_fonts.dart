import 'package:flutter/services.dart';

/// Bridges to the native runners for system font information.
///
/// Lives outside `lib/services` on purpose: the model/format/service layers
/// must stay pure Dart, and this is the one Dart file allowed to speak to a
/// platform channel. Every call degrades to an empty or null answer instead
/// of throwing, so widget tests (no plugin registered) and unsupported hosts
/// keep working and simply fall back to the curated defaults in
/// `AppTypography`.
class SystemFonts {
  const SystemFonts();

  static const MethodChannel _channel = MethodChannel('sub_converter/fonts');

  /// Installed family names as the OS spells them, sorted case-insensitively.
  ///
  /// The names are what the platform APIs report (localized family names on
  /// Windows and macOS), which is exactly what the font picker should offer.
  Future<List<String>> installedFontFamilies() async {
    try {
      final List<String>? families = await _channel
          .invokeListMethod<String>('installedFontFamilies');
      if (families == null) {
        return const <String>[];
      }
      final List<String> usable = families
          .where((String name) => name.trim().isNotEmpty)
          .toList()
        ..sort(
          (String a, String b) =>
              a.toLowerCase().compareTo(b.toLowerCase()),
        );
      return List<String>.unmodifiable(usable);
    } catch (_) {
      return const <String>[];
    }
  }

  /// The platform's own default UI family, or `null` when unknown.
  ///
  /// Windows reports the NONCLIENTMETRICS message font (the font the shell
  /// itself uses), macOS and the Linux runners report the system's CJK UI
  /// face and the desktop's selected font respectively.
  Future<String?> defaultFontFamily() async {
    try {
      return await _channel.invokeMethod<String>('defaultFontFamily');
    } catch (_) {
      return null;
    }
  }
}
