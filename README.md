# MenuHide 隨手藏

Tucks menu bar icons out of sight on macOS. Click its button to show or hide them, and choose which icons hide, which always show, and in what order — apps' and Apple's alike.

在 macOS 選單列隱藏圖示，按一下就能顯示或隱藏；哪些要藏、哪些一直顯示、怎麼排，App 和系統的圖示都能設定。[中文說明在下方](#中文說明)。

## How it works

MenuHide adds two items to the menu bar: a button (‹ / ›) and a thin divider ( | ). The menu bar is laid out like this, left to right:

```
[hidden apps' icons][hidden Apple icons] | [always-shown apps' icons] ‹ [always-shown Apple icons] Control Center  Clock
```

- **Click the button** to hide or show everything left of the divider. Hidden icons go into macOS's own « menu, so they're still a click away.
- **Right-click the button** for Arrange Icons…, the language, Open at Login and Quit.
- **The button stays between the apps' icons and Apple's.** When an app's icon lands right of it (a newly opened app, say), or one of Apple's lands left of it, MenuHide moves that icon back across. It checks at launch, whenever an app opens or quits, and after arranging.

## Features

- **Arrange Icons…** lists the icons in two groups, Hidden and Always Shown, left to right as on the menu bar. Drag a row to reorder it or into the other group, or tick Always Show. **Apply to Menu Bar** ⌘-drags each icon into place, as you would by hand; it takes a few seconds to half a minute, so leave the mouse alone while it works.
- **Apple's icons too**: Wi-Fi, Sound, Bluetooth, Battery, the input menu, Now Playing and the rest can be ordered and hidden like any app's. They're recognized by the system's own names for them, so they stay recognized after moving.
- **New icons stay visible**: an icon MenuHide hasn't seen before starts out always shown, so nothing disappears unasked.
- **Accessibility access**: reading and moving other apps' icons needs it. MenuHide asks at launch until it's allowed; without it, hiding and showing still work, but nothing can be arranged.
- **Traditional Chinese / Simplified Chinese / English UI**, switchable from the right-click menu, and an option to open at login.

| Action | How |
|---|---|
| Show or hide icons | Click the button |
| Arrange Icons…, language, quit | Right-click the button |
| Apply the arrangement | Arrange Icons… → Apply to Menu Bar (Return) |

## Limits

These come from how macOS 27 runs the menu bar; there's no way around them for an app.

- **The « menu stays.** macOS hides an icon only by moving it into its « menu when it doesn't fit, so « shows whenever anything is hidden. The only hiding without « is turning an app off under System Settings → Menu Bar, which apps can't change.
- **Hidden icons can only be left of the divider.** macOS takes an icon that doesn't fit *and everything left of it* into «, so the hidden ones must be the leftmost.
- **The clock and Control Center can't move**, so they aren't listed; they stay at the right end.
- **Icons turned off in System Settings** (Allow in the Menu Bar) can't be moved, and aren't listed.
- **Arranging moves the mouse**: macOS has no way to move another app's icon except ⌘-dragging it, so that's what MenuHide does.

## Install

Requires macOS 13 or later (developed and tested on macOS 27), and Xcode or the Command Line Tools (`xcode-select --install`).

```sh
./build.sh install   # builds and installs /Applications/隨手藏.app
```

Run `./build.sh` alone to build into `build/隨手藏.app` without installing.

**Signing.** macOS grants Accessibility access to an app by its signature. An ad-hoc signature changes with every build, which loses the access each time, so `build.sh` signs with a certificate named **MenuHide Local Signing** when the keychain has one. To make it: Keychain Access → Certificate Assistant → Create a Certificate…, name it `MenuHide Local Signing`, Identity Type *Self-Signed Root*, Certificate Type *Code Signing*. Without it the build is signed ad hoc, and access has to be granted again after each build.

---

## 中文說明

隨手藏在選單列放兩個項目：一個按鈕（‹ / ›）和一條細分隔線（ | ）。選單列由左到右是：

```
[可藏的 App][可藏的系統圖示] | [一直顯示的 App] ‹ [一直顯示的系統圖示] 控制中心 時鐘
```

- **按一下按鈕**：隱藏或顯示分隔線左邊的所有圖示。被藏的圖示會收進 macOS 自己的「«」選單，點「«」也看得到。
- **右鍵按鈕**：「排序與設定…」、語言、登入時自動開啟、結束。
- **按鈕固定在 App 和系統圖示之間**：App 的圖示跑到按鈕右邊（例如剛開啟的 App），或系統圖示跑到按鈕左邊時，隨手藏會把它移回去。隨手藏啟動時、有 App 開啟或結束時，以及套用排序後，都會檢查一次。

### 功能

- **排序與設定**：清單分「隱藏」和「一直顯示」兩區，由左到右對應選單列的順序。拖曳可以調整順序或移到另一區，也可以勾「一直顯示」。按「**套用到選單列**」後，隨手藏會像手動操作一樣用 ⌘ 拖曳把圖示一個個移到位，約幾秒到半分鐘，過程中請不要移動滑鼠。
- **系統圖示也能排、能藏**：Wi‑Fi、聲音、藍牙、電池、輸入法、播放中等，跟 App 圖示一樣可以排序和隱藏。隨手藏用系統內部的名稱辨認它們，移動後也不會認錯。
- **新圖示預設顯示**：沒看過的圖示一開始是「一直顯示」，不會一出現就被藏起來。
- **「輔助使用」權限**：讀取和移動其他 App 的圖示需要這個權限。還沒允許時，隨手藏每次開啟都會提醒；沒有權限時仍可顯示或隱藏，但無法排序。
- **繁體中文／简体中文／English 介面**，在右鍵選單切換；可設定登入時自動開啟。

| 動作 | 方式 |
|---|---|
| 顯示或隱藏圖示 | 按一下按鈕 |
| 排序與設定、語言、結束 | 右鍵按鈕 |
| 套用排序 | 排序與設定 →「套用到選單列」（Return） |

### 限制

以下是 macOS 27 選單列本身的運作方式，App 無法改變。

- **「«」會一直在**：macOS 只會把放不下的圖示收進「«」來隱藏，所以只要有圖示被藏，「«」就會出現。唯一不產生「«」的隱藏方式，是在「系統設定」→「選單列」裡關掉某個 App，這個設定 App 無法代為修改。
- **可藏的圖示只能在分隔線左邊**：macOS 會把放不下的圖示「和它左邊的全部」收進「«」，所以要藏的圖示必須排在最左邊。
- **時鐘和控制中心不能移動**，所以不列在清單裡，固定在最右邊。
- **在系統設定裡關掉顯示的圖示**（「允許在選單列顯示」）無法移動，也不列在清單裡。
- **排序時會用到滑鼠**：macOS 只能用 ⌘ 拖曳來移動其他 App 的圖示，隨手藏也只能這樣做。

### 安裝

需要 macOS 13 以上（在 macOS 27 上開發和測試），以及 Xcode 或 Command Line Tools（`xcode-select --install`）。

```sh
./build.sh install   # 編譯並安裝到 /Applications/隨手藏.app
```

只想編譯不安裝就執行 `./build.sh`，結果在 `build/隨手藏.app`。

**簽名**：macOS 依 App 的簽名記住「輔助使用」權限。臨時簽名（ad-hoc）每次編譯都會變，權限就會失效，所以鑰匙圈裡有名為 **MenuHide Local Signing** 的憑證時，`build.sh` 會改用它簽名。建立方式：「鑰匙圈存取」→「憑證輔助程式」→「製作憑證…」，名稱填 `MenuHide Local Signing`，身分類型選「自簽根憑證」，憑證類型選「程式碼簽署」。沒有這張憑證時會用臨時簽名，每次編譯後都要重新允許權限。

## License

[MIT](LICENSE) © 2026 Jeff Lee
