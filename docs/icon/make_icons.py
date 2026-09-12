#!/usr/bin/env python3
"""Temporary helper: regenerate every platform's app icon from docs/icon/raw.png.

Run it whenever the source artwork changes:

    python docs/icon/make_icons.py

It trims the transparent border off the artwork, re-centres it on a square
canvas with a small margin, and writes:

  * windows/runner/resources/app_icon.ico            (16..256, multi-size)
  * macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_<n>.png
  * linux/runner/resources/app_icon_<n>.png          (hicolor sizes)

Windows and macOS are wired up already: Runner.rc embeds the .ico (and the MSI
packaging reuses the same file), while Contents.json names the macOS PNGs. The
Linux files have no consumer yet -- Flutter's Linux runner has no icon slot --
so they are generated for completeness and must be installed by hand.

Requires Pillow. This is throwaway asset prep, not part of the build.
"""

from __future__ import annotations

import io
import struct
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - operator feedback only
    sys.exit("Pillow is required: pip install pillow")

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / "raw.png"

# Alpha at or below this counts as speckle, not artwork. The raw export carries
# ~12k stray pixels in the 1..16 range which drag a naive alpha bounding box out
# to the canvas edge (0, 9, 1192, 1206) instead of the real artwork box
# (126, 101, 1147, 1147).
ALPHA_CUTOFF = 16

# Transparent breathing room per side, as a fraction of the final canvas.
MARGIN = 0.04

ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)
MACOS_SIZES = (16, 32, 64, 128, 256, 512, 1024)
LINUX_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)


def content_box(image: Image.Image) -> tuple[int, int, int, int]:
    """Bounding box of the real artwork, ignoring near-transparent speckle."""
    opaque = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUTOFF else 0)
    box = opaque.getbbox()
    if box is None:
        sys.exit(f"{SOURCE} looks fully transparent; nothing to convert")
    return box


def square_master(image: Image.Image) -> Image.Image:
    """Crop to the artwork, then centre it on a square canvas with margin."""
    art = image.crop(content_box(image))
    width, height = art.size
    side = max(width, height)
    canvas = round(side / (1 - 2 * MARGIN))
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(art, ((canvas - width) // 2, (canvas - height) // 2), art)
    return out


def render(master: Image.Image, size: int) -> Image.Image:
    """Downscale the master straight to `size`; reducing_gap speeds the trip."""
    return master.resize((size, size), Image.Resampling.LANCZOS, reducing_gap=2.0)


def _dib_frame(image: Image.Image) -> bytes:
    """A 32bpp BI_RGB frame: BITMAPINFOHEADER, BGRA rows bottom-up, AND mask."""
    width, height = image.size
    buffer = io.BytesIO()
    image.save(buffer, format="DIB")  # Pillow writes the header plus XOR pixels
    data = bytearray(buffer.getvalue())
    # biHeight spans the XOR image and the AND mask, so it is twice the height.
    struct.pack_into("<i", data, 8, height * 2)
    # The AND mask is 1bpp, rows padded to 4 bytes. All zero: with a 32bpp frame
    # transparency comes from the alpha channel, but the mask must still be there
    # or Windows reads past the frame while rendering.
    mask_stride = ((width + 31) // 32) * 4
    data += bytes(mask_stride * height)
    return bytes(data)


def _png_frame(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def write_ico(master: Image.Image, dest: Path) -> None:
    """Write a multi-size .ico shaped like the one Flutter ships.

    Small and mid sizes are DIB frames and only the 256px frame is PNG. PNG
    frames are only understood by the Vista+ shell; the Windows Installer icon
    paths behind ARPPRODUCTICON and the shortcut icon are not reliable with an
    all-PNG .ico, so the split above is deliberate. Pillow cannot mix the two
    encodings in one file, hence the hand-assembled directory below.
    """
    frames = []
    for size in ICO_SIZES:
        image = render(master, size)
        blob = _png_frame(image) if size == 256 else _dib_frame(image)
        frames.append((size, blob))

    header = struct.pack("<HHH", 0, 1, len(frames))  # reserved, type=icon, count
    offset = len(header) + 16 * len(frames)
    entries = bytearray()
    payload = bytearray()
    for size, blob in frames:
        # A zero dimension byte means 256, the largest the format can express.
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
        payload += blob
    dest.write_bytes(bytes(header) + bytes(entries) + bytes(payload))


def write_pngs(master: Image.Image, directory: Path, sizes: tuple[int, ...]) -> list[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    written = []
    for size in sizes:
        dest = directory / f"app_icon_{size}.png"
        render(master, size).save(dest, format="PNG", optimize=True)
        written.append(dest)
    return written


def main() -> int:
    if not SOURCE.exists():
        sys.exit(f"missing source artwork: {SOURCE}")

    with Image.open(SOURCE) as raw:
        source_size = raw.size
        master = square_master(raw.convert("RGBA"))
    print(f"source   {SOURCE.relative_to(REPO_ROOT)} {source_size[0]}x{source_size[1]}")
    print(f"master   square {master.size[0]}x{master.size[1]} (margin {MARGIN:.0%}/side)")

    ico = REPO_ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    write_ico(master, ico)
    print(f"windows  {ico.relative_to(REPO_ROOT)}  sizes={list(ICO_SIZES)}")

    macos_dir = REPO_ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for path in write_pngs(master, macos_dir, MACOS_SIZES):
        print(f"macos    {path.relative_to(REPO_ROOT)}")

    linux_dir = REPO_ROOT / "linux" / "runner" / "resources"
    for path in write_pngs(master, linux_dir, LINUX_SIZES):
        print(f"linux    {path.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
