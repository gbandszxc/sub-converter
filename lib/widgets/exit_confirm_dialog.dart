import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';

/// The "do you really want to quit?" dialog shown when the user closes the
/// window. The dialog owns popping its route; the callbacks only report the
/// outcome, so the dialog is trivially testable without any plugin.
class ExitConfirmDialog extends StatelessWidget {
  const ExitConfirmDialog({
    super.key,
    required this.strings,
    required this.onConfirm,
    required this.onCancel,
  });

  final AppStrings strings;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(strings.exitConfirmTitle),
      content: Text(strings.exitConfirmBody),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCancel();
          },
          child: Text(strings.exitConfirmCancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: Text(strings.exitConfirmExit),
        ),
      ],
    );
  }
}
