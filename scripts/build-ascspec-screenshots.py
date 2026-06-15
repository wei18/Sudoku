#!/usr/bin/env python3
"""
build-ascspec-screenshots.py — Marketing-frame pass for ASC iPhone 6.9" screenshots.

Consumes committed snapshot-test baselines (786×1704 RGBA) and emits
ASC-submission-spec PNGs (1290×2796, RGB, no alpha) for both apps in
en + zh-Hant locales.

Outputs:  docs/app-store/screenshots/<app>/iphone-6.9/ascspec/<locale>/NN-<screen>.png
          (sibling to the preview symlinks; never clobbers them)

Tooling:  Python 3 + Pillow (PIL) — already present on this machine.
          No Homebrew / pip installs required.

Usage:
  python3 scripts/build-ascspec-screenshots.py [--verify-only]

  --verify-only : skip generation, only verify existing outputs meet spec.

Wire as mise task:
  mise run store:screenshots build-ascspec
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path
from typing import Optional

from PIL import Image, ImageDraw, ImageFont

# ── Constants ─────────────────────────────────────────────────────────────────

ASC_W = 1290
ASC_H = 2796

REPO_ROOT = Path(__file__).resolve().parent.parent

BASELINES_SUDOKU = REPO_ROOT / "Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__"
BASELINES_MS = REPO_ROOT / "Packages/MinesweeperKit/Tests/MinesweeperUITests/__Snapshots__"

OUT_BASE = REPO_ROOT / "docs/app-store/screenshots"

# ── Theme colors (from DefaultTheme.swift / MinesweeperTheme.swift) ───────────

def hex_to_rgb(h: int) -> tuple[int, int, int]:
    return ((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF)

# Sudoku: warm-paper background, sage accent
SUDOKU_BG        = hex_to_rgb(0xFAF8F3)
SUDOKU_ACCENT    = hex_to_rgb(0x5C7A4F)
SUDOKU_ACCENT_MUTED = hex_to_rgb(0xDCE6D0)

# Minesweeper: cool slate-blue background, steel-blue accent
MS_BG            = hex_to_rgb(0xF4F6F8)
MS_ACCENT        = hex_to_rgb(0x3E6B8C)
MS_ACCENT_MUTED  = hex_to_rgb(0xD5E2EC)

# Overlay copy panel (from screenshot-strategy.md §Overlay copy)
OVERLAY_BG_HEX   = 0xFAF8F3  # warm-paper, used for Sudoku; MS gets its own bg tint

# ── Overlay copy (per shot, per locale) ───────────────────────────────────────

COPY = {
    "sudoku": {
        "01-home": {
            "en":      ("Calm logic, every day.", "Two modes, one focused place to think."),
            "zh-Hant": ("每天，一場安靜的推理。", "兩種模式，一個專注思考的地方。"),
        },
        "02-daily": {
            "en":      ("Three puzzles. Every day.", "Easy, medium, hard — the same world over."),
            "zh-Hant": ("每天三題。世界同題。", "簡單、中等、困難，看你比別人快多少。"),
        },
        "03-board": {
            "en":      ("Notes the way you write them.", "Live error highlighting. Twenty steps of undo."),
            "zh-Hant": ("筆記，跟你紙上寫法一樣。", "即時錯誤提示，20 步 undo。"),
        },
        "04-completion": {
            "en":      ("Solved.", "One scoring attempt per puzzle. Your time, ranked."),
            "zh-Hant": ("完成。", "同題一次計分機會。你的時間，全球排名。"),
        },
        "05-settings": {
            "en":      ("Seven languages. Zero tracking.", "Game Center built in. No third-party SDKs."),
            "zh-Hant": ("七種語言。零追蹤。", "內建 Game Center。沒有第三方 SDK。"),
        },
    },
    "minesweeper": {
        # Minesweeper storyline uses the same 5-shot structure per strategy doc,
        # adapted for MS gameplay. Shots 1-4 have copy; shot 5 (Settings)
        # is identical copy since it's the shared SettingsUI.
        "01-home": {
            "en":      ("Calm logic, every day.", "One board, every day. The same for everyone."),
            "zh-Hant": ("每天，一場安靜的推理。", "每天一局，全球同題。"),
        },
        "02-daily": {
            "en":      ("Three boards. Every day.", "Beginner, intermediate, expert — world-shared."),
            "zh-Hant": ("每天三局。世界同局。", "初級、中級、專家，全球同一題。"),
        },
        "03-board": {
            "en":      ("Flag, reveal, solve.", "Logical deduction. No guessing required."),
            "zh-Hant": ("標記、揭開、解題。", "純邏輯推理，無需猜測。"),
        },
        "04-completion": {
            "en":      ("Cleared.", "One attempt per board. Your time, ranked globally."),
            "zh-Hant": ("完成。", "每局一次計時。你的成績，全球排名。"),
        },
    },
}

# ── Baseline → output slot mapping (matches mise-tasks/store/screenshots MAP) ──

SLOTS = {
    "sudoku": [
        ("01-home",
         BASELINES_SUDOKU / "HomeViewTests/snapshotIPhoneLight.HomeView-iPhone-light.png"),
        ("02-daily",
         BASELINES_SUDOKU / "DailyHubViewTests/snapshotUnfinishedIPhoneLight.DailyHub-iPhone-light-unfinished.png"),
        ("03-board",
         BASELINES_SUDOKU / "BoardViewTests/snapshotInProgress_iPhone_light.Board-iPhone-light-inProgress.png"),
        ("04-completion",
         BASELINES_SUDOKU / "CompletionViewTests/snapshot_authenticatedLoaded_iPhoneLight.Completion-iPhone-light-loaded.png"),
        ("05-settings",
         BASELINES_SUDOKU / "SettingsViewTests/snapshot_iPhone_light_purchased.SettingsView-fullpage-iPhone-light-purchased.png"),
    ],
    "minesweeper": [
        ("01-home",
         BASELINES_MS / "MinesweeperHomeSnapshotTests/snapshotHome_iPhone_light.Home-iPhone-light-compact.png"),
        ("02-daily",
         BASELINES_MS / "MinesweeperDailyHubSnapshotTests/snapshotDaily_iPhone_light.Daily-iPhone-light-compact.png"),
        ("03-board",
         BASELINES_MS / "MinesweeperBoardSnapshotTests/snapshotBeginnerCovered_iPhone_light.Board-iPhone-light-beginner-covered.png"),
        ("04-completion",
         BASELINES_MS / "MinesweeperCompletionSnapshotTests/snapshotWinLoaded_iPhone_light.Completion-iPhone-light-win-loaded.png"),
    ],
}

LOCALES = ["en", "zh-Hant"]

# ── Font resolution ────────────────────────────────────────────────────────────
#
# CRITICAL: SFNS.ttf (San Francisco) has NO CJK glyphs — rendering Chinese /
# Japanese / Korean with it produces .notdef "tofu" boxes (every missing char
# draws the SAME empty rectangle). The original pass only validated pixel
# dimensions, so the tofu went unnoticed for zh-Hant (#311 CR fail).
#
# Fix: pick a font per locale. CJK locales use Hiragino Sans GB (covers
# TC/SC + Latin, so mixed strings like "20 步 undo" render correctly);
# Latin-script locales keep SFNS.

# CJK locales need a font with Han glyph coverage.
CJK_LOCALES = {"zh-Hant", "zh-Hans", "ja", "ko"}

# Hiragino Sans GB .ttc faces: index 0 = W3 (regular), index 2 = W6 (semibold).
_HIRAGINO = "/System/Library/Fonts/Hiragino Sans GB.ttc"
_PINGFANG = "/System/Library/Fonts/PingFang.ttc"  # preferred if present (not on all macOS)


def _cjk_font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    """A CJK-capable font (PingFang if available, else Hiragino Sans GB)."""
    if os.path.exists(_PINGFANG):
        # PingFang.ttc faces: 0=Regular .. weights vary; use a mid weight.
        index = 4 if bold else 2
        try:
            return ImageFont.truetype(_PINGFANG, size, index=index)
        except (OSError, ValueError):
            pass
    if os.path.exists(_HIRAGINO):
        # index 0 = W3 (regular), index 2 = W6 (semibold).
        return ImageFont.truetype(_HIRAGINO, size, index=(2 if bold else 0))
    # Last resort — Latin-only; CJK will tofu but the run won't crash.
    return _latin_font(size)


def _latin_font(size: int) -> ImageFont.FreeTypeFont:
    """SFNS (SF system font on macOS); falls back to Helvetica."""
    for path in ("/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/System/Library/Fonts/HelveticaNeue.ttc"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def font_for(locale: str, size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Return a glyph-complete font for *locale* (CJK-aware)."""
    if locale in CJK_LOCALES:
        return _cjk_font(size, bold)
    return _latin_font(size)


