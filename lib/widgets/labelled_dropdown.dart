import 'package:flutter/material.dart';

import 'section_label.dart';
import 'ui_constants.dart';

/// A compact section label plus a full-width dropdown.
class LabelledDropdown<T> extends StatelessWidget {
  const LabelledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helpText,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Optional explanation shown on hover, on an info icon next to [label].
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(label, tooltip: helpText),
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
      ],
    );
  }
}
