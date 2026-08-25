# Sudoku + Minesweeper 3.0 — 完整設計(v3.3 定稿)

**狀態:** SIGN-OFF CANDIDATE · **日期:** 2026-08-17 · **作者:** UX Designer

**這是一份完整、自洽的設計文件。** 讀這一份就夠,不需要回頭讀 v3.1 / v3.2 / v3.2.1。
那三份仍在 scratchpad 作為歷程紀錄,但**本文為準**。

---

## 0. How we got here(一節,不展開)

| 版本 | 做了什麼 | 為什麼要下一版 |
|---|---|---|
| v3.1 | 結構重整:list-hub → 3 tab;完成時刻做成安靜儀式;色彩 token 分層 | owner:「要採用 iOS 26 Liquid Glass」「感受不到遊戲類別」 |
| v3.2 | Play-first:盤面即主角、滿版盤面 + 浮動玻璃控制;Progress 改紀錄陳列 | owner 認可,但我們自己有一批未解疑慮與錯誤 |
| v3.2.1 | 補 Increased Contrast 色彩層;玻璃逐片清算;**五條自我更正** | owner:要看完整設計,進開發前 sign-off |
| **v3.3** | **合併成一份完整設計 + 全畫面 prototype** | — |

**最重要的一次認知修正**(v3.2.1 更正 1):
現行出貨程式碼**已經有 6 處 `.glassEffect` 套在內容層卡片上** ——
`HomeScreen.swift:295`(共用 ModeCard)· `DailyHubView.swift:278` · `PracticeHubView.swift:74,153` ·
`MinesweeperDailyHubView.swift:208` · `MinesweeperPracticeHubView.swift:91,141`。

> **Don't use Liquid Glass in the content layer.** — `~/.claude/skills/hig/materials.md:28`

所以 3.0 **不是「加玻璃」也不是「拿掉玻璃」,是把玻璃從內容層搬到功能層。**
這也精準回答 owner 的「要採用 iOS 26 Liquid Glass」:**我們已經用了,只是用錯地方。**

---

## 1. 設計主張與依據等級

每條主張標三種等級之一。**這是為了讓 owner 分辨「Apple 規定的」與「我們決定的」。**

| 標記 | 意義 |
|---|---|
| **【官方】** | Apple 文件逐字支持,附出處 |
| **【常見做法】** | 業界普遍如此但查無官方規範,二手來源 |
| **【我方推論】** | 我們的設計判斷。Apple 沒這樣規定 |

**依據來源優先序:**
1. *Adopting Liquid Glass*, Technology Overviews(owner 指定,已全文讀畢)
2. 本機 HIG 語料 `~/.claude/skills/hig/*.md` + DocC JSON(Game Center / Designing for Games)
3. design-playbook(描述性,權重最低)

### 1.1 核心主張:盤面即主角 —— **【我方推論】**

**我們讀完了官方 *Designing for Games* 專章,它不含畫面結構 / 首頁 / 轉場 / 盤面 / 進度陳列的任何指引。**
所以「盤面即主角」是我們的設計判斷,不是 Apple 的要求。**不會因為研究做得多就把自己的判斷包裝成規範。**

### 1.2 遊戲感從哪裡來(在不放棄 calm 品牌的前提下)

**沒有官方證據顯示低彩度與遊戲感互斥。** 官方三個遊戲感訊號 —— collectible card、succinct animation、
consistent haptics —— 全部可在低彩度下做到。**病灶不是彩度,把品牌糖果化是錯的解法。**

| # | 病灶 | 依據等級 |
|---|---|---|
| 1 | 全 App 看不見盤面 | 【我方推論】 |
| 2 | 進度做成統計數字堆疊而非視覺陳列 | **【官方】** |
| 3 | 動作回饋沒有簡短精準的因果動畫 | **【官方】** |
| 4 | 進入遊戲沒有儀式 | 【常見做法】 |

參照對象是 **Apple Fitness 的獎章與 Photos 的回憶**,不是糖果色手遊 —— 兩者都是低彩度系統原生調性,
靠「把成果做成可收藏可回看的東西」建立儀式感。**calm 的顏色 + 收藏品的骨架。**

---

## 2. 導航模型

### 2.1 三個分頁 + 每分頁一條 path

```
ROOT (sidebarAdaptable TabView)
├── Today      path[.today]     ├─ push → SETTINGS
│                               ├─ push → .board(…)  → iOS: fullScreenCover / macOS·iPad: detail push
│                               └─ push → .completion(…)  → review 變體
├── Practice   path[.practice]  ├─ push → SETTINGS
│                               └─ push → .board(…)
└── Progress   path[.progress]  ├─ push → SETTINGS
                                └─ side-effect → GC dashboard(Achievements / Leaderboards)
```

**【官方】** 兩層模型的依據:
> **Establish a clear navigation hierarchy.** …Ensure that you clearly separate your content from navigation elements, like tab bars and sidebars, to establish a distinct functional layer above the content layer.
> — *Adopting Liquid Glass*

**【官方】** 一份 TabView 同時給 iPhone tab bar 與 iPad/macOS sidebar:
> When you use the sidebarAdaptable style of tab view to present a sidebar, you choose whether to display a sidebar or a tab bar when your app opens.
> — HIG *Sidebars*

### 2.2 Route table

| | 現況 | 3.0 |
|---|---|---|
| Sudoku | 7 條(`home`/`daily`/`practice`/`board`/`completion`/`settings`/`stats`) | **3 條**:`board` / `completion` / `settings` |
| Minesweeper | 8 條 | **5 條**:`board` / `replayDailyBoard` / `resumeBoard` / `completion` / `settings` |

`daily` / `practice` / `stats` 從 route 變成 **tab 身分**(`AppTab.today/.practice/.progress`);
`home` 本來就從不 push,直接移除。

### 2.3 Today badge:圓點,不是數字 —— **【官方】約束**

> Use a badge only to show people how many unread notifications they have. **Don't use a badge to convey numeric information that isn't related to notifications, such as … game scores.**
> — HIG *Notifications*(tab-bars 頁把 badge 指引指向此頁)

「今日未完成題數」屬進度數據,與被點名的 game scores 同類。
**定案:無數字圓點** —— 今日尚有未完成時出現,三題全完成即消失。資料來源是既有的 daily 完成狀態,不新增資料;
CK 失敗時**不顯示 badge**(不是顯示 0)。

**⚠️ 實作綁定(裁定):只准用系統 `.badge()` API,不得自繪。**
官方明文避免自繪模仿 badge 的元件;而官方 badge 形態中**並沒有「無數字圓點」這一種**。
因此本條標記從【官方】降為 **【我方推論 + 系統 API 綁定】**:

| 情況 | 處置 |
|---|---|
| 系統 `.badge()` 能呈現無數字形態 | 採用 |
| **做不到** | **整個 badge 放棄** —— 官方也說 badge 不得是唯一通道,而 Today 的內容本身就是信號 |

→ 新增 **U-12**(SwiftUI `.badge` 能否無數字),**實作前驗**。prototype 的紅點是意圖示意,
**以系統 API 呈現為準,不自繪**。

### 2.4 Banner:tab bar accessory,附降級

**【官方】** `View.tabViewBottomAccessory(content:)` + `TabViewBottomAccessoryPlacement`(`.inline` / `.expanded`),iOS/iPadOS/Mac Catalyst 26.0+。

| placement | 呈現 | 何時 |
|---|---|---|
| `.expanded` | 完整高度,浮在 tab bar 上方 | 預設 |
| `.inline` | 收合與 tab bar 同列 | 捲動最小化時 |

⚠️ **AdMob banner 是 `UIViewRepresentable`,包進 accessory 的相容性未驗證**(U-10)。
**降級備案:不相容則退回 tab 內容底部**,不阻擋任何其他設計。**變現路徑不卡在未驗證 API 上。**

#### 2.4.1 ⚠️ macOS 沒有 tab accessory —— D18 在 macOS 缺承載機制

`tabViewBottomAccessory` 只到 iOS / iPadOS / Mac Catalyst,**macOS 原生沒有**。
D18(banner 覆蓋範圍是 feature)在 macOS 因此沒有落點。**方案(擇一,列 U-13 待裁定):**

| 方案 | 說明 | 代價 |
|---|---|---|
| **A(推薦)** | macOS **不顯示 banner** —— sidebar 版面本來就沒有 tab bar 底緣可掛,且桌面 App 的橫幅廣告觀感差 | 少一個曝光位;需確認 AdMob 合約無 macOS 最低要求 |
| B | 放在 detail 欄**底緣固定列** | 佔內容高度,且與「盤面滿版」直接衝突 |
| C | 放在 sidebar 底部 | sidebar 是功能層,塞廣告違反 §4 的層歸屬 |

**推薦 A**,理由是 B 與盤面滿版衝突、C 違反層歸屬 —— 兩者都要犧牲 3.0 的核心結構。

---

## 3. 畫面規格

### 3.1 TODAY

**目的:** 一眼看到連續天數與今天還差什麼,然後一鍵開始。

