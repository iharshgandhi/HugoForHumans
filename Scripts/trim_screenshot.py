#!/usr/bin/env python3
"""
Crops a page screenshot to its real content bounds.

A page captured into a deliberately tall viewport has empty margin above *and*
below the content, and in a slide that reads as a layout mistake. This finds the
topmost and bottommost rows that differ from the page background and crops to
them, with a small margin.

    ./trim_screenshot.py <source.png> <dest.png> [margin]
"""
import sys
from PIL import Image

MARGIN = 24


def main() -> None:
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    src, dest = sys.argv[1], sys.argv[2]
    margin = int(sys.argv[3]) if len(sys.argv) > 3 else MARGIN

    img = Image.open(src).convert("RGB")
    w, h = img.size
    px = img.load()
    bg: tuple = px[3, 3]  # type: ignore[index]

    def differs(x: int, y: int) -> bool:
        p: tuple = px[x, y]  # type: ignore[index]
        return abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]) > 20

    top, bottom = None, None
    for y in range(h):
        if any(differs(x, y) for x in range(0, w, 7)):
            if top is None:
                top = y
            bottom = y

    if top is None or bottom is None:
        # A uniform image: keep it as-is, since cropping would be destructive.
        img.save(dest)
        print(h)
        return

    out_top = max(0, top - margin)
    out_bottom = min(h, bottom + 1 + margin)
    img.crop((0, out_top, w, out_bottom)).save(dest)
    print(out_bottom - out_top)


if __name__ == "__main__":
    main()
