import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../i18n/app_language.dart';
import '../models/conversion_job.dart';
import '../models/subtitle_exception.dart';
import '../models/subtitle_format.dart';
import '../platform/app_typography.dart';
import '../platform/system_fonts.dart';
import '../services/file_service.dart';
import '../services/format_detector.dart';
import '../services/settings_store.dart';

/// One row in the file list.
///
/// Mutable on purpose: inspection and conversion fill it in over time, and the
/// owning [AppController] notifies listeners after each change.
class SubtitleFileEntry {
  SubtitleFileEntry(this.path);

  final String path;

  FormatDetection? detection;
  ConversionResult? result;

  /// Structured inspection failure, localized by the UI. Never a sentence:
  /// the controller holds no display text.
  ConversionFailure? inspectionError;
  String? encodingName;

  SubtitleFormat? get detectedFormat => detection?.format;

  /// True until inspection settles: no format and no recorded error yet.
  bool get isInspecting => detection == null && inspectionError == null;

  ConversionStatus get status => result?.status ?? ConversionStatus.pending;

  bool get isPending => status == ConversionStatus.pending;

  String get fileName => p.basename(path);

  String get folder => p.dirname(path);
}

/// All UI state for the single window.
///
/// Holds no subtitle knowledge: conversion is delegated entirely to
/// [FileService], and [SubtitleFormat] is only read for display labels.
class AppController extends ChangeNotifier {
  AppController({
    FileService? fileService,
    SettingsStore? settingsStore,
    ConversionOptions? initialOptions,
    SystemFonts? systemFonts,
    String? platformName,
  }) : _fileService = fileService ?? FileService(),
       _settingsStore = settingsStore ?? SharedPreferencesSettingsStore(),
       _systemFonts = systemFonts ?? const SystemFonts(),
       platformName = platformName ?? Platform.operatingSystem,
       _options =
           initialOptions ??
           const ConversionOptions(targetFormat: SubtitleFormat.srt);

  static const String _keyTargetFormat = 'targetFormat';
  static const String _keyOutputLocation = 'outputLocation';
  static const String _keyOutputDirectory = 'outputDirectory';
  static const String _keyConflictPolicy = 'conflictPolicy';
  static const String _keyTimeOffsetMs = 'timeOffsetMs';
  static const String _keyWriteUtf8Bom = 'writeUtf8Bom';
  static const String _keyLanguage = 'language';
  static const String _keyFontFamily = 'fontFamily';

  final FileService _fileService;
  final SettingsStore _settingsStore;
  final SystemFonts _systemFonts;

  /// `Platform.operatingSystem`, injectable so tests can pin the platform
  /// (and its default font policy) regardless of the host running the tests.
  final String platformName;

  final List<SubtitleFileEntry> _entries = <SubtitleFileEntry>[];
  final Set<String> _knownPaths = <String>{};

  ConversionOptions _options;
  AppLanguage _language = AppLanguage.system;

  /// The user's app font pick, or `null` to follow the system default.
  String? _fontFamily;

  /// Installed system font families, filled in asynchronously after startup.
  List<String> _systemFontFamilies = const <String>[];

  /// The desktop's own default UI family as the OS reports it, if known.
  String? _platformDefaultFamily;

  bool _isConverting = false;
  bool _disposed = false;

  /// Structured outcome of the last batch, localized by the UI.
  bool _hasBatchSummary = false;
  ConversionFailure? _batchFailure;

  /// Rows in insertion order.
  List<SubtitleFileEntry> get entries =>
      List<SubtitleFileEntry>.unmodifiable(_entries);

  ConversionOptions get options => _options;

  /// UI language choice. An app setting, so it lives outside
  /// [ConversionOptions]; the resolution against the platform locale happens
  /// in `main.dart`.
  AppLanguage get language => _language;

  /// The user's app font pick, or `null` when following the system default.
  String? get fontFamily => _fontFamily;

  /// Installed system font families for the picker; empty until the OS
  /// answers (or when the OS query is unavailable).
  List<String> get systemFontFamilies => _systemFontFamilies;

  /// The desktop's own default UI family as the OS reports it, if known.
  String? get platformDefaultFamily => _platformDefaultFamily;

  /// The family the app renders in: the user's pick, else the platform's
  /// default policy (see `AppTypography`), else `null` for Flutter's own
  /// default.
  String? get effectiveFontFamily => fontFamily ??
      AppTypography.defaultFamily(
        platform: platformName,
        desktopDefault: _platformDefaultFamily,
      );

  bool get isConverting => _isConverting;

  /// True after a batch finished, so the UI can show its summary.
  bool get hasBatchSummary => _hasBatchSummary;

  /// A batch-level failure (a programming error escaping the service), or
  /// `null`. The UI localizes it with `AppStrings.failureTitle`.
  ConversionFailure? get batchFailure => _batchFailure;

