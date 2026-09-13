import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_converter/i18n/app_strings.dart';
import 'package:sub_converter/i18n/strings_en.dart';
import 'package:sub_converter/i18n/strings_zh.dart';
import 'package:sub_converter/widgets/exit_confirm_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required AppStrings strings,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ExitConfirmDialog(
                    strings: strings,
                    onConfirm: onConfirm,
                    onCancel: onCancel,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('English dialog shows title, body and both actions', (
    WidgetTester tester,
  ) async {
    var confirmed = false;
    var cancelled = false;
    await pumpDialog(
      tester,
      strings: const AppStringsEn(),
      onConfirm: () => confirmed = true,
      onCancel: () => cancelled = true,
    );
    expect(find.text('Exit Subtitle Converter?'), findsOneWidget);
    expect(
      find.textContaining('conversion still running will stop'),
      findsOneWidget,
    );
    expect(find.text('Exit'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(confirmed, isFalse);
    expect(cancelled, isFalse);
  });

  testWidgets('Chinese dialog is fully translated', (
    WidgetTester tester,
  ) async {
    await pumpDialog(
      tester,
      strings: const AppStringsZh(),
      onConfirm: () {},
      onCancel: () {},
    );
    expect(find.text('退出 Subtitle Converter？'), findsOneWidget);
    expect(find.text('窗口将关闭，仍在进行的转换会被中止。'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('cancel pops without confirming; exit confirms', (
    WidgetTester tester,
  ) async {
    var confirmed = false;
    var cancelled = false;
    await pumpDialog(
      tester,
      strings: const AppStringsEn(),
      onConfirm: () => confirmed = true,
      onCancel: () => cancelled = true,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(confirmed, isFalse);
    expect(find.byType(ExitConfirmDialog), findsNothing);

    await pumpDialog(
      tester,
      strings: const AppStringsEn(),
      onConfirm: () => confirmed = true,
      onCancel: () => cancelled = true,
    );
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.byType(ExitConfirmDialog), findsNothing);
  });
}
