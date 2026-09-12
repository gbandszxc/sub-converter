import 'package:flutter/material.dart';

import '../screens/app_controller.dart';
import 'ui_constants.dart';

/// Bottom bar: persistent file/result counts plus live batch progress.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: AppSpacing.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: <Widget>[
          _Counts(controller: controller),
          const Spacer(),
          if (controller.isConverting) ...<Widget>[
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                child: LinearProgressIndicator(value: controller.progress),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          if (controller.batchMessage != null)
            Flexible(
              child: Text(
                controller.batchMessage!,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final int files = controller.fileCount;
    if (files == 0) {
      return Text(
        'No files',
        style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
      );
    }
    return Row(
      children: <Widget>[
        Text(
          '$files ${files == 1 ? 'file' : 'files'}',
          style: AppTextStyles.caption,
        ),
        const SizedBox(width: AppSpacing.lg),
        _stat(
          context,
          Icons.check_circle,
          controller.successCount,
          Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: AppSpacing.md),
        _stat(
          context,
          Icons.error_outline,
          controller.failureCount,
          Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: AppSpacing.md),
        _stat(
          context,
          Icons.skip_next,
          controller.skippedCount,
          mutedColor(context),
        ),
        if (controller.lossyCount > 0) ...<Widget>[
          const SizedBox(width: AppSpacing.md),
          _stat(
            context,
            Icons.warning_amber_outlined,
            controller.lossyCount,
            Theme.of(context).colorScheme.tertiary,
          ),
        ],
      ],
    );
  }

  Widget _stat(BuildContext context, IconData icon, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text('$count', style: AppTextStyles.caption),
      ],
    );
  }
}
