#!/usr/bin/env python3
"""Contract-change anchoring gate — Sudoku & Minesweeper 3.0.

USAGE
    python3 scripts/design/contracts.py             # gate mode; exit 1 on drift or bad anchor
    python3 scripts/design/contracts.py --verbose   # list every change entry and its anchor
    python3 scripts/design/contracts.py --coverage  # canonical coverage report only

WHAT THIS CHECKS
    1. The canonical documents still have the shape our change table was written against.
       `docs/screen-contracts.md`  -> N slug sections  (`## HOME`, `## SUD-BOARD`, ...)
       `docs/navigation-flows.md`  -> N enumerated rows (S1-S7, M1-M8, N1-N23)
       If these drift, the 3.0 change table has to be revisited — that is a failure, not a warning.
    2. Every C-x entry anchors to a slug that actually exists in screen-contracts.md.
    3. Every N-x entry anchors to a row id that actually exists in navigation-flows.md.
    4. Reports which C-x / N-x entries have no anchor yet (the remaining spec-PR work).

WHY THIS EXISTS
    The 3.0 change table used its own numbering (C-1..C-36 / N-A..N-AB) and for three
    revisions the totals were quoted wrong, in two different ways:
      - "BREAK subtotal" was added to "total rows" (two different quantities)
      - the *baseline* itself was wrong: we were counting "how many changes we wrote"
        and calling it "how many rows the document has"
    Both are the same class of mistake — a number nobody could reproduce. This script
    makes the numbers reproducible, which is the only reason to trust them.

EXIT CODES
    0  canonical shape matches, all anchors resolve
    1  canonical drift, a broken anchor, or a missing canonical file

No third-party dependencies. Python 3.8+.
"""
from __future__ import annotations
import os
import re
import sys

# ------------------------------------------------------------------ expected canonical shape
# Measured 2026-08-18 against main. If a canonical doc legitimately changes, update these
# in the SAME commit as the change-table revision — that pairing is the point of the gate.
EXPECTED_SLUG_COUNT = 23
EXPECTED_NAV_ROWS = {"S": 7, "M": 8, "N": 23}   # total 38

SCREEN_CONTRACTS = os.path.join("docs", "screen-contracts.md")
NAV_FLOWS = os.path.join("docs", "navigation-flows.md")

