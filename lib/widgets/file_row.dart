import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/conversion_job.dart';
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
          Expanded(child: _details(context)),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            onPressed: controller.isConverting
                ? null
                : () => controller.removeEntry(entry),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
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
      ..._statusLines(context),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  List<Widget> _statusLines(BuildContext context) {
    final ConversionResult? result = entry.result;
    final List<Widget> lines = <Widget>[
      Text(
        _primaryStatus(result),
        style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ];

    final String? secondary = _secondaryStatus(result);
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
      lines.add(_lossyNotice(context, result!.warnings));
    }
    return lines;
  }

  Widget _lossyNotice(BuildContext context, List<String> warnings) {
    final Color color = Theme.of(context).colorScheme.tertiary;
    return Tooltip(
      message: warnings.join('\n'),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_outlined, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              lossyNotice,
              style: AppTextStyles.caption.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _primaryStatus(ConversionResult? result) {
    switch (entry.status) {
      case ConversionStatus.pending:
        return entry.isInspecting ? 'Inspecting...' : 'Ready';
      case ConversionStatus.converting:
        return 'Converting...';
      case ConversionStatus.succeeded:
        return 'Converted to ${result?.targetFormat?.label ?? '?'}';
      case ConversionStatus.failed:
        return result?.failure?.title ?? 'Conversion failed';
      case ConversionStatus.skipped:
        return result?.detail ?? 'Skipped: output file already exists';
    }
  }

  String? _secondaryStatus(ConversionResult? result) {
    if (result == null) {
      return null;
    }
    if (result.isFailure) {
      final String? detail = result.detail;
      return detail == null || detail.isEmpty ? null : detail;
    }
    if (result.isSuccess && result.outputPath != null) {
      return p.basename(result.outputPath!);
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