  int get fileCount => _entries.length;

  int get totalCount => _entries.length;

  /// Entries that reached a final state.
  int get completedCount => _entries.where((SubtitleFileEntry e) {
    final ConversionStatus status = e.status;
    return status == ConversionStatus.succeeded ||
        status == ConversionStatus.failed ||
        status == ConversionStatus.skipped;
  }).length;

  int get successCount => _countStatus(ConversionStatus.succeeded);

  int get failureCount => _countStatus(ConversionStatus.failed);

  int get skippedCount => _countStatus(ConversionStatus.skipped);

  int get lossyCount => _entries
      .where((SubtitleFileEntry e) => e.result?.isLossy ?? false)
      .length;

  /// Determinate progress in `0..1` for the running batch.
  double get progress =>
      _entries.isEmpty ? 0 : completedCount / _entries.length;

  bool get hasConvertibleFiles => _entries.isNotEmpty;

  bool get canConvert =>
      hasConvertibleFiles &&
      !_isConverting &&
      _options.validationError() == null;

  int _countStatus(ConversionStatus status) =>
      _entries.where((SubtitleFileEntry e) => e.status == status).length;

  /// Adds every path that is not already present.
  ///
  /// Duplicates are detected on the normalized absolute path, compared
  /// case-insensitively on Windows. Inspection runs per file and never
  /// blocks or fails the others.
  Future<void> addPaths(Iterable<String> paths) async {
    final List<SubtitleFileEntry> added = <SubtitleFileEntry>[];
    for (final String raw in paths) {
      final String path = raw.trim();
      if (path.isEmpty) {
        continue;
      }
      if (!_knownPaths.add(_normalizeKey(path))) {
        continue;
      }
      final SubtitleFileEntry entry = SubtitleFileEntry(path);
      _entries.add(entry);
      added.add(entry);
    }
    if (added.isEmpty) {
      return;
    }
    _resetBatchOutcome();
    notifyListeners();
    for (final SubtitleFileEntry entry in added) {
      unawaited(_inspect(entry));
    }
  }

  /// Removes [entry]; ignored while a conversion is running.
  void removeEntry(SubtitleFileEntry entry) {
    if (_isConverting) {
      return;
    }
    if (_entries.remove(entry)) {
      _knownPaths.remove(_normalizeKey(entry.path));
      notifyListeners();
    }
  }

  /// Removes every row; ignored while a conversion is running.
  void clearEntries() {
    if (_isConverting || _entries.isEmpty) {
      return;
    }
    _entries.clear();
    _knownPaths.clear();
    _resetBatchOutcome();
    notifyListeners();
  }

  /// Runs the whole batch through [FileService.convertAll].
  ///
  /// Progress is reflected row by row; the batch is not cancellable but never
  /// lets one failure stop the rest.
  Future<void> convertAll() async {
    if (!canConvert) {
      return;
    }
    final List<String> paths = _entries
        .map((SubtitleFileEntry e) => e.path)
        .toList();
    _isConverting = true;
    _resetBatchOutcome();
    for (final SubtitleFileEntry entry in _entries) {
      entry.result = ConversionResult.pending(entry.path);
    }
    _entries.first.result = _convertingResult(paths.first);
    notifyListeners();

    try {
      await _fileService.convertAll(paths, _options, onProgress: _onProgress);
      _hasBatchSummary = true;
    } on SubtitleConversionException catch (error) {
      _batchFailure = error.failure;
    } catch (_) {
      _batchFailure = ConversionFailure.unknown;
    } finally {
      _isConverting = false;
      notifyListeners();
    }
  }

  void _resetBatchOutcome() {
    _hasBatchSummary = false;
    _batchFailure = null;
  }

  void _onProgress(int completed, int total, ConversionResult result) {
    final int finished = completed - 1;
    if (finished >= 0 && finished < _entries.length) {
      _entries[finished].result = result;
    }
    if (completed < _entries.length) {
      _entries[completed].result = _convertingResult(_entries[completed].path);
    }
    notifyListeners();
  }

  ConversionResult _convertingResult(String path) =>
      ConversionResult.pending(path)
          .copyWith(status: ConversionStatus.converting);

  // --- Options -------------------------------------------------------------

  void setTargetFormat(SubtitleFormat format) {
    _updateOptions(_options.copyWith(targetFormat: format));
  }

  void setOutputLocation(OutputLocation location) {
    _updateOptions(_options.copyWith(outputLocation: location));
  }

  void setOutputDirectory(String? directory) {
    _updateOptions(_options.copyWith(outputDirectory: directory));
  }

  void setConflictPolicy(OutputConflictPolicy policy) {
    _updateOptions(_options.copyWith(conflictPolicy: policy));
  }

