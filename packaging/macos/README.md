# Subtitle Converter macOS disk image

Builds a drag-to-install `.dmg` for the Subtitle Converter Flutter desktop app.

## Why hdiutil (and not a third-party tool)

Flutter has no `build macos --dmg` command. Everything the image needs — a
compressed disk image containing the `.app` next to an `/Applications` symlink —
is done by `hdiutil`, which ships with macOS.

Unlike `packaging/msi`, there is therefore **no tool download and no `.tools/`
folder**: the script installs nothing, needs no network access and does not ask
for administrator rights.

## Dependencies

- **macOS** — the script refuses to run anywhere else, because `hdiutil` only
  exists there.
- **Xcode**, with its licence accepted: `flutter build macos` shells out to
  `xcodebuild`. If only the standalone Command Line Tools are installed, the
  active developer directory has to point at Xcode first:
  `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`, then
  `sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch`.
  The Command Line Tools themselves can stay installed.
- **Flutter SDK** on the `PATH`, or pass `--flutter-exe` / set the `FLUTTER_EXE`
  environment variable.

## Usage

```bash
# Full build: flutter build macos --release, then package.
packaging/macos/build-dmg.sh

# Package an existing build/macos/Build/Products/Release folder.
packaging/macos/build-dmg.sh --skip-build

# Override the version (default: x.y.z part of pubspec.yaml's "version:").
packaging/macos/build-dmg.sh --version 0.2.0
```

| Option             | Default                                  | Notes                             |
| ------------------ | ---------------------------------------- | --------------------------------- |
| `--skip-build`     | off                                      | Reuse the existing Flutter output. |
| `--version`        | `pubspec.yaml` `version:` x.y.z           | Used in the file name.            |
| `--configuration`  | `release`                                | `release`, `profile` or `debug`.  |
| `--flutter-exe`    | `$FLUTTER_EXE`, else PATH `flutter`       | Path to the `flutter` executable. |

## Output

`build/dmg/sub-converter-<version>.dmg` — a single compressed (UDZO) image,
about 22 MB.

The staging folder (`build/dmg/stage/`) is left behind for inspection, and so is
the Flutter build tree. Both live under `build/`, which is git-ignored.

## What is in the image

Mounting the DMG shows three items, which is what makes the window work as
drag-to-install:

- `Subtitle Converter.app` — a universal binary (`x86_64` + `arm64`), macOS 12.0
  or later.
- `Applications` → `/Applications`
- `LICENSE.txt` — the Apache-2.0 text, copied into the staging folder by the
  script so the image carries a copy of the licence (section 4 of the licence).
  It is named `.txt` so a double click opens it in TextEdit.

The product is located by scanning `build/macos/Build/Products/<Configuration>/`
for `*.app` rather than hardcoding the name, so renaming the app in
`macos/Runner/Configs/AppInfo.xcconfig` does not break packaging.

## Signing and Gatekeeper

`flutter build macos` signs the app **ad-hoc** (`Signature=adhoc`,
`TeamIdentifier=not set`). Consequences:

- The app runs on the machine that built it.
- Copied to another Mac it trips Gatekeeper; the user has to right-click → Open,
  or the app must be signed and notarised first.
- The ad-hoc signature carries `com.apple.security.get-task-allow`, which Xcode
  injects whenever there is no Developer ID; a Developer ID signature does not
  include it.

Distributing the image publicly needs an Apple Developer ID certificate and a
notarisation step, neither of which this script performs.

## Entitlements

Both `macos/Runner/Release.entitlements` and
`macos/Runner/DebugProfile.entitlements` carry
`com.apple.security.files.user-selected.read-write`. `file_selector` requires it:
under the App Sandbox the picker still opens without it, but the sandbox then
denies every path the user selects — no file can be added and no output written.
Keep the two files identical, as Flutter's macOS guide asks. See
[`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) (File safety).

## Verified

Built, packaged and launched on macOS 26.6.2 with Xcode 26.6 and Flutter 3.47.4:
the release `.app` stays alive after launch, and the mounted image contains the
app plus the `/Applications` symlink. CI's macOS job (`.github/workflows/ci.yml`)
builds and launches the same `.app` but does not build a DMG.
