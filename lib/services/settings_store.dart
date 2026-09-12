import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistence seam for user settings.
///
/// The UI only ever talks to this interface, so widget tests can supply
/// [InMemorySettingsStore] and never touch a platform channel.
abstract interface class SettingsStore {
  /// Reads every persisted value. Keys that were never written are absent.
  Future<Map<String, Object?>> load();

  /// Replaces the persisted values with [values].
  Future<void> save(Map<String, Object?> values);
}

/// [SettingsStore] backed by the platform's shared preferences.
class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore();

  @override
  Future<Map<String, Object?>> load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return <String, Object?>{
      for (final String key in preferences.getKeys()) key: preferences.get(key),
    };
  }

  @override
  Future<void> save(Map<String, Object?> values) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    for (final MapEntry<String, Object?> entry in values.entries) {
      final Object? value = entry.value;
      if (value == null) {
        await preferences.remove(entry.key);
      } else if (value is int) {
        await preferences.setInt(entry.key, value);
      } else if (value is double) {
        await preferences.setDouble(entry.key, value);
      } else if (value is bool) {
        await preferences.setBool(entry.key, value);
      } else {
        await preferences.setString(entry.key, value.toString());
      }
    }
  }
}

/// Volatile [SettingsStore] for tests and previews.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, Object?>? initialValues])
    : _values = <String, Object?>{...?initialValues};

  final Map<String, Object?> _values;

  /// Snapshot of everything currently persisted.
  Map<String, Object?> get values => Map<String, Object?>.unmodifiable(_values);

  @override
  Future<Map<String, Object?>> load() async =>
      Map<String, Object?>.from(_values);

  @override
  Future<void> save(Map<String, Object?> values) async {
    _values
      ..clear()
      ..addAll(values);
  }
}