# ── Compositing helpers ────────────────────────────────────────────────────────

def draw_rounded_rect(draw: ImageDraw.ImageDraw,
                      xy: tuple,
                      radius: int,
                      fill: tuple,
                      outline: Optional[tuple] = None,
                      outline_width: int = 0) -> None:
    """Draw a rounded rectangle on *draw*."""
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill,
                           outline=outline, width=outline_width)


def make_frame(app: str) -> tuple:
    """Return (bg_color, accent_color, accent_muted) for the app."""
    if app == "sudoku":
        return SUDOKU_BG, SUDOKU_ACCENT, SUDOKU_ACCENT_MUTED
    return MS_BG, MS_ACCENT, MS_ACCENT_MUTED


def build_asc_image(baseline_path: Path,
                    headline: str,
                    subhead: str,
                    app: str,
                    locale: str) -> Image.Image:
    """
    Compose one ASC-spec 1290×2796 RGB PNG.

    Layout (top → bottom):
      - Opaque brand background (full canvas)
      - Overlay caption block in the top-third
          • headline (bold)
          • subhead
      - Device bezel (rounded rect, subtle shadow/border)
          • game screen baseline scaled to fit inside
    """
    bg_color, accent_color, accent_muted = make_frame(app)

    canvas = Image.new("RGB", (ASC_W, ASC_H), bg_color)
    draw = ImageDraw.Draw(canvas, "RGBA")

    # ── Background gradient band (subtle, same hue family) ────────────────────
    # Blend a slightly darker strip at top to give the caption area contrast.
    top_band_h = ASC_H // 3
    top_r = max(0, bg_color[0] - 10)
    top_g = max(0, bg_color[1] - 10)
    top_b = max(0, bg_color[2] - 8)
    for y in range(top_band_h):
        t = y / top_band_h  # 0 → darker, 1 → bg_color
        r = int(top_r + t * (bg_color[0] - top_r))
        g = int(top_g + t * (bg_color[1] - top_g))
        b = int(top_b + t * (bg_color[2] - top_b))
        draw.line([(0, y), (ASC_W, y)], fill=(r, g, b))

    # ── Caption block ─────────────────────────────────────────────────────────
    #
    # At 1290×2796 we need generous font sizes. Strategy doc says overlay is
    # in the top-third. We use:
    #   headline: 72pt bold  (≈ 6% of canvas width per character, legible)
    #   subhead:  44pt regular
    #
    # Caption panel background: warm-paper at ~92% opacity blended over bg
    CAPTION_PADDING   = 60           # px padding inside panel
    CAPTION_TOP       = 140          # px from top of canvas
    CAPTION_WIDTH     = ASC_W - 120  # 60px margin on each side
    CAPTION_LEFT      = 60

    font_headline = font_for(locale, 72, bold=True)
    font_subhead  = font_for(locale, 44, bold=False)

    # Measure text to size the panel dynamically
    tmp_draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    def text_w(s: str, font: ImageFont.FreeTypeFont) -> int:
        bbox = tmp_draw.textbbox((0, 0), s, font=font)
        return bbox[2] - bbox[0]

    # Wrap by words (Latin) and fall back to per-character wrapping for any
    # token that itself overflows (CJK has no spaces, so a whole clause is one
    # "word" — without this it would never wrap and could overrun the panel).
    def wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
        lines, current = [], ""
        for word in text.split():
            test = (current + " " + word).strip()
            if text_w(test, font) <= max_width:
                current = test
                continue
            if current:
                lines.append(current)
                current = ""
            if text_w(word, font) <= max_width:
                current = word
            else:
                # Word longer than the panel: break it character by character.
                for ch in word:
                    test = current + ch
                    if text_w(test, font) <= max_width or not current:
                        current = test
                    else:
                        lines.append(current)
                        current = ch
        if current:
            lines.append(current)
        return lines or [""]

    text_width = CAPTION_WIDTH - CAPTION_PADDING * 2
    headline_lines = wrap_text(headline, font_headline, text_width)
    subhead_lines  = wrap_text(subhead,  font_subhead,  text_width)

    LINE_GAP_H = 16
    LINE_GAP_S = 12
    BLOCK_GAP  = 28  # between headline block and subhead block

    def block_height(lines: list[str], font: ImageFont.FreeTypeFont, gap: int) -> int:
        if not lines:
            return 0
        bbox = tmp_draw.textbbox((0, 0), lines[0], font=font)
        line_h = bbox[3] - bbox[1]
        return line_h * len(lines) + gap * (len(lines) - 1)

    h_block_h = block_height(headline_lines, font_headline, LINE_GAP_H)
    s_block_h = block_height(subhead_lines, font_subhead, LINE_GAP_S)
    panel_h   = CAPTION_PADDING * 2 + h_block_h + BLOCK_GAP + s_block_h

    panel_rect = (
        CAPTION_LEFT,
        CAPTION_TOP,
        CAPTION_LEFT + CAPTION_WIDTH,
        CAPTION_TOP + panel_h,
    )

    # Draw semi-opaque panel (warm-paper tint, 92% = alpha 235/255)
    panel_color_alpha = (*bg_color, 235)
    draw.rounded_rectangle(panel_rect, radius=32,
                            fill=panel_color_alpha,
                            outline=(*accent_muted, 200), width=2)

    # Headline text (accent color = sage / steel-blue)
    ty = CAPTION_TOP + CAPTION_PADDING
    for line in headline_lines:
        draw.text((CAPTION_LEFT + CAPTION_PADDING, ty), line,
                  font=font_headline, fill=(*accent_color, 255))
        bbox = tmp_draw.textbbox((0, 0), line, font=font_headline)
        ty += (bbox[3] - bbox[1]) + LINE_GAP_H
    ty += BLOCK_GAP - LINE_GAP_H  # adjust for the inter-block gap

    # Subhead text (slightly muted — 85% of primary text #1A1D21)
    text_primary = (0x1A, 0x1D, 0x21)
    for line in subhead_lines:
        draw.text((CAPTION_LEFT + CAPTION_PADDING, ty), line,
                  font=font_subhead, fill=(*text_primary, 217))
        bbox = tmp_draw.textbbox((0, 0), line, font=font_subhead)
        ty += (bbox[3] - bbox[1]) + LINE_GAP_S

    # ── Device bezel ──────────────────────────────────────────────────────────
    #
    # Place game screen below caption, scaled to fit inside a bezel.
    # Bezel occupies roughly 80% of canvas width, centered, below caption.
    #
    BEZEL_TOP     = CAPTION_TOP + panel_h + 60
    BEZEL_MARGIN  = 60               # px on each side
    BEZEL_W       = ASC_W - BEZEL_MARGIN * 2
    BEZEL_CORNER  = 64               # bezel corner radius
    BEZEL_BORDER  = 12               # bezel border thickness
    BEZEL_PAD     = 20               # inner padding between bezel border and screen

    # Available height for the screen image
    screen_inner_w = BEZEL_W - BEZEL_BORDER * 2 - BEZEL_PAD * 2
    screen_inner_h_max = ASC_H - BEZEL_TOP - 80 - BEZEL_BORDER * 2 - BEZEL_PAD * 2

    # Load and fit baseline
    src = Image.open(baseline_path).convert("RGBA")
    src_w, src_h = src.size

    # Scale to fill screen_inner_w while maintaining aspect ratio (letterbox if needed)
    scale = screen_inner_w / src_w
    fit_w = screen_inner_w
    fit_h = int(src_h * scale)
    if fit_h > screen_inner_h_max:
        scale = screen_inner_h_max / src_h
        fit_h = screen_inner_h_max
        fit_w = int(src_w * scale)

    src_resized = src.resize((fit_w, fit_h), Image.LANCZOS)

    # Actual bezel height wraps the screen
    bezel_inner_h = fit_h + BEZEL_PAD * 2
    bezel_h = bezel_inner_h + BEZEL_BORDER * 2
    bezel_left = BEZEL_MARGIN
    bezel_right = bezel_left + BEZEL_W
    bezel_bottom = BEZEL_TOP + bezel_h

    # Bezel outer rect (slightly off-white, like a device silver/white frame)
    # Use accent_muted for a tasteful on-brand border
    BEZEL_FILL    = (0xF8, 0xF8, 0xF8)  # near-white chassis
    BEZEL_OUTLINE = accent_muted

    draw_rounded_rect(draw,
                      (bezel_left, BEZEL_TOP, bezel_right, bezel_bottom),
                      BEZEL_CORNER,
                      fill=BEZEL_FILL,
                      outline=BEZEL_OUTLINE,
                      outline_width=BEZEL_BORDER)

    # Composite game screen inside bezel (flatten alpha onto bg)
    screen_x = bezel_left + BEZEL_BORDER + BEZEL_PAD + (screen_inner_w - fit_w) // 2
    screen_y = BEZEL_TOP  + BEZEL_BORDER + BEZEL_PAD

    # Flatten the RGBA baseline onto bg_color before pasting (no transparency leak)
    bg_patch = Image.new("RGB", (fit_w, fit_h), bg_color)
    bg_patch.paste(src_resized, (0, 0), src_resized)
    canvas.paste(bg_patch, (screen_x, screen_y))

    # ── Final sanity: canvas must be RGB (no alpha) ───────────────────────────
    assert canvas.mode == "RGB", f"Expected RGB, got {canvas.mode}"
    assert canvas.size == (ASC_W, ASC_H), f"Expected {ASC_W}×{ASC_H}, got {canvas.size}"

    return canvas


