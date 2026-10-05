#!/usr/bin/env python3
"""compare_capture.py — the ONE region-limited pixel comparator used by
`mise run store:capture`'s idempotent publish, its `--verify` gate, and the
sensitivity-proof scripts (#1054 P-A, PM-approved region-limited tolerance).

Policy (hard rules, never relaxed by this script):
  - Any pixel difference OUTSIDE every declared region is an immediate,
    loud failure — regions are NEVER auto-expanded to cover it.
  - Inside a region, both a max per-channel delta AND a max differing-pixel
    count must hold. Both are supplied by the caller (from the cell's
    manifest entry), never invented here.
  - No region list (an "exact" cell) degenerates to a plain byte-for-byte /
    pixel-for-pixel compare: any differing pixel anywhere is OUTSIDE.

Usage:
    compare_capture.py <image_a> <image_b> \
        [--regions '[[x0,y0,x1,y1], ...]'] \
        [--max-delta N] [--max-px N] \
        [--json out.json]

Regions are [x0, y0, x1, y1) integer pixel rects in the SAME coordinate
space as the two images (i.e. already-cropped, published-file space — not
the raw uncropped simulator screenshot). Exit 0 iff outside_px == 0 AND
every region's differing px <= --max-px AND every region's max channel
delta <= --max-delta. Exit 1 on any violation, exit 2 on a usage/IO error.
Always prints one machine-parseable summary line (`RESULT ...`) plus a
human line, and writes the full detail to --json if given.
"""
import argparse
import json
import sys

from PIL import Image, ImageChops


def region_mask_ranges(regions, w, h):
    """Returns a function px_in_any_region(x, y) -> bool, clamping each
    region to the image bounds so a caller-supplied rect that overhangs the
    edge (e.g. a halo region clamped at publish time) still behaves."""
    clamped = []
    for (x0, y0, x1, y1) in regions:
        cx0, cy0 = max(0, x0), max(0, y0)
        cx1, cy1 = min(w, x1), min(h, y1)
        clamped.append((cx0, cy0, cx1, cy1))

    def in_any(x, y):
        for (x0, y0, x1, y1) in clamped:
            if x0 <= x < x1 and y0 <= y < y1:
                return True
        return False

    return in_any, clamped


def compare(path_a, path_b, regions, max_delta, max_px):
    a = Image.open(path_a).convert("RGB")
    b = Image.open(path_b).convert("RGB")
    if a.size != b.size:
        return {
            "error": f"size mismatch: {path_a}={a.size} {path_b}={b.size}",
        }
    w, h = a.size
    diff = ImageChops.difference(a, b)
    px = diff.load()
    in_any_region, clamped_regions = region_mask_ranges(regions, w, h)

    outside_px = 0
    outside_bbox = None
    region_stats = [{"rect": r, "differing_px": 0, "max_delta": 0} for r in clamped_regions]

    for y in range(h):
        for x in range(w):
            r, g, b_ = px[x, y]
            if not (r or g or b_):
                continue
            delta = max(r, g, b_)
            matched_region = None
            for idx, (x0, y0, x1, y1) in enumerate(clamped_regions):
                if x0 <= x < x1 and y0 <= y < y1:
                    matched_region = idx
                    break
            if matched_region is None:
                outside_px += 1
                if outside_bbox is None:
                    outside_bbox = [x, y, x, y]
                else:
                    outside_bbox[0] = min(outside_bbox[0], x)
                    outside_bbox[1] = min(outside_bbox[1], y)
                    outside_bbox[2] = max(outside_bbox[2], x)
                    outside_bbox[3] = max(outside_bbox[3], y)
            else:
                st = region_stats[matched_region]
                st["differing_px"] += 1
                st["max_delta"] = max(st["max_delta"], delta)

    region_ok = all(
        st["differing_px"] <= max_px and st["max_delta"] <= max_delta
        for st in region_stats
    )
    ok = (outside_px == 0) and region_ok

    return {
        "image_a": path_a,
        "image_b": path_b,
        "size": [w, h],
        "regions": region_stats,
        "outside_px": outside_px,
        "outside_bbox": outside_bbox,
        "max_delta_bound": max_delta,
        "max_px_bound": max_px,
        "ok": ok,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image_a")
    parser.add_argument("image_b")
    parser.add_argument("--regions", default="[]", help="JSON list of [x0,y0,x1,y1] rects")
    parser.add_argument("--max-delta", type=int, default=48)
    parser.add_argument("--max-px", type=int, default=0)
    parser.add_argument("--json", default=None, help="write full detail JSON here")
    args = parser.parse_args()

    try:
        regions = json.loads(args.regions)
    except json.JSONDecodeError as e:
        print(f"error: --regions is not valid JSON: {e}", file=sys.stderr)
        return 2
    if not isinstance(regions, list) or not all(isinstance(r, list) and len(r) == 4 for r in regions):
        print("error: --regions must be a JSON list of [x0,y0,x1,y1] rects", file=sys.stderr)
        return 2

    try:
        result = compare(args.image_a, args.image_b, regions, args.max_delta, args.max_px)
    except FileNotFoundError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    if "error" in result:
        print(f"error: {result['error']}", file=sys.stderr)
        return 2

    if args.json:
        with open(args.json, "w") as f:
            json.dump(result, f, indent=2)

    for st in result["regions"]:
        print(f"    region {st['rect']}: differing_px={st['differing_px']} (max<= {args.max_px}) "
              f"max_delta={st['max_delta']} (max<= {args.max_delta})")
    if result["outside_px"] > 0:
        print(f"    OUTSIDE every region: {result['outside_px']} px, bbox={result['outside_bbox']} "
              f"— regions are NEVER auto-expanded", file=sys.stderr)
    else:
        print("    outside every region: 0 px")

    verdict = "OK" if result["ok"] else "VIOLATION"
    print(f"RESULT {verdict} outside_px={result['outside_px']} regions={len(result['regions'])}")

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
