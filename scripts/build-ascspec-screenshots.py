#!/usr/bin/env python3
"""
build-ascspec-screenshots.py — Marketing-frame pass for ASC screenshots.

Store-screenshot redesign (feat/store-screenshots-cb): Direction C (full-bleed
brand-gradient ground, headline set directly into the color, device screenshot
bleeding off the bottom edge, app-icon badge) for every slot, layered with
Direction B (1-2 feature-callout chips + leader lines) on the Board/Completion
slots. Replaces the earlier caption-panel-over-flat-tint + centered-bezel
treatment (see git history for that version).

Consumes committed snapshot-test baselines (RGBA, rendered at each device's
exact ASC pixel size) and emits ASC-submission-spec PNGs (RGB, no alpha) for
both apps in all 7 repo locales (en, zh-Hant, zh-Hans, ja, ko, es, th), for
each device family:
  - iphone-6.9 : 1290×2796
  - ipad-13    : 2064×2752 (#506)

Every locale composites its translated headline/subhead/callout copy over
the SAME underlying screenshot baseline (one baseline per slot, not per
locale). A per-locale-baseline variant was tried and backed out (#977) —
see the `SLOTS`/`Slot` comment below for why.

Outputs:  docs/app-store/screenshots-ascspec/<app>/<device>/<locale>/NN-<screen>.png
          (own tree — matches the uploader's <app>/<device>/<locale> contract;
           leaves the preview symlinks under docs/app-store/screenshots/ untouched)

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

# iPhone 6.9" canvas (default; kept as module-level for back-compat references).
ASC_W = 1290
ASC_H = 2796

# Per-device ASC canvas (exact pixel size ASC requires for that family).
# `dir` is the output device folder under <app>/<device>/<locale>/.
DEVICES = {
    "iphone-6.9": {"w": 1290, "h": 2796},
    "ipad-13":    {"w": 2064, "h": 2752},
}

REPO_ROOT = Path(__file__).resolve().parent.parent

BASELINES_SUDOKU = REPO_ROOT / "Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__"
BASELINES_MS = REPO_ROOT / "Packages/MinesweeperKit/Tests/MinesweeperUITests/__Snapshots__"

APP_ICONS = {
    "sudoku": REPO_ROOT / "App/Sudoku/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png",
    "minesweeper": REPO_ROOT / "App/Minesweeper/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png",
}

OUT_BASE = REPO_ROOT / "docs/app-store/screenshots"
# ASC-spec assets live in their OWN tree so the layout matches the uploader's
# contract exactly: <screenshots-dir>/<app>/<device>/<locale>/NN.png (no extra
# segment). Keeping them out of OUT_BASE leaves the preview symlinks untouched.
# Point `ASCRegister metadata screenshots --screenshots-dir` here.
OUT_ASCSPEC = REPO_ROOT / "docs/app-store/screenshots-ascspec"

# ── Theme colors (from DefaultTheme.swift / MinesweeperTheme.swift) ───────────

def hex_to_rgb(h: int) -> tuple[int, int, int]:
    return ((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF)


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    """Linear-interpolate RGB `a` -> `b` at `t` in [0, 1]."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


# Sudoku: sage accent (accent.primary light 0x5C7A4F) — Direction C's full-bleed
# gradient ground. Minesweeper: steel-blue accent (accent.primary light
# 0x3E6B8C). Own-theme tokens per the redesign spec (do not share a palette).
SUDOKU_ACCENT       = hex_to_rgb(0x5C7A4F)
SUDOKU_ACCENT_DEEP  = blend(SUDOKU_ACCENT, (0, 0, 0), 0.38)   # gradient top
SUDOKU_ACCENT_MUTED = hex_to_rgb(0xDCE6D0)
SUDOKU_BG           = hex_to_rgb(0xFAF8F3)  # screenshot's own light background

MS_ACCENT       = hex_to_rgb(0x3E6B8C)
MS_ACCENT_DEEP  = blend(MS_ACCENT, (0, 0, 0), 0.38)
MS_ACCENT_MUTED = hex_to_rgb(0xD5E2EC)
MS_BG           = hex_to_rgb(0xF4F6F8)

# ── Overlay copy (per shot, per locale) — source-locked to
#    docs/app-store/screenshot-strategy.md for Sudoku (headline ≤5 words /
#    subhead ≤12 words already fits directly-in-color type per the redesign). ──

