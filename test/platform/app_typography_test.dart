import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/platform/app_typography.dart';

/// The per-platform font policy: curated defaults, desktop overrides, and
/// the fallback chains handed to the theme.
void main() {
  group('defaultFamily', () {
    test('curated defaults match each supported platform', () {
      expect(
        AppTypography.defaultFamily(platform: 'windows'),
        'Microsoft YaHei UI',
      );
      expect(AppTypography.defaultFamily(platform: 'macos'), 'PingFang SC');
      expect(
        AppTypography.defaultFamily(platform: 'linux'),
        'Noto Sans CJK SC',
      );
    });

    test('a reported desktop default wins over the curated one', () {
      // Windows shell font on a Japanese system, GNOME font on Linux, ...
      expect(
        AppTypography.defaultFamily(
          platform: 'windows',
          desktopDefault: 'Meiryo UI',
        ),
        'Meiryo UI',
      );
      expect(
        AppTypography.defaultFamily(
          platform: 'linux',
          desktopDefault: 'Cantarell',
        ),
        'Cantarell',
      );
    });

    test('a blank desktop default is ignored', () {
      expect(
        AppTypography.defaultFamily(platform: 'windows', desktopDefault: '  '),
        'Microsoft YaHei UI',
      );
      expect(
        AppTypography.defaultFamily(platform: 'linux', desktopDefault: ''),
        'Noto Sans CJK SC',
      );
    });

    test('an unsupported platform has no default', () {
      expect(AppTypography.defaultFamily(platform: 'android'), isNull);
    });
  });

  group('fallbackChain', () {
    test('every supported platform has a CJK-aware chain', () {
      expect(AppTypography.fallbackChain('windows'), contains('Microsoft YaHei'));
      expect(AppTypography.fallbackChain('macos'), contains('PingFang SC'));
      expect(
        AppTypography.fallbackChain('linux'),
        contains('Noto Sans CJK SC'),
      );
      expect(AppTypography.fallbackChain('android'), isEmpty);
    });

    test('the primary family is removed case-insensitively', () {
      final List<String> chain = AppTypography.fallbackChain(
        'windows',
        primary: 'microsoft yahei ui',
      );
      expect(chain, isNot(contains('Microsoft YaHei UI')));
      expect(chain, contains('Microsoft YaHei'));
      expect(chain, contains('PingFang SC'));
    });

    test('an unknown primary leaves the chain intact', () {
      final List<String> chain = AppTypography.fallbackChain(
        'windows',
        primary: 'Bravo Serif',
      );
      expect(chain, AppTypography.fallbackChain('windows'));
    });

    test('the chain is unmodifiable', () {
      expect(
        () => AppTypography.fallbackChain('windows').add('X'),
        throwsUnsupportedError,
      );
    });
  });
}
