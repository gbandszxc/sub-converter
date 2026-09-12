import 'package:flutter/material.dart';

import '../models/conversion_job.dart';
import '../models/subtitle_format.dart';
import '../screens/app_controller.dart';
import 'labelled_dropdown.dart';
import 'time_offset_field.dart';
import 'ui_constants.dart';

/// Right-hand panel with everything that controls a conversion run.
class OptionsPanel extends StatelessWidget {
  const OptionsPanel({
    super.key,
    required this.controller,
    required this.onChooseDirectory,
    required this.onConvert,
  });

  final AppController controller;
  final VoidCallback onChooseDirectory;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _targetFormat(context),
          const SizedBox(height: AppSpacing.lg),
          _outputLocation(context),
          const SizedBox(height: AppSpacing.lg),
          _conflictPolicy(context),
          const SizedBox(height: AppSpacing.lg),
          TimeOffsetField(controller: controller),
          const SizedBox(height: AppSpacing.md),
          _bomCheckbox(context),
          const SizedBox(height: AppSpacing.lg),
          _convertButton(context),
        ],
      ),
    );
  }

  Widget _sectionText(BuildContext context, String text) =>
      Text(text, style: AppTextStyles.sectionTitle);

  Widget _targetFormat(BuildContext context) {
    return LabelledDropdown<SubtitleFormat>(
      label: 'Target format',
      value: controller.options.targetFormat,
      items: SubtitleFormat.values
          .map(
            (SubtitleFormat format) => DropdownMenuItem<SubtitleFormat>(
              value: format,
              child: Text(
                '${format.label} · ${format.description}',
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body,
              ),
            ),
          )
          .toList(),
      onChanged: (SubtitleFormat? format) {
        if (format != null) {
          controller.setTargetFormat(format);
        }
      },
    );
  }

  Widget _outputLocation(BuildContext context) {
    final ConversionOptions options = controller.options;
    final bool isCustom =
        options.outputLocation == OutputLocation.customDirectory;
    final String? validationError = options.validationError();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionText(context, 'Output'),
        RadioGroup<OutputLocation>(
          groupValue: options.outputLocation,
          onChanged: (OutputLocation? location) {
            if (location != null) {
              controller.setOutputLocation(location);
            }
          },
          child: Column(
            children: OutputLocation.values
                .map(
                  (OutputLocation location) => RadioListTile<OutputLocation>(
                    value: location,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    title: Text(location.label, style: AppTextStyles.body),
                  ),
                )
                .toList(),
          ),
        ),
        if (isCustom) ...<Widget>[
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: onChooseDirectory,
                child: const Text('Choose...'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  options.outputDirectory ?? 'No folder chosen',
                  style: AppTextStyles.caption.copyWith(
                    color: mutedColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                validationError,
                style: AppTextStyles.caption.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _conflictPolicy(BuildContext context) {
    return LabelledDropdown<OutputConflictPolicy>(
      label: 'Conflict',
      value: controller.options.conflictPolicy,
      helperText: _conflictExplanation(controller.options.conflictPolicy),
      items: OutputConflictPolicy.values
          .map(
            (OutputConflictPolicy policy) =>
                DropdownMenuItem<OutputConflictPolicy>(
                  value: policy,
                  child: Text(policy.label, style: AppTextStyles.body),
                ),
          )
          .toList(),
      onChanged: (OutputConflictPolicy? policy) {
        if (policy != null) {
          controller.setConflictPolicy(policy);
        }
      },
    );
  }

  String _conflictExplanation(OutputConflictPolicy policy) {
    switch (policy) {
      case OutputConflictPolicy.autoRename:
        return 'Write a numbered file instead of replacing an existing one.';
      case OutputConflictPolicy.overwrite:
        return 'Replace an existing output file.';
      case OutputConflictPolicy.skip:
        return 'Leave an existing output file and skip the entry.';
    }
  }

  Widget _bomCheckbox(BuildContext context) {
    return CheckboxListTile(
      value: controller.options.writeUtf8Bom,
      onChanged: (bool? value) => controller.setWriteUtf8Bom(value ?? false),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text('Write UTF-8 BOM', style: AppTextStyles.body),
    );
  }

  Widget _convertButton(BuildContext context) {
    final int count = controller.fileCount;
    final String label = count == 0
        ? 'Convert'
        : 'Convert $count ${count == 1 ? 'file' : 'files'}';
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: controller.canConvert ? onConvert : null,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text(label),
      ),
    );
  }
}
