#!/usr/bin/env python3
"""capture_sensitivity_proof.py — proves that the region-limited tolerance
used by `mise run store:capture` (#1054 P-A) still FIRES on real changes, and
states its blind spot in numbers, using the SAME comparator the publish
decision and `--verify` use (scripts/compare_capture.py).

For one committed capture + its manifest region/bounds it synthesises:
  (a) outside-1px   : one pixel changed OUTSIDE the region          -> must VIOLATE
  (b) shift-4px     : the region's content shifted 4 px to the right -> must VIOLATE
  (c) retint-subtle : +N on one channel over the control's light fill
                      inside the region (what a tint-token edit does)  -> must VIOLATE
  (d) blind-spot    : +max_delta on one channel over EXACTLY max_px
                      pixels inside the region                         -> passes (this IS
                      the blind spot, stated in numbers), and the same
                      over max_px + 1 pixels                           -> must VIOLATE

Exit 0 iff every expectation holds. Writes the fixtures and a JSON summary
to --out so a reviewer can re-run the comparator by hand.

Usage:
    capture_sensitivity_proof.py --capture <committed.png> \
        (--manifest docs/app-store/captures/manifest.json --cell <path> |
         --region x0 y0 x1 y1 --max-delta N --max-px N) \
        [--retint 6] [--out build/store-capture/sensitivity/<cell>]
"""
import argparse
import json
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
COMPARATOR = os.path.join(HERE, "compare_capture.py")


def run_comparator(a, b, region, max_delta, max_px):
    cmd = [sys.executable, COMPARATOR, a, b, "--regions", json.dumps([list(region)]),
           "--max-delta", str(max_delta), "--max-px", str(max_px)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    summary = [ln for ln in proc.stdout.splitlines() if ln.startswith("RESULT ")]
    return proc.returncode, (summary[0] if summary else proc.stdout.strip()[-200:])


def light_fill_pixels(im, region, floor=240):
    """Pixels inside the region that belong to the control's light fill —
    the surface a tint token would recolour."""
    px = im.load()
    x0, y0, x1, y1 = region
    out = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if r >= floor and g >= floor and b >= floor:
                out.append((x, y))
    return out


def retint(im, pixels, delta):
    out = im.copy()
    px = out.load()
    for (x, y) in pixels:
        r, g, b = px[x, y]
        px[x, y] = (min(255, r + delta), g, b)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--capture", required=True)
    ap.add_argument("--manifest")
    ap.add_argument("--cell", help="manifest cell path, e.g. minesweeper/ipad-13/en/03-board.png")
    ap.add_argument("--region", nargs=4, type=int, metavar=("X0", "Y0", "X1", "Y1"))
    ap.add_argument("--max-delta", type=int)
    ap.add_argument("--max-px", type=int)
    ap.add_argument("--retint", type=int, default=6, help="subtle retint delta for case (c)")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    if args.manifest:
        with open(args.manifest) as f:
            cells = {c["path"]: c for c in json.load(f)["cells"]}
        cell = cells.get(args.cell)
        if cell is None or cell.get("mode") != "tolerant" or not cell.get("regions"):
            print(f"error: {args.cell} is not a tolerant cell with a region in {args.manifest}", file=sys.stderr)
            return 2
        region = tuple(cell["regions"][0])
        max_delta = cell["bounds"]["max_delta"]
        max_px = cell["bounds"]["max_px"]
    else:
        if not (args.region and args.max_delta is not None and args.max_px is not None):
            print("error: give --manifest/--cell or --region + --max-delta + --max-px", file=sys.stderr)
            return 2
        region, max_delta, max_px = tuple(args.region), args.max_delta, args.max_px

    out = args.out or os.path.join("build", "store-capture", "sensitivity",
                                   os.path.basename(os.path.dirname(args.capture)) or "cell")
    os.makedirs(out, exist_ok=True)
    base = Image.open(args.capture).convert("RGB")
    w, h = base.size
    x0, y0, x1, y1 = region
    base_path = os.path.join(out, "base.png")
    base.save(base_path)

    fixtures = {}

    # (a) one pixel outside the region (top-left corner is outside by construction
    #     unless the region covers it; pick the first pixel not inside).
    ox, oy = next((x, y) for y in range(h) for x in range(w) if not (x0 <= x < x1 and y0 <= y < y1))
    a = base.copy()
    r, g, b = a.getpixel((ox, oy))
    a.putpixel((ox, oy), ((r + 128) % 256, g, b))
    fixtures["outside-1px"] = (a, "VIOLATE")

    # (b) shift the region's content 4 px right
    s = base.copy()
    s.paste(base.crop((x0, y0, x1 - 4, y1)), (x0 + 4, y0))
    fixtures["shift-4px"] = (s, "VIOLATE")

    # (c) subtle retint over the control's light fill
    fill = light_fill_pixels(base, region)
    fixtures["retint-subtle"] = (retint(base, fill, args.retint), "VIOLATE")

    # (d) blind spot: exactly max_px pixels at max_delta -> passes; +1 -> violates
    region_pixels = [(x, y) for y in range(y0, y1) for x in range(x0, x1)]
    if len(region_pixels) <= max_px:
        print(f"error: region has only {len(region_pixels)} px, max_px={max_px} would exempt the whole region", file=sys.stderr)
        return 2
    fixtures["blindspot-pass"] = (retint(base, region_pixels[:max_px], max_delta), "OK")
    fixtures["blindspot-fail"] = (retint(base, region_pixels[:max_px + 1], max_delta), "VIOLATE")

    results = {}
    all_ok = True
    for name, (img, expect) in fixtures.items():
        path = os.path.join(out, f"{name}.png")
        img.save(path)
        code, summary = run_comparator(base_path, path, region, max_delta, max_px)
        verdict = "OK" if code == 0 else ("VIOLATE" if code == 1 else "ERROR")
        passed = (verdict == expect)
        all_ok = all_ok and passed
        results[name] = {"expected": expect, "got": verdict, "comparator": summary, "fixture": path}
        print(f"{'PASS' if passed else 'FAIL'}  {name:15s} expected={expect:7s} got={verdict:7s}  {summary}")

    blind = (f"BLIND SPOT: inside region {list(region)} a change of up to {max_delta}/255 per channel "
             f"on up to {max_px} pixels ({max_px / len(region_pixels):.1%} of the region, "
             f"{max_px / (w * h):.3%} of the frame) passes undetected; one more pixel or one more "
             f"level of delta fires. Subtle retint case used +{args.retint} over {len(fill)} fill pixels.")
    print(blind)
    with open(os.path.join(out, "summary.json"), "w") as f:
        json.dump({"capture": args.capture, "region": list(region), "max_delta": max_delta, "max_px": max_px,
                   "region_px": len(region_pixels), "fill_px": len(fill), "retint": args.retint,
                   "results": results, "blind_spot": blind, "all_ok": all_ok}, f, indent=2)
    print(f"RESULT {'OK' if all_ok else 'FAIL'} fixtures={out}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
