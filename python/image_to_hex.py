"""
File: image_to_hex.py

Description:
    Converts an input image to a grayscale .hex memory file suitable for
    $readmemh in a Verilog testbench.

Usage:
    python image_to_hex.py <input_image> [options]

Options:
    --width   W   Resize image to W pixels wide  (default: 200)
    --height  H   Resize image to H pixels tall  (default: 150)
    --out     F   Output .hex file path          (default: image_in.hex)
    --info    F   Output metadata file path      (default: image_info.txt)

Outputs:
    <out>   One pixel per line as 2-digit uppercase hex (00 to FF).
            Pixels are written in row-major order (left-to-right, top-to-bottom).
    <info>  Plain-text file containing WIDTH and HEIGHT on separate lines,
            read by the Verilog testbench to size its loops.

Example:
    python image_to_hex.py flower.jpg --width 200 --height 150
"""

import argparse
import os
from PIL import Image


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert an image to a grayscale hex memory file for Verilog $readmemh."
    )
    parser.add_argument("input",            help="Path to the input image file.")
    parser.add_argument("--width",  type=int, default=200,            help="Output image width  (default: 200)")
    parser.add_argument("--height", type=int, default=150,            help="Output image height (default: 150)")
    parser.add_argument("--out",    default="image_in.hex",           help="Output hex file     (default: image_in.hex)")
    parser.add_argument("--info",   default="image_info.txt",         help="Output info file    (default: image_info.txt)")
    return parser.parse_args()


def main():
    args = parse_args()

    # Load, convert to grayscale, and resize
    print(f"[image_to_hex] Loading '{args.input}' ...")
    img = Image.open(args.input).convert("L")          # L = 8-bit grayscale
    img = img.resize((args.width, args.height), Image.LANCZOS)

    width, height = img.size
    print(f"[image_to_hex] Resized to {width} x {height} (W x H)")

    # Write hex file
    os.makedirs(os.path.dirname(os.path.abspath(args.out)),  exist_ok=True) if os.path.dirname(args.out) else None
    pixels = list(img.getdata()) # flat list, row-major

    with open(args.out, "w") as fh:
        for px in pixels:
            fh.write(f"{px:02X}\n")

    print(f"[image_to_hex] Wrote {len(pixels)} pixels → '{args.out}'")

    # Write info file
    with open(args.info, "w") as fh:
        fh.write(f"{width}\n{height}\n")

    print(f"[image_to_hex] Wrote image info (W={width}, H={height}) → '{args.info}'")


if __name__ == "__main__":
    main()
