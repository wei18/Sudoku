# v3(3.0)設計 — 落地說明

本目錄是 Sudoku + Minesweeper 3.0 重設計的 **canonical** 規格。`design.md` 是唯一需要讀的文件
（不需回頭讀 scratchpad 的 v3.1 / v3.2 / v3.2.1 草稿），`prototype.html` 是對應的全畫面 prototype。

## 版本敘事

3.0 經過四輪修訂才定稿,每輪都是對前一輪 owner 回饋或自我審查的直接回應:

| 版本 | 做了什麼 | 為什麼要下一版 |
|---|---|---|
| **v3.1** | 結構重整:list-hub 改 3 tab;完成時刻做成安靜儀式;色彩 token 分層 | owner:「要採用 iOS 26 Liquid Glass」「感受不到遊戲類別」 |
| **v3.2** | Board-first:盤面即主角、滿版盤面 + 浮動玻璃控制;Progress 改紀錄陳列 | owner 認可方向,但自我審查發現一批未解疑慮與錯誤 |
| **v3.2.1** | Liquid Glass 從內容層搬到功能層(補 Increased Contrast 色彩層;玻璃逐片清算) | owner:要看完整設計,進開發前 sign-off |
| **v3.3(本版,r2)** | 合併成一份完整設計 + 全畫面 prototype,經 3 位 reviewer 審查 + owner sign-off | — 定稿,落 repo |

## Artifact 預覽

各版本當時發布的可互動預覽(歷史紀錄,非 canonical):

- v3.1 — https://claude.ai/code/artifact/7059753b-121c-49bd-a4af-1c2e145b7961
- v3.2 — https://claude.ai/code/artifact/acea73c6-2c8d-421d-a733-6d8c8bb69914
- v3.2.1 — https://claude.ai/code/artifact/f700d923-9795-4eee-a22c-0b5b9a05ce03
- v3.3(本版) — https://claude.ai/code/artifact/609232ef-89e5-441f-97a6-6311f37ff41b

## 審查紀錄

定稿前經過 3 位獨立 reviewer(consistency / HIG / engineering 三個角度)審查,
共提出 5 個 BLOCKER + 8 個 MAJOR 發現,**全數修復**後才進入 owner sign-off。

過程中作者自己也留下了一份錯誤更正紀錄 —— `design.md` §12〈已知錯誤更正紀錄〉,
15 條,每條都附「錯誤 / 更正 / 教訓」。**這份紀錄刻意保留在定稿裡**,不是草稿殘留:
它們曾經影響過設計敘事(例如 §12 #6/#10 的契約條數誤算、#8 的
`GlassEffectContainer` 用法寫反、#14/#15 是驗證腳本自己抓到的),讀者有權知道。

## 驗證

`design.md` §5 的六十多個色彩 token 數值、§9 的行為契約變更總表,靠兩支落 repo 的腳本
自動複驗,不靠人工核對:

- `scripts/design/contrast.py` — WCAG 對比度門檻(含 Increased Contrast 變體、ramp 相鄰間距)
- `scripts/design/contracts.py` — 變更表格的 C-x / N-x 條目是否都能錨定到
  `docs/screen-contracts.md` / `docs/navigation-flows.md` 裡實際存在的段落

兩支腳本的實跑輸出(含 `RESULT: PASS` 行)貼在 `design.md` **附錄 A〈驗證腳本輸出〉**,
與本次落地時的實際輸出一致(附錄 B 是對比度/契約條數的計算與查證方法說明)。
之後任一腳本的輸出改變,就代表 token 表或契約總表已經偏離 canonical,應視為需要更新
設計文件或修 bug,而不是改腳本讓它通過。

## 開發入口

不要從頭讀設計史。子 session 開發任何一張畫面,先讀:

1. `design.md` §11〈給開發的分期建議〉—— 找到自己要做的階段（階段 0 現在就能做、
   階段 1 等 B-4 spike、階段 2 等驗證、階段 3 獨立 PR),以及每個階段的前置依賴。
2. 該階段條目對應的 §2–§8 規格小節 + `prototype.html` 裡的對應畫面框。
3. §9 的 C-x / N-x 條目,確認自己要動的畫面在 canonical 契約文件裡的錨點。

`docs/screen-contracts.md`、`docs/navigation-flows.md` 本身**不在本次落地範圍內** ——
它們隨各階段實作逐步改,不隨設計文件一次到位。
