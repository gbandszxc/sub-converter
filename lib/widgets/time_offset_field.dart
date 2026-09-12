import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_strings.dart';
import '../screens/app_controller.dart';
import '../utils/subtitle_defaults.dart';
import 'section_label.dart';
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

  /// Tracks focus so an offset changed elsewhere never overwrites what the
  /// user is in the middle of typing.
  final FocusNode _focusNode = FocusNode();

  static final ButtonStyle _stepButtonStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    textStyle: AppTextStyles.caption,
  );

  int get _step => SubtitleDefaults.timeOffsetStep.inMilliseconds;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromOptions);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(TimeOffsetField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromOptions);
      widget.controller.addListener(_syncFromOptions);
      _syncFromOptions();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromOptions);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Mirrors an offset set outside this field, which is what happens when
  /// persisted settings finish loading after the first build.
  void _syncFromOptions() {
    if (_focusNode.hasFocus) {
      return;
    }
    final String value = widget.controller.options.timeOffset.inMilliseconds
        .toString();
    if (_text.text != value) {
      _text.text = value;
      _text.selection = TextSelection.collapsed(offset: value.length);
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Drop an incomplete value such as a lone '-' when focus leaves.
      _syncFromOptions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(strings.timeOffset, tooltip: strings.timeOffsetHint),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child: TextField(
                controller: _text,
                focusNode: _focusNode,
                style: AppTextStyles.body,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                // Digits and a minus sign only; onChanged ignores anything that
                // does not parse, so a half-typed value is never applied.
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
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
              tooltip: strings.resetOffset,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _setOffset(0),
              icon: const Icon(Icons.restart_alt, size: 18),
            ),
          ],
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