COPY = {
    "sudoku": {
        "01-home": {
            "en":      ("Calm logic, every day.", "Two modes, one focused place to think."),
            "zh-Hant": ("每天，一場安靜的推理。", "兩種模式，一個專注思考的地方。"),
            "zh-Hans": ("每天，一场安静的推理。", "两种模式，一个专注思考的地方。"),
            "ja":      ("毎日、静かな論理を。", "ふたつのモード、ひとつの集中する場所。"),
            "ko":      ("매일, 조용한 논리.", "두 가지 모드, 집중할 수 있는 한 곳."),
            "es":      ("Lógica tranquila, cada día.", "Dos modos, un solo lugar para pensar."),
            "th":      ("ตรรกะเงียบๆ ทุกวัน", "สองโหมด หนึ่งพื้นที่สำหรับคิด"),
        },
        "02-daily": {
            "en":      ("Three puzzles. Every day.", "Easy, medium, hard — the same world over."),
            "zh-Hant": ("每天三題。世界同題。", "簡單、中等、困難，看你比別人快多少。"),
            "zh-Hans": ("每天三题。世界同题。", "简单、中等、困难，看你比别人快多少。"),
            "ja":      ("毎日3問。世界中で同じ問題。", "簡単・中級・上級、タイムで世界と並ぶ。"),
            "ko":      ("매일 세 문제. 전 세계 동일.", "쉬움, 보통, 어려움 — 시간이 곧 순위."),
            "es":      ("Tres puzles. Cada día.", "Fácil, medio, difícil — los mismos para todos."),
            "th":      ("สามปริศนา ทุกวัน", "ง่าย กลาง ยาก ชุดเดียวกันทั่วโลก"),
        },
        "03-board": {
            "en":      ("Notes the way you write them.", "Live error highlighting. Twenty steps of undo."),
            "zh-Hant": ("筆記，跟你紙上寫法一樣。", "即時錯誤提示，20 步 undo。"),
            "zh-Hans": ("笔记，跟你纸上写法一样。", "实时错误提示，20 步 undo。"),
            "ja":      ("メモは紙のときと同じ作法で。", "誤入力はその場で表示、20手まで戻せる。"),
            "ko":      ("종이에 적던 그대로 메모.", "실시간 오류 표시, 스무 단계 되돌리기."),
            "es":      ("Notas como en el papel.", "Detección de errores al instante. Veinte pasos de deshacer."),
            "th":      ("โน้ตเหมือนเขียนบนกระดาษ", "เห็นผิดทันที ย้อนได้ยี่สิบขั้น"),
        },
        "04-completion": {
            "en":      ("Solved.", "One scoring attempt per puzzle. Your time, ranked."),
            "zh-Hant": ("完成。", "同題一次計分機會。你的時間，全球排名。"),
            "zh-Hans": ("完成。", "同题一次计分机会。你的时间，全球排名。"),
            "ja":      ("解けた。", "1問1スコア。あなたのタイムが世界に並ぶ。"),
            "ko":      ("완료.", "한 퍼즐당 한 번의 기록. 당신의 시간, 세계 순위에."),
            "es":      ("Resuelto.", "Una puntuación por puzle. Tu tiempo, en el ranking."),
            "th":      ("สำเร็จ", "คิดคะแนนครั้งเดียวต่อปริศนา เวลาคุณบนกระดานอันดับ"),
        },
        "05-settings": {
            "en":      ("Seven languages. Zero tracking.", "Game Center built in. No third-party SDKs."),
            "zh-Hant": ("七種語言。零追蹤。", "內建 Game Center。沒有第三方 SDK。"),
            "zh-Hans": ("七种语言。零追踪。", "内置 Game Center。没有第三方 SDK。"),
            "ja":      ("7言語対応、追跡ゼロ。", "Game Center対応。サードパーティSDKなし。"),
            "ko":      ("일곱 가지 언어. 추적은 0.", "Game Center 내장. 서드파티 SDK 없음."),
            "es":      ("Siete idiomas. Cero seguimiento.", "Game Center integrado. Sin SDK de terceros."),
            "th":      ("เจ็ดภาษา ไม่มีการติดตาม", "รองรับ Game Center ไม่มี SDK ของบุคคลที่สาม"),
        },
    },
    "minesweeper": {
        # Minesweeper storyline uses the same 5-shot structure per strategy doc,
        # adapted for MS gameplay. Shots 1-4 have copy; shot 5 (Settings)
        # is identical copy since it's the shared SettingsUI.
        "01-home": {
            "en":      ("Calm logic, every day.", "One board, every day. The same for everyone."),
            "zh-Hant": ("每天，一場安靜的推理。", "每天一局，全球同題。"),
            "zh-Hans": ("每天，一场安静的推理。", "每天一局，全球同题。"),
            "ja":      ("毎日、静かな論理を。", "毎日ひとつの盤面。誰にとっても同じ問題。"),
            "ko":      ("매일, 조용한 논리.", "매일 하나의 보드. 모두에게 동일합니다."),
            "es":      ("Lógica tranquila, cada día.", "Un tablero cada día. El mismo para todos."),
            "th":      ("ตรรกะเงียบๆ ทุกวัน", "กระดานเดียวทุกวัน เหมือนกันสำหรับทุกคน"),
        },
        "02-daily": {
            "en":      ("Three boards. Every day.", "Beginner, intermediate, expert — world-shared."),
            "zh-Hant": ("每天三局。世界同局。", "初級、中級、高級，全球同一題。"),
            "zh-Hans": ("每天三局。世界同局。", "初级、中级、高级，全球同一题。"),
            "ja":      ("毎日3面。世界中で同じ盤面。", "初級・中級・上級、世界共通の盤面。"),
            "ko":      ("매일 세 개의 보드. 전 세계 동일.", "초급, 중급, 고급 — 전 세계 공통."),
            "es":      ("Tres tableros. Cada día.", "Principiante, intermedio, avanzado — el mismo para todos."),
            "th":      ("สามกระดาน ทุกวัน", "มือใหม่ ระดับกลาง ขั้นสูง — เหมือนกันทั่วโลก"),
        },
        "03-board": {
            "en":      ("Flag, reveal, solve.", "Logical deduction. No guessing required."),
            "zh-Hant": ("標記、揭開、解題。", "純邏輯推理，無需猜測。"),
            "zh-Hans": ("标记、揭开、解题。", "纯逻辑推理，无需猜测。"),
            "ja":      ("旗を立て、開き、解く。", "純粋な論理推理。推測は不要。"),
            "ko":      ("깃발, 열기, 풀이.", "논리적 추론. 추측은 필요 없습니다."),
            "es":      ("Marca, revela, resuelve.", "Deducción lógica. Sin necesidad de adivinar."),
            "th":      ("ปักธง เปิดช่อง ไขปริศนา", "ใช้เหตุผลเชิงตรรกะล้วนๆ ไม่ต้องเดา"),
        },
        "04-completion": {
            "en":      ("Cleared.", "One attempt per board. Your time, ranked globally."),
            "zh-Hant": ("完成。", "每局一次計時。你的成績，全球排名。"),
            "zh-Hans": ("完成。", "每局一次计时。你的成绩，全球排名。"),
            "ja":      ("クリア。", "1面につき1回の挑戦。あなたのタイムが世界に並ぶ。"),
            "ko":      ("클리어.", "보드당 한 번의 시도. 당신의 시간, 세계 랭킹에."),
            "es":      ("Despejado.", "Un intento por tablero. Tu tiempo, en el ranking global."),
            "th":      ("สำเร็จ", "หนึ่งครั้งต่อกระดาน เวลาคุณบนอันดับโลก"),
        },
    },
}

