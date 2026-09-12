import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/app_controller.dart';
import '../utils/subtitle_defaults.dart';
import 'ui_constants.dart';

/// Millisecond offset control with stepped buttons and a reset.
class TimeOffsetField extends StatefulWidget {
  const TimeOffsetField({super.key, required this.controller});

  final AppController controller;

  @override
  State<TimeOffsetField> createState() => _TimeOffsetFieldState();
}

class _TimeOffsetFieldState extends State<TimeOffsetField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.options.timeOffset.inMilliseconds.toString(),
  );

  static final ButtonStyle _stepButtonStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    textStyle: AppTextStyles.caption,
  );

  int get _step => SubtitleDefaults.timeOffsetStep.inMilliseconds;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Time offset', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child: TextField(
                controller: _text,
                style: AppTextStyles.body,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  suffixText: 'ms',
                  suffixStyle: AppTextStyles.caption,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            OutlinedButton(
              style: _stepButtonStyle,
              onPressed: () => _nudge(-_step),
              child: Text('-$_step ms'),
            ),
            const SizedBox(width: AppSpacing.xs),
            OutlinedButton(
              style: _stepButtonStyle,
              onPressed: () => _nudge(_step),
              child: Text('+$_step ms'),
            ),
            IconButton(
              tooltip: 'Reset offset',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _setOffset(0),
              icon: const Icon(Icons.restart_alt, size: 18),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Negative values move cues earlier; timestamps are clamped at zero.',
          style: AppTextStyles.caption.copyWith(color: mutedColor(context)),
        ),
      ],
    );
  }

  void _onChanged(String raw) {
    final int? value = int.tryParse(raw.trim());
    if (value == null) {
      return;
    }
    widget.controller.setTimeOffset(Duration(milliseconds: value));
  }

  void _nudge(int delta) {
    _setOffset(widget.controller.options.timeOffset.inMilliseconds + delta);
  }

  void _setOffset(int milliseconds) {
    _text.text = milliseconds.toString();
    widget.controller.setTimeOffset(Duration(milliseconds: milliseconds));
  }
}
