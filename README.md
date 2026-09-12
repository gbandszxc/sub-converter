# Subtitle Converter

A lightweight, fully offline desktop tool that converts text subtitle files between six
formats (SRT, WebVTT, LRC, ASS, SSA and YouTube SBV). It is a plain Flutter desktop app:
nothing is uploaded, there is no FFmpeg, Python or Node dependency, no network access and no
installer runtime is needed. Drop in files, pick a target format, and the converted files are
written next to the source (or into a folder you choose) as UTF-8.

## Supported formats

| Format | Extension | What is preserved | What is deliberately lost |
| --- | --- | --- | --- |
| SubRip | `.srt` | Start/end times to the millisecond; multi-line plain text; inline **bold**/*italic*/underline/strikethrough as `<b>/<i>/<u>/<s>`. | Cue numbering (output is renumbered 1..n); trailing SRT positioning data (`X1:0 X2:100 ...`) is ignored on read and never written. |
| WebVTT | `.vtt` | The `WEBVTT` header and its `key: value` metadata lines; cue identifiers; trailing cue settings (kept as opaque text and re-emitted by the VTT writer); inline emphasis; HTML entities are decoded. | `STYLE` and `REGION` blocks (skipped, not preserved); cue settings are not interpreted or modelled, so any target other than VTT drops them. |
| LRC | `.lrc` | Metadata tags (`[ti:]`, `[ar:]`, `[al:]`, `[by:]`, `[offset:]`, `[length:]`, unknown `[key:value]`) with original casing; start time to the centisecond; text. The `[offset:]` tag is preserved verbatim. | End times (the format has none; ends are inferred on parse, then dropped on write); inline emphasis; line breaks in multi-line cues (joined with spaces); enhanced-LRC per-word timestamps `<mm:ss.xx>` (stripped). The `[offset:]` tag is **not** applied. |
| ASS | `.ass` | `[Script Info]` fields; styles as raw field maps; `Dialogue:` events; times to the centisecond; style references; `Layer`/`Name`/`MarginL`/`MarginR`/`MarginV`/`Effect`; inline `\b \i \u \s`; `\an`/`\pos` alignment and position; text escapes and line breaks. | Karaoke (`\k`, `\K`, `\kf`, `\ko`); animation/transforms (`\t`, `\move`, `\fad`, `\fade`, `\org`, `\clip`, rotation, blur, borders); vector drawing (`\p1`); inline colour/font overrides (`\c`, `\1c`..`\4c`, `\alpha`, `\fs`, `\fn`); embedded fonts `[Fonts]` and graphics `[Graphics]`; all non-`Dialogue` events (`Comment`, `Picture`, `Sound`, `Movie`, `Command`). The `Text` field must be last, as the spec requires: a file that puts another field after it *and* uses commas in the dialogue text is reported as invalid syntax. |
| SSA | `.ssa` | Same as ASS: both share one dialect-parameterised parser and writer, so behaviour can never drift. Emits `[V4 Styles]`, `ScriptType: v4.00`, the `Marked` event field and SSA style defaults. | Same list as ASS. |
| SBV | `.sbv` | Start/end times to the millisecond; multi-line plain text. | Inline emphasis and cue positioning: SBV has no markup, so only plain text is written. |

Output is always UTF-8 (LF line endings). A UTF-8 BOM can be requested per file.

## Usage

### Run from source

```bash
flutter pub get
flutter run -d windows     # or: -d macos, -d linux
```

Add files by dragging them onto the window, pressing `Ctrl+O`, or using the Add button.
`Ctrl+Enter` starts the batch. On startup the app restores the options you used last time.

### Build a release binary

```bash
flutter build windows --release
flutter build macos   --release
flutter build linux   --release
```

The release artifacts land at:

| Platform | Artifact |
| --- | --- |
| Windows | `build\windows\x64\runner\Release\sub_converter.exe` |
| macOS | `build/macos/Build/Products/Release/Subtitle Converter.app` |
| Linux | `build/linux/x64/release/bundle/sub_converter` |

