# Subtitle Converter MSI installer

Builds a per-machine x64 Windows Installer package (`.msi`) for the Subtitle
Converter Flutter desktop app using the [WiX Toolset v3](https://github.com/wixtoolset/wix3).

## Why WiX v3 (and not the v4/v5 `dotnet tool`)

The WiX v4+ CLI ships as a `dotnet tool`, which needs a .NET SDK. Instead the
**portable WiX v3.14 binaries** are used: `candle.exe` / `heat.exe` /
`light.exe` are .NET Framework programs and run without administrator rights.
`build-msi.ps1` downloads and extracts them on first use into
`packaging/msi/.tools/wix314/` (git-ignored, ~117 MB extracted). If that folder
already exists — for example because it was copied from another machine — no
download happens and the build works offline.

## Dependencies

- **Internet access on the first build only** (to download the WiX portable ZIP,
  ~40 MB). Later builds reuse the extracted toolset.
- **Windows PowerShell 5.1** (the default on Windows 10/11).
- **Flutter SDK** on the `PATH`, or pass `-FlutterExe` / set the `FLUTTER_EXE`
  environment variable.
- Nothing else. WiX is not installed system-wide and no admin rights are needed
  to *build* the package.

## Usage

```powershell
# Full build: flutter build windows --release, then package.
powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1

# Package an existing build\windows\x64\runner\Release folder.
powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1 -SkipBuild

# Override the version (default: x.y.z part of pubspec.yaml's "version:").
powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1 -Version 0.2.0
```

Parameters:

| Parameter        | Default                                 | Notes                            |
| ---------------- | --------------------------------------- | -------------------------------- |
| `-SkipBuild`     | off                                     | Reuse the existing Flutter output. |
| `-Version`       | `pubspec.yaml` `version:` x.y.z          | MSI requires a numeric `x.y.z`.  |
| `-Configuration` | `release`                               | `release`, `profile` or `debug`. |
| `-FlutterExe`    | `$env:FLUTTER_EXE`, else PATH `flutter`  | Path to `flutter.bat`.           |

## Output

`build\msi\sub-converter-<version>.msi` — a single self-contained MSI (the CAB is
embedded). Intermediate files (`Components.wxs`, `.wixobj`, `.wixpdb`) are
written to `packaging/msi/.build/` and are not committed.

## How files are collected

The Flutter Release folder is harvested at build time by `heat.exe`
(`-var var.ReleaseDir`), so every runtime file is packaged automatically and the
generated `Components.wxs` contains no build-machine absolute paths. For this app
that is:

- `sub_converter.exe`
- `flutter_windows.dll`, `desktop_drop_plugin.dll`,
  `file_selector_windows_plugin.dll`
- `data\**` (`app.so`, `icudtl.dat`, `flutter_assets\**`, `NOTICES.Z`)
- `native_assets.json`

Adding a plugin later needs no edit here: its DLL is picked up by the next
harvest.

## Installation behaviour

- **Per-machine** install (`InstallScope="perMachine"`), x64 only.
- Standard WiX wizard (`WixUI_InstallDir`): licence page, **install-directory
  page** and a **Start Menu shortcut page**.
- Installs to the chosen folder (default `%ProgramFiles%\Subtitle Converter`).
- Creates an all-users Start Menu shortcut (**Subtitle Converter**) — ticked
  **by default**; clear the checkbox on the shortcut page to skip it. A silent
  install (`/qn`) keeps the default, because the feature is installed at
  `Level="1"`.
- Registers an entry in Add/Remove Programs with the application icon.
- `MajorUpgrade` blocks downgrades and replaces an older version on upgrade.
  `AllowSameVersionUpgrades="yes"` is set as well: the Flutter build stamps
  every exe/dll with the pubspec version, so reinstalling a **rebuilt** MSI
  without a version bump must remove the previous product first — otherwise
  the Windows Installer keeps the old versioned files (the exe in particular)
  and registers a side-by-side duplicate. Consequence: a same-version
  reinstall runs a full uninstall + install, and the running app must be
  closed during the upgrade.
- Installing/uninstalling requires elevation (UAC), as expected for a
  per-machine package.

Silent install / uninstall:

```powershell
msiexec /i sub-converter-0.1.0.msi /qn
msiexec /x sub-converter-0.1.0.msi /qn
```

To inspect or extract the package without installing it:

```powershell
msiexec /a sub-converter-0.1.0.msi /qn TARGETDIR=C:\Temp\extracted
```

## Licence text

`license.rtf` is shown on the licence page. It currently states what the package
installs, points at the bundled `NOTICES.Z` for third-party licence texts, and
disclaims warranty. **Replace it with your own EULA before distributing the
installer publicly.**