# ------------------------------------------------------------------ the 3.0 change table
# (id, verdict, canonical anchor, one-line description)
# anchor == None  -> not yet anchored (reported, does not fail the gate)
CHANGES_SCREEN = [
 ("C-1",  "BREAK",  "HOME",                   "HOME 整節刪除 —— 畫面退役"),
 ("C-2",  "BREAK",  "SUD-DAILY-HUB",          "併入 TODAY,入口從 HOME 卡改為預設 tab"),
 ("C-2b", "BREAK",  "MS-DAILY-HUB",           "同 C-2(MS 側)"),
 ("C-3",  "EXTEND", "SUD-PRACTICE-HUB",       "改名 PRACTICE;難度 picker 改盤面預覽卡"),
 ("C-3b", "EXTEND", "MS-PRACTICE-HUB",        "同 C-3(MS 側)"),
 ("C-4",  "BREAK",  "STATS",                  "改名 PROGRESS + 紀錄陳列"),
 ("C-5",  "BREAK",  "STATS",                  "「無前向導航」不再成立"),
 ("C-6",  "BREAK",  "SUD-DAILY-HUB",          "CK degraded 改骨架而非整卡消失"),
 ("C-7",  "BREAK",  "SUD-DAILY-HUB",          "exhausted 的 Cancel 落點改留在 Today"),
 ("C-8",  "BREAK",  "SUD-COMPLETION-OVERLAY", "全高三帶 + liveSolve/review 變體"),
 ("C-8b", "BREAK",  "MS-COMPLETION-OVERLAY",  "同 C-8(MS 側)"),
 ("C-9",  "EXTEND", "SUD-COMPLETION-REVIEW",  "標記為 review 變體(無儀式無觸覺)"),
 ("C-9b", "EXTEND", "MS-COMPLETION-REVIEW",   "同 C-9(MS 側)"),
 ("C-10", "EXTEND", "SUD-BOARD-LOAD-FAILED",  "completedRedirect 渲染 review 變體"),
 ("C-11", "EXTEND", "MS-BOARD-LOAD-FAILED",   "Tier2 resolved(.completed) 同上"),
 ("C-12", "BREAK",  "MS-BOARD",               "盤面滿版;header 改系統 toolbar"),
 ("C-13", "EXTEND", "SUD-BOARD",              "難度標示併入 toolbar"),
 ("C-14", "BREAK",  "SETTINGS",               "入口改每 tab 齒輪 + sidebar 固定項"),
 ("C-15", "BREAK",  "GC-DASHBOARD",           "入口從 HOME 卡改 PROGRESS 列"),
 ("C-16", "NEW",    None,                     "新增 ROOT-TABS 契約(canonical 尚無此節)"),
 ("C-17", "KEEP",   "PAUSE-OVERLAY",          "明文確認不碰"),
 ("C-18", "BREAK",  "SUD-DAILY-HUB",          "三題卡改真實盤面縮圖"),
 ("C-19", "EXTEND", "SUD-DAILY-HUB",          "degraded 時縮圖仍可畫(不依賴 CK)"),
 ("C-20", "BREAK",  "HOME",                   "Resume 卡改 standard material + 殘局快照"),
 ("C-21", "BREAK",  "SUD-BOARD",              "滿版 + G4 玻璃叢集;32pt 留白規則作廢"),
 ("C-22", "EXTEND", "SUD-BOARD",              "格徑裁定數字更新 40.1 -> 43.2pt"),
 ("C-23", "BREAK",  "SUD-COMPLETION-OVERLAY", "完成期間盤面保持可見"),
 ("C-24", "EXTEND", "SUD-PRACTICE-HUB",       "難度卡加密度預覽"),
 ("C-25", "BREAK",  "STATS",                  "6 tile 改 personal bests + 連續日曆"),
 ("C-26", "NEW",    "GC-DASHBOARD",           "新增 Achievements 入口(第二個 state)"),
 ("C-27", "NEW",    None,                     "新增 Liquid Glass 表面清單(canonical 尚無此節)"),
 ("C-28", "NEW",    "SUD-BOARD",              "reduce-transparency 版面約束"),
 ("C-29", "BREAK",  "STATS",                  "PROGRESS 兩列文案綁 GC 官方術語"),
 ("C-30", "NEW",    "GC-DASHBOARD",           "GC access point 放置契約(現況已合規)"),
 ("C-31", "EXTEND", "SUD-BOARD",              "格子級成功回饋 M12/M13"),
 ("C-32", "EXTEND", "SETTINGS",               "7 語系 GC 術語譯法"),
 ("C-33", "BREAK",  "ATT-PRIMER",             "ATT 觸發錨點改 Today tab 首次 banner(HOME 移除)"),
 ("C-34", "NEW",    "HOME",                   "Resume pill refresh 改「任一 tab 的 path 縮短」"),
 ("C-35", "BREAK",  "GC-SIGNED-OUT-ALERT",    "HOME leaderboard 卡入口消失"),
 ("C-36", "NEW",    "GC-DASHBOARD",           "Progress 的 Achievements 列入口"),
]

