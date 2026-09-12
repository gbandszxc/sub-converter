import 'package:collection/collection.dart';

/// A named text style, as used by ASS/SSA (`[V4+ Styles]`) and, in a reduced
/// form, by VTT (`STYLE` blocks) and SRT (no styles at all).
///
/// The model keeps style data as the source format spelled it. v0.1 never
/// edits styles, so preserving the raw field map is both simpler and lossless
/// for ASS/SSA round-trips.
class SubtitleStyle {
  SubtitleStyle({
    required this.name,
    Map<String, String>? fields,
  }) : fields = fields ?? <String, String>{};

  /// Style name, e.g. `Default`. Unique within a document.
  String name;

  /// Format-native field name to value, e.g. `Fontname` -> `Arial`.
  ///
  /// Keys keep their original casing so ASS/SSA output stays byte-comparable.
  Map<String, String> fields;

  /// Case-insensitive lookup of a raw field.
  String? field(String key) {
    final String? direct = fields[key];
    if (direct != null) {
      return direct;
    }
    final String lower = key.toLowerCase();
    for (final MapEntry<String, String> entry in fields.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  double? numericField(String key) => double.tryParse(field(key)?.trim() ?? '');

  bool get isEmpty => name.isEmpty && fields.isEmpty;

  SubtitleStyle copy() => SubtitleStyle(name: name, fields: Map<String, String>.of(fields));

  @override
  bool operator ==(Object other) =>
      other is SubtitleStyle &&
      other.name == name &&
      const MapEquality<String, String>().equals(other.fields, fields);

  @override
  int get hashCode => Object.hash(name, const MapEquality<String, String>().hash(fields));

  @override
  String toString() => 'SubtitleStyle($name, ${fields.length} fields)';
}