### Requirements

`pubspec.yaml` declares `environment: sdk: ^3.13.3`, so a Dart 3.13.3 (or later 3.x) SDK is
required. It was built and tested here with Flutter 3.47.4 stable (Dart 3.13.3), which
supports the Windows, macOS and Linux desktop targets used above.

## How conversion works

Every file follows the same pipeline, with no format-to-format shortcuts:

```text
file -> read bytes -> decode encoding -> detect format
     -> Parser -> SubtitleDocument -> Writer -> encode UTF-8 -> write
```

The encoding is resolved first because format detection inspects decoded text; the file name's
extension only acts as a corroborating bonus. A file whose content clearly says SRT is treated
as SRT even if it is named `.ass`.

By default the output goes next to each source file, with the target format's extension. If a
file with that name already exists it is auto-renamed (`E01.srt` -> `E01 (1).srt`), and the
source file is **never** a valid output path: even the overwrite policy falls back to renaming
when the only collision would be the source.

## Options

| Option | Values | Default |
| --- | --- | --- |
| Target format | SRT, VTT, LRC, ASS, SSA, SBV | SRT |
| Output folder | Source file folder, or a chosen custom folder | Source file folder |
| Conflict policy | Auto rename, Overwrite, Skip | Auto rename |
| Time offset | Signed milliseconds (typed, or stepped by ±500 ms, with reset) | 0 ms |
| Write UTF-8 BOM | On / off | Off |

Times are shifted uniformly and clamped at zero, so a negative offset never produces a negative
timestamp. The overwrite policy replaces an existing *output* file but still refuses to replace
the source. Settings (target format, output location, chosen folder, conflict policy, offset,
BOM) are persisted with `shared_preferences` and restored between runs.

## Encoding support

Input:

| Encoding | Notes |
| --- | --- |
| UTF-8 | Without BOM; pure ASCII also lands here. |
| UTF-8 with BOM | The BOM is authoritative and is stripped from the text. |
| UTF-16 LE / BE | With or without a BOM. BOM-less input is guessed from NUL-byte parity, with an extra check for pure-CJK input that contains no NUL bytes. |
| UTF-32 LE / BE | With a BOM. |
| GBK | |
| GB18030 | Including four-byte sequences, via a self-contained decoder. |
| Shift-JIS | |
| EUC-JP | |
| Windows-1252 | Also the permissive last-resort reading. |

Output is always UTF-8, optionally with a BOM.

**The legacy detection is heuristic, not statistical.** A byte order mark is trusted
absolutely; otherwise strict UTF-8 is tried, then candidate legacy encodings are decoded and
scored by the scripts they produce, with ties going to the earlier candidate. GBK/GB18030 and
Shift-JIS share much of their two-byte space, and GBK ideographs cannot be told apart from
Shift-JIS kanji by shape; the scorer leans on kana content and penalises the byte ranges the
two encodings share. The practical consequence is that short or ambiguous files can still be
mis-detected, and single-byte Western text is read as Windows-1252 unless it happens to be
valid UTF-8. Detection failures are reported per file rather than guessed through.

## Testing

```bash
flutter test
```

The suite currently contains **330 tests, all passing**. Coverage:

- **Core**: timestamp parse/format rules, the unified model (`SubtitleDocument`/`SubtitleCue`), and the shared inline-markup scanner.
- **Formats**: dedicated parser/writer tests for each of SRT, VTT, LRC, ASS, SSA and SBV, exercised against real fixtures (including CJK and tag-heavy files).
- **Conversion matrix**: a generated 6x6 test that converts every fixture to every format, re-parses the output with the target's own parser and checks cue count and start-time drift.
- **Encoding**: BOM handling, UTF-16/UTF-32 detection, ASCII/CJK/SJIS/GBK/GB18030 cases, Windows-1252 fallback and failure behavior.
- **Path and file safety**: conflict policies and the "never overwrite the source" rule; batch conversion, progress and per-file failures.
- **UI/controller**: `AppController` state and persistence, widget tests for the home screen, and drag-and-drop tests that drive the window's real `DropTarget` callback (multi-file drops, dropped folders and empty paths ignored, duplicates collapsed).
- **End to end**: the real `FileService` and `AppController` against real files on disk, including the full all-format matrix.

