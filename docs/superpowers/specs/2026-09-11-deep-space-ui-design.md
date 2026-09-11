# PhemeMurmur — Deep Space 視覺改版設計

日期：2026-09-11
狀態：待實作

## 目標

替 PhemeMurmur 建立一套統一的「深空科技感」視覺語言，套用到 App Icon 與三個使用者介面：設定視窗、錄音監聽回饋、Onboarding。

現況問題：

- App Icon 只是把 🗣️ emoji 渲染成 icns（`scripts/generate_icon.swift`），沒有設計可言。
- 所有設定藏在 menu bar 的多層子選單（Provider / Prompt / Hotkey / Config & Logs），API Key 用 `NSAlert` 彈窗輸入。
- 錄音中唯一的回饋是 menu bar icon 變色，使用者視線在螢幕中央時幾乎看不到。
- Onboarding 是手刻 frame 的三頁 emoji 導覽，且不檢查權限是否真的授予。

## 非目標

- 不更動錄音、轉錄、貼上的核心邏輯（`AudioRecorder`、`TranscriptionService`、各 Provider、`PasteService`、`HotkeyManager`）。
- 不引入第三方套件。維持零依賴。
- 不做淺色主題。深空視覺在淺色桌布上一樣成立，不隨系統外觀切換配色。

## 1. 視覺語言（Deep Space）

單一色票，icon 與 UI 共用，定義在 `Sources/PhemeMurmur/UI/DeepSpace.swift`。

| Token | 值 | 用途 |
|---|---|---|
| `spaceVoid` | `#080B1A` → `#0E1230` 徑向漸層 | icon 底、面板底 |
| `auroraCyan` | `#3DE8FF` | 主強調、波形高點、錄音中 |
| `auroraViolet` | `#7B5CFF` | 漸層另一端、選中態 |
| `nebulaPink` | `#FF6EC7` | 極少量重點（脈衝尾端、REC 指示） |
| `starDust` | `#9AA4C8` | 次要文字、分隔線 |

三個共用構件：

1. **深空徑向底** — 中心略亮的暗藍紫，不是平塗黑。
2. **星塵粒子** — 極低透明度亮點，靜態不動畫（省電）；icon 內用固定座標。
3. **軌道弧** — 青→紫漸層細弧，末端淡出。在 icon 上是靜態裝飾，在錄音面板上會旋轉。

所有面板：無標題列、圓角、`.ultraThinMaterial` 之上疊深空漸層、外緣柔光，不做成傳統視窗外觀。

## 2. App Icon — Aurora Waveform（方案 A）

- macOS squircle 底（圓角半徑 = 邊長 × 0.2237），填深空徑向漸層。
- 中央 5 條圓角聲波豎條，高度 `低-中-高-中-低` 對稱，填青→紫縱向漸層並帶外發光。
- 波形下方一道水平光暈帶（地平線輝光）。
- 右側一道軌道弧（自右上繞至右下，末端淡出）+ 4 顆星塵點。
- **小尺寸降級**：≤ 32px 時省略星塵與軌道弧，只留底色與波形；光暈減弱，避免糊成一團。

實作：改寫 `scripts/generate_icon.swift` 為純 Core Graphics 程式化繪製，`make icon` 行為不變（產生 10 種尺寸 → `iconutil` → `Resources/AppIcon.icns`）。

波形的路徑計算抽成 `Sources/PhemeMurmur/UI/WaveformShape.swift`，供 menu bar template icon 與錄音面板共用，確保三處造型一致。

menu bar icon 同步換掉現行的 SF Symbol：idle 用同一組 5 條波形的 template image；錄音中與轉錄中維持現有的變色邏輯（`updateIcon()`）。

## 3. 設定視窗 — 側邊欄五分頁

取代現行的多層子選單。SwiftUI 實作，由 `SettingsWindowController` 以 `NSHostingView` 承載。

- 無標題列（`titlebarAppearsTransparent` + `.fullSizeContentView`），保留可拖曳移動。
- 左側導覽 152pt，選中項以青紫漸層底 + 內描邊表示。

| 分頁 | 內容 |
|---|---|
| 轉錄服務 | 供應商清單（OpenAI / Gemini / Apple / 自訂）、使用中標記、API Key 欄位（取代 `NSAlert`） |
| 快捷鍵 | 從 `HotkeyKey` 清單選擇 |
| 提示模板 | 模板清單與切換 |
| 一般 | 登入時啟動、語音指令（`voice-commands`）、靜音門檻（`silence-threshold`）、前綴詞（`prefix`） |
| 診斷 | 開啟設定檔資料夾、錯誤記錄、版本與 commit hash |

menu bar 選單同步瘦身為：狀態列 → 開始／停止錄音 → 設定… → 結束。

資料來源仍是 `Config`；設定視窗只讀寫既有的 config API，不新增儲存機制。

## 4. 錄音監聽面板 — G5 日冕光束

浮在螢幕底部中央的 `NSPanel`（`.nonactivatingPanel`、`level = .statusBar`、`ignoresMouseEvents = true`、`collectionBehavior` 含 `.canJoinAllSpaces`），不搶焦點、不接受點擊。停止錄音仍靠快捷鍵。

組成（SwiftUI `Canvas` 單一元件 `NebulaHUDView`）：

