import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/models/conversion_job.dart';
import 'package:sub_converter/screens/app_controller.dart';
import 'package:sub_converter/widgets/ui_constants.dart';

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
            successResult(path, options, warnings: <String>['Bold dropped.']),
      ),
    );
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    await controller.addPaths(<String>['/movies/a.srt']);
    await tester.pumpAndSettle();
    await controller.convertAll();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(lossyNotice), findsOneWidget);
    expect(find.text('1 succeeded. 1 lost some styling.'), findsOneWidget);
    expect(controller.successCount, 1);
    expect(controller.lossyCount, 1);
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
