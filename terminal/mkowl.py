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
    ap.add_argument('--canvas', metavar='WxH',
                    help='composite onto an opaque canvas of this size, e.g. 2560x1440. '
                         'Without it the output is the bare mask at its own size, which is '
                         'what a terminal background wants; with it you get a finished '
                         'picture, which is what a lock screen wants.')
    ap.add_argument('--bg', default='#282828',
                    help='canvas colour (default #282828, the ground everything else is '
                         'tuned against). Only used with --canvas.')
    ap.add_argument('--fit', type=float, default=0.78, metavar='F',
                    help='fraction of the canvas height the owl occupies (default 0.78). '
                         'Only used with --canvas.')
    ap.add_argument('--y', type=float, default=0.5, metavar='F',
                    help="where the owl's vertical centre sits, as a fraction of canvas "
                         'height (default 0.5). Lower values lift it, which is how you '
                         'clear a login box that sits dead centre. Only used with --canvas.')
    args = ap.parse_args()

    tint = TINTS.get(args.tint, args.tint).lstrip('#')
    if len(tint) != 6:
        sys.exit(f'not a hex colour or a known name: {args.tint}')
    rgb = tuple(int(tint[i:i + 2], 16) for i in (0, 2, 4))

    mask = Image.open(args.mask).convert('L')
    out = Image.new('RGBA', mask.size, rgb + (0,))
    out.putalpha(mask)

    if args.canvas:
        try:
            cw, ch = (int(n) for n in args.canvas.lower().split('x'))
        except ValueError:
            sys.exit(f'--canvas wants WxH, e.g. 2560x1440: {args.canvas}')
        bg = args.bg.lstrip('#')
        if len(bg) != 6:
            sys.exit(f'--bg is not a hex colour: {args.bg}')
        bg_rgb = tuple(int(bg[i:i + 2], 16) for i in (0, 2, 4))

        # Fit by height. The mask is portrait and every screen this lands on is
        # landscape, so height is always the binding dimension -- fitting by the
        # smaller ratio would leave the owl the same size and the arithmetic
        # harder to read.
        target_h = int(ch * args.fit)
        scale = target_h / out.height
        owl = out.resize((max(1, round(out.width * scale)), target_h), Image.LANCZOS)

        canvas = Image.new('RGB', (cw, ch), bg_rgb)
        canvas.paste(owl, ((cw - owl.width) // 2,
                           int(ch * args.y) - owl.height // 2), owl)
        canvas.save(args.out)
        print(f'{args.out}  {cw}x{ch}  owl #{tint} on #{bg}  fit={args.fit} y={args.y}')
        return

    out.save(args.out)
    print(f'{args.out}  {out.size[0]}x{out.size[1]}  #{tint}')


if __name__ == '__main__':
    main()