# ── Main ──────────────────────────────────────────────────────────────────────

def generate_all(dry_run: bool = False) -> list[dict]:
    """Generate all ASC-spec PNGs; return a list of result dicts for reporting."""
    results = []

    for app, slots in SLOTS.items():
        for slot_name, baseline_path in slots:
            for locale in LOCALES:
                copy_block = COPY.get(app, {}).get(slot_name, {}).get(locale)
                if copy_block is None:
                    results.append({
                        "app": app, "slot": slot_name, "locale": locale,
                        "status": "SKIPPED-NO-COPY", "path": None,
                    })
                    continue

                if not baseline_path.exists():
                    results.append({
                        "app": app, "slot": slot_name, "locale": locale,
                        "status": "SKIPPED-MISSING-BASELINE",
                        "baseline": str(baseline_path),
                        "path": None,
                    })
                    continue

                out_dir = OUT_BASE / app / "iphone-6.9" / "ascspec" / locale
                out_path = out_dir / f"{slot_name}.png"

                if not dry_run:
                    out_dir.mkdir(parents=True, exist_ok=True)
                    headline, subhead = copy_block
                    img = build_asc_image(baseline_path, headline, subhead, app, locale)
                    img.save(str(out_path), "PNG", optimize=False)

                results.append({
                    "app": app, "slot": slot_name, "locale": locale,
                    "status": "OK" if not dry_run else "DRY-RUN",
                    "path": out_path,
                })

    return results


