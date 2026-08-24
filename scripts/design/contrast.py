#!/usr/bin/env python3
"""Design token contrast gate — Sudoku & Minesweeper 3.0.

USAGE
    python3 scripts/design/contrast.py            # gate mode; exit 1 on any unexpected failure
    python3 scripts/design/contrast.py --verbose  # also print every PASS row
    python3 scripts/design/contrast.py --table    # print the per-token target-surface contract

WHAT THIS CHECKS
    1. Every token meets its threshold **against the surface it is actually drawn on**
       (see TARGETS below — that mapping is the methodology contract, not an implementation detail).
    2. The Increased Contrast (IC) variants meet the stricter IC thresholds.
    3. Multi-step ramps (identity tiers, thumbnail fills) keep >= MIN_RAMP_SEP between
       adjacent rungs — raising a contrast floor compresses a ramp, so this is checked
       separately from the floor itself.

THRESHOLDS  (WCAG 2.x relative luminance, values are NOT rounded: 2.999 does not meet 3.0)
    text     default >= 4.5   (AA)      IC >= 7.0   (AAA)
    non-text default >= 3.0   (1.4.11)  IC >= 4.5
    adjacent ramp rungs >= 1.5 in both sets

WHY A PER-TOKEN TARGET SURFACE
    An earlier revision claimed "always take the worse of surface.primary and
    surface.background" but the published numbers mixed bases. A difficulty pip is only
    ever drawn on a card; the streak row only ever sits on the app background. Measuring
    both against a single blanket rule produced numbers that were not reproducible.

DATA SOURCE
    Token values below are the single source of truth for this gate and must match
    docs/designs/design-system.md and MinesweeperUI/Theme/MinesweeperTheme.swift.
    If those files change, change this table in the same commit — that is the point of
    the gate. IC variants ship as Asset Catalog "High Contrast" wells (see the design doc).

KNOWN EXCEPTIONS
    A few DEFAULT values fail their threshold today. Those are listed in EXCEPTIONS with a
    reason, so the gate catches *regressions* rather than re-reporting known state forever.
    If an exception starts passing, the gate fails too — a stale exception is drift.

No third-party dependencies. Python 3.8+.
"""
from __future__ import annotations
import sys

# ----------------------------------------------------------------------------- thresholds
TEXT_DEFAULT, TEXT_IC = 4.5, 7.0
NONTEXT_DEFAULT, NONTEXT_IC = 3.0, 4.5
MIN_RAMP_SEP = 1.5

# ----------------------------------------------------------------------------- colour math
def _srgb_to_linear(channel: int) -> float:
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def luminance(rgb: int) -> float:
    return (0.2126 * _srgb_to_linear((rgb >> 16) & 0xFF)
            + 0.7152 * _srgb_to_linear((rgb >> 8) & 0xFF)
            + 0.0722 * _srgb_to_linear(rgb & 0xFF))

def contrast(a: int, b: int) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def hexs(rgb: int) -> str:
    return "#%06X" % rgb

# ----------------------------------------------------------------------------- surfaces
SURFACES = {
    "sudoku":      {"primary": (0xFFFFFF, 0x1E2024), "background": (0xFAF8F3, 0x15171A)},
    "minesweeper": {"primary": (0xFFFFFF, 0x1C2026), "background": (0xF4F6F8, 0x14171B)},
}

# token -> (role, target)
#   role   : "text" | "nontext" | "ink"  ("ink" = the token is a FILL; we measure the ink on it)
#   target : "primary" | "background" | "worse" | "ink:<hex>"
TARGETS = {
    "text.primary":       ("text",    "worse"),
    "text.secondary":     ("text",    "worse"),
    "text.tertiary":      ("text",    "worse"),
    "accent.primary":     ("ink",     "ink"),
    "accent.celebratory": ("nontext", "background"),
    "identity.tier1":     ("nontext", "primary"),
    "identity.tier2":     ("nontext", "primary"),
    "identity.tier3":     ("nontext", "primary"),
    "thumb.mid":          ("nontext", "primary"),
    "thumb.strong":       ("nontext", "primary"),
    "streak.pipOff":      ("nontext", "background"),
    "status.success":     ("text",    "primary"),
    "status.warning":     ("text",    "primary"),
    "status.error":       ("text",    "primary"),
}
TARGET_RATIONALE = {
    "worse":      "出現在卡片與背景兩處 → 取較差者",
    "primary":    "只畫在卡片上",
    "background": "直接坐在 app 背景上",
    "ink":        "它是填色;判定的是落在它上面的 ink",
}

