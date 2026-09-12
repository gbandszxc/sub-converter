import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/i18n/app_language.dart';
import 'package:sub_converter/i18n/strings_en.dart';
import 'package:sub_converter/i18n/strings_zh.dart';
import 'package:sub_converter/main.dart';
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/loss_report.dart';
import 'package:sub_converter/models/subtitle_exception.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/services/settings_store.dart';

import '../widget/fakes.dart';

/// Localization behavior end to end: auto-detection, the manual switch, its
/// persistence, and the localized rendering of failures and loss.
void main() {
  const AppStringsEn en = AppStringsEn();
  const AppStringsZh zh = AppStringsZh();

  Future<void> useDesktopWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void usePlatformLocale(WidgetTester tester, Locale locale) {
    tester.platformDispatcher.localeTestValue = locale;
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  }

  testWidgets('follows a Chinese platform locale by default', (
    WidgetTester tester,
  ) async {
    usePlatformLocale(tester, const Locale('zh', 'CN'));
    final AppController controller = testController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(SubtitleConverterApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text(zh.emptyTitle), findsOneWidget);
    expect(find.text(zh.addFiles), findsOneWidget);
  });

  testWidgets('follows a non-Chinese platform locale by default', (
    WidgetTester tester,
  ) async {
    usePlatformLocale(tester, const Locale('en', 'US'));
    final AppController controller = testController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(SubtitleConverterApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text(en.emptyTitle), findsOneWidget);
  });

  testWidgets('the Language dropdown switches the UI immediately', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    usePlatformLocale(tester, const Locale('en', 'US'));
    final AppController controller = testController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(SubtitleConverterApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text(en.emptyTitle), findsOneWidget);

    await _selectLanguage(tester, en.languageChinese);
    expect(controller.language, AppLanguage.chinese);
    expect(find.text(zh.emptyTitle), findsOneWidget);
    expect(find.text(en.emptyTitle), findsNothing);

    await _selectLanguage(tester, en.languageEnglish);
    expect(controller.language, AppLanguage.english);
    expect(find.text(en.emptyTitle), findsOneWidget);
    expect(find.text(zh.emptyTitle), findsNothing);
  });

  testWidgets(
    'a failed row shows the localized title and no unrelated detail',
    (WidgetTester tester) async {
      final AppController controller = testController(
        fileService: FakeFileService(
          convertBuilder: (String path, ConversionOptions options) =>
              failureResult(
                path,
                failure: ConversionFailure.unsupportedFormat,
                detail: 'The format of a.srt could not be identified.',
              ),
        ),
      );
      addTearDown(controller.dispose);
      await pumpHomeScreen(tester, controller, language: AppLanguage.chinese);

      await controller.addPaths(<String>['/movies/a.srt']);
      await tester.pumpAndSettle();
      await controller.convertAll();
      await tester.pumpAndSettle();

      expect(find.text('不支持的格式'), findsOneWidget);
      expect(find.textContaining('could not be identified'), findsNothing);
    },
  );

  testWidgets('a lossy success shows the localized lossy notice', (
    WidgetTester tester,
  ) async {
    final AppController controller = testController(
      fileService: FakeFileService(
        convertBuilder: (String path, ConversionOptions options) =>
            successResult(
              path,
              options,
              warnings: const <LossWarning>[
                LossWarning(LossKind.inlineStylesDropped),
              ],
            ),
      ),
    );
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller, language: AppLanguage.chinese);

    await controller.addPaths(<String>['/movies/a.srt']);
    await tester.pumpAndSettle();
    await controller.convertAll();
    await tester.pumpAndSettle();

    expect(find.text(zh.lossyNotice), findsOneWidget);
    expect(find.text(en.lossyNotice), findsNothing);
  });

  test('the language choice persists and is restored', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    final AppController first = testController(settingsStore: store);
    addTearDown(first.dispose);

    first.setLanguage(AppLanguage.chinese);
    await Future<void>.delayed(Duration.zero);
    expect(store.values['language'], 'chinese');

    final AppController second = testController(settingsStore: store);
    addTearDown(second.dispose);
    await second.loadSettings();

    expect(second.language, AppLanguage.chinese);
  });
}

/// Opens the Language dropdown and picks the item labelled [label].
///
/// The two non-system labels are listed in their own script in both locales, so
/// the caller passes the exact text to tap.
Future<void> _selectLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<AppLanguage>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
