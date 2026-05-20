# 2026-05-20 — Phase 10 Operational Rollout

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader 主導 + 使用者執行 Apple Developer 後台操作).

## Goal

完成 plan.md Phase 10 — 把 v1 程式碼層（Phase 0–9）推上 App Store。Phase 10 大量步驟需要 Apple Developer 帳號操作，無法純 subagent 自動化；Leader 角色變為流程追蹤 + 自動化輔助（ASCRegister CLI）+ 文件同步。

## Progress tracker

| 步驟 | 內容 | 負責 | 狀態 |
|---|---|---|---|
| A1 | App Store Connect 後台註冊 `com.wei18.sudoku` bundle ID + iOS app record + Mac app record | User | ✓ 2026-05-20 |
| A2 | 申請 ASC API key（Users & Access → Integrations → ASC API → Keys）取得 `.p8` + Key ID + Issuer ID | User | ⏳ |
| A3 | CloudKit container `iCloud.com.wei18.sudoku` 啟用 Private + Public scope | User | ✓ 2026-05-20 |
| A4 | Xcode Cloud workflows（PR / Main / Release）在 ASC Connect tab 設定 | User | ⏳ |
| A5 | 手動 archive + TestFlight upload（不等 Xcode Cloud）作為第一個 build | User | ⏳ |
| A6 | iPhone + Mac 真機 sandbox GameCenter + CloudKit 端到端驗證 | User（需 TestFlight 安裝） | ⏳ |
| A7 | App Store 商店素材（描述 / 截圖 / what's new × 7 locales）| User（需內容創作）| ⏳ |
| A8 | 送 App Store 審核 | User | ⏳ |

## Decisions（今日記錄）

1. **CloudKit `userZone` 是 lazy-provisioned**：A3 完成的是 container 與 database scope 啟用，實際的 `com.wei18.sudoku.userZone` zone 由 app 首次寫入時由 `SubscriptionInstaller`（見 `Packages/SudokuKit/Sources/Persistence/Live/SubscriptionInstaller.swift`）自動建立。Dashboard 在 A6 之前看不到 zone 是正常現象，不是錯誤。
2. **Public DB 在 v1 不用**：A3 雖然啟用了 Public scope，但 v1 沒有 Public record type；保留給 v2 `PuzzleOverride`（見 `design.md §不在 v1 範圍`）。
3. **A2 與 A5 可平行**：ASC API key 申請（A2）與手動 archive（A5）互相獨立；A5 不依賴 A2，A2 不依賴 A5。順序由使用者偏好決定。
4. **A4 Xcode Cloud 不阻塞 A5/A6**：第一個 TestFlight build 可走手動 archive（A5），不必先等 Xcode Cloud workflows 設定完成。Xcode Cloud 在 A5 後做也行，價值在「之後 PR / main 自動 build」。

## §未決問題

- A2 申請後是否要把 `.p8` 放到 1Password / 之類的 vault？目前規劃：放本機固定路徑（如 `~/.config/sudoku/AuthKey_XXX.p8`），透過 env var `ASC_PRIVATE_KEY_PATH` 指向，gitignored。CI 端透過 Xcode Cloud env var 注入。需 user 確認 vault 偏好。
- A7 截圖 7 locales 是否要自動化？SudokuUI 已有 25 PNG snapshot baselines 但解析度不符 App Store 規格（iPhone 6.5"/6.7" + iPad Pro 12.9" + Mac）；考慮另開 snapshot 規格層或手動截圖。決策延後到 A6 之後。

## §下一步

User 選一個推進：
1. A2 ASC API key — 取得後 Leader 協助跑 ASCRegister plan/apply
2. A4 Xcode Cloud — 一次設定好 PR / Main / Release workflows
3. A5 手動 archive + TestFlight — 拿到第一個可裝 build
