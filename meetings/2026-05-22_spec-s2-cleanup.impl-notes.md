# Spec S2 cleanup — impl notes

Date: 2026-05-22
Branch: `docs/spec-s2-cleanup`
Closes: #79 (S2 Medium doc-drift findings)
Source audit: `meetings/2026-05-21_spec-drift-audit.impl-notes.md`

Scope: code-only doc edits across `docs/design.md`, `docs/v2/design.md`,
`docs/privacy-policy.md`. No `Packages/` touched. Leader handles
git/commit/push/merge per AI Collaboration Mode.

---

## S2-1 — `docs/design.md` Lottie bullet (L1496)

**Before**

> 注意：此為**第一個第三方 dep**，會打破 v1「Apple-only stack」紀律 — 加入前
> 需在 foundations.md §3 補充「為什麼破例」的決策紀錄（2026-05-20）。

**After**

> 注意：AdMob 已於 v2.0 起為第一個第三方 SDK；若引入 Lottie 將為**第二個**
> 第三方 dep，仍會擴大破例範圍 — 加入前需按 `foundations.md §9` §9.2 程序
> 補充「為什麼再次破例」的決策紀錄（2026-05-20）。

Pointer corrected `§3 → §9` and ordinal corrected `第一個 → 第二個`.

---

## S2-2 — `docs/design.md` v1 success criterion (L40)

**Before**

> 除了 CloudKit + Game Center + Xcode Cloud + App Store Connect Analytics +
> MetricKit 之外，**我方不維運任何後端服務、不引第三方 SDK**。

**After**

> 除了 CloudKit + Game Center + Xcode Cloud + App Store Connect Analytics +
> MetricKit 之外，**我方不維運任何後端服務、不引第三方 SDK**。（v2 起 AdMob
> 為受控例外，見 `foundations.md §9.1` 與 `docs/v2/design.md`；本 v1 criterion
> 仍以 v1 build 為準。）

Forward-pointer added; v1 criterion preserved.

---

## S2-3 — `docs/privacy-policy.md` §廣告 boot order

**Before** — order was IDFA → ATT → UMP (zh + en bullets).

**After** — order is IDFA → UMP → ATT, with explicit "UMP before ATT" wording
to match v2/design.md §How.4 + plan.md v2.3.7 actual boot sequence
(UMP consent → ATT prompt → AdMob init).

Edited the two relevant bullets in the bilingual block; IDFA bullet unchanged.

zh-Hant snippet (new ordering):

```
- 對歐盟 / 英國 / 加州…透過 Google 的 UMP 顯示 GDPR / CCPA consent；
  UMP 完成後才會出現 ATT prompt。
- 在 UMP 之後（或不適用 UMP 的地區，於首次啟動時）透過 Apple 的 ATT
  取得追蹤許可。若拒絕，廣告仍會顯示，但為非個人化廣告。
```

en snippet mirrors the same order with "before the ATT prompt is shown" and
"After UMP (or on first launch in regions where UMP does not apply)".

Other 5 locales (ja, zh-Hans, es, th, ko) are downstream of this zh-TW+en
source pair and will be picked up on the next L10n pass; not in scope here.

---

## S2-4 — `docs/v2/design.md` §How.7 AppComposition snippet

**Strategy chosen**: **replace** (preferred path), with a brief preamble
noting the prior intermediate state and that the final shape is grepped from
`Packages/SudokuKit/Sources/AppComposition/AppComposition.swift`.

Grepped real shape — bag carries 12 properties, not just the 5 named in
the issue summary:

```
rootViewModel, routeFactory,
puzzleProvider, persistence, gameCenter, telemetry,
adProvider, iapClient, adGate,
monetizationStateStore, monetizationController,
toastController
```

The 5 in the issue body (`rootViewModel, routeFactory, adProvider,
iapClient, adGate`) are the post-v2.3.3 *new construction signature into
`RootView.init`* concern (RootView only takes `rootViewModel` +
`routeFactory`; the rest hang on the bag for non-RouteFactory callsites).
Snippet now lists all 12 with v2.3.3 / v2.3.6 / v2.4.5 sub-version
annotations sourced from the file's leading doc comment, and `live()` /
`bootMonetization()` are reduced to signatures with `/* ... */` bodies to
keep the snippet skim-readable.

Final paragraph rewritten to state explicitly that `RootView.init` takes
only `rootViewModel` + `routeFactory`, and that escape-hatch callsites
(v2.3.7 boot, HomeView GC modal, Settings restore, banner slot) read other
deps directly from the bag.

---

## Cross-doc consistency check

| Item | Old | New | Aligned? |
| --- | --- | --- | --- |
| Lottie ordinal | 第一個 | 第二個 (AdMob is 第一個) | yes — matches `foundations.md §9.1` |
| Lottie pointer | `foundations.md §3` | `foundations.md §9 §9.2` | yes |
| v1 design.md L40 | no v2 note | "v2 起 AdMob 為受控例外" forward-pointer | yes — points to `foundations.md §9.1` + `docs/v2/design.md`, both confirmed extant |
| privacy-policy boot order | ATT → UMP | UMP → ATT | yes — matches v2/design.md §How.4 + plan.md v2.3.7 |
| v2/design §How.7 snippet | 8 deps intermediate | 12 deps final (from source file) | yes — sourced from `AppComposition.swift` head comment |

All four edits compose: L40 forward-points to `foundations.md §9.1` and
`docs/v2/design.md`; the Lottie bullet now (correctly) recognises AdMob as
the existing exception under `§9.1` and routes future SDKs through `§9.2`;
the privacy-policy bullets describe the same UMP → ATT order that v2/design
§How.4 + plan.md v2.3.7 + the `bootMonetization()` signature in §How.7's
new snippet all describe; the §How.7 snippet's `bootMonetization()` line
echoes the same sequence. No internal contradictions remain across these
four anchors.

---

## Extra drift spotted mid-edit (flagged, not fixed)

1. **`docs/v2/design.md` §How.7 §Decisions table (L307)** still phrases the
   change as "AppComposition 加 3 deps" — technically true at the diff
   level vs v1, but post-RouteFactory the diff is closer to "+1 route
   factory, +3 monetization deps, +2 v2.3.6 monetization-state deps, +1
   v2.4.5 toast". Out of scope for S2 (Decisions table is a historical
   record, not a structural claim); flag for a possible S3-tier sweep.

2. **`docs/design.md` line 1490 L10n bullet** lists v1 locales as
   "zh-TW、en、ja、zh-Hans、es、th、ko" (7). Privacy-policy.md says
   downstream locales pick up from the zh-TW+en source pair — consistent.
   No fix needed; noting for future audit symmetry.

3. **`docs/v2/design.md` §How.7 preamble paragraph above the snippet**
   (existing prose, not edited) still reads as if the bag is purely "v1 +
   3 monetization deps". Did not rewrite — the new code-fence preamble
   sentence already corrects the impression, and rewriting the upstream
   prose would expand the diff beyond S2 scope.

No other drift surfaced in the four touched files.
