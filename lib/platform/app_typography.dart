/// Which family "the system's default" means on each platform, and the
/// ordered fallback chain tried after it.
///
/// Pure data and pure functions: no Flutter imports, no platform calls, so
/// the controller, the theme builder in `main.dart`, and tests all share it.
///
/// The app pins a real UI family instead of letting the engine fall back on
/// its own, because the engine's runtime fallback mixes families across
/// scripts and weights, which shows up as unevenly rendered Chinese text.
abstract final class AppTypography {
  /// Families tried after the primary one on Windows. The first entries are
  /// the Simplified Chinese UI faces; the PingFang/Noto entries cover custom
  /// primary choices that lack CJK glyphs.
  static const List<String> _windowsFallbacks = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'WenQuanYi Micro Hei',
  ];

  /// Families tried after the primary one on macOS.
  static const List<String> _macosFallbacks = <String>[
    'PingFang SC',
    'Hiragino Sans GB',
    'Heiti SC',
    'Noto Sans CJK SC',
  ];

  /// Families tried after the primary one on Linux. Fontconfig/Pango spell
  /// these the same way on every major distribution.
  static const List<String> _linuxFallbacks = <String>[
    'Noto Sans CJK SC',
    'Noto Sans',
    'Source Han Sans SC',
    'WenQuanYi Zen Hei',
    'WenQuanYi Micro Hei',
    'Droid Sans Fallback',
  ];

  /// The family to use when the user follows the system default, or `null`
  /// when the platform has no curated default (then Flutter's own choice
  /// applies). A reported desktop default wins over the curated one so
  /// locale-specific system fonts (Japanese Windows -> Meiryo, GNOME -> the
  /// selected interface font) are honored.
  static String? defaultFamily({
    required String platform,
    String? desktopDefault,
  }) {
    final String reported = desktopDefault?.trim() ?? '';
    if (reported.isNotEmpty) {
      return reported;
    }
    return switch (platform) {
      'windows' => 'Microsoft YaHei UI',
      'macos' => 'PingFang SC',
      'linux' => 'Noto Sans CJK SC',
      _ => null,
    };
  }

  /// Families tried after [primary]; never contains it. [platform] selects
  /// the chain and stays the source of truth when the user picked a primary
  /// that cannot render some script.
  static List<String> fallbackChain(String platform, {String? primary}) {
    final List<String> chain = switch (platform) {
      'windows' => _windowsFallbacks,
      'macos' => _macosFallbacks,
      'linux' => _linuxFallbacks,
      _ => const <String>[],
    };
    if (primary == null) {
      return List<String>.unmodifiable(chain);
    }
    final String key = primary.toLowerCase();
    return List<String>.unmodifiable(
      chain.where((String family) => family.toLowerCase() != key),
    );
  }
}