CHANGES_NAV = [
 ("N-A",  "BREAK",  None,  "Route enums 7->3 / 8->5(§1,非表列)"),
 ("N-B",  "EXTEND", None,  "兩脈絡一張 route table 仍成立(§2,非表列)"),
 ("N-C",  "BREAK",  None,  "resume-pill refresh 觸發改寫(§2,非表列)"),
 ("N-D",  "BREAK",  "S1",  "鏈起點 HOME -> Today tab"),
 ("N-E",  "BREAK",  "M1",  "同上(MS)"),
 ("N-F",  "BREAK",  "S5",  "GC 起點改 PROGRESS"),
 ("N-F2", "BREAK",  "M6",  "同上(MS)"),
 ("N-G",  "BREAK",  "S6",  "reminder deep-link 改選中 tab 並清空 path"),
 ("N-H",  "KEEP",   "N1",  "board 載入失敗不變"),
 ("N-I",  "KEEP",   "N3",  "Practice 抽題失敗不變"),
 ("N-J",  "BREAK",  "N4",  "exhausted 的 Cancel 落點改變"),
 ("N-K",  "KEEP",   "N5",  "Sudoku failed 不變"),
 ("N-L",  "KEEP",   "N6",  "MS 無 empty/failed(D21)不變"),
 ("N-M",  "EXTEND", "N7",  "CK degraded 增列 badge 與 streak 骨架"),
 ("N-N",  "KEEP",   "N8",  "pause mask-tap 不變"),
 ("N-N2", "EXTEND", "N9",  "pause Leave 落點改述為 tab 根層"),
 ("N-O",  "EXTEND", "N10", "completion Close 落點改述"),
 ("N-O2", "EXTEND", "N11", "同上(MS)"),
 ("N-P",  "KEEP",   "N12", "review Close 機制不變"),
 ("N-P2", "KEEP",   "N13", "同上(MS)"),
 ("N-Q",  "EXTEND", "N14", "GC signed-out 入口敘述改 PROGRESS"),
 ("N-R",  "KEEP",   "N15", "ATT primer decline 不變"),
 ("N-S",  "EXTEND", "N17", "banner degraded 姿態隨 accessory 方案重定"),
 ("N-T",  "BREAK",  "N18", "MS reminder deep-link 同 N-G"),
 ("N-U",  "KEEP",   "N19", "clear-cache 不變"),
 ("N-V",  "KEEP",   "N20", "文件列不變"),
 ("N-W",  "KEEP",   "N22", "IAP 不變"),
 ("N-X",  "NEW",    None,  "新增:badge / streak 資料失敗的降級"),
 ("N-Y",  "NEW",    None,  "新增:縮圖資料不可得"),
 ("N-Z",  "NEW",    None,  "新增:Resume 快照不可得"),
 ("N-AA", "NEW",    "N14", "成就列 signed-out 共用既有 guard"),
 ("N-AB", "NEW",    None,  "新增:切 tab 不觸發 resume refresh"),
]

# ------------------------------------------------------------------ canonical parsing
def repo_root() -> str:
    """Prefer the repo the script lives in (scripts/design/x.py -> ../..), else cwd."""
    here = os.path.dirname(os.path.abspath(__file__))
    cand = os.path.abspath(os.path.join(here, os.pardir, os.pardir))
    if os.path.isfile(os.path.join(cand, SCREEN_CONTRACTS)):
        return cand
    return os.getcwd()

def read(path: str):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return fh.read()

def parse_slugs(text: str):
    return [m.group(1).strip() for m in re.finditer(r"^##\s+(.+?)\s*$", text, re.M)]

def parse_nav_rows(text: str):
    ids = {"S": [], "M": [], "N": []}
    for m in re.finditer(r"^\|\s*([SMN])(\d+)\s*\|", text, re.M):
        ids[m.group(1)].append(m.group(1) + m.group(2))
    return ids