- **星雲球核心** — 徑向漸層球體，內部一層旋轉的 conic 極光；音量驅動脹縮與亮度。
- **日冕光束** — 15 道自球體向外放射的模糊光束，各自由一段即時音訊的 RMS 驅動長度與透明度；無硬邊。（採時間分段 RMS 而非頻譜分析，避免引入 FFT。）
- **軌道環** — 一道反向緩慢旋轉的細環。
- **狀態膠囊** — 球體下方一枚獨立的小圓角膠囊：`● LISTENING · 0:07 · ESC`。

狀態轉換：

| 狀態 | 表現 |
|---|---|
| 錄音中 | 球體青紫呼吸，光束隨音量吞吐，膠囊顯示計時與 ESC |
| 轉錄中 | 球體轉深紫，光束收斂為穩定微光，環加速旋轉，膠囊顯示供應商名稱 |
| 完成 | 環收束進球體、閃一下青光，整體淡出（停留約 1.2s） |
| 錯誤 | 球體轉橙紅、膠囊顯示錯誤摘要，停留 3s |

進出動畫：由下往上滑入約 0.22s 帶輕微彈性，離場淡出。

**音量來源**：`AudioRecorder` 既有的 `AVAudioEngine` tap 已逐 buffer 取得 PCM，新增一個 `onLevel: ([Float]) -> Void` callback，在 tap 內把 buffer 切成 15 段各算 RMS 後回拋（節流至 ~30Hz）。錄音與轉檔路徑不受影響。

## 5. Onboarding — O2 沉浸式單欄

同樣是無標題列的浮動深空面板，SwiftUI 實作，取代現行 `OnboardingWindow` 的手刻 frame 版本。

- 大留白置中、星塵背景，中央一顆迷你星雲球（與錄音面板共用 `NebulaHUDView` 的靜態模式）。
- 底部一排進度點 + 主按鈕。

四頁：

1. **歡迎** — 一句話說明用途。
2. **權限** — 輔助使用與麥克風兩項，各自即時顯示授權狀態，未授權時點擊直接開對應的系統設定分頁。
3. **轉錄服務** — 選供應商並填 API Key（面板內輸入，不再彈 `NSAlert`）。
4. **試錄一次** — 引導按一次快捷鍵，成功走完一輪就完成。

**權限輪詢**：沿用 `pollForAccessibility()` 現有機制，擴充為同時檢查 `AVCaptureDevice.authorizationStatus(for: .audio)`，授權後自動打勾並可前進。

完成條件與現行一致：寫入 `~/.config/pheme-murmur/.onboarding-done`。

## 6. 架構與檔案

新增 `Sources/PhemeMurmur/UI/`：

| 檔案 | 職責 |
|---|---|
| `DeepSpace.swift` | 色票、漸層、材質、共用修飾子 |
| `WaveformGeometry.swift` | 5 條波形的幾何計算（icon / menu bar / HUD 共用） |
| `MenuBarIcon.swift` | menu bar 待命狀態的 template image |
| `AudioLevelMeter.swift` | PCM → 15 段 RMS |
| `FloatingPanel.swift` | 無標題列圓角浮動面板的 `NSPanel` 子類 |
| `HUDPhase.swift` | HUD 四種狀態與其呈現參數 |
| `NebulaHUDView.swift` | 星雲球 + 日冕光束 + 軌道環 + 狀態膠囊 |
| `RecordingHUDController.swift` | HUD 的生命週期、定位、狀態轉換 |
| `SettingsTab.swift` | 五個分頁的標題與圖示 |
| `SettingsStore.swift` | SwiftUI 與 `Config` 之間的讀寫橋接 |
| `SettingsView.swift` | 側邊欄五分頁 |
| `SettingsWindowController.swift` | 設定視窗承載與單例管理 |
| `OnboardingFlow.swift` | 四頁的文案與前進條件 |
| `OnboardingView.swift` | 四頁沉浸式導覽 |
| `PermissionStatus.swift` | 輔助使用與麥克風權限的查詢與輪詢 |

修改：

- `main.swift` — 選單瘦身、串接設定視窗與 HUD；移除 `runAPIKeyPrompt` 的 `NSAlert` 路徑與 `rebuild*Submenu` 系列。預期由 729 行降到 400 行以內。
- `AudioRecorder.swift` — 新增 level callback。
- `OnboardingWindow.swift` — 內容改為 `NSHostingView`，保留完成標記邏輯。
- `scripts/generate_icon.swift` — 改為 Core Graphics 繪製。

技術基礎：SwiftUI + `NSHostingView`；menu bar、hotkey、錄音核心維持 AppKit。`Package.swift` 已是 `.macOS(.v13)`，所有用到的 API 皆在此基準內，不需調整。

## 7. 測試策略

現有 `Tests/PhemeMurmurTests` 為單元測試，UI 本身不做自動化測試。

- **單元測試**：`WaveformShape` 的路徑計算在各尺寸下的輸出、`AudioRecorder` level callback 的分頻段 RMS 計算、`PermissionStatus` 的狀態映射。
- **人工驗收**：`make install` 後逐項確認 —— icon 在 Finder / Dock / menu bar 三處尺寸皆清晰；錄音 HUD 不搶焦點且點擊穿透；設定五分頁讀寫 config 正確；刪除 `.onboarding-done` 後 Onboarding 四頁走得完且權限即時打勾。

## 8. 實作順序

1. 視覺基礎：`DeepSpace.swift` + `WaveformShape.swift`
2. App Icon（`generate_icon.swift` 重寫）+ menu bar template icon
3. 錄音 HUD（含 `AudioRecorder` level callback）
4. 設定視窗 + menu bar 選單瘦身
5. Onboarding
6. README 更新

每一步可獨立驗收，順序上前一步是後一步的依賴。
