# Architecture

Subtitle Converter is a Flutter desktop app built around one idea: every conversion goes
through a single, format-neutral model. There are deliberately **no pairwise converters** — no
`srt_to_vtt`, no `ass_to_srt`. Six formats means six parsers and six writers, not thirty-six
conversions.

## Data flow

```text
source file (bytes on disk)
        |
        v
EncodingService.decode          bytes  -> String        (BOM / UTF-8 / heuristics)
        |
        v
FormatDetector.detect           String + file name -> SubtitleFormat
        |
        v
SubtitleParser.parse            String -> SubtitleDocument
        |
        v
 SubtitleDocument                        (the unified model, in memory)
        |
        v
SubtitleWriter.write            SubtitleDocument -> String
        |
        v
EncodingService.encode          String -> UTF-8 bytes   (optional BOM)
        |
        v
FileService writes              bytes -> target file
```

`SubtitleConverter.convert` is the core that runs the middle of this pipeline. It looks up a
parser and a writer by `SubtitleFormat` in the registry, so it has no knowledge of any
individual format and no format-to-format path exists:

```text
registry.parserFor(source).parse(content)
    -> SubtitleDocument
    -> registry.writerFor(target).write(document)
```

Encoding is resolved before format detection because content-based detection needs decoded
text; the file name is only a corroborating signal (an extension bonus in `FormatDetector`).
The encoding service does not use the file name.

## Layering

```text
UI            lib/screens/home_screen.dart, lib/widgets/*
  |
  v
AppController lib/screens/app_controller.dart        ChangeNotifier, all UI state
  |
  +------------> lib/platform/*                        SystemFonts (one channel), AppTypography (pure)
  |
  v
Services      lib/services/*
              FileService          (the only IO)
              EncodingService      (pure)
              FormatDetector       (pure)
              SubtitleConverter    (pure)
              OutputPathResolver   (pure)
              LossAnalyzer         (pure)
  |
  v
Formats       lib/formats/<format>/{parser,writer}
              via FormatRegistry / FormatDescriptor
```

Rules:

- **The UI contains no subtitle knowledge.** `HomeScreen` and the widgets render state and
  forward user actions. `AppController` imports `SubtitleFormat` only to show labels and to
  persist the selected target; it never parses, detects or writes.
- **Parsers and writers are pure.** `SubtitleParser` and `SubtitleWriter` (see
  `lib/models/subtitle_codec.dart`) document and require no file system, no Flutter and no
  network. They take and return `String` / `SubtitleDocument` and nothing else.
- **`FileService` is the only service that touches disk.** Everything below it is synchronous
  and unit-testable without a temporary directory.
- **`lib/platform` is the only platform-channel seam.** System fonts are asked over one method
  channel (`sub_converter/fonts`) implemented in each runner; the typography *policy* stays
  pure Dart (`AppTypography`). No Dart code outside `FileService` reads the file system, and
  `lib/models`, `lib/formats` and `lib/services` keep zero Flutter imports.
- **Dependencies point downward.** No service imports a screen; no parser imports a service.
- **Only the UI knows the locale.** `lib/i18n` is imported by `lib/main.dart`, `lib/screens`
  and `lib/widgets` and by nothing below them. `lib/models`, `lib/formats` and
  `lib/services` emit structured values — `LossKind`, `ConversionFailure`, counts, paths —
  and never a sentence, so they stay pure and locale-free.

`FileService` composes the others and injects them (registry, encoding service, converter,
detector, path resolver) so tests can substitute fakes and a custom registry.

## The model

All types live in `lib/models/`.

### `SubtitleDocument` (`subtitle_document.dart`)

The value every parser produces and every writer consumes.

- `cues` — ordered list of `SubtitleCue`.
- `styles` — list of `SubtitleStyle`.
- `metadata` — a `SubtitleMetadata` (see below).
- `sourceFormat` — which format it was parsed from, when known.
- Helpers: `sortByStart()`, `shift(offset)` / `shifted(offset)`, and
  `resolveMissingEndTimes(fallback)` which fills `null` ends (each cue ends at the next cue's
  start; the last gets `SubtitleDefaults.lrcEndTimeFallback`, currently 5 s).

`SubtitleMetadata` carries `title`, `language` and an **open `fields` map** (format-native
header key -> value, original casing) plus a case-insensitive `field(key)` lookup. This is how
ASS `[Script Info]`, LRC `[ti:]` and VTT header lines survive without the model growing a field
per format.

### `SubtitleCue` (`subtitle_cue.dart`)

- Timing is always a Dart `Duration`: `start` non-null, `end` **nullable** because LRC has no
  end times. `hasExplicitEnd` / `duration` reflect that.