# ------------------------------------------------------------------ main
def main(argv) -> int:
    verbose = "--verbose" in argv or "-v" in argv
    coverage_only = "--coverage" in argv
    root = repo_root()
    sc_path, nf_path = os.path.join(root, SCREEN_CONTRACTS), os.path.join(root, NAV_FLOWS)
    sc, nf = read(sc_path), read(nf_path)

    print("contract anchoring gate")
    print("  repo root: %s" % root)
    print("=" * 78)
    failures = []

    if sc is None:
        failures.append("missing canonical file: %s" % SCREEN_CONTRACTS)
    if nf is None:
        failures.append("missing canonical file: %s" % NAV_FLOWS)
    if failures:
        for f in failures:
            print("  FAIL " + f)
        print("\nRESULT: FAIL")
        return 1

    slugs = parse_slugs(sc)
    # the last section title carries a parenthetical; match on the leading token
    slug_keys = {s.split()[0] for s in slugs}
    nav = parse_nav_rows(nf)
    nav_total = sum(len(v) for v in nav.values())

    print("canonical shape")
    print("  screen-contracts.md : %d slug sections (expected %d)" % (len(slugs), EXPECTED_SLUG_COUNT))
    print("  navigation-flows.md : %d rows  S=%d M=%d N=%d  (expected S=%d M=%d N=%d, total %d)"
          % (nav_total, len(nav["S"]), len(nav["M"]), len(nav["N"]),
             EXPECTED_NAV_ROWS["S"], EXPECTED_NAV_ROWS["M"], EXPECTED_NAV_ROWS["N"],
             sum(EXPECTED_NAV_ROWS.values())))

    if len(slugs) != EXPECTED_SLUG_COUNT:
        failures.append("screen-contracts.md drifted: %d sections, expected %d — "
                        "revisit the 3.0 change table" % (len(slugs), EXPECTED_SLUG_COUNT))
    for k, want in EXPECTED_NAV_ROWS.items():
        if len(nav[k]) != want:
            failures.append("navigation-flows.md %s rows drifted: %d, expected %d"
                            % (k, len(nav[k]), want))

    # ---- anchor resolution
    print()
    print("anchors")
    unanchored_c = [c for c in CHANGES_SCREEN if c[2] is None]
    unanchored_n = [n for n in CHANGES_NAV if n[2] is None]
    for cid, verdict, anchor, desc in CHANGES_SCREEN:
        if anchor is None:
            continue
        if anchor not in slug_keys:
            failures.append("%s anchors to '## %s' which does not exist in screen-contracts.md"
                            % (cid, anchor))
        elif verbose:
            print("  %-6s %-7s -> ## %-24s %s" % (cid, verdict, anchor, desc))
    nav_ids = set(nav["S"]) | set(nav["M"]) | set(nav["N"])
    for nid, verdict, anchor, desc in CHANGES_NAV:
        if anchor is None:
            continue
        if anchor not in nav_ids:
            failures.append("%s anchors to row '%s' which does not exist in navigation-flows.md"
                            % (nid, anchor))
        elif verbose:
            print("  %-6s %-7s -> %-27s %s" % (nid, verdict, anchor, desc))

    # ---- coverage
    touched = {c[2] for c in CHANGES_SCREEN if c[2]}
    untouched = sorted(slug_keys - touched)
    nav_touched = {n[2] for n in CHANGES_NAV if n[2]}
    print()
    print("coverage")
    # Logical entries vs anchor rows are two different units (design.md §9.3
    # quotes the LOGICAL counts): a logical entry like C-2 may be split into
    # per-app anchor rows (C-2/C-2b). Report both so neither number "drifts".
    logical_screen = len({e[0].rstrip("b") for e in CHANGES_SCREEN})
    logical_nav = len({re.sub(r"2$", "", e[0]) for e in CHANGES_NAV})
    print("  change entries      : %d screen-contracts (%d anchor rows), "
          "%d navigation-flows (%d anchor rows)"
          % (logical_screen, len(CHANGES_SCREEN), logical_nav, len(CHANGES_NAV)))
    print("  canonical touched   : %d/%d slug sections, %d/%d nav rows"
          % (len(touched), len(slugs), len(nav_touched), nav_total))
    print("  untouched sections  : %s" % (", ".join(untouched) if untouched else "(none)"))
    if unanchored_c or unanchored_n:
        print("  NOT YET ANCHORED    : %d screen (%s), %d nav (%s)"
              % (len(unanchored_c), ", ".join(c[0] for c in unanchored_c),
                 len(unanchored_n), ", ".join(n[0] for n in unanchored_n)))
        print("                        (these describe new sections or prose-level model changes;")
        print("                         anchoring them is the remaining spec-PR work item)")

    print()
    if failures:
        print("FAILURES (%d):" % len(failures))
        for f in failures:
            print("  " + f)
        print("\nRESULT: FAIL")
        return 1
    if coverage_only:
        print("RESULT: PASS (coverage report only)")
        return 0
    print("RESULT: PASS — canonical shape matches, every stated anchor resolves")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