| 元素 | 說明 |
|---|---|
| Streak 一列 | `12 day streak` + 7 pip + `Best 31`。**內容層普通文字,不用玻璃不用卡片**(見 §4.2) |
| Resume 卡(條件) | **standard material** 面板浮在該局殘局的模糊快照上(見 §3.6) |
| 今日三題卡 ×3 | **真實盤面縮圖**為主體 + 難度名 + 難度 pip + 文字狀態 |
| Banner | tab accessory(§2.4) |

**盤面縮圖畫什麼:** Sudoku 顯示 givens 分佈 + 已填格;MS 顯示已揭開 / 未揭開 / 旗標。
**縮圖尺寸下數字不可讀,這是刻意的** —— 它傳達的是**密度與進度**,不是內容。

**⚠️【官方】無障礙配套:**
> **Convey information with more than color alone.** — `accessibility.md:76`

縮圖**不得是進度的唯一通道**。每張卡保留文字狀態(`Solved · 4:32` / `Not started · 30 givens` /
MS `3 flags · 24 revealed`),縮圖本身 `.accessibilityHidden(true)`,狀態由卡片的 combined a11y label 承擔。

**狀態變體**

| 狀態 | 呈現 |
|---|---|
| `loading` | 縮圖位置放骨架(**保留格線結構**,不是空白方塊);streak 先渲染(讀本地) |
| `loaded` | 完整版面 |
| `allDone` | 三卡改為「今天完成了 + 明日預告」;**badge 消失** |
| `degraded`(CK 失敗) | **縮圖仍可畫**(盤面由 seed 決定,不依賴 CK),只有完成狀態不可知 → 一律畫未開始態;streak hero 顯示骨架而非整塊消失 |
| `exhausted`(Sudoku only) | inline empty block,`Practice`(切 tab)/ `Cancel`(關閉 block,留在 Today) |
| MS 無 `exhausted`/`failed` | D21,結構上不可達 |

### 3.2 PRACTICE

難度三卡帶**密度預覽縮圖**(Sudoku 顯 givens 密度、MS 顯雷密度 + 盤面比例),CTA `New Game`。
Sudoku 保留 `idle`/`drawingQuiet`/`drawingShimmer`/`drawn`/`failed` 五態;MS 單態(同步產盤)——
**這是真實玩法差異,不強行對齊。**

縮圖用**代表性樣本**不是真實下一局(避免把抽題時機前移、踩到既有狀態機)。

### 3.3 PROGRESS

**【官方】** Game Center 對成就呈現有硬規定,現況是它的反面:
> Game Center achievements appear in a **collectible card format**… **Design rich, high-quality images that help players feel rewarded.** … **If you don't provide an asset for an achievement, the card shows a placeholder image instead.**

| 元素 | 說明 |
|---|---|
| Personal bests 陳列 | 每難度一列,**最佳時間為主角**(`.title2`),完成數與平均降為附註 |
| 連續日曆 | 月視圖(紀錄陳列,不是資料視覺化) |
| `Achievements` 列 ↗ | GC 原生 dashboard。**【官方】術語:不可寫 Trophies / Awards / Medals** |
| `Leaderboards` 列 ↗ | 同上。**不可寫 Rankings / Scores / Leaders** |

**⚠️ 明確不做:不在 App 內自建 collectible card 陳列。** 那等於自建成就系統(需 metadata、進度、
以及尚不存在的插畫)→ **違反「不得新增功能」**。正確做法是把入口做好、讓 GC 原生 dashboard 顯示真正的卡片。

**【官方】access point 放置,現況已合規:**
> Display the access point in menu screens. …**Avoid displaying the access point during active gameplay**…

Progress 與 Settings 都是 menu screen ✅;盤面上沒有 GC 入口 ✅。

