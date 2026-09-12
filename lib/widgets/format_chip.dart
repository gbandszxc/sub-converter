import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';
import '../models/subtitle_format.dart';
import '../screens/app_controller.dart';
import 'ui_constants.dart';

/// Detected format plus encoding, or a placeholder while inspecting.
class FormatChip extends StatelessWidget {
  const FormatChip({super.key, required this.entry});

  final SubtitleFileEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool unknown = entry.detectedFormat == null && !entry.isInspecting;
    final Color background = unknown
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final Color foreground = unknown
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    final String tooltip;
    if (entry.inspectionError != null) {
      tooltip = strings.failureTitle(entry.inspectionError!);
    } else if (entry.detectedFormat != null) {
      tooltip = strings.formatDescription(entry.detectedFormat!);
    } else {
      tooltip = '';
    }

    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            ),
            child: Text(
              _label(strings),
              style: AppTextStyles.caption.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (entry.encodingName != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Text(
              entry.encodingName!,
              style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
            ),
          ],
        ],
      ),
    );
  }

  String _label(AppStrings strings) {
    if (entry.isInspecting) {
      return '...';
    }
    final SubtitleFormat? format = entry.detectedFormat;
    return format?.label ?? strings.unknown;
  }
}
