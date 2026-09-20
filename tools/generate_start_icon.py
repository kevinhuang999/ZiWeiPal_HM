"""
Generate startIcon.png for ZiWeiPal_HM (HarmonyOS startWindow icon).

Why this exists:
  The previous startIcon.png was a full 512x512 artwork (opaque chart plate).
  HarmonyOS renders startWindowIcon centered on top of startWindowBackground,
  so an opaque full-bleed image covers the whole window and reads as "just a
  big picture" instead of a clean icon.

  This script renders the brand badge used on the home page -- a cinnabar
  circle with a gold "紫" glyph -- on a TRANSPARENT background, so the OS
  background colour shows through, matching the home header.

Design tokens are kept in sync with entry/src/main/ets/engine/Constants.ets
  primary : #9B2E23  (cinnabar circle fill)
  goldInk : #F8E9C8  (glyph colour)
  ratio   : glyph / circle = 28 / 60 (from the 60x60 in-app badge)

Portability notes:
  - Output path is resolved relative to this script, not hardcoded.
  - Fonts are located via %WINDIR% with sensible fallbacks.
  - No third-party config, no absolute user paths.

Usage:
  python generate_start_icon.py [--size 512] [--out <path>]
"""

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

# --- design tokens (mirror Constants.ets) ---------------------------------
CINNABAR = (0x9B, 0x2E, 0x23, 255)   # COLORS.primary
GOLD_INK = (0xF8, 0xE9, 0xC8, 255)   # COLORS.goldInk
GLYPH = "紫"
GLYPH_RATIO = 28.0 / 60.0            # home badge: fontSize 28 on circle 60
CIRCLE_RATIO = 0.72                  # circle diameter / canvas size
SS = 4                               # supersampling factor for antialiasing

FONT_CANDIDATES = (
    "simhei.ttf",    # Heiti - bold, survives downscaling
    "msyhbd.ttc",    # Microsoft YaHei Bold
    "msyh.ttc",      # Microsoft YaHei
    "simsun.ttc",    # fallback serif
)


def find_font_dir() -> str:
    windir = os.environ.get("WINDIR") or os.environ.get("SystemRoot") or r"C:\Windows"
    return os.path.join(windir, "Fonts")


def load_font(px: int) -> ImageFont.FreeTypeFont:
    fdir = find_font_dir()
    for name in FONT_CANDIDATES:
        path = os.path.join(fdir, name)
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, px)
            except OSError:
                continue
    sys.exit(f"No usable CJK font found in {fdir}. Install a Chinese font first.")


def render(size: int) -> Image.Image:
    """Draw at size*SS then downscale -> smooth circle edges."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = cy = big / 2.0
    r = (big * CIRCLE_RATIO) / 2.0
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CINNABAR)

    font = load_font(int(big * CIRCLE_RATIO * GLYPH_RATIO))
    # Nudge down slightly: CJK glyph boxes carry extra head room.
    d.text((cx, cy + big * 0.012), GLYPH, font=font, fill=GOLD_INK, anchor="mm")

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    # this script lives in <project>/tools/, so the project root is one level up
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default_out = os.path.join(
        project_root, "entry", "src", "main", "resources", "base", "media",
        "startIcon.png",
    )

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--size", type=int, default=512, help="output edge length in px")
    ap.add_argument("--out", default=default_out, help="output PNG path")
    args = ap.parse_args()

    img = render(args.size)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    img.save(args.out, "PNG")

    px = img.load()
    corner = px[0, 0]
    print(f"written : {args.out}")
    print(f"size    : {args.size}x{args.size}  mode={img.mode}")
    print(f"corner  : RGBA{corner}  (alpha 0 == transparent background OK)"
          if corner[3] == 0 else
          f"corner  : RGBA{corner}  <-- WARNING: background is not transparent")


if __name__ == "__main__":
    main()
