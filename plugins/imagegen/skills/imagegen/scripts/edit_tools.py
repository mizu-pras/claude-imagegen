"""Region-locked image edits and edit verification (requires Pillow).

Codex image_gen re-renders the whole image on every edit, so pixels outside the
intended change drift. These commands lock everything outside an editable
region to the original and report how much actually changed.

Usage:
  edit_tools.py composite --original O --edited E --out OUT (--region R... | --mask M)
                          [--feather PX] [--diff DIFF.png] [--preview PREVIEW.png]
  edit_tools.py compare   --original O --edited E [--region R... | --mask M]
                          [--diff DIFF.png] [--preview PREVIEW.png]

--region x,y,w,h   Editable rectangle in original pixels, or as fractions (0-1) of
                   width/height when all four values are <= 1. Repeatable.
--mask M           Grayscale image; white = editable, black = locked. Resized to the
                   original's size if needed.
--feather PX       Soft blend width inside the region edge (default: 1% of the
                   shorter side, at least 4). Pixels outside stay exactly original.
--diff DIFF.png    Write an amplified difference heatmap (edited vs original) with
                   the editable region outlined in red.
--preview P.png    Write a zoomed side-by-side of the region plus a margin
                   (original | generated | final for composite, original | edited for
                   compare) on a checkerboard, for visual inspection with an image viewer.
"""

import argparse
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    sys.exit("Pillow is required: pip install pillow (or install uv so the script can fetch it).")

CHANGE_THRESHOLD = 24  # max per-channel difference counted as "changed"


def parse_region(text, size):
    try:
        vals = [float(v) for v in text.split(",")]
    except ValueError:
        sys.exit(f"Bad --region '{text}': expected x,y,w,h")
    if len(vals) != 4:
        sys.exit(f"Bad --region '{text}': expected x,y,w,h")
    w, h = size
    if all(0 <= v <= 1 for v in vals):
        vals = [vals[0] * w, vals[1] * h, vals[2] * w, vals[3] * h]
    x, y, rw, rh = (int(round(v)) for v in vals)
    return max(0, x), max(0, y), min(w, x + rw), min(h, y + rh)


def build_mask(args, size):
    if args.mask:
        mask = Image.open(args.mask).convert("L")
        if mask.size != size:
            mask = mask.resize(size, Image.NEAREST)
        return mask.point(lambda v: 255 if v >= 128 else 0)
    if not args.region:
        return None
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    for r in args.region:
        x0, y0, x1, y1 = parse_region(r, size)
        if x1 > x0 and y1 > y0:
            draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=255)
    return mask


