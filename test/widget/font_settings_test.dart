import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/i18n/strings_en.dart';
import 'package:sub_converter/main.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/services/settings_store.dart';

import 'fakes.dart';

/// The app font setting end to end: default resolution per platform, the
/// picker in the options panel, and persistence.
void main() {
  const AppStringsEn en = AppStringsEn();

  final FakeSystemFonts systemFonts = FakeSystemFonts(
    families: <String>['Alpha Sans', 'Bravo Serif'],
    desktopDefault: 'Default UI',
  );
  Future<void> useDesktopWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  ThemeData currentTheme(WidgetTester tester) => tester
      .widget<MaterialApp>(find.byType(MaterialApp))
      .theme!;

  group('AppController font state', () {
    // The font query is fire-and-forget, so tests flush the microtask queue
    // to let the fake answer land.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('follows the desktop default until a pick is made', () async {
      final AppController controller = testController(
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(controller.dispose);
      await controller.loadSettings();
      await settle();

      expect(controller.systemFontFamilies, <String>['Alpha Sans', 'Bravo Serif']);
      expect(controller.fontFamily, isNull);
      expect(controller.effectiveFontFamily, 'Default UI');

      controller.setFontFamily('Bravo Serif');
      expect(controller.effectiveFontFamily, 'Bravo Serif');

      controller.setFontFamily(null);
      expect(controller.effectiveFontFamily, 'Default UI');
    });

    test('the pick is persisted and restored', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final AppController controller = testController(
        settingsStore: store,
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(controller.dispose);
      await controller.loadSettings();
      await settle();

      controller.setFontFamily('Alpha Sans');
      await Future<void>.delayed(Duration.zero);
      expect(store.values['fontFamily'], 'Alpha Sans');

      final AppController reopened = testController(        settingsStore: InMemorySettingsStore(store.values),
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(reopened.dispose);
      await reopened.loadSettings();
      expect(reopened.fontFamily, 'Alpha Sans');
      expect(reopened.effectiveFontFamily, 'Alpha Sans');
    });

    test('a font the OS no longer offers still applies', () async {
      // The picker keeps unknown choices selectable, so the controller must
      // not silently drop them either.
      final AppController controller = testController(
        settingsStore: InMemorySettingsStore(<String, Object?>{
          'fontFamily': 'Removed Font',
        }),
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(controller.dispose);
      await controller.loadSettings();
      await settle();

      expect(controller.fontFamily, 'Removed Font');
      expect(controller.effectiveFontFamily, 'Removed Font');
    });

    test('a failed OS query degrades to the curated default', () async {
      final AppController controller = testController(
        systemFonts: FakeSystemFonts(failure: StateError('no channel')),
        platformName: 'linux',
      );
      addTearDown(controller.dispose);
      await controller.loadSettings();
      await settle();

      expect(controller.systemFontFamilies, isEmpty);
      expect(controller.platformDefaultFamily, isNull);
      expect(controller.effectiveFontFamily, 'Noto Sans CJK SC');
    });
  });

  group('font picker in the options panel', () {
    testWidgets('dropdown values render at the regular weight', (
      WidgetTester tester,
    ) async {
      await useDesktopWindow(tester);
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final AppController controller = testController(
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(SubtitleConverterApp(controller: controller));
      await tester.pumpAndSettle();

      // DropdownButton styles its closed value with titleMedium, whose
      // Material default is w500. CJK UI fonts rarely ship a 500 face, so the
      // theme must pin the regular weight or every dropdown value renders in
      // Bold next to regular text.
      final ThemeData theme = currentTheme(tester);
      expect(theme.textTheme.titleMedium!.fontWeight, FontWeight.w400);
      expect(theme.textTheme.titleMedium!.fontSize, 13);
      expect(theme.textTheme.titleMedium!.fontFamily, 'Default UI');
    });

    testWidgets('picks a font, renders it, and shows the system default',
        (WidgetTester tester) async {
      await useDesktopWindow(tester);
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final InMemorySettingsStore store = InMemorySettingsStore();
      final AppController controller = testController(
        settingsStore: store,
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(SubtitleConverterApp(controller: controller));
      await tester.pumpAndSettle();

      // Following the system default: the OS-reported family drives the
      // theme, with the curated Windows chain as fallback.
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamily,
        'Default UI',
      );
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamilyFallback,
        contains('Microsoft YaHei UI'),
      );
      expect(find.text(en.fontSystemDefault), findsOneWidget);
      expect(find.text(en.fontSystemDefaultHelp), findsOneWidget);

      await _selectFont(tester, 'Bravo Serif');
      expect(controller.fontFamily, 'Bravo Serif');
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamily,
        'Bravo Serif',
      );
      expect(store.values['fontFamily'], 'Bravo Serif');
      // The helper only explains the system default choice.
      expect(find.text(en.fontSystemDefaultHelp), findsNothing);

      await _selectFont(tester, en.fontSystemDefault);
      expect(controller.fontFamily, isNull);
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamily,
        'Default UI',
      );
    });

    testWidgets('a restored font that is not installed stays selectable',
        (WidgetTester tester) async {
      await useDesktopWindow(tester);
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final AppController controller = testController(
        settingsStore: InMemorySettingsStore(<String, Object?>{
          'fontFamily': 'Removed Font',
        }),
        systemFonts: systemFonts,
        platformName: 'windows',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(SubtitleConverterApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Removed Font'), findsOneWidget);
      expect(
        currentTheme(tester).textTheme.bodyMedium!.fontFamily,
        'Removed Font',
      );
    });
  });
}

Future<void> _selectFont(WidgetTester tester, String label) async {
  final Finder dropdown = find.byType(DropdownButtonFormField<String>);
  // The picker sits at the bottom of the scrolling options panel.
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