## Scope

Not in v0.1:

- No video or audio handling, no playback, no preview, no timeline editing.
- No OCR, no speech recognition, no translation, no subtitle downloading.
- No accounts, no cloud, no network code at all.
- No FFmpeg: no muxing, extraction or burn-in.
- Not yet supported as input/output: MicroDVD, MPL2, TTML, SAMI, SCC, VobSub.

The architecture leaves room for more formats: conversion is always
`source -> Parser -> SubtitleDocument -> Writer -> target`, so a new format is one new directory
plus one registration line, not a new converter per pair.

## Adding a new format

1. Add a value to the `SubtitleFormat` enum in `lib/models/subtitle_format.dart` (label, extension, description).
2. Create `lib/formats/<name>/<name>_parser.dart` implementing `SubtitleParser`.
3. Create `lib/formats/<name>/<name>_writer.dart` implementing `SubtitleWriter`.
4. Create `lib/formats/<name>/<name>_format.dart` exporting a `FormatDescriptor`: parser/writer factories, content `FormatSignature`s, extension aliases and capability flags (`supportsStyles`, `supportsInlineStyles`, `supportsPositions`, `requiresEndTime`).
5. Append the descriptor to `builtInFormatDescriptors` in `lib/formats/built_in_formats.dart`.
6. Add fixtures under `test/fixtures/<name>/` and tests under `test/formats/<name>_test.dart`; the 6x6 matrix picks the format up automatically.

No core switch statements or pairwise converters need to change.

## Project layout

```text
lib/
  main.dart                     App entry point and root widget.
  models/                       Format-independent types.
    subtitle_document.dart      SubtitleDocument, SubtitleMetadata.
    subtitle_cue.dart           SubtitleCue, InlineStyleRange, CuePosition.
    subtitle_style.dart         SubtitleStyle (raw field map).
    subtitle_format.dart        The SubtitleFormat enum.
    subtitle_codec.dart         SubtitleParser / SubtitleWriter interfaces.
    format_descriptor.dart      FormatDescriptor (capabilities + factories).
    format_signature.dart       Content fingerprints and signature factories.
    conversion_job.dart         Options, conflict/location enums, results.
    subtitle_exception.dart     ConversionFailure and exception types.
  formats/
    built_in_formats.dart       The one registration list of the six formats.
    format_registry.dart        Format-agnostic lookup by format/extension.
    srt/ vtt/ lrc/ ass/ ssa/ sbv/
                                One parser + writer + descriptor per format.
  services/
    file_service.dart           The only IO: read, batch, write.
    encoding_service.dart       Decoding heuristics and UTF-8 encoding.
    gb18030_codec.dart          Self-contained GB18030 decoder (incl. 4-byte).
    format_detector.dart        Scored content + extension detection.
    subtitle_converter.dart     Parse -> document -> write core.
    loss_analyzer.dart          Reports unavoidable information loss.
    output_path_resolver.dart   Output naming and conflict rules.
    settings_store.dart         Persistence seam (shared_preferences).
  screens/
    app_controller.dart         All UI state; delegates to FileService.
    home_screen.dart            The single window, drop target and shortcuts.
  widgets/                      Header, file list, options panel, status bar.
  utils/                        Timestamp, inline markup, defaults.
test/
  core/ formats/ services/ widget/ integration/
                                Unit, matrix, path, UI and end-to-end tests.
  fixtures/                     Real sample files per format.
```

## Privacy

All processing happens locally inside the app. There is no network code, no telemetry and no
upload path: subtitle content is read from disk, converted in memory and written back to disk.
Nothing is ever sent anywhere.
