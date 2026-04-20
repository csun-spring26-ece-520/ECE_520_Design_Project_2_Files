#!/usr/bin/env python3
"""
File: show_result.py

Description:

    Reads the original grayscale hex file and the filtered output hex file
    produced by the Verilog testbench, then displays both images side by side
    in a labeled Matplotlib window and saves a comparison PNG.

Usage:
    python show_result.py [options]

Options:
    --input   F   Input  hex file  (default: image_in.hex)
    --output  F   Output hex file  (default: image_out.hex)
    --info    F   Image info file  (default: image_info.txt)
    --filter  S   Filter name shown in the title (default: "Filtered")
    --save    F   Save comparison PNG to this path (default: comparison.png)

Example:
    python show_result.py --filter "Sobel Edge" --save results/sobel.png
"""

import argparse
import os
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec

def parse_args():
    parser = argparse.ArgumentParser(
        description="Display original and filtered images side by side."
    )
    parser.add_argument("--input",  default="image_in.hex",   help="Input hex file   (default: image_in.hex)")
    parser.add_argument("--output", default="image_out.hex",  help="Output hex file  (default: image_out.hex)")
    parser.add_argument("--info",   default="image_info.txt", help="Image info file  (default: image_info.txt)")
    parser.add_argument("--filter", default="Filtered",       help="Filter name for title")
    parser.add_argument("--save",   default="comparison.png", help="Save comparison PNG (default: comparison.png)")
    return parser.parse_args()


def read_hex_image(hex_path, width, height):
    """Read a hex file (one 2-digit hex value per line) into a NumPy array.

    Lines that contain uninitialized simulation values ('xx', 'XX', 'x', 'X')
    or any other non-hex token are replaced with 0 and a warning is printed.
    """
    pixels = []
    bad_lines = 0
    with open(hex_path, "r") as fh:
        for lineno, line in enumerate(fh, start=1):
            line = line.strip()
            if not line:
                continue
            # Replace any x/z nibbles (Verilog unknowns) with 0
            sanitized = line.lower().replace("x", "0").replace("z", "0")
            try:
                pixels.append(int(sanitized, 16))
            except ValueError:
                pixels.append(0)
                bad_lines += 1
                if bad_lines <= 5:
                    print(f"[show_result] WARNING: line {lineno}: "
                          f"unreadable token '{line}' replaced with 0")

    if bad_lines > 0:
        print(f"[show_result] WARNING: {bad_lines} invalid token(s) in '{hex_path}' "
              f"replaced with 0. Re-run the simulation to regenerate the file.")

    expected = width * height
    if len(pixels) != expected:
        print(f"[show_result] WARNING: {hex_path} has {len(pixels)} pixels, "
              f"expected {expected} ({width}x{height}).")

    # Pad with zeros if short, truncate if long
    pixels = (pixels + [0] * expected)[:expected]
    arr = np.array(pixels, dtype=np.uint8).reshape(height, width)
    return arr


def main():
    args = parse_args()

    # ── Read image dimensions ─────────────────────────────────────────────────
    with open(args.info, "r") as fh:
        lines = fh.read().strip().splitlines()
    width  = int(lines[0])
    height = int(lines[1])
    print(f"[show_result] Image dimensions: {width} x {height}")

    # ── Load hex images ───────────────────────────────────────────────────────
    img_in  = read_hex_image(args.input,  width, height)
    img_out = read_hex_image(args.output, width, height)

    # ── Compute a simple difference image for reference ───────────────────────
    diff = np.abs(img_in.astype(np.int16) - img_out.astype(np.int16)).astype(np.uint8)

    # ── Plot ──────────────────────────────────────────────────────────────────
    fig = plt.figure(figsize=(14, 5))
    fig.suptitle(f"Image Filter Comparison — {args.filter}",
                 fontsize=14, fontweight="bold", y=1.01)

    gs = gridspec.GridSpec(1, 3, figure=fig, wspace=0.35)

    titles = ["Original (Grayscale)", args.filter, "Difference (|in − out|)"]
    images = [img_in, img_out, diff]

    for idx, (title, data) in enumerate(zip(titles, images)):
        ax = fig.add_subplot(gs[idx])
        im = ax.imshow(data, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
        ax.set_title(title, fontsize=11)
        ax.axis("off")
        plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)

    plt.tight_layout()

    # ── Save and show ─────────────────────────────────────────────────────────
    os.makedirs(os.path.dirname(os.path.abspath(args.save)), exist_ok=True) if os.path.dirname(args.save) else None
    plt.savefig(args.save, dpi=150, bbox_inches="tight")
    print(f"[show_result] Saved comparison image → '{args.save}'")
    plt.show()


if __name__ == "__main__":
    main()
