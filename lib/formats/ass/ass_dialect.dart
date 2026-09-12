import '../../models/subtitle_format.dart';

/// The two members of the SubStation Alpha family.
///
/// ASS (`Advanced SubStation Alpha`, `[V4+ Styles]`) and SSA (`SubStation
/// Alpha`, `[V4 Styles]`) share almost all of their grammar: identical
/// section layout, identical `Dialogue:` event lines and identical override
/// tags. They differ only in a handful of constants (section name, script
/// type, style/event field lists and script resolution defaults).
///
/// Everything shared lives behind this enum so ASS and SSA never duplicate
/// parsing or writing logic.
enum AssDialect {
  ass(
    format: SubtitleFormat.ass,
    stylesSection: '[V4+ Styles]',
    scriptType: 'v4.00+',
  ),
  ssa(
    format: SubtitleFormat.ssa,
    stylesSection: '[V4 Styles]',
    scriptType: 'v4.00',
  );

  const AssDialect({
    required this.format,
    required this.stylesSection,
    required this.scriptType,
  });

  /// The unified format this dialect maps to.
  final SubtitleFormat format;

  /// Canonical style section header, brackets included.
  final String stylesSection;

  /// Canonical `ScriptType` value.
  final String scriptType;
}

/// Canonical ASS (`v4.00+`) style fields, in order.
const List<String> assStyleFields = <String>[
  'Name',
  'Fontname',
  'Fontsize',
  'PrimaryColour',
  'SecondaryColour',
  'OutlineColour',
  'BackColour',
  'Bold',
  'Italic',
  'Underline',
  'StrikeOut',
  'ScaleX',
  'ScaleY',
  'Spacing',
  'Angle',
  'BorderStyle',
  'Outline',
  'Shadow',
  'Alignment',
  'MarginL',
  'MarginR',
  'MarginV',
  'Encoding',
];

/// Canonical SSA (`v4.00`) style fields, in order.
///
/// SSA has no `OutlineColour` (it is `TertiaryColour`), no `Underline` /
/// `StrikeOut` / `ScaleX` / `ScaleY` / `Spacing` / `Angle`, and instead
/// carries `AlphaLevel`.
const List<String> ssaStyleFields = <String>[
  'Name',
  'Fontname',
  'Fontsize',
  'PrimaryColour',
  'SecondaryColour',
  'TertiaryColour',
  'BackColour',
  'Bold',
  'Italic',
  'BorderStyle',
  'Outline',
  'Shadow',
  'Alignment',
  'MarginL',
  'MarginR',
  'MarginV',
  'AlphaLevel',
  'Encoding',
];

/// Canonical ASS event fields, in order. `Text` is always last.
const List<String> assEventFields = <String>[
  'Layer',
  'Start',
  'End',
  'Style',
  'Name',
  'MarginL',
  'MarginR',
  'MarginV',
  'Effect',
  'Text',
];

/// Canonical SSA event fields, in order. `Text` is always last.
const List<String> ssaEventFields = <String>[
  'Marked',
  'Start',
  'End',
  'Style',
  'Name',
  'MarginL',
  'MarginR',
  'MarginV',
  'Effect',
  'Text',
];

/// Dialect-dependent canonical field lists.
extension AssDialectFields on AssDialect {
  List<String> get styleFields =>
      this == AssDialect.ass ? assStyleFields : ssaStyleFields;

  List<String> get eventFields =>
      this == AssDialect.ass ? assEventFields : ssaEventFields;

  /// Name of the event field that carries the layer/marked flag.
  String get layerField => this == AssDialect.ass ? 'Layer' : 'Marked';
}

/// Named constants for canonical section headers.
abstract final class AssSections {
  static const String scriptInfo = 'Script Info';
  static const String events = 'Events';
}

/// Named constants for canonical line prefixes.
abstract final class AssLinePrefixes {
  static const String format = 'Format';
  static const String style = 'Style';
  static const String dialogue = 'Dialogue';
}

/// Named constants for `[Script Info]` keys and default values.
abstract final class AssScriptInfo {
  static const String scriptType = 'ScriptType';
  static const String title = 'Title';

  static const String wrapStyleKey = 'WrapStyle';
  static const String wrapStyleValue = '0';

  static const String scaledBorderAndShadowKey = 'ScaledBorderAndShadow';
  static const String scaledBorderAndShadowValue = 'yes';

  static const String playResXKey = 'PlayResX';
  static const String playResYKey = 'PlayResY';

  /// ASS default script resolution.
  static const String assPlayResX = '1920';
  static const String assPlayResY = '1080';

  /// SSA default script resolution.
  static const String ssaPlayResX = '384';
  static const String ssaPlayResY = '288';
}

/// Per-field fallbacks for styles a document does not fully specify.
///
/// Every value is a named constant so writers never sprout inline literals.
abstract final class AssStyleDefaults {
  static const String defaultStyleName = 'Default';

  static const String fontName = 'Arial';
  static const String fontSize = '20';

  static const String primaryColour = '&H00FFFFFF';
  static const String secondaryColour = '&H000000FF';
  static const String outlineColour = '&H00000000';
  static const String tertiaryColour = '&H00000000';
  static const String backColour = '&H00000000';

  static const String bold = '0';
  static const String italic = '0';
  static const String underline = '0';
  static const String strikeOut = '0';

  static const String scaleX = '100';
  static const String scaleY = '100';
  static const String spacing = '0';
  static const String angle = '0';

  static const String borderStyle = '1';
  static const String outline = '2';
  static const String shadow = '0';

  static const String alignment = '2';

  static const String marginL = '10';
  static const String marginR = '10';
  static const String marginV = '10';

  static const String alphaLevel = '0';
  static const String encoding = '1';

  /// Case-insensitive field name to fallback value.
  static const Map<String, String> byField = <String, String>{
    'name': defaultStyleName,
    'fontname': fontName,
    'fontsize': fontSize,
    'primarycolour': primaryColour,
    'secondarycolour': secondaryColour,
    'outlinecolour': outlineColour,
    'tertiarycolour': tertiaryColour,
    'backcolour': backColour,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'strikeout': strikeOut,
    'scalex': scaleX,
    'scaley': scaleY,
    'spacing': spacing,
    'angle': angle,
    'borderstyle': borderStyle,
    'outline': outline,
    'shadow': shadow,
    'alignment': alignment,
    'marginl': marginL,
    'marginr': marginR,
    'marginv': marginV,
    'alphalevel': alphaLevel,
    'encoding': encoding,
  };

  /// Fallback for [field], or `'0'` for a field the model does not know.
  static String valueFor(String field) => byField[field.toLowerCase()] ?? '0';
}
