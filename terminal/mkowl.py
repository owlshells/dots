#!/usr/bin/env python3
"""Tint the owl mask and write a terminal background image.

    ./mkowl.py                       # slate, the current default
    ./mkowl.py --tint '#C6C4BE'      # brighter
    ./mkowl.py -o /mnt/c/Users/matth/Pictures/owl-ash.png --tint '#A8A6A0'

Only the mask is stored, not a finished picture. The image is a single flat
colour behind an alpha mask, so the colour is redundant data -- keeping the mask
alone is a third the size and regenerates any tint, which matters because the
tint is the part that gets retuned.

Writing to a *new filename* every time is not optional: Windows Terminal caches
backgroundImage by path and will keep rendering the old bitmap from an unchanged
name, even in a fresh tab. See README.md.
"""
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit('needs Pillow:  pip install --user Pillow')

HERE = os.path.dirname(os.path.abspath(__file__))
TINTS = {'bone': '#C6C4BE', 'ash': '#A8A6A0', 'slate': '#8A8984', 'char': '#6E6D69'}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--tint', default='slate',
                    help='hex colour, or one of: ' + ', '.join(f'{k} ({v})' for k, v in TINTS.items()))
    ap.add_argument('-o', '--out', default='owl.png', help='output path')
    ap.add_argument('--mask', default=os.path.join(HERE, 'owl-mask.png'))
    args = ap.parse_args()

    tint = TINTS.get(args.tint, args.tint).lstrip('#')
    if len(tint) != 6:
        sys.exit(f'not a hex colour or a known name: {args.tint}')
    rgb = tuple(int(tint[i:i + 2], 16) for i in (0, 2, 4))

    mask = Image.open(args.mask).convert('L')
    out = Image.new('RGBA', mask.size, rgb + (0,))
    out.putalpha(mask)
    out.save(args.out)
    print(f'{args.out}  {out.size[0]}x{out.size[1]}  #{tint}')


if __name__ == '__main__':
    main()