- `text` is **plain text only**, markup removed, lines separated by `\n`.
- Emphasis is modelled as `List<InlineStyleRange>`: `start`/`end` offsets into `text` (UTF-16
  code units, i.e. `String.substring` indices) plus a `Set<InlineStyle>` of
  `bold`/`italic`/`underline`/`strikethrough`. Parsers translate format-native markup into
  these ranges; writers translate them back. `clampTo` and `normalizeInlineStyles`
  (`lib/utils/inline_markup.dart`) keep them sorted, clamped and non-overlapping by equal set.
- `position` is an optional `CuePosition` (`alignment` for ASS `\an`, `x`/`y` for `\pos`).
- `styleRef` names the `SubtitleStyle` a cue uses.
- `metadata` is an **open `Map<String, Object?>`** for format-specific extras that must
  round-trip (ASS `Layer`, `MarginL`, `Effect`; SRT index; VTT identifier and settings).

### `SubtitleStyle` (`subtitle_style.dart`)

A name plus a **raw field map** (`Fontname` -> `Arial`, original casing). v0.1 never edits
styles, so keeping the source spelling is both simpler and lossless for ASS/SSA round-trips.

### `SubtitleFormat` (`subtitle_format.dart`)

The enum of the six formats, each carrying `label` (SRT, VTT, ... — language-neutral) and
the canonical `extension`. Display text, including the per-format description, lives in the
string tables instead: the model layer must not know the locale.
Adding a format starts here.

### `FormatDescriptor` + `FormatSignature` + `FormatRegistry`

- `FormatDescriptor` (`format_descriptor.dart`) is everything the rest of the app needs about
  one format: `createParser` / `createWriter` factories, content `signatures`, extension
  aliases, and capability flags `supportsStyles`, `supportsInlineStyles`, `supportsPositions`,
  `requiresEndTime`. The capability flags drive loss reporting; nothing hard-codes a format.
- `FormatSignature` (`format_signature.dart`) is a cheap, non-throwing content fingerprint with
  an `id` and a `weight`; `FormatSignatures` provides `contains`, `matchesPattern`,
  `firstLineMatches` and `linePatternCount` factories.
- `FormatRegistry` (`lib/formats/format_registry.dart`) is plain data: maps formats to
  descriptors and extensions to descriptors, and hands out parsers/writers. It never branches
  on a format.

## Extension points

| Concern | Where it lives |
| --- | --- |
| The set of formats | `lib/models/subtitle_format.dart` |
| One format's parser | `lib/formats/<name>/<name>_parser.dart` |
| One format's writer | `lib/formats/<name>/<name>_writer.dart` |
| One format's capabilities and fingerprints | `lib/formats/<name>/<name>_format.dart` |
| The single registration list | `lib/formats/built_in_formats.dart` (`builtInFormatDescriptors`) |
| Format lookup and factories | `lib/formats/format_registry.dart` |
| Detection scoring | `lib/services/format_detector.dart` plus each descriptor's signatures |
| Encoding detection | `lib/services/encoding_service.dart`, `gb18030_codec.dart` |
| Conversion core | `lib/services/subtitle_converter.dart` |
| Loss reporting | `lib/services/loss_analyzer.dart` |
| Output naming / conflict rules | `lib/services/output_path_resolver.dart` |
| Batch orchestration and IO | `lib/services/file_service.dart` |
| Persistence seam | `lib/services/settings_store.dart` |
| App font policy (defaults, fallback chains) | `lib/platform/app_typography.dart` |
| System font queries (installed list, desktop default) | `lib/platform/system_fonts.dart` plus each platform runner |
| UI strings, language choice | `lib/i18n/` (`strings_en.dart`, `strings_zh.dart`, `app_strings.dart`, `app_language.dart`) |

Shared code is factored so dialects and formats do not duplicate each other: `ass/` holds one
dialect-parameterised parser/writer/text-codec serving both ASS and SSA, and
`lib/utils/inline_markup.dart` holds the HTML-ish scanner shared by SRT/VTT.

Adding a format means: a value in the `SubtitleFormat` enum, a parser, a writer, a descriptor
with its content signatures, and one line in `built_in_formats.dart`. There is no central
`switch` on the format enum and no pairwise converter anywhere — every conversion goes through
the same `parse -> SubtitleDocument -> write` path. Two deliberate exceptions are format-specific
rules rather than format registration: `LossAnalyzer` has an LRC branch (LRC has neither end
times nor line breaks), and each writer knows its own output grammar.

## Lossy conversions

