import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/screens/app_controller.dart';

import 'fakes.dart';

/// Exercises the real drag-and-drop wiring: the window's [DropTarget] callback
/// is invoked exactly as the platform plugin would invoke it, so the path from
/// an OS drop to the file list is covered without a real drag.
void main() {
  Future<void> useDesktopWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  DropTarget dropTarget(WidgetTester tester) =>
      tester.widget<DropTarget>(find.byType(DropTarget));

  DropDoneDetails dropOf(List<DropItem> items) => DropDoneDetails(
    files: items,
    localPosition: Offset.zero,
    globalPosition: Offset.zero,
  );

  DropEventDetails dragAt() =>
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero);

  testWidgets('a dropped file is added to the list', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    expect(find.text('Drag subtitle files here'), findsOneWidget);

    dropTarget(tester).onDragDone!(
      dropOf(<DropItem>[DropItemFile('/movies/E01.ass')]),
    );
    await tester.pumpAndSettle();

    expect(controller.fileCount, 1);
    expect(controller.entries.single.path, '/movies/E01.ass');
    expect(find.text('E01.ass'), findsOneWidget);
    expect(find.text('1 file'), findsOneWidget);
    expect(find.text('Drag subtitle files here'), findsNothing);
  });

  testWidgets('several files drop in at once', (WidgetTester tester) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    dropTarget(tester).onDragDone!(
      dropOf(<DropItem>[
        DropItemFile('/movies/E01.srt'),
        DropItemFile('/movies/E02.ass'),
        DropItemFile('/movies/E03.vtt'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(controller.fileCount, 3);
    expect(find.text('3 files'), findsOneWidget);
  });

  testWidgets('dropped directories and empty paths are ignored', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    dropTarget(tester).onDragDone!(
      dropOf(<DropItem>[
        DropItemDirectory('/movies/Season 1', <DropItem>[]),
        DropItemFile(''),
        DropItemFile('/movies/E01.srt'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(controller.fileCount, 1);
    expect(controller.entries.single.path, '/movies/E01.srt');
  });

  testWidgets('dropping the same file twice keeps one row', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    dropTarget(tester).onDragDone!(
      dropOf(<DropItem>[DropItemFile('/movies/E01.srt')]),
    );
    await tester.pumpAndSettle();
    dropTarget(tester).onDragDone!(
      dropOf(<DropItem>[DropItemFile('/movies/E01.srt')]),
    );
    await tester.pumpAndSettle();

    expect(controller.fileCount, 1);
    expect(find.text('1 file'), findsOneWidget);
  });

  testWidgets('drag enter and exit do not add anything', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    final DropTarget target = dropTarget(tester);
    target.onDragEntered!(dragAt());
    await tester.pumpAndSettle();
    expect(controller.fileCount, 0);

    target.onDragExited!(dragAt());
    await tester.pumpAndSettle();
    expect(controller.fileCount, 0);
    expect(find.text('Drag subtitle files here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropped files convert through the injected service', (
    WidgetTester tester,
  ) async {
    await useDesktopWindow(tester);
    final AppController controller = testController();
    addTearDown(controller.dispose);
    await pumpHomeScreen(tester, controller);

    dropTarget(tester).onDragDone!(
      dropOf(<DropItem>[DropItemFile('/movies/E01.srt')]),
    );
    await tester.pumpAndSettle();

    await controller.convertAll();
    await tester.pumpAndSettle();

    expect(controller.successCount, 1);
    expect(find.text('1 succeeded.'), findsOneWidget);
  });
}
