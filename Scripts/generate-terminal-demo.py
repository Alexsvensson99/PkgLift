#!/usr/bin/env python3
"""Render the README terminal demo from the recorded v0.3.0 fixture output."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 960
HEIGHT = 540
BACKGROUND = "#070b10"
CHROME = "#0d131a"
TEXT = "#dbe7f3"
MUTED = "#778697"
ACCENT = "#62e6a7"
BLUE = "#8ab4ff"

TRANSCRIPT = [
    ("command", "$ pkglift analyze --no-color"),
    ("muted", "Project: Fixtures/MixedLanguageSDWebImage"),
    ("plain", "Readiness score: 80/100"),
    ("plain", "Direct dependencies: 1"),
    ("accent", "AUTO     SDWebImage 5.18.1"),
    ("muted", "         exact registry + Swift/Objective-C evidence"),
    ("blank", ""),
    ("command", "$ pkglift plan --no-color"),
    ("plain", "Plan saved: .pkglift/plan.json"),
    ("accent", "AUTO 1  ·  REVIEW 0  ·  BLOCKED 0  ·  UNKNOWN 0"),
    ("blank", ""),
    ("command", "$ pkglift migrate --no-color"),
    ("plain", "Dry run mode. Add --apply to execute."),
    ("accent", "1 AUTO migration: SDWebImage → SwiftPM"),
]

VISIBLE_COUNTS = [1, 4, 6, 9, 10, 14]
DURATIONS = [900, 900, 1_100, 900, 1_100, 3_200]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("/System/Library/Fonts/Menlo.ttc"),
        Path("/System/Library/Fonts/Monaco.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    raise FileNotFoundError("Menlo or Monaco is required to render the terminal demo")


def render_frame(visible_count: int) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(image)
    body_font = load_font(18)
    title_font = load_font(15)

    draw.rectangle((0, 0, WIDTH, 46), fill=CHROME)
    for x, color in [(22, "#ff6b6b"), (44, "#ffd166"), (66, ACCENT)]:
        draw.ellipse((x - 6, 17, x + 6, 29), fill=color)
    draw.text((92, 15), "PkgLift v0.3.0 · repo-owned fixture · dry run", font=title_font, fill=MUTED)

    palette = {
        "command": TEXT,
        "plain": TEXT,
        "muted": MUTED,
        "accent": ACCENT,
        "blank": TEXT,
    }
    y = 76
    for kind, line in TRANSCRIPT[:visible_count]:
        if kind == "command":
            draw.text((34, y), "$", font=body_font, fill=ACCENT)
            draw.text((54, y), line[2:], font=body_font, fill=TEXT)
        else:
            draw.text((34, y), line, font=body_font, fill=palette[kind])
        y += 29

    draw.rounded_rectangle((30, 493, 930, 521), radius=8, fill="#101720", outline="#263341")
    draw.text((44, 498), "Condensed from v0.3.0 analysis, plan, and dry-run output — no apply performed", font=title_font, fill=BLUE)
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    frames = [render_frame(count) for count in VISIBLE_COUNTS]
    frames[0].save(
        args.output,
        save_all=True,
        append_images=frames[1:],
        duration=DURATIONS,
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"Rendered {args.output} ({args.output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
