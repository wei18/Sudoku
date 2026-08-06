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
  - mac        : 2880×1800, APP_DESKTOP 16:10 (#984) — a DIFFERENT layout
    (copy left / app-window-with-chrome right, see `build_mac_asc_image()`),
    not a scaled variant of the iPhone/iPad full-bleed-bottom-bleed frame.

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
import unicodedata
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
    "mac":        {"w": 2880, "h": 1800},  # APP_DESKTOP 16:10, #984
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
        # 01-home — REWRITTEN (marketing overhaul, decision P1 option B, 2026-08):
        # replaces the "Calm logic, every day." / "Two modes..." pairing. Translated
        # to all 7 locales (ai-translated-localization pass).
        "01-home": {
            "en":      ("A quiet place to think.", "Race the clock some days. Just think, on the others."),
            "zh-Hant": ("一個安靜思考的地方。", "想比快就比，不想比就純粹想一想。"),
            "zh-Hans": ("一个安静思考的地方。", "想比快就比，不想比就纯粹想一想。"),
            "ja":      ("静かに考えられる場所。", "急ぐ日はタイムに挑み、そうでない日はただ考える。"),
            "ko":      ("조용히 생각할 수 있는 곳.", "어떤 날은 시간과 겨룹니다. 어떤 날은 그냥 생각만 합니다."),
            "es":      ("Un lugar tranquilo para pensar.", "Algunos días compites con el reloj. Otros, solo piensas."),
            "th":      ("พื้นที่เงียบๆ สำหรับคิด", "บางวันแข่งกับเวลา บางวันแค่คิดเฉยๆ"),
        },
        # 02-daily — REWRITTEN (decision P2, 2026-08): replaces "Three puzzles.
        # Every day." Translated to all 7 locales (ai-translated-localization pass).
        "02-daily": {
            "en":      ("Seven days running, and counting.", "Easy, medium, hard — the same three, for the whole world."),
            "zh-Hant": ("連續好幾天，還在繼續。", "簡單、中等、困難——全世界拿到的是同一組。"),
            "zh-Hans": ("连续好几天，还在继续。", "简单、中等、困难——全世界拿到的是同一组。"),
            "ja":      ("7日連続、まだ更新中。", "やさしい・ふつう・むずかしい、世界中で同じ3問。"),
            "ko":      ("7일 연속, 계속 이어지는 중.", "쉬움, 보통, 어려움 — 전 세계가 똑같은 세 문제."),
            "es":      ("Siete días seguidos, y sigue.", "Fácil, medio, difícil — los mismos tres para todo el mundo."),
            "th":      ("ต่อเนื่องเจ็ดวัน และนับต่อไป", "ง่าย ปานกลาง ยาก ชุดเดียวกันทั่วโลก"),
        },
        # 02b-rank (marketing payoff of #983) — NEW slot, en-only
        # pending the ai-translated-localization pass (registered in
        # PENDING_TRANSLATION_SLOTS below). Every claim is either visible in
        # THIS frame (World/Friends toggle tabs, numbered "TOP RANKED" rows,
        # per-row time, the "You" highlight row) or a plain outcome statement
        # ("every day" mirrors the Daily Rank screen's own daily reset,
        # matching 02-daily's "seven days running" framing) — no claim of a
        # ranking feature not shown, no "best time" (each day is one scoring
        # attempt per 04-completion's "it only counts once").
        "02b-rank": {
            "en":      ("World and Friends, every day.",
                        "See exactly where you land — daily rank, your time, right there."),
            "zh-Hant": ("全球、朋友，天天都在。",
                        "看到自己確切排在哪裡——每日排名、你的時間，就在這裡。"),
            "zh-Hans": ("全球、好友，天天都在。",
                        "看到自己确切排在哪里——每日排名、你的时间，就在这里。"),
            "ja":      ("グローバルとフレンド、毎日。",
                        "自分の順位がひと目でわかる。デイリーランキングと、あなたのタイムがここに。"),
            "ko":      ("전체와 친구, 매일.",
                        "내 위치가 정확히 보입니다. 일일 순위와 나의 시간, 바로 여기에."),
            "es":      ("Global y Amigos, cada día.",
                        "Mira exactamente dónde te ubicas. Ranking diario, tu tiempo, aquí mismo."),
            "th":      ("ทั่วโลกและเพื่อน ทุกวัน",
                        "ดูอันดับของคุณได้ชัดเจน อันดับประจำวัน เวลาของคุณอยู่ตรงนี้"),
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
        # 04-completion subhead — REWRITTEN (#984): the old "Your time,
        # ranked." claimed a ranking that is not depicted anywhere in the
        # frame (the completion card removed a leaderboard-slice presenter
        # in #698 and has been `state: .hidden` since v2.6 — see
        # `CompletionViewModel.swift`). Every claim here must now be either
        # visible in THIS frame (time, mistake count) or an outcome
        # statement independent of what's on screen (one scoring attempt
        # per puzzle). Translated to all 7 locales (ai-translated-
        # localization pass, #984 follow-up) — no locale claims a ranking.
        # 04-completion subhead — REWRITTEN AGAIN (decision P2, 2026-08): "One
        # scoring attempt per puzzle." → "It only counts once", same accuracy
        # constraint as the #984 fix this replaces (only what's visible in THIS
        # frame). Headline "Solved." unchanged. Translated to all 7 locales
        # (ai-translated-localization pass).
        "04-completion": {
            "en":      ("Solved.", "It only counts once — your time and mistakes are right here."),
            "zh-Hant": ("完成。", "同一題只計分一次——你的時間與錯誤次數，就在這裡。"),
            "zh-Hans": ("完成。", "同一题只计分一次——你的时间与错误次数，就在这里。"),
            "ja":      ("解けた。", "スコアは1回きり。あなたのタイムとミス数がここに。"),
            "ko":      ("완료.", "점수는 한 번만 기록됩니다. 당신의 시간과 실수 횟수, 바로 여기에."),
            "es":      ("Resuelto.", "Solo cuenta una vez. Tu tiempo y tus errores, aquí mismo."),
            "th":      ("สำเร็จ", "คิดคะแนนเพียงครั้งเดียว เวลาและจำนวนที่พลาดของคุณอยู่ตรงนี้"),
        },
        # 05-settings — REWRITTEN (#984): the old "Zero tracking." / "No
        # third-party SDKs." directly contradicts
        # `App/Sudoku/Resources/PrivacyInfo.xcprivacy`
        # (`NSPrivacyTracking = true`, 8 declared AdMob tracking domains) and
        # the linked GoogleMobileAds dependency (`AppMonetizationKit`) — a
        # false privacy claim in live App Store metadata. New copy sells
        # only what's true and defensible: seven fully-localized languages,
        # Game Center, and the ads-removal purchase (both visible in this
        # frame's "Ads Removed / Active" row and "Game Center" row) — no
        # privacy/tracking claim at all, to stay safely clear of
        # PrivacyInfo.xcprivacy. Translated to all 7 locales (ai-translated-
        # localization pass, #984 follow-up) — no locale claims tracking.
        # 05-settings — REWRITTEN AGAIN (decision P2, 2026-08): replaces the #984
        # "Seven languages, fully localized." pairing. Translated to all 7
        # locales (ai-translated-localization pass).
        "05-settings": {
            "en":      ("Set it up once, then forget about it.", "Seven languages. One purchase drops the ads for good. Game Center's already there."),
            "zh-Hant": ("設定一次，之後不用再管。", "七種語言全部到位。一次購買永久移除廣告，Game Center 也內建好了。"),
            "zh-Hans": ("设置一次，之后不用再管。", "七种语言全部到位。一次购买永久移除广告，Game Center 也内置好了。"),
            "ja":      ("一度設定すれば、あとは気にしなくていい。", "7言語すべて対応済み。一度の購入で広告を永久に削除、Game Centerも最初から搭載。"),
            "ko":      ("한 번 설정하면 끝.", "일곱 가지 언어 모두 준비. 한 번 구매로 광고를 영구 제거, Game Center도 이미 포함."),
            "es":      ("Configúralo una vez y olvídate.", "Siete idiomas. Una compra elimina los anuncios para siempre. Game Center ya está incluido."),
            "th":      ("ตั้งค่าครั้งเดียว แล้วไม่ต้องกังวลอีก", "รองรับ 7 ภาษาครบ ซื้อครั้งเดียวลบโฆษณาถาวร มี Game Center พร้อมใช้งาน"),
        },
    },
    "minesweeper": {
        # Minesweeper storyline uses the same shot numbering as the strategy
        # doc, adapted for MS gameplay. MS has NO "05-settings" slot in this
        # generator — despite both apps sharing the same SettingsUI, no MS
        # Settings ASC screenshot has ever been wired into `SLOTS` (verified
        # against `SLOTS` below: iphone-6.9/ipad-13 "minesweeper" lists only
        # 01-04). An earlier version of this comment claimed shot 5 existed
        # for MS "since it's the shared SettingsUI" — that never shipped;
        # corrected as part of the #984 caption-accuracy sweep. MS's
        # macOS-only "06-stats" slot (below) is a different, new slot, not a
        # settings shot.
        # 01-home — REWRITTEN (marketing overhaul, decision P1, 2026-08): replaces
        # the "Calm logic, every day." pairing. Translated to all 7 locales
        # (ai-translated-localization pass).
        "01-home": {
            "en":      ("First tap, always safe.", "Pure deduction. No guessing, no unlucky losses."),
            "zh-Hant": ("第一下，永遠安全。", "純邏輯推理，不用猜，不會開局就爆。"),
            "zh-Hans": ("第一下，永远安全。", "纯逻辑推理，不用猜，不会开局就炸。"),
            "ja":      ("初手は、必ず安全。", "純粋な論理推理。推測不要、運で負けることもない。"),
            "ko":      ("첫 탭은 언제나 안전합니다.", "순수한 논리 추론. 추측도, 억울한 패배도 없습니다."),
            "es":      ("El primer toque, siempre seguro.", "Pura deducción. Sin adivinar, sin derrotas por mala suerte."),
            "th":      ("แตะแรก ปลอดภัยเสมอ", "ใช้เหตุผลล้วนๆ ไม่ต้องเดา ไม่มีแพ้เพราะโชคร้าย"),
        },
        # 02-daily headline — REWRITTEN (decision P2 mirror, 2026-08): "Two days
        # running, and counting." NOT "seven" — MS's daily baseline shows a
        # 2-day streak (see COPY_TWO_DAY note / DailyHub-iPhone-light-streak2
        # fixture), unlike Sudoku's 7-day fixture. Subhead UNCHANGED. Translated
        # to all 7 locales (ai-translated-localization pass) — no locale may say
        # "seven" here.
        "02-daily": {
            "en":      ("Two days running, and counting.", "Beginner, intermediate, expert — world-shared."),
            "zh-Hant": ("連續兩天，還在繼續。", "初級、中級、高級，全球同一題。"),
            "zh-Hans": ("连续两天，还在继续。", "初级、中级、高级，全球同一题。"),
            "ja":      ("2日連続、まだ更新中。", "初級・中級・上級、世界共通の盤面。"),
            "ko":      ("2일 연속, 계속 이어지는 중.", "초급, 중급, 고급 — 전 세계 공통."),
            "es":      ("Dos días seguidos, y sigue.", "Principiante, intermedio, avanzado — el mismo para todos."),
            "th":      ("ต่อเนื่องสองวัน และนับต่อไป", "มือใหม่ ระดับกลาง ขั้นสูง — เหมือนกันทั่วโลก"),
        },
        # 02b-rank — see the Sudoku "02b-rank" comment above; same shared
        # DailyRankView, same accuracy constraints. "solve time" mirrors this
        # app's own 04-completion vocabulary ("your solve time is right here").
        "02b-rank": {
            "en":      ("World and Friends, every day.",
                        "See exactly where you land — daily rank, your solve time, right there."),
            "zh-Hant": ("全球、朋友，天天都在。",
                        "看到自己確切排在哪裡——每日排名、你的解題時間，就在這裡。"),
            "zh-Hans": ("全球、好友，天天都在。",
                        "看到自己确切排在哪里——每日排名、你的解题时间，就在这里。"),
            "ja":      ("グローバルとフレンド、毎日。",
                        "自分の順位がひと目でわかる。デイリーランキングと、あなたのクリアタイムがここに。"),
            "ko":      ("전체와 친구, 매일.",
                        "내 위치가 정확히 보입니다. 일일 순위와 나의 클리어 시간, 바로 여기에."),
            "es":      ("Global y Amigos, cada día.",
                        "Mira exactamente dónde te ubicas. Ranking diario, tu tiempo de resolución, aquí mismo."),
            "th":      ("ทั่วโลกและเพื่อน ทุกวัน",
                        "ดูอันดับของคุณได้ชัดเจน อันดับประจำวัน เวลาไขของคุณอยู่ตรงนี้"),
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
        # 04-completion subhead — REWRITTEN (#984), same reasoning as
        # Sudoku's: "ranked globally" is not depicted in this frame (the win
        # card shows only "You won" + time, no leaderboard/rank UI).
        # Translated to all 7 locales (ai-translated-localization pass, #984
        # follow-up) — no locale claims a ranking.
        # 04-completion subhead — REWRITTEN AGAIN (decision P2 mirror, 2026-08),
        # mirrors the Sudoku 04-completion rewrite above. Headline "Cleared."
        # unchanged. Translated to all 7 locales (ai-translated-localization
        # pass).
        "04-completion": {
            "en":      ("Cleared.", "It only counts once — your solve time is right here."),
            "zh-Hant": ("完成。", "每局只計分一次——你的解題時間，就在這裡。"),
            "zh-Hans": ("完成。", "每局只计分一次——你的解题时间，就在这里。"),
            "ja":      ("クリア。", "スコアは1回きり。あなたのクリアタイムがここに。"),
            "ko":      ("클리어.", "점수는 한 번만 기록됩니다. 당신의 클리어 시간, 바로 여기에."),
            "es":      ("Despejado.", "Solo cuenta una vez. Tu tiempo, aquí mismo."),
            "th":      ("สำเร็จ", "คิดคะแนนเพียงครั้งเดียว เวลาไขของคุณอยู่ตรงนี้"),
        },
        # 06-stats — macOS-only slot (#984), NEW copy: no iOS "Stats" slot
        # exists to reuse (MS has no iOS Settings slot either — see comment
        # above — and Sudoku's own Stats screen was never one of the 5
        # iOS shots). Translated (#984 follow-up) — "Daily"/"Practice"
        # reuse the exact in-app MinesweeperKit `Localizable.xcstrings`
        # terms, "synced with iCloud" mirrors the app's own "Stats sync
        # with your iCloud account." footer string.
        "06-stats": {
            "en":      ("Every best time, saved.", "Daily and practice results, synced with iCloud."),
            "zh-Hant": ("每個最佳時間，都被記錄下來。", "今日與練習成績，與 iCloud 同步。"),
            "zh-Hans": ("每个最佳时间，都被记录下来。", "每日与练习成绩，与 iCloud 同步。"),
            "ja":      ("すべてのベストタイムを記録。", "デイリーと練習の記録をiCloudと同期。"),
            "ko":      ("모든 최고 기록을 저장합니다.", "데일리와 연습 기록을 iCloud와 동기화합니다."),
            "es":      ("Cada mejor tiempo, guardado.", "Resultados de Diario y Práctica, sincronizados con iCloud."),
            "th":      ("เวลาที่ดีที่สุด บันทึกไว้ทุกครั้ง", "ผลประจำวันและฝึกฝน ซิงค์กับ iCloud"),
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
# No entry for ("sudoku"|"minesweeper", "02b-rank") (#995): even the fuller
# 10-row "populatedFull" marketing fixture (see DailyRankViewTests.swift) is
# a dense, evenly-spaced list — a leader-line dot anchored to any one row
# (e.g. the "You" row) would sit ON that row's own text, and every anchor
# points at something the subhead already names ("your time, right there").
# A clean cropped frame beats a decorated one here — skipped, not forgotten.
CALLOUTS = {
    ("sudoku", "03-board"): [{
        # Anchor dot = the red error cell (row0,col2) — the actual thing
        # "catches mistakes instantly" refers to. The OLD default (chip
        # dropped straight below the dot) landed on row2's live "9"/"8"
        # cells. A first `chip_at` attempt tried the empty block at
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
        # No `anchor` here (#984): this slot renders with `crop_all_sides=True`
        # (see `build_asc_image`), which crops the completion card tightly on
        # all 4 sides and centers it (never upscaling past 1:1) instead of
        # the fixed-fraction-of-baseline placement every other callout uses —
        # a static fx/fy anchor computed against the OLD full-bleed crop would
        # land in the wrong place once the card's size/position on canvas
        # changes with locale-independent geometry. `build_asc_image` computes
        # this callout's anchor directly from the rendered card's own bottom
        # edge instead. Label REWRITTEN (#984): "timed & ranked" claimed a
        # ranking nothing in the frame shows (see COPY's 04-completion
        # comment) — now names only what the card visibly shows. All 7
        # locales carry the rewritten wording, vocabulary anchored to the
        # same slot's COPY subhead (approved en → l10n pass, #984).
        "en": "Your time and mistake count", "zh-Hant": "你的時間與錯誤次數", "zh-Hans": "你的时间与错误次数",
        "ja": "タイムとミス数", "ko": "시간과 실수 횟수",
        "es": "Tu tiempo y tus errores", "th": "เวลาและจำนวนที่พลาดของคุณ",
    }],
    ("minesweeper", "03-board"): [{
        # iPad: the default below-anchor drop landed the chip on the covered
        # grid tiles. `chip_at` moves the chip into the right-hand
        # control column, well below the Reveal button (both measured off
        # the baseline: grid's own right edge, and the button's bottom
        # edge). fx is deliberately far enough right that draw_callout_chip's
        # own margin clamp is what places it (any fx past ~0.83 clamps to
        # the same spot) — the clamped position clears the grid's right edge
        # with room to spare. iPhone's anchor already has clear space
        # directly below it (verified — the stacked-controls layout puts the
        # grid much lower on that device), so it keeps the default drop.
        #
        # `chip_max_w` (iPad only): the "room to spare" comment above was
        # verified against `en`'s 662px-wide chip only. Re-verifying every
        # locale (feat/store-screenshots-cb fullness audit's own instruction)
        # found ja (838px), es (868px) and th (790px) all wider than the
        # ~772px of actual blank column space measured off the baseline —
        # long enough to spill left onto the grid's rightmost cells. Capping
        # at 30% of canvas width forces those into a second line instead.
        # LESSON: this is what happens when a `chip_at` callout is verified
        # against one locale's chip width instead of measured space — any
        # CALLOUTS entry that sets `chip_at` (squeezing the chip next to a
        # fixed-position UI element rather than dropping it into open canvas)
        # needs a `chip_max_w` sanity check as a matter of course, not just
        # the slot someone happens to be touching that round.
        "anchor": {"iphone-6.9": (0.092, 0.045), "ipad-13": (0.700, 0.016)},
        "chip_at": {"ipad-13": (0.850, 0.200)},
        "chip_max_w": {"ipad-13": 0.30},
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
        #
        # iPhone diverges from iPad here because the two devices use DIFFERENT
        # baseline fixtures (screenshot-fullness audit, feat/store-screenshots-cb):
        # iPad still uses `win-loaded` (content ends at the Close button, 0.637 —
        # same as before), but iPhone was swapped to `win-reminder`, which adds a
        # real "Remind me when tomorrow's boards are ready" row below Close. The
        # OLD 0.637 anchor (Close button's bottom edge) now lands ON that new
        # row's text instead of past it — re-measured via detect_content_bottom()
        # against the win-reminder baseline: content now ends at 0.702, not 0.637.
        #
        # #984: that fixed-fraction `anchor` is now DEAD — this slot renders
        # with `crop_all_sides=True` (see the Sudoku completion callout's
        # comment above; same reasoning applies here), so `build_asc_image`
        # computes the anchor from the rendered card's own bottom edge
        # instead of a baseline-fraction lookup. Label REWRITTEN: "timed &
        # ranked" claimed a ranking the win card never shows (only "You won"
        # + time). All 7 locales carry the rewritten wording, vocabulary
        # anchored to the same slot's COPY subhead (approved en → l10n, #984).
        "en": "Your solve time", "zh-Hant": "你的解題時間", "zh-Hans": "你的解题时间",
        "ja": "あなたのクリアタイム", "ko": "당신의 클리어 시간",
        "es": "Tu tiempo de resolución", "th": "เวลาไขของคุณ",
    }],
}

# ── Slots with EN-only copy pending Leader approval + native translation ──────
#
# (app, slot_name) pairs where the `en` COPY/CALLOUTS entry was just
# rewritten (#984 completion accuracy fix, #984 privacy-claim fix) or is
# brand new (#984 mac-only "06-stats", no iOS counterpart to reuse). Any
# OTHER locale entry present in COPY/CALLOUTS for these slots is stale
# leftover text (the pre-fix wording, or simply absent) — `generate_all()`
# skips rendering every locale but `en` for these until the ai-translated-
# localization pass lands and this set is trimmed. This is what keeps a
# routine re-run of the full generator from silently regenerating 6 locales
# of a slot using either untranslated English or the very wording that was
# just found to be false/inaccurate.
#
# The #984 slots and "02b-rank" (#983) below completed the ai-translated-
# localization pass — every locale now carries the accuracy-fixed / approved
# wording. Repopulate with `(app, slot_name)` the next time an `en`
# COPY/CALLOUTS entry is rewritten ahead of its translation pass.
PENDING_TRANSLATION_SLOTS: set[tuple[str, str]] = set()

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
            Slot("02-daily", "DailyHubViewTests", "DailyHub-iPhone-light-allDone", "snapshotAllCompletedIPhoneLight"),
            # 02b-rank (marketing payoff of #983): the shared Daily Rank
            # screen (World/Friends toggle, "You" highlight) landed in #989.
            # Lexicographic name deliberately sorts right after "02-daily"
            # ("02-daily" < "02b-rank" < "03-board") so the upload tool's
            # filename ordering places it there WITHOUT renaming any existing
            # slot (a rename would force a full re-upload of every locale).
            Slot("02b-rank", "DailyRankViewTests", "DailyRankView-iPhone-light-populatedFull",
                 "snapshotPopulatedFullIPhoneLight"),
            Slot("03-board", "BoardViewPencilNotesTests", "Board-iPhone-light-pencilNotesWithError",
                 "snapshotPencilNotesWithError_iPhone_light"),
            Slot("04-completion", "CompletionViewTests", "Completion-iPhone-light-loaded",
                 "snapshot_authenticatedLoaded_iPhoneLight"),
            Slot("05-settings", "SettingsViewTests", "SettingsView-fullpage-iPhone-light-purchased",
                 "snapshot_iPhone_light_purchased"),
        ],
        "minesweeper": [
            Slot("01-home", "MinesweeperHomeSnapshotTests", "Home-iPhone-light-compact", "snapshotHome_iPhone_light"),
            Slot("02-daily", "MinesweeperDailyHubSnapshotTests", "Daily-iPhone-light-streak2", "snapshotDaily_iPhone_light_streak"),
            # 02b-rank — see the Sudoku comment above; same shared
            # DailyRankView, MS's own populated baseline.
            Slot("02b-rank", "DailyRankViewTests", "DailyRankView-iPhone-light-populatedFull",
                 "snapshotPopulatedFullIPhoneLight"),
            Slot("03-board", "MinesweeperBoardRevealedSnapshotTests", "Board-iPhone-light-beginner-flagged",
                 "snapshotFlagged_iPhone_light"),
            Slot("04-completion", "MinesweeperCompletionSnapshotTests", "Completion-iPhone-light-win-reminder",
                 "snapshotWinDailyReminder_iPhone_light"),
        ],
    },
    "ipad-13": {
        "sudoku": [
            Slot("01-home", "HomeViewTests", "HomeView-iPad-light", "snapshotIPadLight"),
            Slot("02-daily", "DailyHubViewTests", "DailyHub-iPad-light-unfinished", "snapshotUnfinishedIPadLight"),
            # 02b-rank: NO iPad-13 DailyRank snapshot baseline exists (#989
            # only rendered iPhone + Mac fixtures) — reuse the SAME iPhone
            # "populatedFull" baseline (786×1704, #983's 10-row marketing
            # fixture — see DailyRankViewTests.swift) here. `Slot.baseline()`
            # resolves purely from suite_dir/named/prefix, independent of
            # which device key this entry sits under, so pointing it at the
            # iPhone file is a supported, not a hacked-in, path. This slot
            # renders `crop_all_sides=True` at capped (never-upscale-past-1:1)
            # scale (see IOS_GAP_TRIM below), so unlike every OTHER iPhone
            # slot's width-fill upscale, this one does NOT get blown up
            # further for the wider iPad-13 canvas — it just centers smaller.
            Slot("02b-rank", "DailyRankViewTests", "DailyRankView-iPhone-light-populatedFull",
                 "snapshotPopulatedFullIPhoneLight"),
            Slot("03-board", "BoardViewPencilNotesTests", "Board-iPad-light-pencilNotesWithError",
                 "snapshotPencilNotesWithError_iPad_light"),
            Slot("04-completion", "CompletionViewTests", "Completion-iPad-light-loaded",
                 "snapshot_authenticatedLoaded_iPadLight"),
            Slot("05-settings", "SettingsViewTests", "SettingsView-fullpage-iPad-light-purchased",
                 "snapshot_iPad_light_purchased"),
        ],
        "minesweeper": [
            Slot("01-home", "MinesweeperHomeSnapshotTests", "Home-iPad-light-regular", "snapshotHome_iPad_light"),
            Slot("02-daily", "MinesweeperDailyHubSnapshotTests", "Daily-iPad-light-streak2",
                 "snapshotDaily_iPad_light_streak"),
            # 02b-rank — see the Sudoku ipad-13 comment above.
            Slot("02b-rank", "DailyRankViewTests", "DailyRankView-iPhone-light-populatedFull",
                 "snapshotPopulatedFullIPhoneLight"),
            Slot("03-board", "MinesweeperBoardSnapshotTests", "Board-iPad-light-beginner-covered",
                 "snapshotBeginnerCovered_iPad_light"),
            Slot("04-completion", "MinesweeperCompletionSnapshotTests", "Completion-iPad-light-win-loaded",
                 "snapshotWinLoaded_iPad_light"),
        ],
    },
    # macOS APP_DESKTOP arm (#984). Slot NAMES intentionally reuse the iOS
    # slot names ("01-home", "03-board", "05-settings") wherever the same
    # copy applies — COPY/CALLOUTS lookup is keyed by (app, slot.name), so
    # reusing the name is what makes the mac frame automatically inherit the
    # already-authored/translated iOS copy with zero duplication, rather
    # than a separate mac-specific copy table. "06-stats" (Minesweeper) has
    # no iOS counterpart, hence the new slot name + new COPY entry above.
    # Deliberately a plain dict keyed by slot name, same shape as the iOS
    # device entries above, so a possible future 4th slot (Game Center
    # leaderboards, under discussion) is a one-line addition, not a new code
    # path.
    "mac": {
        "sudoku": [
            Slot("03-board", "BoardViewTests", "Board-Mac-light-inProgress", "snapshotInProgress_Mac_light"),
            Slot("01-home", "HomeViewTests", "HomeView-Mac-light-resume", "snapshotMacLightWithResume"),
            # 02b-rank — see the iPhone-6.9 "02b-rank" comment above; Mac has
            # its own native DailyRank baseline (#989), no reuse needed here.
            Slot("02b-rank", "DailyRankViewTests", "DailyRankView-Mac-light-populatedFull",
                 "snapshotPopulatedFullMacLight"),
            Slot("05-settings", "SettingsViewTests", "SettingsView-fullpage-mac-light-purchased",
                 "snapshot_mac_light_purchased"),
        ],
        "minesweeper": [
            Slot("03-board", "MinesweeperBoardRevealedSnapshotTests", "Board-Mac-light-beginner-flagged",
                 "snapshotFlagged_Mac_light"),
            Slot("01-home", "MinesweeperHomeSnapshotTests", "Home-mac-light-regular", "snapshotHome_regular_light"),
            # 02b-rank — see above.
            Slot("02b-rank", "DailyRankViewTests", "DailyRankView-Mac-light-populatedFull",
                 "snapshotPopulatedFullMacLight"),
            Slot("06-stats", "MinesweeperStatsTests", "Stats-mac-light", "snapshotMacLight"),
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
    on a transparent canvas (content ends where alpha drops to ~0)."""
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


def _content_flags(rgba: Image.Image, bg_color: tuple[int, int, int], axis: str,
                    tolerance: int, step: int) -> list[tuple[int, bool]]:
    """Per-column (`axis="x"`) or per-row (`axis="y"`) list of
    `(position, has_any_content_pixel)` — the same any-non-bg/non-transparent
    pixel test `detect_content_bottom()` uses, sampled every `step` pixels on
    both scan axes."""
    w, h = rgba.size
    px = rgba.load()
    br, bg_g, bb = bg_color

    def is_content(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 40 and (abs(r - br) + abs(g - bg_g) + abs(b - bb)) > tolerance

    flags: list[tuple[int, bool]] = []
    if axis == "x":
        for x in range(0, w, step):
            flags.append((x, any(is_content(x, y) for y in range(0, h, step))))
    else:
        for y in range(0, h, step):
            flags.append((y, any(is_content(x, y) for x in range(0, w, step))))
    return flags


def _axis_bounds(flags: list[tuple[int, bool]], step: int,
                  gap_threshold: Optional[int] = None) -> tuple[Optional[int], Optional[int]]:
    """First/last content position from a `_content_flags()` list.

    `gap_threshold=None` (default): plain min/max over every position that
    has any content — the direct horizontal-axis extension of
    `detect_content_bottom()`'s own "any pixel" test, nothing fancier.

    `gap_threshold=<pixels>`: stop the scan at the first run of background
    at least that wide found AFTER the first content position, instead of
    following content all the way to the far edge. Opt-in only — see the
    `MAC_GAP_TRIM` comment below for why this can't be a global default.
    """
    positions_with_content = [p for p, has in flags if has]
    if not positions_with_content:
        return None, None
    if gap_threshold is None:
        return positions_with_content[0], positions_with_content[-1] + step

    start_index = next(i for i, (_, has) in enumerate(flags) if has)
    last_content_pos = flags[start_index][0]
    background_run = 0
    for pos, has in flags[start_index:]:
        if has:
            last_content_pos = pos
            background_run = 0
        else:
            background_run += step
            if background_run >= gap_threshold:
                break
    return flags[start_index][0], last_content_pos + step


def detect_content_bbox(img: Image.Image, bg_color: tuple[int, int, int], tolerance: int = 12,
                         step: int = 3, x_gap_threshold: Optional[int] = None,
                         y_gap_threshold: Optional[int] = None) -> tuple[int, int, int, int]:
    """Content bounding box on ALL FOUR sides — `detect_content_bottom()`'s
    "any non-bg, non-transparent pixel" test extended to the horizontal
    axis too (#984), returning `(left, top, right, bottom)` in source
    pixel space.

    Plain min/max (the default, `x_gap_threshold=y_gap_threshold=None`) is
    enough for a single content block near the canvas's own edges — a
    completion card floating with dead margin on every side (#984), or the
    macOS Home/Settings/Stats baselines below, which already span nearly
    their own full width. It is NOT enough for the macOS Board baseline
    (#982/#984): that bake's square 9×9 grid ends with a real ~56px gap, but
    a header/Reveal-button sliver sits further right (individual UI runs of
    12-240px within an otherwise-empty ~600px band) — plain min/max follows
    that sliver to the far edge, leaving the dead band BETWEEN grid and
    sliver inside the crop (the "hole in the frame" that slot was flagged
    for). `x_gap_threshold`/`y_gap_threshold` fix that by cutting at the
    first sufficiently-wide background gap instead of the last content
    found anywhere.

    This can't be a global default: Sudoku/MS Home's two-column list layout
    has genuine 350-500px gaps between its OWN left/right content columns
    that must NOT be cut (verified — the MS macOS Board's dead-zone-boundary
    gap that DOES need cutting is only ~56px, i.e. *smaller* than the gap
    a correct crop must tolerate elsewhere; gap size alone can't tell the
    two apart, so this is opt-in per slot, not a default — see
    `MAC_GAP_TRIM`).
    """
    rgba = img if img.mode == "RGBA" else img.convert("RGBA")
    w, h = rgba.size
    x_flags = _content_flags(rgba, bg_color, "x", tolerance, step)
    y_flags = _content_flags(rgba, bg_color, "y", tolerance, step)
    left, right = _axis_bounds(x_flags, step, x_gap_threshold)
    top, bottom = _axis_bounds(y_flags, step, y_gap_threshold)
    if left is None or top is None:
        return 0, 0, w, h
    return left, top, min(right, w), min(bottom, h)


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


def grapheme_clusters(s: str) -> list[str]:
    """Split a string into user-perceptible clusters — a base code point
    plus any trailing Unicode combining marks (category Mn/Mc/Me) that
    attach to it — instead of raw code points. Thai vowel/tone signs (MAI
    HAN-AKAT, SARA U, SARA II, MAI EK, ...) are combining marks: iterating
    `for ch in s` directly can break a line right before one, leaving a
    bare diacritic floating over nothing on the next line.

    Uses `unicodedata.category()`, NOT `unicodedata.combining()` — Thai is
    a visual-order script, so Unicode assigns most of its vowel/tone marks
    combining CLASS 0 (verified: of the 8 Mn marks in a real shipped Thai
    callout label, only 3 have combining() != 0; category() catches all 8).
    `combining()` is the wrong test for this script and silently reproduces
    the exact bug this function exists to fix. Hangul is precomposed and
    CJK carries no combining marks, so both pass through unchanged either
    way."""
    clusters: list[str] = []
    for ch in s:
        if clusters and unicodedata.category(ch) in ("Mn", "Mc", "Me"):
            clusters[-1] += ch
        else:
            clusters.append(ch)
    return clusters


# Closing/trailing punctuation that must never START a wrapped line (kinsoku
# shori) — CJK full-width terminators/brackets plus their common Latin
# counterparts. A line consisting SOLELY of one of these (e.g. an orphaned
# 「。」 pushed onto its own line by a width-driven wrap) has near-zero ink
# height, which throws off ink-bbox-based line-height math elsewhere.
_KINSOKU_LEADING_FORBIDDEN = "。、．，！？…」』）】》〉!?,.;:"


def _apply_kinsoku(lines: list[str]) -> list[str]:
    """Post-process a greedily-wrapped line list so no line starts with
    closing punctuation: pull the offending leading character(s) back onto
    the previous line, letting that line overflow max_width by the
    punctuation's own (narrow) advance rather than orphan it onto a line by
    itself. Standard kinsoku shori line-start rule."""
    i = 1
    while i < len(lines):
        while lines[i] and lines[i][0] in _KINSOKU_LEADING_FORBIDDEN:
            lines[i - 1] += lines[i][0]
            lines[i] = lines[i][1:]
        if not lines[i]:
            del lines[i]
            continue
        i += 1
    return lines


def draw_callout_chip(
    canvas: Image.Image,
    anchor_xy: tuple[int, int],
    label: str,
    locale: str,
    accent_color: tuple[int, int, int],
    asc_w: int,
    chip_xy: Optional[tuple[int, int]] = None,
    max_width: Optional[int] = None,
    slot_name: str = "",
) -> None:
    """One Direction-B feature callout: a small dot at the anchor (the actual
    UI feature being called out), a leader line, and a rounded pill chip
    carrying the (per-locale) label.

    `chip_xy`, when given, is the chip's own target position (verified empty
    canvas — grid geometry measured directly off the baseline, not guessed)
    and the leader line is drawn straight from the anchor dot to the
    chip instead of assuming "chip sits directly below the dot". When
    omitted, falls back to the original below-anchor default (chip centered
    under the dot, dropped by a fixed offset) for callouts that already have
    clear space directly beneath their anchor.

    `max_width`, when given, caps the chip's own pixel width (independent of
    the canvas-edge margin clamp below). Some placements are squeezed into a
    space narrower than the canvas margins allow — MS iPad Board's chip sits
    in the control column beside the grid, not against the canvas edge — so
    the generic margin clamp alone doesn't stop a long translated label from
    spilling sideways onto the grid. Found via a fullness audit
    (feat/store-screenshots-cb) that swapped in fuller baselines and, per that
    task's own instruction to re-verify geometry per locale rather than just
    `en`, caught ja/es/th labels overlapping the MS iPad board grid — `en`'s
    label was short enough to fit by accident. When the single-line label
    would exceed `max_width`, it wraps onto a second line instead."""
    draw = ImageDraw.Draw(canvas, "RGBA")
    ax, ay = anchor_xy

    dot_r = max(6, int(asc_w * 0.007))
    draw.ellipse((ax - dot_r, ay - dot_r, ax + dot_r, ay + dot_r),
                 fill=(255, 255, 255, 255), outline=accent_color, width=3)

    chip_font = font_for(locale, int(asc_w * 0.030), bold=True)
    tmp = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    pad_x, pad_y = int(asc_w * 0.026), int(asc_w * 0.016)

    def measure(s: str) -> tuple[int, int, int]:
        b = tmp.textbbox((0, 0), s, font=chip_font)
        return b[2] - b[0], b[3] - b[1], b[1]

    text_w, text_h, top_bearing = measure(label)
    lines = [label]
    if max_width is not None and text_w + pad_x * 2 > max_width:
        max_line_w = max_width - pad_x * 2
        # Word-split first (Latin/Hangul), falling back to a character split
        # for any "word" that alone exceeds max_line_w — CJK and Thai carry
        # no spaces at all, so for them the whole label is one "word" and
        # this fallback is the ONLY thing that wraps it (verified: a
        # space-only splitter left ja/th completely unwrapped, still
        # overflowing max_width, since `label.split()` never breaks them).
        lines, current = [], ""
        for word in label.split():
            test = (current + " " + word).strip()
            if measure(test)[0] <= max_line_w:
                current = test
                continue
            if current:
                lines.append(current)
                current = ""
            if measure(word)[0] <= max_line_w:
                current = word
            else:
                for ch in grapheme_clusters(word):
                    test = current + ch
                    if measure(test)[0] <= max_line_w or not current:
                        current = test
                    else:
                        lines.append(current)
                        current = ch
        if current:
            lines.append(current)
        lines = lines or [label]  # degenerate empty-label case: keep the
        # pre-existing fallback rather than let max() below crash on [].
        if len(lines) > 2:
            # A third line means the chip is too narrow for this locale's
            # text and needs a wider slot, not more wrapping — silently
            # dropping the tail would ship truncated user-visible copy with
            # every automated check still green (exactly how this pipeline's
            # earlier chip-overlap defects slipped through). Fail loudly
            # instead so the next locale/copy change that overflows here
            # gets caught at generation time, not by someone eyeballing a
            # screenshot after the fact.
            raise ValueError(
                f"callout chip label wraps to {len(lines)} lines (max 2) — "
                f"slot={slot_name!r} locale={locale!r} label={label!r}; "
                f"widen chip_max_w or shorten the translation"
            )
        text_w = max(measure(line)[0] for line in lines)
        _, text_h, top_bearing = measure(lines[0])

    line_gap = int(text_h * 0.35)
    chip_w = text_w + pad_x * 2
    chip_h = text_h * len(lines) + line_gap * (len(lines) - 1) + pad_y * 2

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
        radius=chip_h // len(lines) // 2 if len(lines) > 1 else chip_h // 2,
        fill=(*accent_color, 240)
    )
    ty = chip_y + pad_y - top_bearing
    for line in lines:
        line_w = measure(line)[0]
        tx = chip_x + (chip_w - line_w) // 2
        draw.text((tx, ty), line, font=chip_font, fill=(255, 255, 255, 255))
        ty += text_h + line_gap


# Slots needing the `y_gap_threshold` opt-in on `detect_content_bbox()` when
# rendering in `crop_all_sides` mode — mirrors `MAC_GAP_TRIM` below, same
# rationale (see that function's docstring): a plain min/max bbox follows
# content all the way to the last non-background pixel found ANYWHERE, which
# for the Daily Rank "populatedFull" fixture (#983, 10 rows — see
# DailyRankViewTests.swift) is the persistent "Open Game Center" pill pinned
# near the canvas bottom — that drags the crop across the dead gap between
# the last rank row and the pill instead of stopping right after the list.
# `y_gap_threshold=100` (verified against both apps' iPhone AND Mac
# "populatedFull" baselines via `detect_content_bbox`: 100 and 150 give the
# identical trimmed bbox, comfortably past the ~40px inter-row spacing and
# well short of the dead gap before the pill, so it can't accidentally cut
# mid-list) trims the crop to the tab bar + toggle + all 10 rows, excluding
# only the empty middle and the button below it.
IOS_GAP_TRIM = {
    ("sudoku", "02b-rank"): {"y_gap_threshold": 100},
    ("minesweeper", "02b-rank"): {"y_gap_threshold": 100},
}


def build_asc_image(baseline_path: Path,
                    headline: str,
                    subhead: str,
                    app: str,
                    locale: str,
                    asc_w: int = ASC_W,
                    asc_h: int = ASC_H,
                    callouts: Optional[list[dict]] = None,
                    device: str = "iphone-6.9",
                    slot_name: str = "",
                    crop_all_sides: bool = False) -> Image.Image:
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
        content-bearing region first so the bleed cuts into content,
        never a large flat area of the screenshot's own dead space.
      - Direction B: callout chips + leader lines anchored to specific UI,
        positioned in normalized screen-fraction coordinates (CALLOUTS above)
        — `chip_at` optionally repositions the CHIP itself away from the
        anchor when the default below-anchor drop would land on content.

    `crop_all_sides` (#984, "04-completion" ONLY — every other slot must stay
    byte-identical to before): use `detect_content_bbox()` (all 4 sides)
    instead of `detect_content_bottom()` (bottom only), capping the fit
    scale at 1.0 (never upscale) and centering the resulting — possibly
    much smaller than `screen_w` — content horizontally in the screen band
    instead of stretching it to fill the width. Corners round on all 4
    sides (the content no longer necessarily bleeds off the canvas bottom)
    instead of just the top. Callout anchors for this mode are computed
    from the actual rendered position/size, not a baseline-fraction lookup
    (see the loop below) — a fixed fx/fy anchor would be wrong as soon as
    crop+scale+center moves the content around.
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
                for ch in grapheme_clusters(word):
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
    # Bleeding the FULL baseline (device-height) screenshot let the
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
    # #985: margin trimmed 0.045→0.030 (screen_w grows ~3.3%, so the
    # width-fill scale below is proportionally bigger for every slot —
    # more of the canvas is real app panel, less is decorative side
    # gutter) and the subhead→panel gap trimmed 0.055→0.035 (this constant
    # was the single biggest source of the panel's "floating in empty
    # space" read; both apply uniformly to every slot so the panel starts
    # at a small, CONSISTENT offset below the copy block rather than
    # varying with each slot's own headline/subhead line count).
    SCREEN_MARGIN = int(asc_w * 0.030)
    SCREEN_TOP = ty + int(asc_h * 0.035)
    screen_w = asc_w - SCREEN_MARGIN * 2

    CONTENT_PAD_FRAC = 0.03  # breathing room below the last content row

    src_full = Image.open(baseline_path).convert("RGBA")
    src_w, src_h_full = src_full.size
    scale = screen_w / src_w

    corner_radius = int(asc_w * 0.045)

    if crop_all_sides:
        # #984 — see the docstring above. All 4 sides, capped scale, centered.
        # `IOS_GAP_TRIM` opt-in (#995, "02b-rank" only — see that dict's own
        # comment): every other crop_all_sides slot keeps the plain min/max
        # bbox (gap_cfg == {} -> both thresholds None, same call as before).
        gap_cfg = IOS_GAP_TRIM.get((app, slot_name), {})
        left, top, right, bottom = detect_content_bbox(
            src_full, bg_color,
            x_gap_threshold=gap_cfg.get("x_gap_threshold"),
            y_gap_threshold=gap_cfg.get("y_gap_threshold"),
        )
        pad = int(max(right - left, bottom - top) * CONTENT_PAD_FRAC)
        crop_box = (
            max(0, left - pad), max(0, top - pad),
            min(src_w, right + pad), min(src_h_full, bottom + pad),
        )
        content = src_full.crop(crop_box)
        content_w, content_h = content.size
        scale = min(1.0, screen_w / content_w)  # never upscale past 1:1
        fit_w = max(1, round(content_w * scale))
        fit_h = max(1, round(content_h * scale))
        src_resized = content.resize((fit_w, fit_h), Image.LANCZOS)
        bg_patch = Image.new("RGB", (fit_w, fit_h), bg_color)
        bg_patch.paste(src_resized, (0, 0), src_resized)
        mask = Image.new("L", (fit_w, fit_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, fit_w - 1, fit_h - 1), radius=corner_radius, fill=255)
        paste_x = SCREEN_MARGIN + (screen_w - fit_w) // 2  # narrower than screen_w now — center it
        # #985: top-anchor at SCREEN_TOP — the SAME small, fixed
        # gap-below-copy every other slot uses — instead of centering the
        # card in the leftover canvas below the text. That centering was
        # the actual cause of the 40-50% "gap above panel" measured on
        # this slot and "02b-rank": centering in a large `available_h`
        # (nearly the full remaining canvas) pushes a small, capped
        # (never-upscaled) card deep into the middle of the frame, then
        # leaves an even BIGGER stranded gradient band above it than the
        # bottom-bleed slots ever had. Anchoring it directly below the
        # copy block — where its own native (uncropped) size can't fill
        # 60% of the canvas without upscaling past 1:1, so it stays
        # smaller than the other slots' panels; see the module report —
        # leaves the leftover gradient below the card instead, where
        # Direction C's callout chip (04-completion) already anchors off
        # the card's own bottom edge with room to spare.
        paste_y = SCREEN_TOP
    else:
        content_bottom_px = detect_content_bottom(src_full, bg_color)
        crop_h = min(src_h_full, content_bottom_px + int(src_h_full * CONTENT_PAD_FRAC))

        fit_w, fit_h = screen_w, int(crop_h * scale)
        src_resized = src_full.crop((0, 0, src_w, crop_h)).resize((fit_w, fit_h), Image.LANCZOS)
        bg_patch = Image.new("RGB", (fit_w, fit_h), bg_color)
        bg_patch.paste(src_resized, (0, 0), src_resized)
        mask = rounded_top_mask((fit_w, fit_h), corner_radius)
        paste_x = SCREEN_MARGIN
        paste_y = SCREEN_TOP

    canvas.paste(bg_patch, (paste_x, paste_y), mask)

    # ── Direction B: feature-callout chips (Board / Completion only) ──────
    #
    # fx/fy are fractions of the ORIGINAL (uncropped) baseline — that's the
    # stable reference frame regardless of how much the block above zoomed
    # in, and X is unaffected by the (vertical-only) crop, so this maps
    # correctly whether or not this slot needed any zoom. `crop_all_sides`
    # slots have no `anchor` entry (dead once cropping moves the content) —
    # anchor to the rendered card's own bottom-center instead.
    if callouts:
        for callout in callouts:
            label = callout.get(locale) or callout["en"]
            if crop_all_sides:
                anchor_xy = (paste_x + fit_w // 2, paste_y + fit_h)
            else:
                fx, fy = callout["anchor"][device]
                anchor_xy = (SCREEN_MARGIN + int(fx * screen_w), SCREEN_TOP + int(fy * src_h_full * scale))
            chip_target = callout.get("chip_at", {}).get(device)
            chip_xy = None
            if chip_target:
                cfx, cfy = chip_target
                chip_xy = (SCREEN_MARGIN + int(cfx * screen_w), SCREEN_TOP + int(cfy * src_h_full * scale))
            chip_max_w_frac = callout.get("chip_max_w", {}).get(device)
            max_width = int(chip_max_w_frac * asc_w) if chip_max_w_frac else None
            draw_callout_chip(canvas, anchor_xy, label, locale, accent_color, asc_w,
                               chip_xy=chip_xy, max_width=max_width, slot_name=slot_name)

    # ── Final sanity: canvas must be RGB (no alpha) ───────────────────────────
    assert canvas.mode == "RGB", f"Expected RGB, got {canvas.mode}"
    assert canvas.size == (asc_w, asc_h), f"Expected {asc_w}×{asc_h}, got {canvas.size}"

    return canvas


# ── macOS APP_DESKTOP layout (#984) — copy left / app-window right ──────────
#
# A DIFFERENT layout from Direction C above, not a scaled variant of it: the
# 2880×1800 16:10 canvas is too wide/short for a bottom-bleeding portrait
# device screenshot to read as anything but a sliver. Instead: brand
# gradient fills the canvas, the app window (given Mac chrome — rounded
# corners + traffic-light dots, since the baselines carry none of their
# own) sits vertically centered on the right with the FULL window visible
# (never bled off the canvas edge — on a landscape Mac window that reads as
# a cropping mistake, unlike the deliberate portrait bleed on iPhone/iPad),
# headline/subhead sit vertically centered on the left, width-constrained
# to the gap between the left margin and the window (computed from the
# window's OWN rect, which varies per slot) so translated text can never
# run under the art.
MAC_WINDOW_MAX_W = 1580     # starting point from the approved prototype
MAC_RIGHT_MARGIN = 90
MAC_LEFT_MARGIN = 180
MAC_GUTTER = 80              # min gap between the copy column and the window
MAC_TITLEBAR_H = 64
MAC_CHROME_RADIUS = 28
MAC_CONTENT_PAD_FRAC = 0.02  # breathing room on all 4 sides inside the chrome

# Slots needing the `x_gap_threshold`/`y_gap_threshold` opt-in on
# `detect_content_bbox()` — see that function's docstring for why this is
# per-slot, not a global default. Currently only the MS macOS Board's
# header/Reveal-button sliver (#982/#984).
MAC_GAP_TRIM = {
    ("minesweeper", "03-board"): {"x_gap_threshold": 45},
    # 02b-rank (#995): same dead-middle-gap fix as IOS_GAP_TRIM above, same
    # threshold — the Mac "populatedFull" DailyRank baseline has an identical
    # tab-bar+toggle+10-rows-then-gap-then-"Open Game Center"-pill shape as
    # the iPhone one, verified independently via `detect_content_bbox` against
    # the Mac baseline (100 and 150 both give the same trimmed bbox).
    ("sudoku", "02b-rank"): {"y_gap_threshold": 100},
    ("minesweeper", "02b-rank"): {"y_gap_threshold": 100},
}


def _mac_wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int,
                    tmp_draw: ImageDraw.ImageDraw) -> list[str]:
    """Word-wrap (falling back to a grapheme-cluster split for CJK/Thai,
    which carry no spaces) at `max_width` — the same algorithm as
    `build_asc_image()`'s own nested `wrap_text`, kept as a SEPARATE
    function rather than hoisted to module scope so this new mac path
    cannot, even accidentally, change a single pixel of the existing
    iPhone/iPad output (only "04-completion" is allowed to change there,
    #984)."""
    def text_w(s: str) -> int:
        bbox = tmp_draw.textbbox((0, 0), s, font=font)
        return bbox[2] - bbox[0]

    lines, current = [], ""
    for word in text.split():
        test = (current + " " + word).strip()
        if text_w(test) <= max_width:
            current = test
            continue
        if current:
            lines.append(current)
            current = ""
        if text_w(word) <= max_width:
            current = word
        else:
            for ch in grapheme_clusters(word):
                test = current + ch
                if text_w(test) <= max_width or not current:
                    current = test
                else:
                    lines.append(current)
                    current = ch
    if current:
        lines.append(current)
    return _apply_kinsoku(lines) or [""]


def build_mac_asc_image(baseline_path: Path,
                        headline: str,
                        subhead: str,
                        app: str,
                        locale: str,
                        asc_w: int,
                        asc_h: int,
                        slot_name: str = "") -> Image.Image:
    """Compose one macOS APP_DESKTOP ASC-spec RGB PNG — see the
    `MAC_WINDOW_MAX_W` module comment above for the layout. No Direction-B
    callout chips on this arm (not requested for mac; the copy-left/
    window-right layout has no single anchored UI element the way the
    full-bleed portrait frames do)."""
    bg_color, accent_color, accent_deep, accent_muted = make_frame(app)

    canvas = Image.new("RGB", (asc_w, asc_h), accent_color)
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Full-bleed vertical gradient over the WHOLE canvas — unlike Direction
    # C's iPhone/iPad frames, nothing bleeds off the bottom edge here, so
    # there's no fixed point where the gradient needs to hand off to a
    # screenshot; it simply covers top to bottom.
    for y in range(asc_h):
        t = y / asc_h
        r, g, b = blend(accent_deep, accent_color, t)
        draw.line([(0, y), (asc_w, y)], fill=(r, g, b))

    # ── App window art (right, vertically centered, full window visible) ──
    src_full = Image.open(baseline_path).convert("RGBA")
    src_w, src_h = src_full.size
    gap_cfg = MAC_GAP_TRIM.get((app, slot_name), {})
    left, top, right, bottom = detect_content_bbox(
        src_full, bg_color,
        x_gap_threshold=gap_cfg.get("x_gap_threshold"),
        y_gap_threshold=gap_cfg.get("y_gap_threshold"),
    )
    pad = int(max(right - left, bottom - top) * MAC_CONTENT_PAD_FRAC)
    crop_box = (
        max(0, left - pad), max(0, top - pad),
        min(src_w, right + pad), min(src_h, bottom + pad),
    )
    content = src_full.crop(crop_box)
    content_w, content_h = content.size

    scale = min(1.0, MAC_WINDOW_MAX_W / content_w)  # never upscale past 1:1
    win_content_w = max(1, round(content_w * scale))
    win_content_h = max(1, round(content_h * scale))
    content_resized = content.resize((win_content_w, win_content_h), Image.LANCZOS)

    window_w = win_content_w
    window_h = MAC_TITLEBAR_H + win_content_h
    window_img = Image.new("RGB", (window_w, window_h), bg_color)
    wdraw = ImageDraw.Draw(window_img)
    wdraw.rectangle((0, 0, window_w, MAC_TITLEBAR_H), fill=(0xE3, 0xE3, 0xE6))
    dot_r = 11
    dot_cy = MAC_TITLEBAR_H // 2
    for i, dot_color in enumerate([(0xFF, 0x5F, 0x57), (0xFF, 0xBD, 0x2E), (0x28, 0xC8, 0x40)]):
        cx = 24 + i * 28
        wdraw.ellipse((cx - dot_r, dot_cy - dot_r, cx + dot_r, dot_cy + dot_r), fill=dot_color)
    content_patch = Image.new("RGB", (win_content_w, win_content_h), bg_color)
    content_patch.paste(content_resized, (0, 0), content_resized)
    window_img.paste(content_patch, (0, MAC_TITLEBAR_H))

    window_mask = Image.new("L", (window_w, window_h), 0)
    ImageDraw.Draw(window_mask).rounded_rectangle(
        (0, 0, window_w - 1, window_h - 1), radius=MAC_CHROME_RADIUS, fill=255
    )

    window_x = asc_w - MAC_RIGHT_MARGIN - window_w
    window_y = (asc_h - window_h) // 2
    canvas.paste(window_img, (window_x, window_y), window_mask)

    # ── Icon badge (top-left, shelf recognition — same brand language as
    #    the iPhone/iPad frames) ─────────────────────────────────────────
    badge_margin = int(asc_w * 0.035)
    badge_size = int(asc_w * 0.045)
    paste_icon_badge(canvas, app, asc_w, badge_margin, badge_size)

    # ── Copy column (left) — width-constrained to the gap between the left
    #    margin and this SLOT's own window rect (window width varies per
    #    slot, #984), so translated text can never run under the art. ─────
    copy_right = window_x - MAC_GUTTER
    copy_width = max(200, copy_right - MAC_LEFT_MARGIN)

    font_headline = font_for(locale, int(asc_w * 0.044), bold=True)
    font_subhead = font_for(locale, int(asc_w * 0.020), bold=False)
    tmp_draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    headline_lines = _mac_wrap_text(headline, font_headline, copy_width, tmp_draw)
    subhead_lines = _mac_wrap_text(subhead, font_subhead, copy_width, tmp_draw)

    def line_h(font: ImageFont.FreeTypeFont) -> int:
        # Fixed per-font metric (ascent + descent), NOT a per-line ink bbox —
        # a line whose only glyph is closing punctuation (e.g. an orphaned
        # 「。」) has near-zero ink height, and stacking by ink height let
        # such a line collapse into the next line's baseline, overlapping
        # its first glyph. Metrics-based height is constant regardless of
        # which characters happen to be on the line, so the block still
        # advances by a full line each time.
        ascent, descent = font.getmetrics()
        return ascent + descent

    headline_line_h = line_h(font_headline)
    subhead_line_h = line_h(font_subhead)

    line_gap_h = int(asc_h * 0.010)
    line_gap_s = int(asc_h * 0.008)
    block_gap = int(asc_h * 0.022)

    text_block_h = (
        headline_line_h * len(headline_lines)
        + line_gap_h * (len(headline_lines) - 1)
        + block_gap
        + subhead_line_h * len(subhead_lines)
        + line_gap_s * (len(subhead_lines) - 1)
    )
    ty = (asc_h - text_block_h) // 2

    for line in headline_lines:
        draw.text((MAC_LEFT_MARGIN, ty), line, font=font_headline, fill=(255, 255, 255, 255))
        ty += headline_line_h + line_gap_h
    ty += block_gap - line_gap_h
    for line in subhead_lines:
        draw.text((MAC_LEFT_MARGIN, ty), line, font=font_subhead, fill=(255, 255, 255, 217))
        ty += subhead_line_h + line_gap_s

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
                    if locale != "en" and (app, slot.name) in PENDING_TRANSLATION_SLOTS:
                        results.append({
                            "device": device, "app": app, "slot": slot.name,
                            "locale": locale, "status": "SKIPPED-PENDING-TRANSLATION", "path": None,
                        })
                        continue

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
                        if device == "mac":
                            img = build_mac_asc_image(
                                baseline_path, headline, subhead, app, locale,
                                asc_w=dev["w"], asc_h=dev["h"],
                                slot_name=slot.name,
                            )
                        else:
                            img = build_asc_image(
                                baseline_path, headline, subhead, app, locale,
                                asc_w=dev["w"], asc_h=dev["h"],
                                callouts=slot_callouts, device=device,
                                slot_name=slot.name,
                                # #984: 04-completion was the first slot allowed
                                # to render differently — every OTHER slot that
                                # existed at the time must stay byte-identical to
                                # what's already uploaded. "02b-rank" (#983) is a
                                # brand-new slot with nothing already uploaded to
                                # stay identical to, so adding it here is safe;
                                # it needs the same tight all-sides crop to avoid
                                # shipping the populated baseline's own dead
                                # middle gap (see IOS_GAP_TRIM above).
                                crop_all_sides=(slot.name in {"04-completion", "02b-rank"}),
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