def verify_outputs(results: list[dict]) -> list[dict]:
    """
    Verify every generated PNG is exactly 1290×2796 with no alpha.
    Annotates each result dict with 'verified' / 'fail_reason'.
    Returns only the FAIL entries.
    """
    failures = []
    for r in results:
        if r["status"] != "OK" or r["path"] is None:
            continue
        path = r["path"]
        if not path.exists():
            r["verified"] = False
            r["fail_reason"] = "file not found"
            failures.append(r)
            continue
        try:
            img = Image.open(path)
            w, h = img.size
            mode = img.mode
            ok = (w == ASC_W and h == ASC_H and mode == "RGB")
            r["verified"] = ok
            r["dims"] = f"{w}×{h}"
            r["mode"] = mode
            r["md5"] = hashlib.md5(path.read_bytes()).hexdigest()[:8]
            if not ok:
                r["fail_reason"] = f"got {w}×{h} {mode}, expected {ASC_W}×{ASC_H} RGB"
                failures.append(r)
        except Exception as exc:
            r["verified"] = False
            r["fail_reason"] = str(exc)
            failures.append(r)
    return failures


def print_report(results: list[dict], failures: list[dict]) -> None:
    print()
    print("── ASC-spec screenshot build report ──────────────────────────────────────────")
    print(f"{'App':<14} {'Locale':<8} {'Slot':<16} {'Status':<26} {'Dims / Mode'}")
    print("─" * 90)
    for r in results:
        path_str = ""
        if r.get("dims"):
            path_str = f"{r['dims']} {r.get('mode','')}  md5={r.get('md5','')}"
        elif r["path"]:
            path_str = str(r["path"]).replace(str(REPO_ROOT), "")
        status_str = r["status"] + (" ✓" if r.get("verified") else
                                    (" ✗ " + r.get("fail_reason","") if "fail_reason" in r else ""))
        print(f"{r['app']:<14} {r['locale']:<8} {r['slot']:<16} {status_str:<30} {path_str}")

    print()
    print(f"Total: {len(results)} slots processed  |  "
          f"Generated: {sum(1 for r in results if r['status']=='OK')}  |  "
          f"Skipped: {sum(1 for r in results if r['status'].startswith('SKIPPED'))}  |  "
          f"Failures: {len(failures)}")
    if failures:
        print("\n⚠️  VERIFICATION FAILURES:")
        for f in failures:
            print(f"  {f['app']}/{f['locale']}/{f['slot']}: {f.get('fail_reason')}")
        sys.exit(1)
    else:
        print("\nAll generated PNGs are 1290×2796 RGB (no alpha). Spec: ✓")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build ASC-spec marketing-frame screenshots from snapshot baselines."
    )
    parser.add_argument("--verify-only", action="store_true",
                        help="Skip generation; verify existing outputs only.")
    args = parser.parse_args()

    if args.verify_only:
        print("Verify-only mode: checking existing outputs…")
        results = []
        for app, slots in SLOTS.items():
            for slot_name, _ in slots:
                for locale in LOCALES:
                    out_path = OUT_BASE / app / "iphone-6.9" / "ascspec" / locale / f"{slot_name}.png"
                    copy_block = COPY.get(app, {}).get(slot_name, {}).get(locale)
                    results.append({
                        "app": app, "slot": slot_name, "locale": locale,
                        "status": "OK" if out_path.exists() and copy_block else "SKIPPED-NO-COPY",
                        "path": out_path if out_path.exists() else None,
                    })
        failures = verify_outputs(results)
        print_report(results, failures)
        return

    print(f"Building ASC-spec screenshots → {OUT_BASE}/<app>/iphone-6.9/ascspec/<locale>/")
    print(f"Canvas: {ASC_W}×{ASC_H} RGB (no alpha)  |  Baselines: 786×1704 RGBA  |  Pillow compositing")
    print()

    results = generate_all()
    failures = verify_outputs(results)
    print_report(results, failures)


if __name__ == "__main__":
    main()