# ----------------------------------------------------------------------------- tokens
# (light_default, dark_default, light_ic, dark_ic)  — None means "IC same as default"
#
# identity.tier1-3 / thumb.mid / thumb.strong / streak.pipOff have NO Asset Catalog
# colorset yet (#1016) — the features that would draw them (identity pips, thumbnail
# fills, streak row) are not built (see #1015's clarification). This table is still
# the DESIGN-value-level source of truth per §5.2/§5.3: the checks and ramp-separation
# assertions below run against these hex constants directly, independent of whether a
# colorset exists. When those colorsets land, wire their IC wells from these same values.
TOKENS = {
 "sudoku": {
  "text.primary":      (0x1A1D21, 0xF2F3F5, None,     None),
  "text.secondary":    (0x54595F, 0xA8ADB3, 0x51555B, None),
  "text.tertiary":     (0x86898E, 0x787C82, 0x535559, 0xA8AAAE),
  "accent.primary":    (0x5C7A4F, 0x9BB87E, 0x485F3E, None),
  "identity.tier1":    (0x6F935F, 0x5D7842, 0x5D7C50, 0x729451),
  "identity.tier2":    (0x557049, 0x799C56, 0x445A3A, 0x9DBA81),
  "identity.tier3":    (0x3B4E33, 0xABC392, 0x2B3925, 0xD8E3CD),
  "thumb.mid":         (0x859B7B, 0x5F6F53, 0x5D7C50, 0x729451),
  "thumb.strong":      (0x5C7A4F, 0x849D6E, 0x3D5135, 0xACC493),
  "streak.pipOff":     (0x719561, 0x5C7641, 0x5D7A50, 0x6B894C),
  "status.success":    (0x1B7A3E, 0x4BC579, 0x176634, None),
  "status.warning":    (0xA86A0E, 0xE0A95C, 0x7D4F0A, None),
  "status.error":      (0xC8362B, 0xE66258, 0xA52C23, 0xED918A),
 },
 "minesweeper": {
  "text.primary":      (0x1A1E24, 0xEEF1F4, None,     None),
  "text.secondary":    (0x545B63, 0xA4ACB4, 0x4E545C, None),
  "text.tertiary":     (0x868D95, 0x767D85, 0x4F545A, 0xA6ABB0),
  "accent.primary":    (0x3E6B8C, 0x7FAFCF, 0x365C79, 0x80B0D0),
  "accent.celebratory":(0xD4501F, 0xEB774C, 0xC2491C, None),
  "identity.tier1":    (0x578DB4, 0x3B759D, 0x46799E, 0x4D90BC),
  "identity.tier2":    (0x3E6C8D, 0x5A98C1, 0x335772, 0x8BB6D3),
  "identity.tier3":    (0x2B4B62, 0x9AC0D9, 0x203748, 0xD0E2ED),
  "thumb.mid":         (0x7897AE, 0x516D81, 0x46799E, 0x4D90BC),
  "thumb.strong":      (0x3E6B8C, 0x6F98B4, 0x2E4F68, 0x9BC1DA),
  "streak.pipOff":     (0x5B8FB6, 0x3A739A, 0x44759A, 0x4386B3),
  "status.success":    (0x1B7A3E, 0x4BC579, 0x176634, None),
  "status.warning":    (0xD9822B, 0xE8A560, 0x824C17, None),
  "status.error":      (0xC8362B, 0xE66258, 0xA52C23, 0xED918A),
 },
}

# The ink that sits on an "ink"-role fill, per scheme.
INK = {"sudoku": (0xFFFFFF, 0x1E2024), "minesweeper": (0xFFFFFF, 0x1C2026)}

RAMPS = [("identity", ["identity.tier1", "identity.tier2", "identity.tier3"]),
         ("thumbnail", ["thumb.mid", "thumb.strong"])]

# (app, token, set, scheme) -> reason.  Known-and-accepted default-set failures.
EXCEPTIONS = {
 ("sudoku", "text.tertiary", "default", "light"):
   "既有缺陷:3.31:1 未達 AA。IC 變體已修到 7.04;預設集的修復不在 3.0 範圍",
 ("sudoku", "text.tertiary", "default", "dark"):
   "同上(dark 3.89:1)",
 ("minesweeper", "text.tertiary", "default", "light"):
   "同 Sudoku(3.10:1)",
 ("minesweeper", "text.tertiary", "default", "dark"):
   "同上(3.93:1)",
 ("sudoku", "status.warning", "default", "light"):
   "4.44:1,差 0.06 未達 AA(不四捨五入,4.44 不算過)。與 MS 的同名 token 值不同(跨 app drift),統一與修復同列 backlog",
 ("minesweeper", "status.warning", "default", "light"):
   "2.93:1,連非文字 3:1 都不過。實際使用位置未查清(U-11)→ 未宣稱為 bug,但列為已知例外",
}

# ----------------------------------------------------------------------------- checking
class Result:
    def __init__(self):
        self.unexpected = []   # hard failures
        self.stale = []        # exceptions that now pass
        self.checked = 0
        self.rows = []

def threshold_for(role: str, which: str) -> float:
    if role == "nontext":
        return NONTEXT_IC if which == "ic" else NONTEXT_DEFAULT
    return TEXT_IC if which == "ic" else TEXT_DEFAULT