def soften(mask, feather):
    """Feather inward only, over roughly `feather` px: outside the hard mask stays exactly 0."""
    if feather <= 0:
        return mask
    eroded = mask
    for _ in range(max(1, feather // 2)):
        eroded = eroded.filter(ImageFilter.MinFilter(3))
    soft = eroded.filter(ImageFilter.GaussianBlur(feather / 4))
    return ImageChops.multiply(soft, mask)


def load_pair(args):
    original = Image.open(args.original)
    edited = Image.open(args.edited)
    resized = edited.size != original.size
    o = original.convert("RGBA")
    e = edited.convert("RGBA")
    if resized:
        e = e.resize(o.size, Image.LANCZOS)
    return original, o, e, edited.size, resized


def changed_map(a, b):
    """L image: 255 where any channel (incl. alpha) differs by more than the threshold."""
    diff = ImageChops.difference(a, b)
    bands = diff.split()
    m = bands[0]
    for band in bands[1:]:
        m = ImageChops.lighter(m, band)
    return m, m.point(lambda v: 255 if v > CHANGE_THRESHOLD else 0)


def pct(count, total):
    return 100.0 * count / total if total else 0.0


def count_white(img, region=None):
    if region is not None:
        img = ImageChops.multiply(img, region)
    return img.histogram()[255]


def report(o, e, mask, label):
    total = o.size[0] * o.size[1]
    _, changed = changed_map(o, e)
    n_changed = count_white(changed)
    print(f"{label}: {pct(n_changed, total):.1f}% of all pixels changed")
    if mask is not None:
        inside = mask.histogram()[255]
        outside = total - inside
        n_in = count_white(changed, mask)
        n_out = n_changed - n_in
        print(f"  inside editable region:  {pct(n_in, inside):.1f}% changed ({inside} px)")
        print(f"  outside editable region: {pct(n_out, outside):.1f}% changed ({outside} px)")
        return n_in, inside, n_out
    return None


def write_diff(o, e, mask, path):
    raw, _ = changed_map(o, e)
    heat = raw.point(lambda v: min(255, v * 4)).convert("RGB")
    if mask is not None:
        edge = mask.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(5))
        heat.paste((255, 0, 0), (0, 0), edge)
    heat.save(path)
    print(f"diff heatmap: {path}")


def checkerboard(size, cell=16):
    board = Image.new("RGBA", size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(board)
    for y in range(0, size[1], cell):
        for x in range((y // cell) % 2 * cell, size[0], cell * 2):
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(205, 205, 205, 255))
    return board


def write_preview(panels, mask, path, max_width=1800):
    """panels: list of (label, RGBA image, outline_region)."""
    w, h = panels[0][1].size
    box = mask.getbbox() if mask is not None else None
    if box is None:
        box = (0, 0, w, h)
    margin = max(24, round(0.15 * max(box[2] - box[0], box[3] - box[1])))
    crop = (max(0, box[0] - margin), max(0, box[1] - margin),
            min(w, box[2] + margin), min(h, box[3] + margin))
    cw, ch = crop[2] - crop[0], crop[3] - crop[1]
    gap, label_h = 12, 28
    scale = min(4.0, (max_width - gap * (len(panels) - 1)) / (cw * len(panels)))
    pw, ph = max(1, round(cw * scale)), max(1, round(ch * scale))

    sheet = Image.new("RGB", (pw * len(panels) + gap * (len(panels) - 1), ph + label_h), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for i, (label, img, outline) in enumerate(panels):
        tile = img.crop(crop).resize((pw, ph), Image.LANCZOS)
        bg = checkerboard((pw, ph))
        bg.alpha_composite(tile)
        if outline and mask is not None:
            edge = mask.crop(crop).resize((pw, ph), Image.NEAREST).filter(ImageFilter.FIND_EDGES)
            edge = edge.filter(ImageFilter.MaxFilter(3))
            bg.paste((255, 0, 0, 255), (0, 0), edge)
        x = i * (pw + gap)
        sheet.paste(bg.convert("RGB"), (x, label_h))
        draw.text((x + 6, 8), label, fill=(255, 255, 255))
    sheet.save(path)
    print(f"preview: {path} (crop {crop[0]},{crop[1]} {cw}x{ch}, scale {scale:.2f}x)")


def cmd_compare(args):
    _, o, e, edited_size, resized = load_pair(args)
    if resized:
        print(f"note: edited size {edited_size[0]}x{edited_size[1]} differs from original "
              f"{o.size[0]}x{o.size[1]}; edited was resized for comparison")
    mask = build_mask(args, o.size)
    report(o, e, mask, "edited vs original")
    if args.diff:
        write_diff(o, e, mask, args.diff)
    if args.preview:
        write_preview([("original", o, True), ("edited", e, False)], mask, args.preview)


def cmd_composite(args):
    original, o, e, edited_size, resized = load_pair(args)
    mask = build_mask(args, o.size)
    if mask is None or mask.histogram()[255] == 0:
        sys.exit("composite needs a non-empty --region or --mask")
    if resized:
        print(f"note: generated size {edited_size[0]}x{edited_size[1]} resized to original "
              f"{o.size[0]}x{o.size[1]}")

    stats = report(o, e, mask, "raw generated vs original")
    feather = args.feather if args.feather is not None else max(4, round(min(o.size) * 0.01))
    result = Image.composite(e, o, soften(mask, feather))

    keep_alpha = original.mode in ("RGBA", "LA", "PA") or "transparency" in original.info
    final = result if keep_alpha else result.convert("RGB")
    final.save(args.out)

    saved = Image.open(args.out).convert("RGBA")
    raw_final, _ = changed_map(o, saved)
    any_diff = raw_final.point(lambda v: 255 if v else 0)
    outside = ImageChops.invert(mask)
    leaked = count_white(any_diff, outside)
    print(f"final: outside region identical to original: {'yes' if leaked == 0 else f'NO ({leaked} px differ)'}")
    if stats and stats[1] and pct(stats[0], stats[1]) < 1.0:
        print("warning: almost nothing changed inside the editable region; the edit may not have happened there")
    if args.diff:
        write_diff(o, saved, mask, args.diff)
    if args.preview:
        write_preview([("original", o, True), ("generated (raw)", e, True),
                       ("final (check the seam)", saved, False)], mask, args.preview)
    print(f"saved: {args.out}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("composite", "compare"):
        s = sub.add_parser(name)
        s.add_argument("--original", required=True)
        s.add_argument("--edited", required=True)
        s.add_argument("--region", action="append")
        s.add_argument("--mask")
        s.add_argument("--diff")
        s.add_argument("--preview")
        if name == "composite":
            s.add_argument("--out", required=True)
            s.add_argument("--feather", type=int)
    args = p.parse_args()
    if args.region and args.mask:
        sys.exit("use either --region or --mask, not both")
    (cmd_composite if args.cmd == "composite" else cmd_compare)(args)


if __name__ == "__main__":
    main()
