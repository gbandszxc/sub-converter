import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/subtitle_format.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/services/settings_store.dart';

import 'fakes.dart';

/// Regression tests for restoring persisted settings into the UI.
///
/// `loadSettings` is asynchronous, so any control that keeps its own local
/// state must resync when the loaded options arrive.
void main() {
  Future<void> useDesktopWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A store as it would look after a previous session.
  InMemorySettingsStore savedStore({
    String targetFormat = 'lrc',
    String conflictPolicy = 'skip',
    int timeOffsetMs = 500,
    bool writeUtf8Bom = true,
    bool stripMediaSuffix = false,
    String? outputDirectory,
  }) {
    return InMemorySettingsStore(<String, Object?>{
      'targetFormat': targetFormat,
      'outputLocation': outputDirectory == null
          ? 'sourceDirectory'
          : 'customDirectory',
      'outputDirectory': outputDirectory,
      'conflictPolicy': conflictPolicy,
      'timeOffsetMs': timeOffsetMs,
      'writeUtf8Bom': writeUtf8Bom,
      'stripMediaSuffix': stripMediaSuffix,
    });
  }

  testWidgets('persisted settings are restored into the controls', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = AppController(
      fileService: FakeFileService(),
      settingsStore: savedStore(stripMediaSuffix: true),
    );
    addTearDown(controller.dispose);

    await pumpHomeScreen(tester, controller);

    // The controller itself holds the restored values.
    expect(controller.options.targetFormat, SubtitleFormat.lrc);
    expect(controller.options.conflictPolicy, OutputConflictPolicy.skip);
    expect(controller.options.timeOffset, const Duration(milliseconds: 500));
    expect(controller.options.writeUtf8Bom, isTrue);
    expect(controller.options.stripMediaSuffix, isTrue);

    // ...and the controls show them, not their construction-time defaults.
    expect(find.text('LRC · LRC'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '500',
    );
    // Two checkboxes exist (BOM and media suffix); find them by their labels.
    CheckboxListTile checkboxOf(String label) {
      return tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, label),
      );
    }

    expect(checkboxOf('Write UTF-8 BOM').value, isTrue);
    expect(checkboxOf('Strip media suffix').value, isTrue);
  });

  testWidgets('a custom output folder is restored and shown', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = AppController(
      fileService: FakeFileService(),
      settingsStore: savedStore(outputDirectory: r'D:\Converted'),
    );
    addTearDown(controller.dispose);

    await pumpHomeScreen(tester, controller);

    expect(controller.options.outputLocation, OutputLocation.customDirectory);
    expect(controller.options.outputDirectory, r'D:\Converted');
    expect(find.text(r'D:\Converted'), findsOneWidget);
  });

  testWidgets('the step buttons still drive the offset after a restore', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = AppController(
      fileService: FakeFileService(),
      settingsStore: savedStore(timeOffsetMs: 500),
    );
    addTearDown(controller.dispose);

    await pumpHomeScreen(tester, controller);
    await tester.tap(find.text('+500 ms'));
    await tester.pumpAndSettle();

    expect(controller.options.timeOffset, const Duration(seconds: 1));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '1000',
    );
  });
}