**⚠️ 已上線缺陷(不在 3.0 範圍,已轉 #1012):** 兩 app 各 11 個成就(合計 22)**全部沒有插畫**
(`ASCRegisterKit` 從未上傳,grep `gameCenterAchievementImages` 零命中),
所以玩家今天在 GC 看到的是 22 張佔位圖。修它不算新增功能,但規模是獨立 epic。

### 3.4 BOARD

**盤面滿版到邊;控制項收進浮動玻璃叢集。**

```
┌─────────────────────────┐
│ ▤ toolbar(系統,玻璃)   │  難度 pip · 計時 · 暫停
│                         │
│    盤面(內容層)          │  滿版,標準材質,不用玻璃
│    從玻璃底下透出         │
│                         │
│ ▤ G4 控制叢集(玻璃)     │  Sudoku:數字鍵 + undo/redo/鉛筆
│ ▤ G4(MS 版)             │  MS:揭開/旗標模式切換 + undo
└─────────────────────────┘
```

**⚠️ iPhone 上 board 沒有 tab bar。** D3 規定 iOS 的 board 是 `fullScreenCover`,它會蓋掉 tab bar。
上圖第二列在前一版被誤標成「tab bar」,導致 prototype 把三分頁列畫進 board 與 completion ——
**已更正:那一列是 G4 的 MS 變體。**

| 畫面 | iPhone 有 tab bar? | 為什麼 |
|---|---|---|
| Today / Practice / Progress / Settings | ✅ 有 | tab 根層或 tab 內 push |
| **Board(進行中)** | ❌ **無** | `fullScreenCover` 蓋掉(D3) |
| **Board(暫停)** | ❌ 無 | 同上,且 pause 遮罩覆蓋全屏 |
| **Completion(liveSolve / MS loss)** | ❌ **無** | 它是 board 內的 overlay,仍在 cover 裡 |
| **Completion(review)** | ✅ 有 | 它是 tab 內的 **push**,不是 cover |

**格徑(實算):**

| 裝置 | 現況(左右內縮 16pt) | 3.0 滿版 | vs HIG 預設 44pt |
|---|---|---|---|
| iPhone SE (3rd) 320pt | 32.0pt | **35.1pt** | 仍未達 |
| iPhone 15/17 Pro 393pt | 40.1pt | **43.2pt** | 仍未達,差距 3.9→0.8pt |
| iPhone Pro Max 430pt | 44.2pt | **47.3pt** | **首次跨過** |

**裁定(沿用並更新數字):** 盤面格預設 ~43.2pt 低於 HIG 預設 44pt、高於官方下限 28pt。
理由:9 欄硬性擠壓,提高格徑只能靠捲動,而捲動破壞「一眼看完整盤」的玩法前提。
緩解:選取環清晰、MS Intermediate/Expert 已在 #764 提到 44pt、#815 提供 pinch-to-zoom。

**⚠️ MS Intermediate(24.3pt)與 Expert(13.0pt)在未縮放時低於官方 28pt 絕對下限。**
合規路徑是 **#815 的 pinch-to-zoom** —— 玩家可放大到 2×(≈48.6 / 26pt)。
**B-5 驗收要加一條:zoom 後格徑 ≥28pt。**

⚠️ 另更正:前一版把「格間無間隙」列為緩解措施 —— **移除**。
官方把間距與尺寸視為同等重要,零間距是一個**取捨**(避免點擊掉進縫隙),不是把格子做小的緩解理由。

**保留不碰:** Sudoku 即時錯誤高亮 + 鉛筆註記 · pause 現狀(D5/D6)· `.idle`/`.leaveReady` 逃生口。

### 3.5 COMPLETION

**玻璃面板從完成的盤面升起;盤面留在後方,不被蓋掉。**
accent 光暈畫在**玻璃背後** → 玻璃自然被染色(**【官方】** `color.md:68`:玻璃無固有色、取自背後內容)。

**為什麼 completion 可以不遮盤面而 pause 必須遮:** pause 遮盤是防偷看(D5);completion 時題目已解完,
沒有可偷看的東西,讓盤面留著反而有意義 —— 你看得見自己剛做出來的東西。

**四種語境的 CTA 階層**

| 語境 | 主 CTA | 次 CTA |
|---|---|---|
| Daily,今日還有未完成 | `Next: Medium` / `下一題:中等` | `Done` / `完成` |
| Daily,今日全完成 | `See you tomorrow` / `明天見` | 提醒 opt-in(未授權時) |
| Practice | `Play Again` / `再來一局` | `Close` / `關閉` |
| MS 失敗 | `Try Again` / `再試一次` | `Close` / `關閉` |

`See you tomorrow` 是**全 flow 唯一的價值詞 CTA**(價值詞是稀缺資源)。

**兩個變體**

| 變體 | 儀式 | 觸覺 |
|---|---|---|
| `liveSolve` | 完整(滲透波 + streak 推進) | success ×1 |
| `review`(回顧已完成的 daily) | **無儀式、面板不播升起** | **無** |
| MS `loss` | 無儀式,hero 用 `status.error` | error ×1 |

**為什麼必須兩個變體:** 現況有 **4 條路徑**產出同一張完成卡(live overlay、pushed `.completion`
re-view、Sudoku loader 的 `.completedRedirect`、MS Tier2 guard 的 `.resolved(.completed)`)。
後三條都是「看一個已經完成的東西」—— 播 streak 推進與成功觸覺會是**謊報**。

### 3.6 RESUME

**standard material** 面板浮在該局**真實殘局**的模糊快照上。

**資料可行性(已查證):** `ResumeCandidate` 只有 title/subtitle/route,**但**兩 app 的 `latestInProgress()`
**已經抓了完整 CK payload**(Sudoku `boardState`、MS `stateBlob`),只是 mapper 丟掉。
→ **可行且不需新增網路往返**,只需擴充 mapper + `ResumeCandidate` 欄位。

### 3.6.1 【F3】ATT 觸發錨點必須改 —— 前一版把它列在「原封不動」是錯的

`screen-contracts.md:1122-1127` 記載 ATT-PRIMER 的 entry point 是
**「`GameHomeView` 的 banner slot `.task`」** —— 但 HOME 畫面在 3.0 被移除,**這個錨點會消失**。
前一版 §9 把 ATT 列在「內圈幾乎原封不動」,**那是錯的**。

**裁定:ATT 改錨到 Today tab 的首次 banner 載入。**
語意等價(仍然是「第一個廣告脈絡」),且既有行為全部保留:不擋 Today 互動、
一次性 `hasOffered` latch、decline 後不再提供、`.notDetermined` 才出現。
→ 契約總表補一條 **BREAK**(C-33)。

---

**⚠️ 型別約束(前一版寫錯模組,已更正):** `ResumeCandidate` 住在 **GameAppKit**(它依賴 Persistence),
**不是** GameShellKit。正確的推理鏈是:**新的值型別 `BoardPreview` 放 GameShellKit(零依賴,D2),
由 GameAppKit 的 `ResumeCandidate` 引用它** —— 這樣繪縮圖的 shell 視圖只認 `BoardPreview`,
Persistence 型別仍然不會洩進 GameShellKit。
設計一個輕量值型別 `BoardPreview { columns, rows, cells: [CellMark] }` 住在 GameShellKit,
兩 app 各自把存檔格式**映射**成它。

**降級:** payload 缺失 / 解析失敗 → 退回純文字 Resume 卡,**不阻擋 resume 本身**。

### 3.6.2 【F4】Resume pill 的 refresh 在 per-tab path 下要重新定義

現況(#679,`GameRoot.swift:170-194`)把 refresh 綁在**單一 `path` 縮短偵測**上。
3.0 有三條 path 之後,**玩家在 Practice 完成一局、切回 Today,pill 可能不會更新**。

**新契約:**

> **Resume pill refresh 觸發 =**
> ① **任一 tab 的 path 縮短**(不只當前 tab)
> ∪ ② `dismissGame()`(iOS cover 收合)
> ∪ ③ `bootstrap()`(啟動)
>
> **切換 tab 本身不觸發 refresh** —— 切 tab 不是 pop,沒有任何局結束。

→ 契約總表補一條 **NEW**(C-34 / N-AB)。

### 3.7 三平台

| | iPhone | iPad regular | macOS |
|---|---|---|---|
| 導航 | 浮動玻璃 tab bar | sidebar(可收合成 tab bar) | sidebar |
| Settings | 每 tab 右上齒輪 | 齒輪 + sidebar 固定項 | 同 iPad |
| Board | `fullScreenCover`(D3) | detail 欄 push | detail 欄 push(D3) |
| 內容延伸 | — | **【官方】** `backgroundExtensionEffect()` —— ⚠️ **用法更正**:它是**鏡射背景**製造「延伸到 sidebar 底下」的印象,**不是真的把內容塞到 sidebar 下**。所以**只用於背景層**;**可點的卡片列必須留在 sidebar 範圍外**,不得被裁切 | 同 iPad |

**⚠️ 最高實作風險(R2):** `sidebarAdaptable` 會改寫 `RootShellView`,而 #763 的 overlay 上提就掛在那裡。
**驗收必須明文包含:pause / completion 期間 sidebar 與 tab 切換皆不可互動。** 快照測試驗不了這條,必須 idb 實機。

---

## 4. 玻璃系統

### 4.1 最終表面清單

**【官方】**
> **Avoid overusing Liquid Glass effects.** …**Limit these effects to the most important functional elements in your app.**
> — *Adopting Liquid Glass*

| # | 表面 | 類型 | 裁定 |
|---|---|---|---|
| **G1** | Tab bar / sidebar | **系統自帶** | ✅ 保留(自動取得玻璃) |
| **G2** | 各 tab 的 toolbar(含齒輪、board 的計時/暫停) | **系統自帶** | ✅ 保留 |
| ~~G3~~ | ~~Board 上緣自訂膠囊~~ | ~~自訂~~ | 🗑 **刪除** → 併入 G2 標準 toolbar |
| **G4** | Board 下緣控制叢集 | **自訂** | ✅ 保留 —— 盤面的主要輸入介面 |
| ~~G5~~ | ~~Resume 面板~~ | ~~自訂~~ | 🗑 **刪除** → standard material(它是內容層卡片) |
| **G6** | Completion 面板 | **自訂** | ✅ 保留為**明示例外**(見 §4.4) |
| **G7** | Tab bar accessory(banner 容器) | **系統自帶** | ✅ 保留 —— 免計(系統元件自動取得玻璃)。前一版清單漏列 |

**自訂玻璃只有 2 片(G4、G6),且同一時間最多一片可見。**

### 4.2 為什麼 streak / 卡片不用玻璃

**【官方】** `materials.md:28` 明文禁止內容層玻璃,唯一例外是「內容層中帶**暫態互動**的 Slider / Toggle」。
streak 是不可互動的資訊列、Today 三卡與 Resume 面板是會捲動的內容層卡片 —— **都拿不到那個例外**。
內容層元素用 **standard materials**。

### 4.3 疊層:同一時間只有一個自訂玻璃「場景」

**【官方】**
> **Check for crowding or overlapping of controls.** …**avoid overcrowding or layering Liquid Glass elements on top of each other.**

> **規則:同一畫面同一時間,只有一個自訂玻璃「場景」可見。**

⚠️ **措辭更正:** G4 依 §4.6(M-g)拆成兩個 group(輸入組 / 編輯組),
所以前一版寫的「最多一**片**自訂玻璃」會自打臉。
**正確的約束單位是「場景」** —— board 場景的 G4(不論內部分幾組,同屬一個 `GlassEffectContainer`)
與 completion 場景的 G6,**不得同時存在**。

→ **completion 面板出現時,G4 必須先退場**(不是被蓋住,是真的 unmount 或去玻璃化)。
pause overlay 是 `ultraThinMaterial`(standard material,非 Liquid Glass),不構成疊層,
但 G4 在 pause 期間本來就該隱藏。

### 4.4 G6 的明示例外(D-3.3 已裁定 A)

> **【明示例外】G6 completion 面板使用自訂 Liquid Glass,而非系統 sheet。**
>
> **理由:** completion 有 **4 條 production 路徑**共用同一個 scaffold,其中 pushed review route
> 在 macOS / iPad 是 **detail 欄 push**;系統 sheet 在該脈絡是錯的呈現
> (macOS sheet = 視窗置中 modal,回顧畫面不該是 modal)。
> **overlay 是唯一能讓 4 條路徑跨三平台一致的機制。**
>
> **代價:** 多一片自訂玻璃。以 §4.3 的退場規則約束。

### 4.5 變體:一律 `regular`,不用 `clear`

**【官方】** `clear` 的適用對象明文是「media backgrounds — such as **photos and videos**」;
盤面是高對比線稿與文字,不是 media。而我們的玻璃叢集**全都含大量文字**(計時、1–9 數字鍵、CTA),
正是官方點名該用 `regular` 的情況。
**連帶好處:35% dimming 層不需要**(那條只在用 `clear` 且底下偏亮時適用)。

### 4.6 容器、間距、圓角

**【官方】**
> **Combine custom Liquid Glass effects to improve rendering performance.** …**make sure to combine them using a** `GlassEffectContainer`

- G4 = **`GlassEffectContainer`**(SwiftUI,26.0+)
- ⚠️ **前一版把用法寫反了,已更正。** 官方原文:
  > Each view with a Liquid Glass effect **contributes a shape** rendered with the effect to a set of shapes.
  > SwiftUI renders the effects together… Configure how shapes interact with one another by **customizing the default spacing value of the container**. As shapes near one another, their paths start to blend.
  >
  > — `GlassEffectContainer`(SwiftUI 文件)

  也就是說**容器靠子視圖各自的 `.glassEffect` 來合併**;若「容器內不套」,做出來的是一個空容器。
- **正確寫法:容器內的按鈕各自套 `.glassEffect`,或用 `.buttonStyle(.glass)`。**
  官方那句「Instead of creating buttons with custom Liquid Glass effects…」的本意是
  **不要自己手刻玻璃外觀**,不是「不要套 glass 修飾符」。
- 容器的 **spacing** 參數控制形狀何時開始融合 —— 這也部分回答了 U-2(官方確實有 spacing 語意,
  是「融合距離」而非內距)
- **不覆寫標準間距**:「Prefer to use **standard spacing metrics** instead of overriding them」→ 叢集內距引用系統標準,不寫死
- **分組原則用官方的**:「Group items that perform similar actions or affect the same part of the interface, and maintain consistent groupings and placement across platforms」→ **輸入組**(數字鍵 / 模式切換)與**編輯組**(undo / redo / 鉛筆),兩 app 一致、三平台一致
- ⚠️ **G4 拆成兩個 group,不是一個**:官方同段明文「**don't mix text and icons across items that share a background**」—— 數字鍵(文字)與工具鍵(圖示)不能共用同一個背景。兩組各有自己的背景,同屬一個 `GlassEffectContainer`
- **【官方】每個圖示按鈕必須有 accessibility label**:「**Provide an accessibility label for every icon.** Regardless of what you show in the interface, always specify an accessibility label for each icon.」
- **圓角同心**:官方要求「using rounded shapes that are **concentric to their containers**」【官方】;**但「內圓角 = 外圓角 − 內距」這條公式是【我方推論】**,官方沒有給公式
- 官方**沒給**「一組最多幾項」的數字 → **不自訂上限**

### 4.7 著色:表面不著色,控制項有條件著色

**【官方】** `color.md:78`:
> **Apply color sparingly**… reserve it for elements that truly benefit from emphasis, such as **status indicators or primary actions**. To emphasize primary actions, apply color to the **background** rather than to symbols or text… **Refrain from adding color to the background of multiple controls.**

| 對象 | 規則 |
|---|---|
| 玻璃**表面**本身 | **一律不著色** —— 取背後內容的顏色 |
| 狀態指示 | 可著色:MS 的 Reveal/Flag 選取態、Sudoku 的鉛筆開啟態 |
| 主要動作 | 可著色:G6 的主 CTA |
| **同一片玻璃** | **最多一個著色控制項** |

### 4.8 Scroll edge effect

**【官方】**「**Optimize for legibility when content scrolls beneath controls.**」→
Today / Progress / Settings 這類會捲到玻璃下方的畫面,用預設 `automatic` 樣式,**不當裝飾用**。
Board 不捲動,不適用。

---

## 5. Token 總表

### 5.1 政策

- 兩 app 各一份 token;**per-app 可覆寫**:`surface.*` / `accent.*` / `identity.*` / `thumb.*` / `streak.*`
- **不可覆寫**:`status.success` / `status.error`(功能色跨 app 必須一致)
  ⚠️ **既有 drift:兩 app 的 `status.warning` 目前值不同**(`#A86A0E` vs `#D9822B`)——
  依原則應統一,但**超出 3.0 範圍**,記錄待另案
- **【官方】** 每個自訂色必須有 light / dark / **increased contrast** 三組(`color.md:28` + *Adopting Liquid Glass*)

### 5.2 Sudoku(sage / 暖紙)

| Token | Light | Dark | **IC Light** | **IC Dark** | 目標 surface | 對比(預設 → IC) |
|---|---|---|---|---|---|---|
| `surface.background` | `#FAF8F3` | `#15171A` | 同 | 同 | — | — |
| `surface.primary` | `#FFFFFF` | `#1E2024` | 同 | 同 | — | — |
| `text.primary` | `#1A1D21` | `#F2F3F5` | 同 | 同 | 兩者較差 | 15.94 / 14.69 已 AAA |
| `text.secondary` | `#54595F` | `#A8ADB3` | **`#51555B`** | 同 | 兩者較差 | 6.66 → **7.07**;dark 7.22 已達標 |
| `text.tertiary` | `#86898E` | `#787C82` | **`#535559`** | **`#A8AAAE`** | 兩者較差 | light 3.31 → **7.04**;**dark 3.89 → 7.01**(前一版 dark 欄誤抄 light 值) |
| `accent.primary` | `#5C7A4F` | `#9BB87E` | **`#485F3E`** | 同 | 承載 ink | 白字 4.83 → **7.04**;dark ink 7.42 已達標 |
| `identity.tier1` | `#6F935F` | `#5D7842` | **`#5D7C50`** | **`#729451`** | surface.primary | 3.29 → **4.70 / 4.72** |
| `identity.tier2` | `#557049` | `#799C56` | **`#445A3A`** | **`#9DBA81`** | surface.primary | 5.21 → **7.58 / 7.59** |
| `identity.tier3` | `#3B4E33` | `#ABC392` | **`#2B3925`** | **`#D8E3CD`** | surface.primary | 8.52 → **12.25 / 12.27** |
| `thumb.given` | `#859B7B` | `#5F6F53` | **`#5D7C50`** | **`#729451`** | surface.primary | 3.01 → **4.70 / 4.72** |
| `thumb.userFilled` | `#5C7A4F` | `#849D6E` | **`#3D5135`** | **`#ACC493`** | surface.primary | 4.83 → **8.65 / 8.60** |
| `streak.pipOff` | `#719561` | `#5C7641` | **`#5D7A50`** | **`#6B894C`** | surface.background | 3.20 / 3.53 → **4.53 / 4.54** |
| `status.success` | `#1B7A3E` | `#4BC579` | **`#176634`** | 同 | surface.primary | 5.38 → **7.03**;dark 7.43 已達標 |
| `status.warning` | `#A86A0E` | `#E0A95C` | **`#7D4F0A`** | 同 | surface.primary | 4.44 → **7.01**;dark 7.77 已達標 |
| `status.error` | `#C8362B` | `#E66258` | **`#A52C23`** | **`#ED918A`** | surface.primary | 5.23 → **7.04**;dark 4.86 → **7.01** |

⚠️ `identity.tier1` 與 `thumb.given` 的 IC 值相同(同一目標、同一門檻推導出來),這是預期的,不是複製錯誤。

### 5.3 Minesweeper(blueprint / 冷紙)

| Token | Light | Dark | **IC Light** | **IC Dark** | 目標 surface | 對比(預設 → IC) |
|---|---|---|---|---|---|---|
| `surface.background` | `#F4F6F8` | `#14171B` | 同 | 同 | — | — |
| `surface.primary` | `#FFFFFF` | `#1C2026` | 同 | 同 | — | — |
| `text.primary` | `#1A1E24` | `#EEF1F4` | 同 | 同 | 兩者較差 | 15.44 / 14.43 已 AAA |
| `text.secondary` | `#545B63` | `#A4ACB4` | **`#4E545C`** | 同 | 兩者較差 | 6.35 → **7.06**;dark 7.12 已達標 |
| `text.tertiary` | `#868D95` | `#767D85` | **`#4F545A`** | **`#A6ABB0`** | 兩者較差 | light 3.10 → **7.05**;**dark 3.93 → 7.07**(前一版 dark 欄誤抄 light 值) |
| `accent.primary` | `#3E6B8C` | `#7FAFCF` | **`#365C79`** | **`#80B0D0`** | 承載 ink | 白字 5.70 → **7.09**;dark ink 6.96 → **7.04** |
| `accent.celebratory` | `#D4501F` | `#EB774C` | **`#C2491C`** | 同 | surface.background | 3.90 → **4.55** |
| `identity.tier1` | `#578DB4` | `#3B759D` | **`#46799E`** | **`#4D90BC`** | surface.primary | 3.30 → **4.68 / 4.70** |
| `identity.tier2` | `#3E6C8D` | `#5A98C1` | **`#335772`** | **`#8BB6D3`** | surface.primary | 5.19 → **7.64 / 7.58** |
| `identity.tier3` | `#2B4B62` | `#9AC0D9` | **`#203748`** | **`#D0E2ED`** | surface.primary | 8.48 → **12.34 / 12.29** |
| `thumb.covered` | `#7897AE` | `#516D81` | **`#46799E`** | **`#4D90BC`** | surface.primary | 3.07 → **4.68 / 4.70** |
| `thumb.flag` | `#3E6B8C` | `#6F98B4` | **`#2E4F68`** | **`#9BC1DA`** | surface.primary | 5.70 → **8.63 / 8.59** |
| `streak.pipOff` | `#5B8FB6` | `#3A739A` | **`#44759A`** | **`#4386B3`** | surface.background | 3.20 / 3.51 → **4.55 / 4.54** |
| `status.success` | `#1B7A3E` | `#4BC579` | **`#176634`** | 同 | surface.primary | 5.38 → **7.03**;dark 7.45 已達標 |
| `status.warning` | `#D9822B` | `#E8A560` | **`#824C17`** | 同 | surface.primary | **2.93** → **7.01**;dark 7.77 已達標 |
| `status.error` | `#C8362B` | `#E66258` | **`#A52C23`** | **`#ED918A`** | surface.primary | 5.23 → **7.04**;dark 4.87 → **7.02** |

⚠️ **MS `status.warning` 在 light 下只有 2.70:1,連預設集的非文字 3:1 都不過。**
這是**既有缺陷**,不是 IC 造成的。但它的實際使用位置尚未查清(MS 旗標另有專用 token `flagInk` `#9C5C1C`)
→ **本文不宣稱它是 bug**,列為待查。

### 5.4 IC 的三條規則

**門檻:** 文字 **≥7:1(AAA)**、非文字 **≥4.5:1** —— 官方要求「significantly higher amount of visual differentiation」,AAA 是有標準定義的下一級。

**✅【明示裁定 D-3.2】IC 變體只調整前景(文字/填色/描邊),不調整 surface。**
理由:surface 已是近白與近黑,再推空間極小;改 surface 會讓**每一個既有配對的對比幾何全部位移**,
等於重算整份 token。只動前景可達同等效果而**改動半徑小一個數量級**。
**適用範圍:**兩 app 全部 IC 變體;日後若出現「IC 下必須改 surface」的個案須單獨裁定,**不得作為通則援引**。

**⚠️ IC 會壓縮 ramp —— 一般性結論:**
> **提高對比下限會把 ramp 的低階往高階推;若只逐階滿足下限,ramp 的內部層次會被壓扁。
> 任何多階 ramp 在 IC 變體都必須「整體重排」,不能逐階微調。**

逐階推的後果:`identity.tier1` 相鄰間距從 1.58:1 崩到 **1.15:1**;thumbnail 兩階崩到 **1.06:1**。
重排後目標:identity **4.7 / 7.6 / 12.3**、thumbnail **4.7 / 8.6** →
兩 app、明暗四組全部 rung PASS 且相鄰間距 **1.61–1.84**。

**✅【D-3.1 已裁定:接受】** IC 下難度色退化為純明度階 —— 這正是 IC 使用者需要的;
pip 數量冗餘編碼(●○○ / ●●○ / ●●●)在 IC 下仍有效,**與 WCAG 1.4.1 相容性反而更好**。

### 5.5 落地路徑:Asset Catalog 六色井

**【官方】** Asset Catalog 原生支援 Appearances(Any/Light/Dark)+ 獨立 High Contrast 勾選,交叉最多 6 色井。
官方 `colorSchemeContrast` 文件明講:**單純換色就交給 Asset Catalog,不要在程式碼判斷。**

→ **不寫程式碼分支備案**(官方明文反對)。唯一例外是「IC 下要改的不只是顏色」的情境,
目前專案**沒有**這種情境。

**⚠️ 工程成本:repo 目前一個 Asset Catalog color set 都沒有**,token 全是程式碼 hex 常數(`ThemeColor` struct);
`colorSchemeContrast` / `accessibilityReduceTransparency` / `accessibilityDifferentiateWithoutColor` **全部零命中**。
所以這是「**兩 app 全部 token 從程式碼常數遷移到 Asset Catalog**」,不是「加個變體」。
影響:全部 token · `ThemeColor` 型別 · 既有快照基準(可能整批 churn)· theme 注入路徑。

### 5.6 字級與間距

字級走 SwiftUI 樣式名不寫死 pt;驗收線 = 放大 200% 不截斷**且不減內容量**。
間距沿用兩級契約:**content spacing** 隨 Dynamic Type 縮放、**structural spacing** 固定(螢幕邊距、
卡片外距、熱區下限、盤面幾何)。
⚠️ **例外:G4 叢集內部間距改為引用系統標準**(§4.6),不走本契約。

---

## 6. 動效與觸覺總表

| # | 動效 | 預設 | Reduce Motion 降級 | 依據 |
|---|---|---|---|---|
| M1 | Completion accent 滲透波 | 0.6s ease-out,**不擋互動** | crossfade 0.25s | 【官方】 |
| M2 | Completion hero 揭示 | 350ms fade + 8pt 上升,stagger 60ms | 純 fade,無位移 | 【官方】 |
| M3 | Streak pip 推進 | 0.35s 填色 + 1.0→1.12→1.0 | **只填色,不縮放** | 【官方】 |
| M4 | 連續數 +1 | 0.3s 數字上滑替換 | crossfade 替換 | 【官方】 |
| M5 | Tab badge 出現 | 0.2s scale 0.6→1.0 + fade | 只 fade | 【官方】 |
| M6 | Tab badge 消失 | 0.2s fade out | 同 | — |
| M7 | 卡片 loading → loaded | shimmer(100–500ms) | 靜態 placeholder | — |
| M8 | Tab 切換 | 系統預設 | 系統處理 | — |
| M9 | 縮圖 → 盤面 shared-element | 矩形放大 + 交叉淡入 0.4s | **純 crossfade** | 【官方】 |
| M10 | Completion 玻璃升起 | 由下升起 0.45s + 光暈 0.6s | **面板 fade 就位不位移** | 【官方】 |
| M11 | G4 叢集進場 | 隨盤面就位淡入 0.25s | 同 | — |
| **M12** | **Sudoku 填對數字** | 80ms scale 0.9→1.0;若行/列/宮完成則 180ms 淡光掃過 | 無縮放;淡光改靜態閃現 | **【官方】** |
| **M13** | **MS 正確揭開連通區** | 由點擊點向外 120ms 波狀展開(每格 8ms,上限 200ms) | **全部同時顯示,無延遲** | **【官方】** |

**【官方】M12/M13 的依據:**
> **Aim for brevity and precision in feedback animations.** …**when a game displays a succinct animation that's precisely tied to a successful action, players can instantly get the message without being distracted from their gameplay.**
> — `motion.md:34`

**⚠️ 兩條硬約束:**
1. **不得擋互動**(`~/.claude/skills/hig/motion.md:38`):完成動畫每局都觸發,CTA 從第 0 frame 就可點。
2. **Reduce Motion 不是關掉,是換 fade** —— 官方五條替代原則的第 4 條
   「**Replacing transitions in x-, y-, and z-axes with fades to avoid motion**」。
   ⚠️ **出處更正**:前一版標成 `motion.md`,實際在 **`~/.claude/skills/hig/accessibility.md:177-181`**
   (HIG Accessibility 的 Reduce Motion 段)。**內容與【官方】等級不變,錯的是檔名行號。**

### 6.1 觸覺

| 事件 | 觸覺 |
|---|---|
| Daily / Practice 完成(勝利) | `.success` **×1** |
| MS 踩雷 | `.error` ×1 |
| `review` 開啟 | **無**(沒有任務完成,放了是謊報) |
| Streak pip 推進 | **無獨立觸覺**(與完成是同一因果事件) |
| M12 / M13 格子級 | **無**(一局 40+ 次會稀釋 completion 那一次) |
| Tab badge / 難度卡選取 | 無 |

**【官方】禁則:** 同一個 haptic pattern **不得同時用於正面與負面結果**
(`playing-haptics.md:31`)。`.success` 只給解開/清除,`.error` 只給踩雷,**永不共用**。
**【官方】必須可關閉**(`:39`)—— Settings 的 Sound 區已有 haptics toggle,新觸覺接同一開關,**不新增第二個設定**。

---

## 7. 無障礙

| 項目 | 規則 |
|---|---|
| **三個正交開關** | Reduce Motion × Increase Contrast × Reduce Transparency = **8 種組合**,不是 4 種 |
| **玻璃降級** | **分兩種**:G1/G2(系統元件)**自動適應**;**G4/G6 是自訂玻璃,官方只保證「要測」不保證自動降級**(「Ensure you test your app's custom elements, colors, and animations with different configurations of these settings」)→ 走 B-5。我們負責提供 IC 色彩變體 |
| **版面硬規則** | **G4 不得覆蓋任何可互動格子** —— 這是版面規則,幾何不隨開關改變,**必須以最壞情況(IC+RT)為設計基準** |
| **顏色非唯一通道** | 難度用 pip **數量**冗餘編碼;縮圖進度必配文字狀態 |
| **動態播報** | 完成、全完成等狀態變化須 announcement(WCAG 4.1.3),不能只做視覺 |
| **Dynamic Type** | 200% 不截斷且不減內容量;盤面格內數字是已記錄的例外 |

⚠️ **玻璃在 IC / RT 下官方只有質化描述,沒有數值門檻** —— 任何不透明度/描邊數值都是**我方自訂**。
官方要求的是「**測**」不是「達到某數值」:
> **Ensure you test your app's custom elements, colors, and animations with different configurations of these settings.**

---

## 8. 定案彙整表

### 8.1 3.0 新裁定

| # | 決策 | 裁定 |
|---|---|---|
| D-1 | Streak hero 形態 | **B:週條放大**(v3.3 再降為一列,見 §3.1) |
| D-2 | 難度色方案 | **選項 2:各 app accent 的單色明度階** + pip 數量冗餘 |
| D-3 | Today badge | **B:無數字圓點**(HIG 禁止數字) |
| D-4 | 明日預告語氣 | **B 當 CTA(`See you tomorrow`)+ A 當副標** |
| D-5 | 卡片的 Liquid Glass | **收回** —— 且查證後確認這是**修既存違規**,非偏好 |
| D-6 | Resume 位置 | **A:只在 Today** |
| D-7 | 完成後「下一題」怎麼挑 | **B:挑剩下最簡單的** |
| D-2.1 | 難度預覽用真實下一局? | **B:代表性樣本** |
| D-2.2 | Today 顯示幾局真實進度 | **A:只有 resume 那一局** |
| D-2.3 | Progress 連續紀錄形態 | **A:月曆** |
| D-2.4 | Streak 用玻璃? | **不用** —— 內容層,拿不到 `materials.md:28` 的例外 |
| D-2.5 | 格子級動作配觸覺? | **A:不配** |
| D-2.6 | Resume 的 restore 規則 | **記為明示例外**(Today 本身就是上次離開的位置) |
| D-2.7 | 成就插畫 epic | **現在開 issue(#1012),不綁進 3.0** |
| **D-3.1** | IC 下難度色退化成純明度階 | ✅ **接受** |
| **D-3.2** | IC 只動前景不動 surface | ✅ **記為明示裁定**(§5.4) |
| **D-3.3** | Completion 改系統 sheet? | ✅ **A:維持盤內 overlay**,G6 記為明示例外(§4.4) |
| **D-3.4** | G5 Resume 改 standard material | ✅ **接受** |

### 8.2 22 條既有決策的存廢

| # | 決策 | 3.0 狀態 |
|---|---|---|
| D1 | Mirror principle | ✅ **沿用**(3.0 全部新元件走共用 shell + 兩份 token) |
| D2 | GameShellKit 零依賴 | ✅ **沿用**(`BoardPreview` 值型別即為守此線) |
| D3 | board iOS modal / macOS push | ✅ **沿用** |
| D4 | completion overlay 為唯一終端完成面 | ✅ **沿用並強化**(D-3.3 明示例外) |
| D5 | pause 合併單一按鈕 | ✅ **沿用,不碰** |
| D6 | AD-002 pause 重設計取消 | ✅ **沿用** |
| D7 | 排行榜走 GC 原生 dashboard | ✅ **沿用**(Achievements 沿用同機制) |
| D8 | completion 無排行榜切片 | ✅ **沿用** |
| D9 | 計時器在盤面 header 不在 nav bar | ⚠️ **修改** —— 3.0 改為**系統 toolbar**(G2)。精神(不在全域 nav bar、屬於盤面)保留 |
| D10 | Brand essence / 不慶祝 / glass 限導航 | ⚠️ **演進** —— 不慶祝 → 安靜儀式;glass 從「限導航」明確化為「限功能層」 |
| D11 | Sudoku sage accent | ✅ **沿用** + 新增 IC 變體 |
| D12 | MS 自有 blueprint theme | ✅ **沿用** + 新增 IC 變體 |
| D13 | Practice 不進 GC leaderboard | ✅ **沿用** |
| D14 | OS floor iOS 26 / macOS 26 | ✅ **沿用**(3.0 的玻璃 API 全部依賴它) |
| D15 | 7 locale 齊全 | ✅ **沿用**(新增字串走同流程) |
| D16 | Statistics 刻意不是 HomeMode | ❌ **推翻** —— 升為 Progress tab |
| D17 | Home 移除 Remove Ads 卡 | ⚪ **失效** —— Home 畫面本身退役 |
| D18 | Banner 覆蓋範圍是 feature | ✅ **沿用**(位置改 accessory) |
| D19 | 不做 onboarding | ✅ **沿用** |
| D20 | Settings 保持原生 Form | ✅ **沿用,不碰** |
| D21 | MS 無 empty/exhausted 狀態 | ✅ **沿用** |
| D22 | iPad 不是第三套 contract | ✅ **沿用**(`sidebarAdaptable` 更強化這點) |

---

## 9. 行為契約變更總表(已複核)

### 9.1 ⚠️ 先更正三個數字 —— 先前的累計數是錯的

我通讀 v3.1 與 v3.2 的表格逐列數過(腳本 `contracts.py`),發現**三處計數錯誤**:

| # | 錯誤宣稱 | 實際 | 錯在哪 |
|---|---|---|---|
| 1 | v3.1 §6:「navigation-flows **24 條中 9 條 BREAK**」 | **8 條 BREAK** | 多算一條 |
| 2 | v3.2:「screen-contracts 累計 **9 + 11 = 20**」 | **17 + 15 = 32** | 把 v3.1 的 **BREAK 小計(9)**當成**總列數(17)**相加;且「+11」是舊值,後來補了 C-29…C-32 變 15,摘要沒更新 |
| 3 | v3.2:「navigation-flows 累計 **9 + 3 = 12**」 | **24 + 3 = 27** | 同上 —— 又是拿 BREAK 小計(9)當總數(24) |

**根因:同一個錯誤犯了兩次 —— 把「BREAK 的數量」和「總列數」相加。** 兩個不同的量綱不能相加。

### 9.2 【F5】前一版的基數也是錯的 —— 我們的編號從來沒有錨回 canonical 文件

r2 又抓到一層問題:**C-x / N-x 是我們自己的編號,從來沒有對應到 canonical 文件的實際段落與列。**
而且拿來當基數的「17 條 / 24 條」本身就不是 canonical 的數量:

| | 我們以為的基數 | **canonical 實際** | 差在哪 |
|---|---|---|---|
| `screen-contracts.md` | 17 | **23 個 slug 段落**(`## HOME` … `## UMP-CONSENT`) | 17 是**我們的變更條數**,不是文件的段落數 |
| `navigation-flows.md` | 24 | **38 列**(S1–S7 = 7 · M1–M8 = 8 · N1–N23 = 23) | 24 從 v3.1 起就錯,且錯到 v3.3 |

**根因:我們一直在數「自己寫了幾條變更」,卻把它講成「文件有幾條」。** 這是兩個不同的量
—— 跟 §12 更正 6(BREAK 小計 ≠ 總列數)是同一類錯誤,只是換一個位置再犯一次。

### 9.3 正確的表述方式

**變更條數與 canonical 覆蓋率要分開講:**

| | 我們的變更條數 | 涉及的 canonical 範圍 |
|---|---|---|
| `screen-contracts.md` | **36 條**(C-1…C-32 + r2 新增 C-33…C-36)= 腳本 **40 個錨點列** | 23 個 slug 段落中的 **19 個**;`REMINDER-PRIMER` / `REMINDER-DENIED` / `CLEAR-CACHE-DIALOG` / `UMP-CONSENT` 四段不受影響 |
| `navigation-flows.md` | **28 條**(N-A…N-AA + r2 新增 N-AB)= 腳本 **32 個錨點列** | **24 列**(以 `contracts.py` 實測為準);N15/N16/N19/N21/N22/N23 與 UMP 相關列不受影響 |

**⚠️ 「條」與「錨點列」是兩個單位,不要互相對帳。**
一條邏輯變更若兩個 app 各有一個 canonical 落點,會拆成兩個錨點列(`C-2` / `C-2b`、`N-F` / `N-F2`)。
拆出來的是 4 條 screen(C-2b / C-3b / C-8b / C-9b)與 4 條 nav(N-F2 / N-N2 / N-O2 / N-P2),
所以 **36 + 4 = 40**、**28 + 4 = 32**。附錄 A 的腳本輸出兩個數字都印,就是為了讓這次的對帳不必再做一次。

**⚠️ 尚未錨定的 9 條(spec PR 要補完的就是這 9 條):**

| 條目 | 判定 | 為什麼還沒有錨點 |
|---|---|---|
| `C-16` | NEW | 新增 `ROOT-TABS` 契約段 —— canonical 目前**沒有這一節**,要新開 |
| `C-27` | NEW | 新增 Liquid Glass 表面清單 —— 同上,canonical 沒有對應段落 |
| `N-A` | BREAK | Route enum 7→3 / 8→5,寫在 `navigation-flows.md` §1 散文,不是表列 |
| `N-B` | EXTEND | 「兩脈絡共用一張 route table」的模型敘述,§2 散文 |
| `N-C` | BREAK | resume-pill refresh 觸發條件改寫,§2 散文(表列化後即 N-AB 的正向面) |
| `N-X` | NEW | badge / streak 資料失敗的降級 —— canonical **無對應負向列** |
| `N-Y` | NEW | 縮圖資料不可得 —— 同上 |
| `N-Z` | NEW | Resume 快照不可得 —— 同上 |
| `N-AB` | NEW | 切 tab 不觸發 resume refresh —— 同上 |

分成兩類:**C-16 / C-27 與 N-X / N-Y / N-Z / N-AB 是要新增的段落與列**(錨點在 spec PR 寫出來才會存在),
**N-A / N-B / N-C 是既有散文的改寫**(要嘛表列化、要嘛錨到段落編號)。
兩類都不算漏,但都必須在 spec PR 收掉 —— `contracts.py` 會一直把它們印在 `NOT YET ANCHORED` 裡當提醒。

**⚠️ 每一條 C-x / N-x 都必須帶 canonical 錨點(slug + 行號範圍)才算完成。**
本文只重述總數與覆蓋率;**逐條錨點對照表是 spec PR 的第一項工作**,
且 `contracts.py` 與 `contrast.py` 要一起落進 `scripts/design/`,**輸出貼進附錄 A**,否則這些數字下一版又會漂。

### 9.4 判定分佈(依 36 / 28 重述)

| | BREAK | EXTEND | KEEP | NEW | 合計 |
|---|---|---|---|---|---|
| screen-contracts | **17**(+C-33 / C-35) | 11 | 1 | **7**(+C-34 / C-36) | **36** |
| navigation-flows | 8 | 5 | 10 | **5**(+F4) | **28** |

**⚠️ 新增的四條(r2):**

| # | 條目 | 判定 | 來源 |
|---|---|---|---|
| C-33 | `ATT-PRIMER` entry point 從 `GameHomeView` banner slot 改錨 Today tab | **BREAK** | F3 |
| C-34 | Resume pill refresh 觸發改為「任一 tab 的 path 縮短」 | **NEW** | F4 |
| C-35 | `GC-DASHBOARD` / `GC-SIGNED-OUT-ALERT` 的 **HOME leaderboard 卡入口消失** | **BREAK** | M-e |
| C-36 | `GC-DASHBOARD` 新增 **Progress 的 Achievements 列**入口 | **NEW** | M-e |
| N-AB | 負向流程:切 tab 不觸發 resume refresh(不是 pop) | **NEW** | F4 |

§9.3 / §9.4 的 **36 / 28** 已含這五條。
**這正是為什麼腳本必須落 repo:手工維護這個數字已經連錯三次。**

**好消息:BREAK 集中在入口與落點敘述,不是狀態機本身。**
內圈(MS 四層 loader、pause 狀態機、completion 的 `dismiss()`/`exitToHub` 機制、IAP、UMP)幾乎原封不動。
⚠️ **更正:前一版把 ATT 也列在這裡是錯的** —— ATT 的觸發錨點依附於 HOME,HOME 移除後必須改錨(§3.6.1 / C-33)。

---

## 10. Unconfirmed 與驗證步驟總表

### 10.1 Unconfirmed

| # | 項目 | 擋實作? | 出路 |
|---|---|---|---|
| ~~U-1~~ | tab accessory API | — | ✅ 已解:`tabViewBottomAccessory` |
| ~~U-3~~ | IC 變體要求 | — | ✅ 已解:官方明文要求 |
| ~~U-4~~ | Resume 盤面資料 | — | ✅ 已解:判定 B,可行 |
| ~~U-5~~ | games 專章 | — | ✅ 已結案:**官方無介面結構規範** |
| ~~U-6~~ | `GlassEffectContainer` | — | ✅ 已解:存在,26.0+ |
| **U-2** | 玻璃叢集官方間距數值 | ❌ 不擋 | 引用系統標準即可 |
| **U-7** | 各語系系統 GC 用詞 | ⚠️ **擋 L10n 定案** | B-3 |
| **U-9** | `GlassEffectContainer` × 系統 button style | ⚠️ **擋 G4 實作細節** | B-7 |
| **U-10** | `tabViewBottomAccessory` × AdMob | ❌ **不擋**(有降級備案) | B-6 |
| **U-11** | MS `status.warning` 的實際使用位置 | ❌ 不擋 | 查清後決定是否另開 issue |
| ~~U-12~~ | SwiftUI `.badge()` 能否呈現**無數字**形態 | — | ✅ 已解(#1020 spike,2026-08-24):**做不到** —— tab bar 上的圓點來自未文件化的空白字串行為且各表面不一致(iPhone `""` 可、iPad tab bar 只有 `" "` 可),sidebar 展開態一律渲染為文字附註、無圓點形態 → 依 §2.3 **整個放棄 badge**,不自繪 |
| **U-13** | macOS 沒有 `tabViewBottomAccessory`,banner 的 macOS 落點 | ⚠️ 擋 macOS 變現版面 | §2.4.1,推薦方案 A |

### 10.2 驗證步驟

| # | 項目 | 誰 | 判準 | 現在可執行? |
|---|---|---|---|---|
| B-1 | MS 盤面留白成因 | sim agent | Beginner >32pt 且 Expert ≈0 → 成因確認 | ✅ |
| B-2 | Dynamic Type AX5 | sim agent | 不截斷且不減內容量。**⚠️ 不可用注入 env 快照(假通過)** | ✅ |
| B-3 | GC 六語系實機用詞 | sim agent | 我方譯法與系統一致 | ✅ |
| B-4 | `sidebarAdaptable` vs #763 | macOS agent | pause/completion 期間 sidebar 與 tab 皆不可互動 | ❌ **需實作原型** |
| B-5 | 八種開關組合 | sim agent | 盤面格全可見可點 · IC 下 pip 三階可辨 · RT 下版面不位移 · RM 走 fade | ✅ |
| B-6 | accessory × AdMob | dev | banner 不塌、impression 正常 | ✅(最小樣板) |
| B-7 | `GlassEffectContainer` × button style | dev | 正確合併為單一玻璃形狀 | ✅(最小樣板) |

**⚠️ B-2 我預期會失敗**:streak 一列在 AX5 下「12 day streak + 7 pip + Best 31」極可能放不下,
需 `ViewThatFits` 或換行策略。**失敗是預期結果不是意外。**

---

## 11. 給開發的分期建議

### 階段 0 — 現在就可以開始(無阻擋)

| 項目 | 說明 | 為何可先做 |
|---|---|---|
| **Token 遷移到 Asset Catalog** | 兩 app 全部 token 從程式碼常數改為 color set | 與 UI 重構**完全解耦**;做完才有地方放 IC 變體 |
| **IC 色彩層** | 六色井填入 §5.2/§5.3 的 IC 值 | 依賴上一項,不依賴任何 UI 改動 |
| **`BoardPreview` 值型別 + mapper 擴充** | 停止丟棄 `boardState` / `stateBlob` | 純資料層,不動 UI |
| **M12 / M13 格子級回饋動畫** | 盤面內的成功動作動畫 | 現有 board 就能加,不等重構 |
| **B-4 spike:`sidebarAdaptable` × #763** | **只搭最小骨架**(sidebarAdaptable + pause overlay),驗 #763 行為,**不含三屏內容** | ⚠️ **從階段 1 提前到這裡** —— 它決定整個 shell 的可行性,驗過才展開階段 1,否則整期返工 |

**這四項合起來就能讓「進度」看得見,而且風險最低。**

### 階段 1 — UI 重構主體

| 項目 | 前置 |
|---|---|
| 3 tab 骨架(`sidebarAdaptable`)+ per-tab path | — |
| Today / Practice / Progress 三屏 | 階段 0 的 `BoardPreview` |
| Board 滿版 + G4 玻璃叢集 | B-7 的結果(決定容器內按鈕形態) |
| Completion 全高面板 + 兩變體 | — |

⚠️ **B-4 已提前到階段 0(見下),不再是本階段的驗收項** —— 但本階段完成時要再跑一次回歸。

### 階段 2 — 等驗證

| 項目 | 等什麼 | 沒等到就 |
|---|---|---|
| Banner 改 tab accessory | B-6 | **退回 tab 內容底部**(設計已備案,不阻擋出貨) |
| L10n 新字串定案 | B-3 / U-7 | 先只上英文,其餘語系待核對 |

### 階段 3 — 獨立 PR,不綁 3.0

| 項目 | 說明 |
|---|---|
| **#1012 成就插畫** | 22 張不重用插畫 + `ASCRegisterKit` 上傳路徑。**需美術產能,獨立 epic** |
| **孤兒字串清理** | 8 個 GC 死鍵 + 英文禁用詞鍵(#49 收尾 backlog) |
| **`status.warning` 跨 app 統一** | 兩 app 值不同,依「功能色不可覆寫」原則應統一 |
| **MS 四層 loader 收斂** | 3.0 明確不碰;各 tier 修的是真實競態(#841/#842/#910),硬併會重新引入 bug |

### 建議的第一個 PR

**Token 遷移 + IC 層**(階段 0 前兩項)。理由:
它是後面所有視覺工作的地基、與 UI 完全解耦、可獨立驗收(對比度可用腳本自動驗)、
而且**它修的是一個目前完全不存在的無障礙能力**,價值明確。

⚠️ **前置動作:把 `contrast.py` 與 `contracts.py` 落進 `scripts/design/`**,
否則 §5 的 60 多個數值與 §9 的條數沒有人能複驗。兩支都已交付、可從 repo 根目錄直接跑,
輸出見**附錄 A**。(設計期的推導腳本 `ic.py` / `ic2.py` / `ic3.py` 是草稿工具,
其結論已固化進 `contrast.py` 的 `TARGETS` / `TOKENS` 表,**不落 repo**。)

---

## 12. 已知錯誤更正紀錄(我自己的)

**這一節保留在定稿裡,因為它們影響過敘事,讀者有權知道。**

| # | 錯誤 | 更正 | 教訓 |
|---|---|---|---|
| 1 | 「卡片不用玻璃」隱含現況無玻璃 | 現況**有 6 處** shipping 玻璃在內容層 | **談現況要查程式碼,不要只讀設計文件** |
| 2 | MS 成就 13 個 | **11 個**(兩 app 各 11,合計 22) | **數量要找權威列舉,不要 grep 宣告樣式** |
| 3 | ja「兩種譯法並存」+ 英文來源詞全合規 | 並存不成立(8/9 是孤兒);英文 `No Rankings Yet` / `Couldn't Load Rankings` **本身就用了禁用詞** | **判定合規要看全部樣本,不能只看一個鍵** |
| 4 | 「v3.2 有 14 片玻璃」 | 實際宣告 **6 片** —— 14 是我的腳本數 HTML class 出現次數 | **驗證腳本的計數欄位要對齊它宣稱測量的概念** |
| 5 | 「Sudoku 側沒有等價 `allShortIds`」 | **有**,在 `SudokuEngine/GameCenterIdentifiers.swift:82-94` | **找不到時先確認找對模組;跨 app 對稱假設不是每處都成立** |
| 6 | 契約累計 20 / 12 | **32 / 27**(r2 再更正為 **36 / 28**,見 #10) | **不同量綱不能相加**(BREAK 小計 ≠ 總列數) |
| **7** | §3.4 ASCII 圖把 **G4 的 MS 變體標成「tab bar」** | 那一列是 **G4(MS 版)** | **圖表標籤錯一個字,prototype 就照著錯畫了五個框** —— 圖是規格的一部分,要跟文字一樣校對 |
| **8** | `GlassEffectContainer` 用法**寫反**(「容器內按鈕不各自套 `glassEffect`」) | **相反** —— 官方:「Each view with a Liquid Glass effect **contributes a shape**」,容器**靠**子視圖的 `.glassEffect` 合併 | **引用一句話前要讀完整段**;「不要手刻玻璃按鈕」與「不要套 glass 修飾符」是兩件事 |
| **9** | 五條 reduce-motion 替代原則標成 `motion.md` | 實際在 **`accessibility.md:177-181`** | **內容對、出處錯也是錯** —— 出處錯了就無法被複驗 |
| **10** | 契約基數「screen-contracts 17 / navigation-flows 24」 | canonical 實際是 **23 個 slug 段落 / 38 列**;我們數的是**自己的變更條數** | **「我寫了幾條」與「文件有幾條」是兩個量** —— 與 #6 同類錯誤換位置再犯 |
| **11** | `ResumeCandidate` 說在 GameShellKit | 在 **GameAppKit**(它依賴 Persistence) | 同 #5:**假設模組位置前先查** |
| **12** | 自訂玻璃降級講成「系統處理,我們不寫降級代碼」 | 只有 **G1/G2 系統元件**自動;**G4/G6 官方只保證「要測」** | **把系統元件的保證套到自訂元件上** |
| **13** | 「ATT 幾乎原封不動」 | ATT 錨點依附 HOME,**必須改錨**(C-33) | **移除一個畫面時要追它身上掛了什麼**,不只追它自己 |
| **14** | `contrast.py` 的例外清單裡把 `status.error` dark 標成「4.86:1,差 0.13 未達 AA」 | **4.86 ≥ 4.5,本來就通過** —— 比較方向寫反了;腳本第一次跑就以 `STALE` 判它並 exit 1 | **會抓自己作者的閘門才有價值**:這條是腳本抓到的,不是我複核抓到的 |
| **15** | §9.3 只寫「36 / 28 條」,沒說腳本會印 **40 / 32** 個錨點列 | 兩個單位:一條邏輯變更可拆成兩個 app 的錨點列(C-2/C-2b),**36+4=40、28+4=32**;§9.3 現在兩個都列 | **同一件事有兩種計數單位時,文件要兩個都寫**,否則對帳的人只能猜哪個是錯的 —— 這是第 4 次數字漂移,也是最後一次靠人工對帳 |

---

## 附錄 A:驗證腳本輸出(逐字,repo 根目錄實跑)

§9.3 要求「輸出貼進附錄」。以下兩段是 `python3 scripts/design/<script>.py` 的**原樣輸出**,
未刪節、未改寫;數字若與正文不符,**以腳本為準**並更新正文(本節即為此而存在)。

**`scripts/design/contracts.py`**(exit 0)

```
contract anchoring gate
  repo root: <repo>
==============================================================================
canonical shape
  screen-contracts.md : 23 slug sections (expected 23)
  navigation-flows.md : 38 rows  S=7 M=8 N=23  (expected S=7 M=8 N=23, total 38)

anchors

coverage
  change entries      : 36 screen-contracts (40 anchor rows), 28 navigation-flows (32 anchor rows)
  canonical touched   : 19/23 slug sections, 24/38 nav rows
  untouched sections  : CLEAR-CACHE-DIALOG, REMINDER-DENIED, REMINDER-PRIMER, UMP-CONSENT
  NOT YET ANCHORED    : 2 screen (C-16, C-27), 7 nav (N-A, N-B, N-C, N-X, N-Y, N-Z, N-AB)
                        (these describe new sections or prose-level model changes;
                         anchoring them is the remaining spec-PR work item)

RESULT: PASS — canonical shape matches, every stated anchor resolves
```

**`scripts/design/contrast.py`**(exit 0)

```
design contrast gate — 132 checks
==============================================================================
  sudoku      text.tertiary      default light KNOWN   3.31:1  need 4.5  vs surface.background
  sudoku      text.tertiary      default dark  KNOWN   3.89:1  need 4.5  vs surface.primary
  sudoku      status.warning     default light KNOWN   4.44:1  need 4.5  vs surface.primary
  minesweeper text.tertiary      default light KNOWN   3.10:1  need 4.5  vs surface.background
  minesweeper text.tertiary      default dark  KNOWN   3.93:1  need 4.5  vs surface.primary
  minesweeper status.warning     default light KNOWN   2.93:1  need 4.5  vs surface.primary

RESULT: PASS — 6 known exceptions still apply (see EXCEPTIONS)
```

**怎麼讀這兩段:**

- `KNOWN` 是**現況既有債**(shipping token 就是這個值),不是本設計新引入的;IC 層(§5.2/5.3)
  的新值全部通過,所以沒有出現在清單裡。例外一旦被修好、變成通過,腳本會判 `STALE` 並**失敗** ——
  例外清單不會靜靜地爛掉。
- `NOT YET ANCHORED` 的 9 條逐條說明見 §9.3;它們**不擋設計定稿**,擋的是 spec PR 的完成。
- 兩支腳本都 stdlib-only、可從 repo 根目錄直接跑、失敗回非零 —— 可以直接進 CI。

---

## 附錄 B:計算與查證方法

**對比度:** WCAG 2.x 相對亮度公式,從 token 原始 hex 實算,不四捨五入。

⚠️ **方法論更正:前一版宣稱「一律對兩個 surface 取較差者」,但實際數字混用了不同基準。**
r2 改採 **per-token 目標 surface**:每個 token 對「它實際畫在哪個 surface」計算。對照表如下,
**它是方法論契約,已固化成 `scripts/design/contrast.py` 的 `TARGETS` 表** —— §11 的「腳本自動驗收」要成立就得靠它。

| Token | 角色 | 目標 surface | 為什麼 |
|---|---|---|---|
| `text.primary/secondary/tertiary` | 文字 | **兩者較差** | 卡片內文與 streak 列都會出現 |
| `accent.primary` | 填色 | **承載 ink** | 判定的是白字 / 深底 ink 落在它上面 |
| `identity.tier1-3` | 非文字 | **surface.primary** | 難度 pip 只畫在卡片上 |
| `thumb.*` | 非文字 | **surface.primary** | 縮圖空格就是 surface.primary |
| `streak.pipOff` | 非文字描邊 | **surface.background** | streak 列直接坐在背景上 |
| `status.*` | 文字 | **surface.primary** | 只作為卡片內的狀態文字 |
| `accent.celebratory` | 非文字(光暈) | **surface.background** | 光暈鋪在盤面/背景上 |

門檻:文字 預設 ≥4.5 / **IC ≥7.0**;非文字 預設 ≥3.0 / **IC ≥4.5**;多階 ramp 相鄰 ≥1.5。
腳本:落 repo 的是 `scripts/design/contrast.py`(132 項檢查 + 6 條既有債例外 + 例外過期偵測);
設計期推導用的 `ic.py` / `ic2.py` / `ic3.py` 是草稿工具,結論已固化,不落 repo。

**格徑:** 以裝置點寬度實算,扣除外框。

**契約條數:** `scripts/design/contracts.py` 逐列 parse 兩份 canonical 文件
(`docs/screen-contracts.md` 的 `## slug` 段落、`docs/navigation-flows.md` 的 `| S/M/N<n> |` 列),
並區分「邏輯條數」與「錨點列數」(§9.3)。輸出見附錄 A。

**HIG 引文:** 第一順位為 owner 指定的 *Adopting Liquid Glass*(Technology Overviews,全文讀畢);
次順位為本機語料 `~/.claude/skills/hig/*.md`(標行號);未下載頁面經 DocC JSON endpoint
(`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`)取得。
**所有引文逐字未改寫。**