A conversion that loses information still succeeds — loss is a value, not an error.
`LossAnalyzer.analyze` compares the document against the target descriptor and returns a
`LossReport` of structured `LossWarning`s (`LossKind` plus a count, see
`lib/models/loss_report.dart`), which `ConversionResult.warnings` carries to the UI; a result
with warnings is still `succeeded` and `ConversionResult.isLossy` is true. The kinds are not
sentences: the UI turns each one into localized text with the target format label, which is
why the analyzer can stay pure and locale-free.

It also reports one source-side oddity: a cue whose end precedes its start. That is usually a
typo in the source, but the file still converts — rejecting a whole file over one bad cue would
lose far more than it protects — so the interval is written through unchanged and the user is
told.

The analyzer is capability-driven, so a new format gets sensible reporting just by declaring
its flags:

- target does not `supportsInlineStyles` and cues carry emphasis -> warning;
- target does not `supportsPositions` and cues carry a position -> warning;
- target does not `supportsStyles` and styles are present -> warning;
- target is LRC and cues have end times or embedded newlines -> warnings for each.

Some specific target-model rules cannot be expressed as a flag (LRC has no end times and no
line breaks), so they are checked explicitly in `LossAnalyzer` guarded by a same-format
exclusion. Writers themselves are deliberately lossy and drop what they cannot express; they
never fail on it.

## File safety

`OutputPathResolver` decides the output path from three inputs: the requested name
(`<source base>.<target extension>`), the chosen directory, and an injected
`exists(path)` predicate — so the rules are unit-testable and the resolver can never write.

- The source file is never a valid output. If the resolved path equals the source (including
  absolute-form and Windows case-insensitive comparison via `package:path`), the name is
  changed **even under `overwrite`**.
- `autoRename` (the default) tries `name (1)`, `name (2)`, ... up to
  `maxAutoRenameAttempts` (500), then reports a skip rather than loop.
- `overwrite` replaces an existing output, but not the source.
- `skip` returns an `OutputPathResolution.skip` with a reason when the output exists or would
  hit the source; `FileService` turns that into a `skipped` `ConversionResult`, not a failure.

`FileService` enforces the same invariants in practice: it reads bytes, resolves the directory
(source folder by default, or an existing custom folder), asks the resolver, and only then
writes. It checks the output's parent directory exists and writes with `flush: true`. Source
files are only ever opened for reading. Conversion happens on a copy of the parsed document
(`document.copy()..shift(offset)`), so the input text is never mutated.

## Error model

`lib/models/subtitle_exception.dart` defines `ConversionFailure`, the user-facing reason enum:
`unsupportedFormat`, `encodingDetectionFailed`, `invalidSubtitleSyntax`, `emptyDocument`,
`cannotWriteOutput`, `permissionDenied`, `targetPathUnavailable`, `readFailed`, `unknown`. Each
carries a short English title and a one-sentence message. Those are the developer-facing
diagnostic (tests and logs use them); the UI shows the localized title from
`AppStrings.failureTitle` instead, and the technical `detail` only for the kinds whose text
is a path or file name.

`SubtitleConversionException` wraps a `ConversionFailure` with a single-line technical detail
and an optional `cause` for debug logs only; `userMessage` is what the UI shows. Parsers throw
`SubtitleSyntaxException`; unknown formats throw `UnsupportedFormatException`. `FileSystemException`
is mapped onto the closest `ConversionFailure` (Windows/POSIX access-denied codes 5/13 ->
`permissionDenied`, 2/3 -> `readFailed`, and so on).

**Failures are per-file values, not batch-level exceptions.** `FileService.convertFile` catches
everything and returns a `ConversionResult` with `ConversionStatus.failed`, a `ConversionFailure`
and a short `detail` (never a stack trace). `convertAll` loops over the paths, reports progress
after each file and continues, so one broken file cannot stop a batch. The only exceptions that
escape a single conversion are programming errors, and the controller catches those to set a
batch message.

## Localization

`lib/i18n/` holds two hand-written `AppStrings` tables (English, Simplified Chinese) rather than
generated ARB files: this is a single-window app with no navigation and no `intl` formatting
needs, so a codegen pipeline would add a dependency and build steps for nothing.

- `AppStrings` is abstract, so a forgotten translation is a compile error. The runtime checks a
  compiler cannot do live in `test/i18n/strings_test.dart`: every member is called, no value may
  be empty, and no Chinese entry may equal its English counterpart except an explicit allow-list
  (the language names, and format names that are proper nouns).
- `StringsScope` carries the active table down the tree and **throws** when it is missing, rather
  than silently falling back to English and showing the wrong language.