# ── Direction B: feature-callout chips (Board / Completion slots only) ────────
#
# NEW copy — not a rewrite of the locked screenshot-strategy.md headline/subhead
# text above. Short (2-4 word) chip labels naming ONE concrete, currently-visible
# UI element per slot. Authored ONCE per (app, slot, device) in NORMALIZED
# SCREEN-FRACTION coordinates (fx, fy — fraction of the baseline PNG's own
# width/height) and reused across every locale (translated text only, never a
# per-locale position) per the redesign spec. Device classes get their OWN
# anchor because the Board/Completion layouts are NOT proportionally identical
# between iPhone (stacked) and iPad (side-by-side controls) — verified by
# eyeballing both baselines, not guessed.
CALLOUTS = {
    ("sudoku", "03-board"): [{
        # Anchor dot = the red error cell (row0,col2) — the actual thing
        # "catches mistakes instantly" refers to. The OLD default (chip
        # dropped straight below the dot) landed on row2's live "9"/"8"
        # cells — #979. A first `chip_at` attempt tried the empty block at
        # columns 6-8 — that's real empty grid space, but the chip's own
        # width (measured: ~42% of canvas width for the longest label) means
        # centering it there pushes past the right margin, and the margin
        # clamp in draw_callout_chip then drags it back LEFT onto the very
        # cells being avoided. Fixed target instead: the empty gap in the
        # HEADER ROW above the grid, between "Easy" and the timer/pause
        # controls — measured directly (column-scan for non-background
        # pixels in that row) at 56%/76% of the baseline's own width on
        # iPhone/iPad respectively, comfortably wider than the chip in every
        # locale, so no clamp ever engages.
        "anchor": {"iphone-6.9": (0.295, 0.180), "ipad-13": (0.207, 0.315)},
        "chip_at": {"iphone-6.9": (0.403, 0.112), "ipad-13": (0.360, 0.210)},
        "en": "Catches mistakes instantly", "zh-Hant": "即時抓出錯誤", "zh-Hans": "实时揪出错误",
        "ja": "ミスをその場で検出", "ko": "실수를 즉시 잡아냄",
        "es": "Detecta errores al instante", "th": "จับข้อผิดพลาดได้ทันที",
    }],
    ("sudoku", "04-completion"): [{
        # Anchor = the completion card's OWN bottom edge (measured by scanning
        # the baseline for the card's near-white bounding box), not the tiny
        # time glyph inside it — an anchor that sits ON dense card content had
        # the chip overlap the checkmark/"Solved!" text; the card's edge always
        # has clear blank canvas below it to drop the chip into.
        "anchor": {"iphone-6.9": (0.500, 0.620), "ipad-13": (0.500, 0.574)},
        "en": "Every solve, timed & ranked", "zh-Hant": "每次完成，計時排名", "zh-Hans": "每次完成，计时排名",
        "ja": "解くたびにタイム計測＆ランキング", "ko": "풀 때마다 시간 측정 및 순위",
        "es": "Cada partida, cronometrada y clasificada", "th": "ทุกครั้งที่ไข จับเวลาและจัดอันดับ",
    }],
    ("minesweeper", "03-board"): [{
        # iPad: the default below-anchor drop landed the chip on the covered
        # grid tiles — #979. `chip_at` moves the chip into the right-hand
        # control column, well below the Reveal button (both measured off
        # the baseline: grid's own right edge, and the button's bottom
        # edge). fx is deliberately far enough right that draw_callout_chip's
        # own margin clamp is what places it (any fx past ~0.83 clamps to
        # the same spot) — the clamped position clears the grid's right edge
        # with room to spare. iPhone's anchor already has clear space
        # directly below it (verified — the stacked-controls layout puts the
        # grid much lower on that device), so it keeps the default drop.
        "anchor": {"iphone-6.9": (0.092, 0.045), "ipad-13": (0.700, 0.016)},
        "chip_at": {"ipad-13": (0.850, 0.200)},
        "en": "Flag suspected mines", "zh-Hant": "標記可疑地雷", "zh-Hans": "标记可疑地雷",
        "ja": "疑わしいマスに旗を立てる", "ko": "의심되는 칸에 깃발 표시",
        "es": "Marca las minas sospechosas", "th": "ปักธงจุดที่สงสัยว่ามีระเบิด",
    }],
    ("minesweeper", "04-completion"): [{
        # See the Sudoku completion callout's comment. MS's card sits closer to
        # its own "Close" button than Sudoku's does to the canvas edge (no
        # "Mistakes" row), so the fixed below-offset from the CARD bottom would
        # land the chip ON the Close button — anchor to the Close BUTTON's own
        # bottom edge instead (measured the same way), which always has clear
        # canvas below it.
        "anchor": {"iphone-6.9": (0.500, 0.637), "ipad-13": (0.500, 0.585)},
        "en": "Every board, timed & ranked", "zh-Hant": "每一局，計時排名", "zh-Hans": "每一局，计时排名",
        "ja": "毎回タイム計測＆ランキング", "ko": "매 판마다 시간 측정 및 순위",
        "es": "Cada tablero, cronometrado y clasificado", "th": "ทุกกระดาน จับเวลาและจัดอันดับ",
    }],
}

