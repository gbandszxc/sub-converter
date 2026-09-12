import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import '../screens/app_controller.dart';
import 'file_row.dart';
import 'ui_constants.dart';

/// Scrollable list of added files, or the empty drop-zone prompt.
class FileListView extends StatelessWidget {
  const FileListView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final List<SubtitleFileEntry> entries = controller.entries;
    if (entries.isEmpty) {
      return const _EmptyDropHint();
    }
    return Scrollbar(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) =>
            FileRow(controller: controller, entry: entries[index]),
      ),
    );
  }
}

class _EmptyDropHint extends StatelessWidget {
  const _EmptyDropHint();

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.file_download_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            strings.emptyTitle,
            style: AppTextStyles.bodyStrong.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            strings.emptySubtitle,
            style: AppTextStyles.caption.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
