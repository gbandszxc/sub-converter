import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../i18n/app_strings.dart';
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
    final AppStrings strings = AppStrings.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _targetFormat(context, strings),
          const SizedBox(height: AppSpacing.lg),
          _outputLocation(context, strings),
          const SizedBox(height: AppSpacing.lg),
          _conflictPolicy(context, strings),
          const SizedBox(height: AppSpacing.lg),
          TimeOffsetField(controller: controller),
          const SizedBox(height: AppSpacing.md),
          _bomCheckbox(context, strings),
          const SizedBox(height: AppSpacing.lg),
          _language(context, strings),
          const SizedBox(height: AppSpacing.lg),
          _convertButton(context, strings),
        ],
      ),
    );
  }

  Widget _sectionText(String text) =>
      Text(text, style: AppTextStyles.sectionTitle);

  Widget _targetFormat(BuildContext context, AppStrings strings) {
    return LabelledDropdown<SubtitleFormat>(
      label: strings.targetFormat,
      value: controller.options.targetFormat,
      items: SubtitleFormat.values
          .map(
            (SubtitleFormat format) => DropdownMenuItem<SubtitleFormat>(
              value: format,
              child: Text(
                '${format.label} · ${strings.formatDescription(format)}',
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

  Widget _outputLocation(BuildContext context, AppStrings strings) {
    final ConversionOptions options = controller.options;
    final bool isCustom =
        options.outputLocation == OutputLocation.customDirectory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionText(strings.output),
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
                    title: Text(
                      _outputLocationLabel(strings, location),
                      style: AppTextStyles.body,
                    ),
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
                child: Text(strings.choose),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  options.outputDirectory ?? strings.noFolderChosen,
                  style: AppTextStyles.caption.copyWith(
                    color: mutedColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (options.isOutputDirectoryMissing)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                strings.chooseFolderError,
                style: AppTextStyles.caption.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _outputLocationLabel(AppStrings strings, OutputLocation location) {
    switch (location) {
      case OutputLocation.sourceDirectory:
        return strings.outputSourceFolder;
      case OutputLocation.customDirectory:
        return strings.outputCustomFolder;
    }
  }

  Widget _conflictPolicy(BuildContext context, AppStrings strings) {
    return LabelledDropdown<OutputConflictPolicy>(
      label: strings.conflict,
      value: controller.options.conflictPolicy,
      helperText: _conflictExplanation(
        strings,
        controller.options.conflictPolicy,
      ),
      items: OutputConflictPolicy.values
          .map(
            (OutputConflictPolicy policy) =>
                DropdownMenuItem<OutputConflictPolicy>(
                  value: policy,
                  child: Text(
                    _conflictLabel(strings, policy),
                    style: AppTextStyles.body,
                  ),
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

  String _conflictLabel(AppStrings strings, OutputConflictPolicy policy) {
    switch (policy) {
      case OutputConflictPolicy.autoRename:
        return strings.conflictAutoRename;
      case OutputConflictPolicy.overwrite:
        return strings.conflictOverwrite;
      case OutputConflictPolicy.skip:
        return strings.conflictSkip;
    }
  }

  String _conflictExplanation(AppStrings strings, OutputConflictPolicy policy) {
    switch (policy) {
      case OutputConflictPolicy.autoRename:
        return strings.conflictAutoRenameHelp;
      case OutputConflictPolicy.overwrite:
        return strings.conflictOverwriteHelp;
      case OutputConflictPolicy.skip:
        return strings.conflictSkipHelp;
    }
  }

  Widget _bomCheckbox(BuildContext context, AppStrings strings) {
    return CheckboxListTile(
      value: controller.options.writeUtf8Bom,
      onChanged: (bool? value) => controller.setWriteUtf8Bom(value ?? false),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(strings.writeBom, style: AppTextStyles.body),
    );
  }

  Widget _language(BuildContext context, AppStrings strings) {
    return LabelledDropdown<AppLanguage>(
      label: strings.language,
      value: controller.language,
      items: AppLanguage.values
          .map(
            (AppLanguage language) => DropdownMenuItem<AppLanguage>(
              value: language,
              child: Text(
                _languageLabel(strings, language),
                style: AppTextStyles.body,
              ),
            ),
          )
          .toList(),
      onChanged: (AppLanguage? language) {
        if (language != null) {
          controller.setLanguage(language);
        }
      },
    );
  }

  String _languageLabel(AppStrings strings, AppLanguage language) {
    switch (language) {
      case AppLanguage.system:
        return strings.languageSystem;
      case AppLanguage.english:
        return strings.languageEnglish;
      case AppLanguage.chinese:
        return strings.languageChinese;
    }
  }

  Widget _convertButton(BuildContext context, AppStrings strings) {
    final int count = controller.fileCount;
    final String label = count == 0
        ? strings.convert
        : strings.convertWithCount(count);
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
