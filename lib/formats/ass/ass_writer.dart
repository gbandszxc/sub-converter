import '../../models/subtitle_codec.dart';
import '../../models/subtitle_cue.dart';
import '../../models/subtitle_document.dart';
import '../../models/subtitle_style.dart';
import '../../utils/subtitle_defaults.dart';
import '../../utils/timestamp.dart';
import 'ass_dialect.dart';
import 'ass_text_codec.dart';

/// Writer shared by ASS and SSA.
///
/// The two dialects differ only in constants, so this single class is
/// parameterised by [AssDialect]; `SsaWriter` is a thin subclass that fixes
/// the dialect to [AssDialect.ssa]. Output uses LF line endings and ends with
/// exactly one trailing newline.
///
/// The writer is deliberately lossy: it emits only what the unified model
/// carries. Dropped ASS/SSA features are:
/// * karaoke timing (`\k`, `\K`, `\kf`, `\ko`),
/// * animation and transforms (`\t`, `\move`, `\fad`, `\fade`, `\org`,
///   `\clip`, rotation, blur, shadow, borders),
/// * vector drawing (`\p1` / `\p0`),
/// * inline colour and font overrides (`\c`, `\1c`..`\4c`, `\alpha`, `\fs`,
///   `\fn`, ...),
/// * embedded fonts (`[Fonts]`) and graphics (`[Graphics]`),
/// * non-`Dialogue` event types (`Comment`, `Picture`, `Sound`, `Movie`,
///   `Command`).
///
/// Cues with empty or whitespace-only text are skipped because players treat
/// them as invisible.
class AssWriter implements SubtitleWriter {
  AssWriter([this.dialect = AssDialect.ass]);

  /// Which member of the ASS family this writer emits.
  final AssDialect dialect;

  @override
  String write(SubtitleDocument document) {
    // Never mutate the caller's document; fill in LRC-style missing ends.
    final SubtitleDocument resolved = document.resolveMissingEndTimes(
      fallback: SubtitleDefaults.lrcEndTimeFallback,
    );

    final StringBuffer output = StringBuffer();
    _writeScriptInfo(output, resolved.metadata);
    output.write('\n');
    _writeStyles(output, resolved.styles);
    output.write('\n');
    _writeEvents(output, resolved.cues);
    return output.toString();
  }

  void _writeScriptInfo(StringBuffer output, SubtitleMetadata metadata) {
    final Set<String> emitted = <String>{};
    _writeLine(output, AssSections.scriptInfo, wrapInBrackets: true);
    _writeLine(output, '${AssScriptInfo.scriptType}: ${dialect.scriptType}');
    emitted.add(AssScriptInfo.scriptType.toLowerCase());

    final String title =
        metadata.title ?? metadata.field(AssScriptInfo.title) ?? '';
    _writeLine(output, '${AssScriptInfo.title}: $title');
    emitted.add(AssScriptInfo.title.toLowerCase());

    for (final MapEntry<String, String> entry in metadata.fields.entries) {
      final String key = entry.key.toLowerCase();
      if (emitted.contains(key) || entry.key.trim().isEmpty) {
        continue;
      }
      _writeLine(output, '${entry.key}: ${entry.value}');
      emitted.add(key);
    }

    final String playResX = dialect == AssDialect.ass
        ? AssScriptInfo.assPlayResX
        : AssScriptInfo.ssaPlayResX;
    final String playResY = dialect == AssDialect.ass
        ? AssScriptInfo.assPlayResY
        : AssScriptInfo.ssaPlayResY;

    _writeDefault(
      output,
      emitted,
      AssScriptInfo.wrapStyleKey,
      AssScriptInfo.wrapStyleValue,
    );
    _writeDefault(
      output,
      emitted,
      AssScriptInfo.scaledBorderAndShadowKey,
      AssScriptInfo.scaledBorderAndShadowValue,
    );
    _writeDefault(output, emitted, AssScriptInfo.playResXKey, playResX);
    _writeDefault(output, emitted, AssScriptInfo.playResYKey, playResY);
  }

  void _writeDefault(
    StringBuffer output,
    Set<String> emitted,
    String key,
    String value,
  ) {
    if (emitted.contains(key.toLowerCase())) {
      return;
    }
    _writeLine(output, '$key: $value');
    emitted.add(key.toLowerCase());
  }