  void setTimeOffset(Duration offset) {
    _updateOptions(_options.copyWith(timeOffset: offset));
  }

  void setWriteUtf8Bom(bool value) {
    _updateOptions(_options.copyWith(writeUtf8Bom: value));
  }

  void _updateOptions(ConversionOptions options) {
    _options = options;
    notifyListeners();
    unawaited(_persist());
  }

  /// Changes the UI language and persists it. The rebuild in `main.dart` picks
  /// the new table up immediately.
  void setLanguage(AppLanguage value) {
    if (_language == value) {
      return;
    }
    _language = value;
    notifyListeners();
    unawaited(_persist());
  }

  /// Changes the app font, or follows the system default with `null`.
  /// The theme rebuild in `main.dart` applies it immediately.
  void setFontFamily(String? family) {
    if (_fontFamily == family) {
      return;
    }
    _fontFamily = family;
    notifyListeners();
    unawaited(_persist());
  }

  // --- Persistence ---------------------------------------------------------

  /// Loads persisted settings; a missing or corrupt value keeps the default.
  Future<void> loadSettings() async {
    Map<String, Object?> values = const <String, Object?>{};
    try {
      values = await _settingsStore.load();
    } catch (_) {
      // A broken store must never prevent the app from starting.
    }
    if (_disposed) {
      return;
    }
    _options = ConversionOptions(
      targetFormat: _readEnum(
        values[_keyTargetFormat],
        SubtitleFormat.values,
        _options.targetFormat,
      ),
      outputLocation: _readEnum(
        values[_keyOutputLocation],
        OutputLocation.values,
        _options.outputLocation,
      ),
      outputDirectory: _readString(values[_keyOutputDirectory]),
      conflictPolicy: _readEnum(
        values[_keyConflictPolicy],
        OutputConflictPolicy.values,
        _options.conflictPolicy,
      ),
      timeOffset: Duration(milliseconds: _readInt(values[_keyTimeOffsetMs], 0)),
      writeUtf8Bom: values[_keyWriteUtf8Bom] is bool
          ? values[_keyWriteUtf8Bom]! as bool
          : _options.writeUtf8Bom,
    );
    _language = _readEnum(values[_keyLanguage], AppLanguage.values, _language);
    _fontFamily = _readString(values[_keyFontFamily]);
    notifyListeners();
    // The font query rides along after the persisted settings apply; the UI
    // rebuilds again when the OS answer arrives.
    unawaited(_loadSystemFonts());
  }

  /// Asks the OS which fonts are installed and which family it uses as its
  /// own default. Best effort: a missing or failing platform answer leaves
  /// the lists empty and the curated defaults in `AppTypography` in charge.
  Future<void> _loadSystemFonts() async {
    final List<String> families;
    final String? desktopDefault;
    try {
      families = await _systemFonts.installedFontFamilies();
      desktopDefault = await _systemFonts.defaultFontFamily();
    } catch (_) {
      return;
    }
    if (_disposed) {
      return;
    }
    _systemFontFamilies = families;
    _platformDefaultFamily = desktopDefault;
    notifyListeners();
  }

  Future<void> _persist() async {
    final ConversionOptions options = _options;
    try {
      await _settingsStore.save(<String, Object?>{
        _keyTargetFormat: options.targetFormat.name,
        _keyOutputLocation: options.outputLocation.name,
        _keyOutputDirectory: options.outputDirectory,
        _keyConflictPolicy: options.conflictPolicy.name,
        _keyTimeOffsetMs: options.timeOffset.inMilliseconds,
        _keyWriteUtf8Bom: options.writeUtf8Bom,
        _keyLanguage: _language.name,
        _keyFontFamily: _fontFamily,
      });
    } catch (_) {
      // Persistence is best effort; the in-memory setting still applies.
    }
  }

  Future<void> _inspect(SubtitleFileEntry entry) async {
    try {
      final FileInspection inspection = await _fileService.inspect(entry.path);
      if (_disposed) {
        return;
      }
      entry.detection = inspection.detection;
      entry.encodingName = inspection.encodingName;
    } on SubtitleConversionException catch (error) {
      entry.inspectionError = error.failure;
    } catch (_) {
      entry.inspectionError = ConversionFailure.unknown;
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  static String _normalizeKey(String path) {
    final String normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static T _readEnum<T extends Enum>(Object? raw, List<T> values, T fallback) {
    if (raw is! String || raw.isEmpty) {
      return fallback;
    }
    for (final T value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    for (final T value in values) {
      if (value.toString().toLowerCase() == raw.toLowerCase()) {
        return value;
      }
    }
    return fallback;
  }

  static String? _readString(Object? raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return raw;
    }
    return null;
  }

  static int _readInt(Object? raw, int fallback) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim()) ?? fallback;
    }
    return fallback;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
