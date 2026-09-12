import 'package:flutter/material.dart';

import 'ui_constants.dart';

/// Section title with an optional hover tooltip for a longer explanation.
///
/// Desktop hints live in tooltips instead of caption lines below the control,
/// which keeps the panel compact; the icon next to the title is the hover
/// target. Without a [tooltip] this renders the plain title.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.tooltip});

  final String text;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final String? tooltip = this.tooltip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(text, style: AppTextStyles.sectionTitle),
        if (tooltip != null && tooltip.trim().isNotEmpty) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          Tooltip(
            message: tooltip,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.help_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
