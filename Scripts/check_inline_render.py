#!/usr/bin/env python3
"""
Measures the inline image in an editor screenshot: is it drawn, is its aspect
ratio right, and does it sit between the two surrounding sentences?

Looking at a composite screenshot is not enough on its own. An earlier capture
drew the inspector twice at two offsets, which made a correct image look
clipped, portrait-shaped and stripped of its contents. These are the numbers
that would have caught that, and they fail loudly rather than reassuringly.

    ./Scripts/check_inline_render.py <editor-screenshot.png>
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install --user Pillow")

# The exact fill makeSampleImage paints. The editor's own backgrounds are
# #1C1C1C and #212629, far enough away to be unambiguous.
FIELD = (0x25, 0x2D, 0x35)
BAR = (0xED, 0x84, 0x2F)
SOURCE_RATIO = 900 / 500


def near(pixel, target, tolerance=3):
    return all(abs(pixel[i] - target[i]) <= tolerance for i in range(3))


def light(pixel):
    return min(pixel) > 150


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    image = Image.open(path).convert("RGB")
    width, height = image.size
    pixels = image.load()

    field = [(x, y) for y in range(height) for x in range(width)
             if near(pixels[x, y], FIELD)]
    bar = sum(1 for y in range(height) for x in range(width)
              if near(pixels[x, y], BAR, 45))

    print(f"{path}: {width}x{height}")
    if not field:
        print("  field: 0 px")
        print("\nFAIL: no image is drawn in the writing area")
        return 1

    xs = [p[0] for p in field]
    ys = [p[1] for p in field]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    ratio = w / h
    print(f"  field: {len(field):7d} px  block {w}x{h} at ({x0},{y0})")
    print(f"  bar:   {bar:7d} px")
    print(f"  aspect: {ratio:.2f}  (source {SOURCE_RATIO:.2f})")

    # Text rows in the writing column, above and below the picture.
    column = range(0, min(width, 700))

    def rows_with_text(lo, hi):
        return [y for y in range(max(0, lo), min(height, hi))
                if sum(1 for x in column if light(pixels[x, y])) > 3]

    above = rows_with_text(0, y0)
    below = rows_with_text(y1, height)
    print(f"  text rows above: {len(above)}   below: {len(below)}")

    problems = []
    if not 1.2 < ratio < 2.6:
        problems.append(f"aspect {ratio:.2f} is not a scaled 900x500")
    if bar < 150:
        problems.append("the accent bar is missing, so the picture is clipped")
    if not above or not below:
        problems.append("the picture is not between the two paragraphs")
    # The window includes the inspector, so the picture is measured against the
    # space left of it rather than against the whole frame.
    if x0 > 0.70 * width:
        problems.append("the picture starts too far right, inside the inspector")
    if x1 > width * 0.98:
        problems.append("the picture runs off the right edge")

    if problems:
        for problem in problems:
            print(f"  ! {problem}")
        print("\nFAIL")
        return 1
    print("\nPASS: a correctly scaled image is drawn between the two paragraphs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