- `AppLanguage` holds no display text. `resolve(Locale)` is the whole auto-detect rule: `system`
  becomes `chinese` for any `zh*` locale and `english` otherwise, and a pinned choice wins. The
  app ships one Chinese translation, so Traditional locales get Simplified rather than English.
- `main.dart` resolves the effective language, wraps `MaterialApp` in a `StringsScope`, and pins
  `MaterialApp.locale` to match, with the Flutter localization delegates for Material's own
  strings. Rebuilding is driven by the controller, so switching languages updates the window
  immediately and needs no restart.
- The language is an app setting, not a conversion option, so it lives on `AppController` and is
  persisted under the `language` settings key (default `system`).

What is deliberately **not** localized: parser and service `detail` strings. Parsers must stay
locale-free (see the layering rules), so those messages remain English diagnostics. The row shows
the localized reason plus the English detail only for the kinds that carry a path, and the paths
themselves are language-neutral.

## System fonts

The app pins its text families instead of trusting the engine's runtime fallback, which renders
CJK with uneven weights. The policy lives in `lib/platform/app_typography.dart` (pure data, no
Flutter): a curated default per platform — Microsoft YaHei UI on Windows, PingFang SC on macOS,
Noto Sans CJK SC on Linux — plus an ordered CJK-aware fallback chain that applies on top of
whatever family is active, so a user-chosen font that lacks Chinese glyphs still renders them
consistently.

`lib/platform/system_fonts.dart` wraps the `sub_converter/fonts` method channel; each runner
implements it natively:

- **Windows** (`windows/runner/system_fonts.cpp`) — `EnumFontFamiliesExW` lists the installed
  families (leading-`@` vertical variants dropped, duplicates merged case-insensitively); the
  default family comes from `NONCLIENTMETRICS` `lfMessageFont`, i.e. the font the shell itself
  uses ("Microsoft YaHei UI" on Chinese Windows, "Segoe UI" on English Windows, ...), so a
  localized system gets its own UI face.
- **macOS** (`macos/Runner/MainFlutterWindow.swift`) — `NSFontManager.availableFontFamilies`
  lists; "PingFang SC" is reported as the default.
- **Linux** (`linux/runner/my_application.cc`) — the realized window's Pango font map
  (fontconfig) lists; the default family is the desktop's default UI font: the
  `gtk-font-name` setting when the session provides it (GNOME, or KDE with plasma
  integration), else KDE's own record in `kdeglobals` (`General/font=`, a QFont string whose
  first comma-separated field is the family).

Both queries degrade silently: if the channel is missing (widget tests, an unsupported host)
the app falls back to the curated defaults with an empty picker list. The user's pick is
persisted under the `fontFamily` settings key (`null` = follow system) and is not validated
against the installed list — a font that later disappears, or that was chosen on another
machine, keeps applying through the standard fallback.

## Deliberate v0.1 simplifications

- **Heuristic encoding detection.** BOMs are authoritative, strict UTF-8 is tried next, then
  legacy candidates are decoded and scored by script content. Ambiguous short files — GBK vs
  Shift-JIS in particular — can still be misdetected. There is no statistical model.
- **LRC `offset` tag preserved but not applied.** The tag is kept in metadata so an LRC file
  round-trips, but its value never shifts timestamps. Use the time-offset option instead.
- **ASS/SSA non-`Dialogue` events are dropped**, as are `[Fonts]`, `[Graphics]` and unknown
  sections: the model has no representation for them, and v0.1 does not edit styling.
- **No isolate.** Per-file CPU work is a parse plus a render of a text file of at most a few
  hundred kilobytes, so a plain async loop in `FileService` keeps the UI responsive without the
  cost and complexity of an isolate. `SubtitleConverter`, `FormatDetector` and `EncodingService`
  are synchronous by design.
- **Uniform time offset.** One offset applies to every cue in the batch; there is no per-cue
  timeline editing, and negative offsets are clamped at zero.
- **VTT cue settings are opaque.** `line`/`position`/`align` and cue identifiers are stored as
  raw text and re-emitted only by the VTT writer; `supportsPositions` is false because they are
  not modelled as positions, so a conversion to another format drops them without a dedicated
  positioning warning.
- **Path comparison is case-insensitive only on Windows.** `AppController` lowercases its
  duplicate-detection key when `Platform.isWindows` is true, and compares exactly elsewhere
  because `A.srt` and `a.srt` are genuinely distinct files on macOS and Linux. Collapsing them
  there could hide a file from the user, so the conservative direction is deliberate. Both
  branches are asserted in the test suite, and CI runs it on all three platforms.