# ── Baseline → output slot mapping ─────────────────────────────────────────────
#
# One baseline per slot, reused for every locale — same as pre-redesign. A
# per-locale-baseline variant was tried and backed out (#977): SwiftUI's
# `Text(LocalizedStringKey)` resolves against `Bundle.main`, not
# `.environment(\.locale, ...)`, so inside a headless `swift test` host (no
# compiled `.lproj` in `Bundle.main`) the underlying screenshot never
# localizes — all 108 locale-specific baselines that attempt came out
# byte-identical to `en`. Only the composited overlay below (headline /
# subhead / Direction-B callouts) is locale-aware; see #977 for the real fix.
#
# `named` is the `named:` string the snapshot test passes to
# `assertSnapshot`/`assertUISnapshot`.


class Slot:
    __slots__ = ("name", "suite_dir", "named", "prefix")

    def __init__(self, name: str, suite_dir: str, named: str, prefix: str):
        self.name = name
        self.suite_dir = suite_dir
        self.named = named
        self.prefix = prefix

    def baseline(self, baselines_root: Path) -> Path:
        return baselines_root / self.suite_dir / f"{self.prefix}.{self.named}.png"


SLOTS = {
    "iphone-6.9": {
        "sudoku": [
            Slot("01-home", "HomeViewTests", "HomeView-iPhone-light", "snapshotIPhoneLight"),
            Slot("02-daily", "DailyHubViewTests", "DailyHub-iPhone-light-unfinished", "snapshotUnfinishedIPhoneLight"),
            Slot("03-board", "BoardViewTests", "Board-iPhone-light-inProgress", "snapshotInProgress_iPhone_light"),
            Slot("04-completion", "CompletionViewTests", "Completion-iPhone-light-loaded",
                 "snapshot_authenticatedLoaded_iPhoneLight"),
            Slot("05-settings", "SettingsViewTests", "SettingsView-fullpage-iPhone-light-purchased",
                 "snapshot_iPhone_light_purchased"),
        ],
        "minesweeper": [
            Slot("01-home", "MinesweeperHomeSnapshotTests", "Home-iPhone-light-compact", "snapshotHome_iPhone_light"),
            Slot("02-daily", "MinesweeperDailyHubSnapshotTests", "Daily-iPhone-light-compact", "snapshotDaily_iPhone_light"),
            Slot("03-board", "MinesweeperBoardSnapshotTests", "Board-iPhone-light-beginner-covered",
                 "snapshotBeginnerCovered_iPhone_light"),
            Slot("04-completion", "MinesweeperCompletionSnapshotTests", "Completion-iPhone-light-win-loaded",
                 "snapshotWinLoaded_iPhone_light"),
        ],
    },
    "ipad-13": {
        "sudoku": [
            Slot("01-home", "HomeViewTests", "HomeView-iPad-light", "snapshotIPadLight"),
            Slot("02-daily", "DailyHubViewTests", "DailyHub-iPad-light-unfinished", "snapshotUnfinishedIPadLight"),
            Slot("03-board", "BoardViewTests", "Board-iPad-light-inProgress", "snapshotInProgress_iPad_light"),
            Slot("04-completion", "CompletionViewTests", "Completion-iPad-light-loaded",
                 "snapshot_authenticatedLoaded_iPadLight"),
            Slot("05-settings", "SettingsViewTests", "SettingsView-fullpage-iPad-light-purchased",
                 "snapshot_iPad_light_purchased"),
        ],
        "minesweeper": [
            Slot("01-home", "MinesweeperHomeSnapshotTests", "Home-iPad-light-regular", "snapshotHome_iPad_light"),
            Slot("02-daily", "MinesweeperDailyHubSnapshotTests", "Daily-iPad-light-regular", "snapshotDaily_iPad_light"),
            Slot("03-board", "MinesweeperBoardSnapshotTests", "Board-iPad-light-beginner-covered",
                 "snapshotBeginnerCovered_iPad_light"),
            Slot("04-completion", "MinesweeperCompletionSnapshotTests", "Completion-iPad-light-win-loaded",
                 "snapshotWinLoaded_iPad_light"),
        ],
    },
}

BASELINES_ROOT = {"sudoku": BASELINES_SUDOKU, "minesweeper": BASELINES_MS}

LOCALES = ["en", "zh-Hant", "zh-Hans", "ja", "ko", "es", "th"]

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

# Han-script locales (Traditional/Simplified Chinese + Japanese) share Hiragino
# Sans GB's glyph coverage (Han + kana). Korean and Thai each need a DIFFERENT
# system font — Hiragino Sans GB has NO Hangul glyphs and SFNS has NO Thai
# glyphs, so routing ko/th through either produces silent .notdef "tofu"
# (verified via fontTools cmap inspection before this locale expansion: ko
# 가/U+AC00 and th ก/U+0E01 are both MISSING from those fonts' cmaps).
HAN_LOCALES = {"zh-Hant", "zh-Hans", "ja"}
KO_LOCALES = {"ko"}
TH_LOCALES = {"th"}