  void _writeStyles(StringBuffer output, List<SubtitleStyle> styles) {
    _writeLine(output, dialect.stylesSection);
    final List<String> fields = dialect.styleFields;
    _writeLine(output, '${AssLinePrefixes.format}: ${fields.join(', ')}');

    final List<SubtitleStyle> effective = styles.isEmpty
        ? <SubtitleStyle>[
            SubtitleStyle(name: AssStyleDefaults.defaultStyleName),
          ]
        : styles;

    for (final SubtitleStyle style in effective) {
      final List<String> values = <String>[
        for (final String field in fields) _styleValue(style, field),
      ];
      _writeLine(output, '${AssLinePrefixes.style}: ${values.join(',')}');
    }
  }

  String _styleValue(SubtitleStyle style, String field) {
    if (field.toLowerCase() == 'name') {
      return style.name.isEmpty
          ? AssStyleDefaults.defaultStyleName
          : style.name;
    }
    return style.field(field) ?? AssStyleDefaults.valueFor(field);
  }

  void _writeEvents(StringBuffer output, List<SubtitleCue> cues) {
    _writeLine(output, AssSections.events, wrapInBrackets: true);
    final List<String> fields = dialect.eventFields;
    _writeLine(output, '${AssLinePrefixes.format}: ${fields.join(', ')}');

    for (final SubtitleCue cue in cues) {
      if (!cue.hasVisibleText) {
        continue;
      }
      final Duration end = cue.end ?? cue.start;
      final String startText = formatTimestamp(
        cue.start,
        fractionDigits: 2,
        hourDigits: 1,
      );
      final String endText = formatTimestamp(
        end,
        fractionDigits: 2,
        hourDigits: 1,
      );
      final String text = AssTextCodec.render(
        cue.text,
        cue.inlineStyles,
        position: cue.position,
      );

      final Map<String, String> values = <String, String>{
        'Start': startText,
        'End': endText,
        'Style': _styleRefValue(cue),
        'Name': _metaValue(cue, 'Name') ?? '',
        'MarginL': _numericMeta(cue, 'MarginL'),
        'MarginR': _numericMeta(cue, 'MarginR'),
        'MarginV': _numericMeta(cue, 'MarginV'),
        'Effect': _metaValue(cue, 'Effect') ?? '',
        'Text': text,
      };

      final String layerField = dialect.layerField;
      final String alternateLayerField = dialect == AssDialect.ass
          ? 'Marked'
          : 'Layer';
      values[layerField] = _layerValue(
        _metaValue(cue, layerField) ?? _metaValue(cue, alternateLayerField),
      );

      final String line = fields
          .map((String field) => values[field] ?? '')
          .join(',');
      _writeLine(output, '${AssLinePrefixes.dialogue}: $line');
    }
  }

  String _styleRefValue(SubtitleCue cue) {
    final String? reference = cue.styleRef?.trim();
    if (reference == null || reference.isEmpty) {
      return AssStyleDefaults.defaultStyleName;
    }
    return reference;
  }

  /// SSA conventionally writes the marked flag as `Marked=0`.
  String _layerValue(String? raw) {
    if (raw == null || raw.isEmpty) {
      return dialect == AssDialect.ssa ? 'Marked=0' : '0';
    }
    if (dialect == AssDialect.ssa &&
        !raw.contains('=') &&
        int.tryParse(raw.trim()) != null) {
      return 'Marked=$raw';
    }
    return raw;
  }

  String _numericMeta(SubtitleCue cue, String key) {
    final String? value = _metaValue(cue, key);
    return value == null || value.isEmpty ? '0' : value;
  }

  static String? _metaValue(SubtitleCue cue, String key) {
    final String lower = key.toLowerCase();
    for (final MapEntry<String, Object?> entry in cue.metadata.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value?.toString();
      }
    }
    return null;
  }

  static void _writeLine(
    StringBuffer output,
    String line, {
    bool wrapInBrackets = false,
  }) {
    if (wrapInBrackets) {
      output.write('[$line]\n');
    } else {
      output.write('$line\n');
    }
  }
}
