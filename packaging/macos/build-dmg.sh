#!/usr/bin/env bash
#
# Builds a drag-to-install .dmg for Subtitle Converter.
#
# The application itself comes from `flutter build macos --<configuration>`,
# which Flutter already knows how to do. What it has no command for is the disk
# image around it: this script adds the .app to a staging folder next to an
# /Applications symlink and compresses that folder with hdiutil, which is what
# makes the mounted window work as drag-to-install.
#
# Only tools that ship with macOS are used (hdiutil, ln, cp), so there is
# nothing to install and no network access is needed at any point.
#
# The .app is signed ad-hoc by the Flutter build. It runs on the machine that
# built it; copying the DMG to another Mac trips Gatekeeper until the app is
# signed with a Developer ID and notarised.
#
# Usage: see --help.

set -euo pipefail

SkipBuild=0
Version=''
Configuration='release'
FlutterExe=''

PackageName='sub-converter'

usage() {
    cat <<'EOF'
Builds a drag-to-install .dmg for Subtitle Converter.

Usage:
  packaging/macos/build-dmg.sh [options]

Options:
  --skip-build           Reuse an existing build instead of running flutter build.
  --version X.Y.Z        Version for the file name (default: pubspec.yaml "version:").
  --configuration NAME   Flutter build configuration: release (default), profile or debug.
  --flutter-exe PATH     Path to the flutter executable (default: $FLUTTER_EXE, else PATH).
  -h, --help             Show this help.

Output:
  build/dmg/sub-converter-<version>.dmg
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build)     SkipBuild=1 ;;
        --version)        Version="${2:-}"; shift ;;
        --configuration)  Configuration="${2:-}"; shift ;;
        --flutter-exe)    FlutterExe="${2:-}"; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

case "$Configuration" in
    release|profile|debug) ;;
    *) echo "Unknown configuration '$Configuration' (expected release, profile or debug)." >&2; exit 2 ;;
esac

if [ "$(uname -s)" != 'Darwin' ]; then
    echo 'This script builds a macOS disk image and only runs on macOS.' >&2
    exit 1
fi

ScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RepoRoot="$(cd "$ScriptDir/../.." && pwd)"

# Flutter capitalises the configuration name when it names the output folder.
ConfigDir="$(printf '%s' "${Configuration:0:1}" | tr '[:lower:]' '[:upper:]')${Configuration:1}"
BuildDir="$RepoRoot/build/macos/Build/Products/$ConfigDir"
OutDir="$RepoRoot/build/dmg"

resolve_version() {
    if [ -n "$Version" ]; then printf '%s\n' "$Version"; return; fi

    local pubspec="$RepoRoot/pubspec.yaml" parsed
    if [ ! -f "$pubspec" ]; then
        echo "pubspec.yaml not found at $pubspec; pass --version explicitly." >&2
        exit 1
    fi
    parsed="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' "$pubspec" | head -n 1)"
    if [ -z "$parsed" ]; then
        echo "Could not parse an x.y.z version from $pubspec; pass --version explicitly." >&2
        exit 1
    fi
    printf '%s\n' "$parsed"
}

resolve_flutter() {
    if [ -n "$FlutterExe" ]; then printf '%s\n' "$FlutterExe"; return; fi
    if [ -n "${FLUTTER_EXE:-}" ]; then printf '%s\n' "$FLUTTER_EXE"; return; fi

    # Resolve flutter from the PATH so no machine-specific SDK location is
    # baked into this script.
    command -v flutter 2>/dev/null || {
        echo 'flutter was not found on the PATH; pass --flutter-exe or set FLUTTER_EXE.' >&2
        exit 1
    }
}

Version="$(resolve_version)"
echo "Subtitle Converter DMG build - version $Version, configuration $Configuration"

if [ "$SkipBuild" -eq 1 ]; then
    echo
    echo "==> --skip-build set; reusing $BuildDir"
else
    FlutterBin="$(resolve_flutter)"
    echo
    echo "==> flutter build macos --$Configuration"
    ( cd "$RepoRoot" && "$FlutterBin" build macos "--$Configuration" )
fi

# Find the product instead of hardcoding its name, so renaming the app in
# macos/Runner/Configs/AppInfo.xcconfig does not break packaging.
shopt -s nullglob
apps=("$BuildDir"/*.app)
shopt -u nullglob

if [ ${#apps[@]} -eq 0 ]; then
    echo "No .app found in $BuildDir; build first or drop --skip-build." >&2
    exit 1
fi
AppPath="${apps[0]}"
AppName="$(basename "$AppPath")"

echo
echo "==> staging $AppName"
StageDir="$OutDir/stage"
rm -rf "$StageDir"
mkdir -p "$StageDir"
# COPYFILE_DISABLE keeps cp from writing AppleDouble ._ sidecar files into the
# image, which would otherwise show up next to the app in the mounted window.
COPYFILE_DISABLE=1 cp -R "$AppPath" "$StageDir/"
# Apache-2.0 section 4 asks for a copy of the licence in each binary
# distribution, and the image is how the app reaches macOS users.
LicenseFile="$RepoRoot/LICENSE"
if [ ! -f "$LicenseFile" ]; then
    echo "LICENSE not found at $LicenseFile" >&2
    exit 1
fi
COPYFILE_DISABLE=1 cp "$LicenseFile" "$StageDir/LICENSE.txt"
ln -s /Applications "$StageDir/Applications"

DmgPath="$OutDir/$PackageName-$Version.dmg"
mkdir -p "$OutDir"

echo
echo '==> hdiutil create (UDZO)'
hdiutil create \
    -volname "${AppName%.app}" \
    -srcfolder "$StageDir" \
    -ov -format UDZO \
    "$DmgPath" > /dev/null

if [ ! -f "$DmgPath" ]; then
    echo "hdiutil reported success but $DmgPath does not exist." >&2
    exit 1
fi

SizeMb="$(du -m "$DmgPath" | cut -f1)"
echo
echo "Built $DmgPath (${SizeMb} MB)"
