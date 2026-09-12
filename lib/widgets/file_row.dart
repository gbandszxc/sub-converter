import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/app_strings.dart';
import '../models/conversion_job.dart';
import '../models/loss_report.dart';
import '../models/subtitle_exception.dart';
import '../screens/app_controller.dart';
import 'format_chip.dart';
import 'ui_constants.dart';

/// A single dense file row: status, name, detected format, result, remove.
class FileRow extends StatelessWidget {
  const FileRow({super.key, required this.controller, required this.entry});

  final AppController controller;
  final SubtitleFileEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 20, height: 20, child: _statusIcon(context)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _details(context, strings)),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: strings.remove,
            onPressed: controller.isConverting
                ? null
                : () => controller.removeEntry(entry),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context, AppStrings strings) {
    final List<Widget> lines = <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              entry.fileName,
              style: AppTextStyles.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FormatChip(entry: entry),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        entry.folder,
        style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 2),
      ..._statusLines(context, strings),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  List<Widget> _statusLines(BuildContext context, AppStrings strings) {
    final ConversionResult? result = entry.result;
    final List<Widget> lines = <Widget>[
      Text(
        _primaryStatus(result, strings),
        style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ];

    final String? secondary = _secondaryStatus(result, strings);
    if (secondary != null) {
      lines.add(
        Text(
          secondary,
          style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (result?.isLossy ?? false) {
      lines.add(_lossyNotice(context, strings, result!));
    }
    return lines;
  }

  Widget _lossyNotice(
    BuildContext context,
    AppStrings strings,
    ConversionResult result,
  ) {
    final Color color = Theme.of(context).colorScheme.tertiary;
    final String target = result.targetFormat?.label ?? strings.unknown;
    final String tooltip = result.warnings
        .map(
          (LossWarning warning) => strings.lossWarning(
            warning.kind,
            targetFormat: target,
            count: warning.count,
          ),
        )
        .join('\n');
    return Tooltip(
      message: tooltip,
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_outlined, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              strings.lossyNotice,
              style: AppTextStyles.caption.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _primaryStatus(ConversionResult? result, AppStrings strings) {
    switch (entry.status) {
      case ConversionStatus.pending:
        return entry.isInspecting ? strings.inspecting : strings.ready;
      case ConversionStatus.converting:
        return strings.converting;
      case ConversionStatus.succeeded:
        return strings.convertedTo(
          result?.targetFormat?.label ?? strings.unknown,
        );
      case ConversionStatus.failed:
        return strings.failureTitle(
          result?.failure ?? ConversionFailure.unknown,
        );
      case ConversionStatus.skipped:
        return strings.skippedExisting;
    }
  }

  String? _secondaryStatus(ConversionResult? result, AppStrings strings) {
    if (result == null) {
      return null;
    }
    if (result.isFailure) {
      // The localized title already explains most failures. Only these carry
      // a path or file name the user needs to act on, and paths are
      // language-neutral, so the English technical detail is shown for them
      // and omitted for every other kind.
      const Set<ConversionFailure> pathBearingFailures = <ConversionFailure>{
        ConversionFailure.readFailed,
        ConversionFailure.cannotWriteOutput,
        ConversionFailure.permissionDenied,
        ConversionFailure.targetPathUnavailable,
      };
      final ConversionFailure? failure = result.failure;
      if (failure == null || !pathBearingFailures.contains(failure)) {
        return null;
      }
      final String? detail = result.detail;
      return detail == null || detail.isEmpty ? null : detail;
    }
    if (result.isSuccess && result.outputPath != null) {
      final String name = p.basename(result.outputPath!);
      // A rename is not information loss, so it is a quiet note here rather
      // than part of the lossy affordance.
      return result.outputRenamed ? strings.renamedNote(name) : name;
    }
    return null;
  }

  Widget _statusIcon(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    switch (entry.status) {
      case ConversionStatus.pending:
        if (entry.inspectionError != null) {
          return Icon(Icons.help_outline, size: 18, color: scheme.error);
        }
        return Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant);
      case ConversionStatus.converting:
        return const CircularProgressIndicator(strokeWidth: 2);
      case ConversionStatus.succeeded:
        return Icon(Icons.check_circle, size: 18, color: scheme.primary);
      case ConversionStatus.failed:
        return Icon(Icons.error_outline, size: 18, color: scheme.error);
      case ConversionStatus.skipped:
        return Icon(Icons.skip_next, size: 18, color: scheme.onSurfaceVariant);
    }
  }
}
