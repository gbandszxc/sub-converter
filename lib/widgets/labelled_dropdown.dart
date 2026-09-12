import 'package:flutter/material.dart';

import 'ui_constants.dart';

/// A compact section label plus a full-width dropdown.
class LabelledDropdown<T> extends StatelessWidget {
  const LabelledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Optional one-line explanation shown under the dropdown.
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
        if (helperText != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            helperText!,
            style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
          ),
        ],
      ],
    );
  }
}