# Hiragino Sans GB .ttc faces: index 0 = W3 (regular), index 2 = W6 (semibold).
_HIRAGINO = "/System/Library/Fonts/Hiragino Sans GB.ttc"
_PINGFANG = "/System/Library/Fonts/PingFang.ttc"  # preferred if present (not on all macOS)

# Apple SD Gothic Neo .ttc faces: index 0 = Regular, index 6 = Bold. Full
# Hangul coverage (verified via fontTools cmap); this machine has no PingFang
# Korean face, so Apple SD Gothic Neo is the only Hangul-complete system font.
_APPLE_SD_GOTHIC_NEO = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

# Ayuthaya.ttf is the PRIMARY Thai font, not Thonburi: this Pillow build has
# no `raqm` (verified via PIL.features.check("raqm") == False, and a fresh
# `pip install Pillow` wheel in a scratch venv still reports no raqm — the
# macOS PyPI wheel does not bundle it, and `libraqm` itself would need
# Homebrew, which this repo's operating rules forbid). Without raqm, Pillow
# can't do OpenType mark-to-base GPOS positioning, so Thonburi's combining
# vowel/tone marks render as orphaned dotted-circle placeholders (visually
# confirmed — real tofu-equivalent breakage). Ayuthaya predates OpenType
# complex-script shaping and bakes mark vertical offsets into the glyph
# outlines themselves, so it renders correctly under Pillow's non-shaped
# layout. Thonburi is kept only as a secondary fallback if Ayuthaya is ever
# absent (worse than nothing being unlikely, since Ayuthaya ships on every
# stock macOS). Ayuthaya has one weight only — `bold` synthesizes via stroke.
_AYUTHAYA = "/System/Library/Fonts/Supplemental/Ayuthaya.ttf"
_THONBURI = "/System/Library/Fonts/Supplemental/Thonburi.ttc"


def _han_font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    """A Han/kana-capable font (PingFang if available, else Hiragino Sans GB)."""
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


def _ko_font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    """A Hangul-capable font (Apple SD Gothic Neo)."""
    if os.path.exists(_APPLE_SD_GOTHIC_NEO):
        return ImageFont.truetype(_APPLE_SD_GOTHIC_NEO, size, index=(6 if bold else 0))
    # Last resort — Latin-only; Hangul will tofu but the run won't crash.
    return _latin_font(size)


def _th_font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    """A Thai-capable font that renders correctly WITHOUT raqm shaping
    (Ayuthaya; Thonburi is a fallback but needs raqm to avoid dotted-circle
    mark breakage — see the module comment above _AYUTHAYA). Ayuthaya has one
    weight, so `bold` is a no-op (still legible: headline is already set apart
    by size 72 vs subhead 44 and the accent color)."""
    if os.path.exists(_AYUTHAYA):
        return ImageFont.truetype(_AYUTHAYA, size)
    if os.path.exists(_THONBURI):
        return ImageFont.truetype(_THONBURI, size, index=(1 if bold else 0))
    # Last resort — Latin-only; Thai will tofu but the run won't crash.
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
    """Return a glyph-complete font for *locale* (script-aware)."""
    if locale in HAN_LOCALES:
        return _han_font(size, bold)
    if locale in KO_LOCALES:
        return _ko_font(size, bold)
    if locale in TH_LOCALES:
        return _th_font(size, bold)
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
    """Return (bg_color, accent_color, accent_deep, accent_muted) for the app."""
    if app == "sudoku":
        return SUDOKU_BG, SUDOKU_ACCENT, SUDOKU_ACCENT_DEEP, SUDOKU_ACCENT_MUTED
    return MS_BG, MS_ACCENT, MS_ACCENT_DEEP, MS_ACCENT_MUTED


def rounded_top_mask(size: tuple[int, int], radius: int) -> Image.Image:
    """An 'L' mode mask: rounded top-left/top-right corners, square bottom —
    the device screenshot's top edge reads as a screen, its bottom edge
    bleeds flush into the canvas edge (Direction C's structural fix for the
    old 'floating bezel in an empty canvas' problem)."""
    w, h = size
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, w - 1, h - 1 + radius), radius=radius, fill=255)
    return mask


def detect_content_bottom(img: Image.Image, bg_color: tuple[int, int, int], tolerance: int = 12) -> int:
    """Return the y-coordinate (source pixel space) of the last row carrying
    real content, scanning bottom-up. A pixel counts as content if it's not
    (near-)transparent AND its color differs from the app's own background
    by more than `tolerance` — one test that handles both baseline shapes in
    this pipeline: a full opaque device screenshot (content ends where the
    List/Form's own cream background starts) and a floating hero-reveal card
    on a transparent canvas (content ends where alpha drops to ~0). #979."""
    rgba = img if img.mode == "RGBA" else img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    br, bg_g, bb = bg_color
    for y in range(h - 1, -1, -1):
        for x in range(0, w, 2):
            r, g, b, a = px[x, y]
            if a > 40 and (abs(r - br) + abs(g - bg_g) + abs(b - bb)) > tolerance:
                return y
    return 0


