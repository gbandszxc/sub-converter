import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import '../screens/app_controller.dart';
import 'ui_constants.dart';

/// Window header: app name on the left, batch actions on the right.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.controller,
    required this.onAddFiles,
  });

  final AppController controller;
  final VoidCallback onAddFiles;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final bool busy = controller.isConverting;
    return SizedBox(
      height: AppSpacing.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.subtitles_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(strings.appTitle, style: AppTextStyles.appTitle),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onAddFiles,
              icon: const Icon(Icons.add, size: 16),
              label: Text(strings.addFiles),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: busy ? null : controller.clearEntries,
              icon: const Icon(Icons.clear_all, size: 16),
              label: Text(strings.clear),
            ),
          ],
        ),
      ),
    );
  }
}