def measure(app: str, token: str, colour: int, scheme_idx: int):
    """Return (ratio, description-of-what-it-was-measured-against)."""
    role, target = TARGETS[token]
    surf = SURFACES[app]
    if target == "ink":
        ink = INK[app][scheme_idx]
        return contrast(ink, colour), "ink %s on fill" % hexs(ink)
    if target == "worse":
        p, b = surf["primary"][scheme_idx], surf["background"][scheme_idx]
        rp, rb = contrast(colour, p), contrast(colour, b)
        return (rp, "surface.primary") if rp <= rb else (rb, "surface.background")
    s = surf[target][scheme_idx]
    return contrast(colour, s), "surface." + target

def run(verbose: bool) -> Result:
    res = Result()
    for app in ("sudoku", "minesweeper"):
        for token, values in TOKENS[app].items():
            if token not in TARGETS:
                res.unexpected.append((app, token, "-", "-", "no TARGETS entry — 每個 token 都必須宣告目標 surface"))
                continue
            role, _ = TARGETS[token]
            light_d, dark_d, light_ic, dark_ic = values
            plan = [("default", "light", light_d, 0), ("default", "dark", dark_d, 1),
                    ("ic", "light", light_ic if light_ic is not None else light_d, 0),
                    ("ic", "dark",  dark_ic  if dark_ic  is not None else dark_d, 1)]
            for which, scheme, colour, idx in plan:
                thr = threshold_for(role, which)
                ratio, against = measure(app, token, colour, idx)
                res.checked += 1
                ok = ratio >= thr
                key = (app, token, which, scheme)
                exc = EXCEPTIONS.get(key)
                if ok and exc:
                    res.stale.append((app, token, which, scheme, ratio, thr, exc))
                elif not ok and not exc:
                    res.unexpected.append((app, token, which, scheme,
                        "%.2f:1 < %.1f:1 against %s" % (ratio, thr, against)))
                if verbose or (not ok):
                    flag = "PASS" if ok else ("KNOWN" if exc else "FAIL")
                    res.rows.append("  %-11s %-18s %-7s %-5s %s %6.2f:1  need %.1f  vs %s"
                                    % (app, token, which, scheme, flag, ratio, thr, against))
    # ---- ramps
    for app in ("sudoku", "minesweeper"):
        for ramp_name, members in RAMPS:
            for which in ("default", "ic"):
                for scheme, idx in (("light", 0), ("dark", 1)):
                    cols = []
                    for tok in members:
                        v = TOKENS[app][tok]
                        c = v[0 if scheme == "light" else 1]
                        if which == "ic":
                            ic = v[2 if scheme == "light" else 3]
                            if ic is not None:
                                c = ic
                        cols.append(c)
                    for i in range(len(cols) - 1):
                        sep = contrast(cols[i], cols[i + 1])
                        res.checked += 1
                        if sep < MIN_RAMP_SEP:
                            res.unexpected.append((app, "%s ramp %d-%d" % (ramp_name, i + 1, i + 2),
                                which, scheme, "adjacent separation %.2f:1 < %.1f:1 — ramp 被壓縮" % (sep, MIN_RAMP_SEP)))
                        elif verbose:
                            res.rows.append("  %-11s %-18s %-7s %-5s PASS %6.2f:1  sep >= %.1f"
                                            % (app, "%s %d-%d" % (ramp_name, i + 1, i + 2), which, scheme, sep, MIN_RAMP_SEP))
    return res

def print_table() -> None:
    print("PER-TOKEN TARGET SURFACE (methodology contract)")
    print("-" * 78)
    for token, (role, target) in TARGETS.items():
        print("  %-18s role=%-8s target=%-11s %s"
              % (token, role, target, TARGET_RATIONALE[target]))
    print()
    print("  thresholds: text %.1f/%.1f  non-text %.1f/%.1f  (default/IC)   ramp sep >= %.1f"
          % (TEXT_DEFAULT, TEXT_IC, NONTEXT_DEFAULT, NONTEXT_IC, MIN_RAMP_SEP))

def main(argv) -> int:
    if "--table" in argv:
        print_table()
        return 0
    verbose = "--verbose" in argv or "-v" in argv
    res = run(verbose)

    print("design contrast gate — %d checks" % res.checked)
    print("=" * 78)
    if res.rows:
        for r in res.rows:
            print(r)
        print()

    if res.stale:
        print("STALE EXCEPTIONS (%d) — these now PASS; delete them from EXCEPTIONS:" % len(res.stale))
        for app, token, which, scheme, ratio, thr, reason in res.stale:
            print("  %s %s (%s/%s) now %.2f:1 >= %.1f — was excused as: %s"
                  % (app, token, which, scheme, ratio, thr, reason))
        print()

    if res.unexpected:
        print("FAILURES (%d):" % len(res.unexpected))
        for app, token, which, scheme, msg in res.unexpected:
            print("  %s %s (%s/%s): %s" % (app, token, which, scheme, msg))
        print()

    if res.unexpected or res.stale:
        print("RESULT: FAIL")
        return 1
    print("RESULT: PASS — %d known exceptions still apply (see EXCEPTIONS)" % len(EXCEPTIONS))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