def paste_icon_badge(canvas: Image.Image, app: str, asc_w: int, margin: int, size: int) -> None:
    """Composite the app's own AppIcon (real shipped asset) as a small
    rounded-square badge in the top-left corner, for shelf recognition."""
    icon_path = APP_ICONS[app]
    if not icon_path.exists():
        return
    icon = Image.open(icon_path).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.22), fill=255)
    icon.putalpha(mask)
    canvas.paste(icon, (margin, margin), icon)
    # Hairline stroke so the badge pops off the gradient at low contrast.
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.rounded_rectangle(
        (margin, margin, margin + size - 1, margin + size - 1),
        radius=int(size * 0.22), outline=(255, 255, 255, 130), width=3
    )


def draw_callout_chip(
    canvas: Image.Image,
    anchor_xy: tuple[int, int],
    label: str,
    locale: str,
    accent_color: tuple[int, int, int],
    asc_w: int,
    chip_xy: Optional[tuple[int, int]] = None,
) -> None:
    """One Direction-B feature callout: a small dot at the anchor (the actual
    UI feature being called out), a leader line, and a rounded pill chip
    carrying the (per-locale) label.

    `chip_xy`, when given, is the chip's own target position (verified empty
    canvas — grid geometry measured directly off the baseline, not guessed;
    #979) and the leader line is drawn straight from the anchor dot to the
    chip instead of assuming "chip sits directly below the dot". When
    omitted, falls back to the original below-anchor default (chip centered
    under the dot, dropped by a fixed offset) for callouts that already have
    clear space directly beneath their anchor."""
    draw = ImageDraw.Draw(canvas, "RGBA")
    ax, ay = anchor_xy

    dot_r = max(6, int(asc_w * 0.007))
    draw.ellipse((ax - dot_r, ay - dot_r, ax + dot_r, ay + dot_r),
                 fill=(255, 255, 255, 255), outline=accent_color, width=3)

    chip_font = font_for(locale, int(asc_w * 0.030), bold=True)
    tmp = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    bbox = tmp.textbbox((0, 0), label, font=chip_font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    pad_x, pad_y = int(asc_w * 0.026), int(asc_w * 0.016)
    chip_w = text_w + pad_x * 2
    chip_h = text_h + pad_y * 2

    if chip_xy is not None:
        cx, cy = chip_xy
        chip_x = min(max(cx - chip_w // 2, int(asc_w * 0.04)), asc_w - chip_w - int(asc_w * 0.04))
        chip_y = cy
    else:
        offset = int(asc_w * 0.12)
        chip_x = min(max(ax - chip_w // 2, int(asc_w * 0.04)), asc_w - chip_w - int(asc_w * 0.04))
        chip_y = ay + offset

    draw.line((ax, ay, chip_x + chip_w // 2, chip_y), fill=(255, 255, 255, 220), width=3)

    draw.rounded_rectangle(
        (chip_x, chip_y, chip_x + chip_w, chip_y + chip_h),
        radius=chip_h // 2, fill=(*accent_color, 240)
    )
    draw.text(
        (chip_x + pad_x, chip_y + pad_y - bbox[1]), label,
        font=chip_font, fill=(255, 255, 255, 255)
    )


def build_asc_image(baseline_path: Path,
                    headline: str,
                    subhead: str,
                    app: str,
                    locale: str,
                    asc_w: int = ASC_W,
                    asc_h: int = ASC_H,
                    callouts: Optional[list[dict]] = None,
                    device: str = "iphone-6.9") -> Image.Image:
    """
    Compose one ASC-spec RGB PNG at the given canvas size — Direction C
    (full-bleed brand-gradient ground + headline set directly into the color +
    device screenshot bleeding off the bottom + app-icon badge), optionally
    layered with Direction B (feature-callout chips, Board/Completion only).

    Layout (top → bottom):
      - Full-bleed vertical gradient (app's OWN accent, deep → mid)
      - App-icon badge, top-left corner
      - Headline (bold, set directly into the gradient) + subhead
      - Device screenshot, full canvas width minus side margins, rounded top
        corners, bottom edge bleeding past the canvas edge (PIL clips
        automatically — no bezel/frame drawn around it). Cropped to its
        content-bearing region first (#979) so the bleed cuts into content,
        never a large flat area of the screenshot's own dead space.
      - Direction B: callout chips + leader lines anchored to specific UI,
        positioned in normalized screen-fraction coordinates (CALLOUTS above)
        — `chip_at` optionally repositions the CHIP itself away from the
        anchor when the default below-anchor drop would land on content.
    """
    bg_color, accent_color, accent_deep, accent_muted = make_frame(app)

    canvas = Image.new("RGB", (asc_w, asc_h), accent_color)
    draw = ImageDraw.Draw(canvas, "RGBA")

    # ── Full-bleed brand gradient (deep accent at top → accent at ~55% down,
    #    where the screenshot begins) ──────────────────────────────────────
    gradient_h = int(asc_h * 0.55)
    for y in range(gradient_h):
        t = y / gradient_h
        r, g, b = blend(accent_deep, accent_color, t)
        draw.line([(0, y), (asc_w, y)], fill=(r, g, b))

    # ── App-icon badge (top-left, shelf recognition) ──────────────────────
    badge_margin = int(asc_w * 0.055)
    badge_size = int(asc_w * 0.088)
    paste_icon_badge(canvas, app, asc_w, badge_margin, badge_size)

    # ── Headline + subhead set directly into the gradient ─────────────────
    TEXT_LEFT = int(asc_w * 0.070)
    TEXT_WIDTH = asc_w - TEXT_LEFT * 2
    TEXT_TOP = badge_margin + badge_size + int(asc_h * 0.045)

    font_headline = font_for(locale, int(asc_w * 0.068), bold=True)
    font_subhead = font_for(locale, int(asc_w * 0.036), bold=False)

    tmp_draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    def text_w(s: str, font: ImageFont.FreeTypeFont) -> int:
        bbox = tmp_draw.textbbox((0, 0), s, font=font)
        return bbox[2] - bbox[0]

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

    headline_lines = wrap_text(headline, font_headline, TEXT_WIDTH)
    subhead_lines = wrap_text(subhead, font_subhead, TEXT_WIDTH)

    LINE_GAP_H = int(asc_h * 0.006)
    LINE_GAP_S = int(asc_h * 0.005)
    BLOCK_GAP = int(asc_h * 0.014)

    ty = TEXT_TOP
    for line in headline_lines:
        draw.text((TEXT_LEFT, ty), line, font=font_headline, fill=(255, 255, 255, 255))
        bbox = tmp_draw.textbbox((0, 0), line, font=font_headline)
        ty += (bbox[3] - bbox[1]) + LINE_GAP_H
    ty += BLOCK_GAP - LINE_GAP_H
    for line in subhead_lines:
        draw.text((TEXT_LEFT, ty), line, font=font_subhead, fill=(255, 255, 255, 217))
        bbox = tmp_draw.textbbox((0, 0), line, font=font_subhead)
        ty += (bbox[3] - bbox[1]) + LINE_GAP_S

    # ── Device screenshot: full width minus margins, rounded top corners,
    #    bottom bleeds past the canvas edge when content reaches that far ──
    #
    # #979: bleeding the FULL baseline (device-height) screenshot let the
    # panel's dead-space tail (a scrolled list's own empty background below
    # its last row) become the thing that bleeds, not the content — some
    # slots (Home: 49% content, Daily: 39%, Settings: 52%) showed a large
    # flat cream area inside the panel instead of the "no empty canvas is
    # possible" guarantee Direction C was built for. Fix: crop the baseline
    # to its content-bearing region (detect_content_bottom + a little
    # padding) before compositing, at the SAME width-fill scale as before
    # (unchanged) — so the panel is exactly as tall as its real content.
    #
    # An earlier version of this fix also zoomed PAST the width-fill scale
    # to force every slot to bleed all the way to the canvas edge. That
    # regressed worse than the bug it fixed: a slot whose content is short
    # relative to its width (MS iPad's covered board — grid + control panel
    # together only reach 44% down) needed enough zoom to also outgrow
    # screen_w, and center-cropping the overflow back down clipped the right
    # control panel's own "Reveal" button off the edge — hiding real product
    # UI, the exact failure mode Direction B's chip-overlap fix (below) also
    # exists to avoid. A shorter panel with the brand gradient showing below
    # it (not cream, not clipped controls) satisfies the actual acceptance
    # bar — no flat area with nothing in it — without that risk. Slots whose
    # content already reaches deep enough (Board's digit pad, ~92%) still
    # bleed past the edge exactly as before; nothing tries to force it.
    SCREEN_MARGIN = int(asc_w * 0.045)
    SCREEN_TOP = ty + int(asc_h * 0.055)
    screen_w = asc_w - SCREEN_MARGIN * 2

    CONTENT_PAD_FRAC = 0.03  # breathing room below the last content row

    src_full = Image.open(baseline_path).convert("RGBA")
    src_w, src_h_full = src_full.size
    scale = screen_w / src_w

    content_bottom_px = detect_content_bottom(src_full, bg_color)
    crop_h = min(src_h_full, content_bottom_px + int(src_h_full * CONTENT_PAD_FRAC))

    fit_w, fit_h = screen_w, int(crop_h * scale)
    src_resized = src_full.crop((0, 0, src_w, crop_h)).resize((fit_w, fit_h), Image.LANCZOS)
    bg_patch = Image.new("RGB", (fit_w, fit_h), bg_color)
    bg_patch.paste(src_resized, (0, 0), src_resized)

    corner_radius = int(asc_w * 0.045)
    mask = rounded_top_mask((fit_w, fit_h), corner_radius)
    canvas.paste(bg_patch, (SCREEN_MARGIN, SCREEN_TOP), mask)

    # ── Direction B: feature-callout chips (Board / Completion only) ──────
    #
    # fx/fy are fractions of the ORIGINAL (uncropped) baseline — that's the
    # stable reference frame regardless of how much the block above zoomed
    # in, and X is unaffected by the (vertical-only) crop, so this maps
    # correctly whether or not this slot needed any zoom.
    if callouts:
        for callout in callouts:
            fx, fy = callout["anchor"][device]
            anchor_xy = (SCREEN_MARGIN + int(fx * screen_w), SCREEN_TOP + int(fy * src_h_full * scale))
            label = callout.get(locale) or callout["en"]
            chip_target = callout.get("chip_at", {}).get(device)
            chip_xy = None
            if chip_target:
                cfx, cfy = chip_target
                chip_xy = (SCREEN_MARGIN + int(cfx * screen_w), SCREEN_TOP + int(cfy * src_h_full * scale))
            draw_callout_chip(canvas, anchor_xy, label, locale, accent_color, asc_w, chip_xy=chip_xy)

    # ── Final sanity: canvas must be RGB (no alpha) ───────────────────────────
    assert canvas.mode == "RGB", f"Expected RGB, got {canvas.mode}"
    assert canvas.size == (asc_w, asc_h), f"Expected {asc_w}×{asc_h}, got {canvas.size}"

    return canvas


# ── Main ──────────────────────────────────────────────────────────────────────

def generate_all(dry_run: bool = False) -> list[dict]:
    """Generate all ASC-spec PNGs (every device × app × slot × locale)."""
    results = []

    for device, apps in SLOTS.items():
        dev = DEVICES[device]
        for app, slots in apps.items():
            for slot in slots:
                baselines_root = BASELINES_ROOT[app]
                slot_callouts = CALLOUTS.get((app, slot.name))
                for locale in LOCALES:
                    copy_block = COPY.get(app, {}).get(slot.name, {}).get(locale)
                    if copy_block is None:
                        results.append({
                            "device": device, "app": app, "slot": slot.name,
                            "locale": locale, "status": "SKIPPED-NO-COPY", "path": None,
                        })
                        continue

                    baseline_path = slot.baseline(baselines_root)
                    if not baseline_path.exists():
                        results.append({
                            "device": device, "app": app, "slot": slot.name,
                            "locale": locale, "status": "SKIPPED-MISSING-BASELINE",
                            "baseline": str(baseline_path), "path": None,
                        })
                        continue

                    out_dir = OUT_ASCSPEC / app / device / locale
                    out_path = out_dir / f"{slot.name}.png"

                    if not dry_run:
                        out_dir.mkdir(parents=True, exist_ok=True)
                        headline, subhead = copy_block
                        img = build_asc_image(
                            baseline_path, headline, subhead, app, locale,
                            asc_w=dev["w"], asc_h=dev["h"],
                            callouts=slot_callouts, device=device,
                        )
                        img.save(str(out_path), "PNG", optimize=False)

                    results.append({
                        "device": device, "app": app, "slot": slot.name,
                        "locale": locale,
                        "status": "OK" if not dry_run else "DRY-RUN",
                        "path": out_path,
                    })

    return results


def verify_outputs(results: list[dict]) -> list[dict]:
    """
    Verify every generated PNG matches its device's exact ASC pixel size with
    no alpha. Annotates each result dict with 'verified' / 'fail_reason'.
    Returns only the FAIL entries.
    """
    failures = []
    for r in results:
        if r["status"] != "OK" or r["path"] is None:
            continue
        dev = DEVICES[r["device"]]
        exp_w, exp_h = dev["w"], dev["h"]
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
            ok = (w == exp_w and h == exp_h and mode == "RGB")
            r["verified"] = ok
            r["dims"] = f"{w}×{h}"
            r["mode"] = mode
            r["md5"] = hashlib.md5(path.read_bytes()).hexdigest()[:8]
            if not ok:
                r["fail_reason"] = f"got {w}×{h} {mode}, expected {exp_w}×{exp_h} RGB"
                failures.append(r)
        except Exception as exc:
            r["verified"] = False
            r["fail_reason"] = str(exc)
            failures.append(r)
    return failures


def print_report(results: list[dict], failures: list[dict]) -> None:
    print()
    print("── ASC-spec screenshot build report ──────────────────────────────────────────")
    print(f"{'Device':<12} {'App':<14} {'Locale':<8} {'Slot':<16} {'Status':<26} {'Dims / Mode'}")
    print("─" * 100)
    for r in results:
        path_str = ""
        if r.get("dims"):
            path_str = f"{r['dims']} {r.get('mode','')}  md5={r.get('md5','')}"
        elif r["path"]:
            path_str = str(r["path"]).replace(str(REPO_ROOT), "")
        status_str = r["status"] + (" ✓" if r.get("verified") else
                                    (" ✗ " + r.get("fail_reason","") if "fail_reason" in r else ""))
        print(f"{r['device']:<12} {r['app']:<14} {r['locale']:<8} {r['slot']:<16} {status_str:<30} {path_str}")

    print()
    print(f"Total: {len(results)} slots processed  |  "
          f"Generated: {sum(1 for r in results if r['status']=='OK')}  |  "
          f"Skipped: {sum(1 for r in results if r['status'].startswith('SKIPPED'))}  |  "
          f"Failures: {len(failures)}")
    if failures:
        print("\n⚠️  VERIFICATION FAILURES:")
        for f in failures:
            print(f"  {f['device']}/{f['app']}/{f['locale']}/{f['slot']}: {f.get('fail_reason')}")
        sys.exit(1)
    else:
        print("\nAll generated PNGs match their device ASC pixel size, RGB (no alpha). Spec: ✓")


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
        for device, apps in SLOTS.items():
            for app, slots in apps.items():
                for slot in slots:
                    for locale in LOCALES:
                        out_path = OUT_ASCSPEC / app / device / locale / f"{slot.name}.png"
                        copy_block = COPY.get(app, {}).get(slot.name, {}).get(locale)
                        results.append({
                            "device": device, "app": app, "slot": slot.name,
                            "locale": locale,
                            "status": "OK" if out_path.exists() and copy_block else "SKIPPED-NO-COPY",
                            "path": out_path if out_path.exists() else None,
                        })
        failures = verify_outputs(results)
        print_report(results, failures)
        return

    print(f"Building ASC-spec screenshots → {OUT_ASCSPEC}/<app>/<device>/<locale>/")
    device_summary = ", ".join(
        "{} ({}×{})".format(d, v["w"], v["h"]) for d, v in DEVICES.items()
    )
    print(f"Devices: {device_summary}  |  RGB (no alpha)  |  Pillow compositing")
    print()

    results = generate_all()
    failures = verify_outputs(results)
    print_report(results, failures)


if __name__ == "__main__":
    main()
