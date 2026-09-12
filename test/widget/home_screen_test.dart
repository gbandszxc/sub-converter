import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/i18n/strings_en.dart';
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/models/loss_report.dart';
import 'package:sub_converter/screens/app_controller.dart';

import 'fakes.dart';

void main() {
  Future<void> useDesktopWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  FilledButton convertButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('empty state shows the drop-zone prompt', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);

    await pumpHomeScreen(tester, controller);

    expect(find.text('Drag subtitle files here'), findsOneWidget);
    expect(find.text('or click Add files to choose them'), findsOneWidget);
    expect(find.text('No files'), findsOneWidget);
  });

  testWidgets(
    'adding paths populates rows and status bar; duplicates ignored',
    (WidgetTester tester) async {
      await useDesktopWindow(tester);
      final AppController controller = testController();
      addTearDown(controller.dispose);
      await pumpHomeScreen(tester, controller);

      await controller.addPaths(<String>[
        '/movies/a.srt',
        '/movies/a.srt',
        '/movies/b.ass',
      ]);
      await tester.pumpAndSettle();

      expect(find.text('a.srt'), findsOneWidget);
      expect(find.text('b.ass'), findsOneWidget);
      expect(find.text('2 files'), findsOneWidget);
      expect(controller.fileCount, 2);
    },
  );

  testWidgets(
    'Convert is disabled when empty and enabled after adding a file',
    (WidgetTester tester) async {
      await useDesktopWindow(tester);
      final AppController controller = testController();
      addTearDown(controller.dispose);
      await pumpHomeScreen(tester, controller);

      expect(convertButton(tester).onPressed, isNull);

      await controller.addPaths(<String>['/movies/a.srt']);
      await tester.pumpAndSettle();

      expect(convertButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets('failed result renders its failure title and summary', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController(
      fileService: FakeFileService(
        convertBuilder: (String path, ConversionOptions options) =>
            failureResult(path),
      ),
    );
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    await controller.addPaths(<String>['/movies/a.srt']);
    await tester.pumpAndSettle();
    await controller.convertAll();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(find.text('1 failed.'), findsOneWidget);
    expect(controller.failureCount, 1);
  });

  testWidgets('lossy success renders as a success, not an error', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
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
    await pumpHomeScreen(tester, controller);

    await controller.addPaths(<String>['/movies/a.srt']);
    await tester.pumpAndSettle();
    await controller.convertAll();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(const AppStringsEn().lossyNotice), findsOneWidget);
    expect(find.text('1 succeeded. 1 lost some styling.'), findsOneWidget);
    expect(controller.successCount, 1);
    expect(controller.lossyCount, 1);
  });

  testWidgets('an auto-renamed success is not shown as lossy', (
    WidgetTester tester,
  ) async {
    // Regression: the rename notice used to be mixed into the loss warnings,
    // so a plain rename was reported as "some styling could not be
    // represented".
    await useDesktopWindow(tester);
    final AppController controller = testController(
      fileService: FakeFileService(
        convertBuilder: (String path, ConversionOptions options) =>
            successResult(path, options).copyWith(outputRenamed: true),
      ),
    );
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    await controller.addPaths(<String>['/movies/a.srt']);
    await tester.pumpAndSettle();
    await controller.convertAll();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(const AppStringsEn().lossyNotice), findsNothing);
    expect(find.text('1 succeeded.'), findsOneWidget);
    expect(controller.successCount, 1);
    expect(controller.lossyCount, 0);
    expect(find.textContaining('renamed, name was taken'), findsOneWidget);
  });

  testWidgets('inspection failure shows Unknown without throwing', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController(
      fileService: FakeFileService(
        inspectHandler: (String path) async => throw StateError('boom'),
      ),
    );
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    await controller.addPaths(<String>['/movies/a.srt']);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Unknown'), findsOneWidget);
  });
}
