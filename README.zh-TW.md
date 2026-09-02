# Discord Voice Hotkey for macOS

[English](README.md) | **繁體中文**

[![Build macOS DMG](https://github.com/EasonC13/discord-voice-hotkey-mac/actions/workflows/build-dmg.yml/badge.svg)](https://github.com/EasonC13/discord-voice-hotkey-mac/actions/workflows/build-dmg.yml)

原生 macOS 選單列 App，可快速錄音，並將語音檔案貼到 Discord 或其他支援貼上檔案的 App。

## 下載

請從 [GitHub Releases](https://github.com/EasonC13/discord-voice-hotkey-mac/releases/latest) 下載最新版 DMG。

## 安裝

1. 開啟 `Discord-Voice-Hotkey-*.dmg`。
2. 將 **Discord Voice Hotkey.app** 拖入 **Applications** 捷徑。
3. 從「應用程式」開啟 App。
   - 發布版採用 ad-hoc 簽署，但未經 Apple 公證。第一次啟動時，可能需要對 App 按右鍵並選擇「打開」。
4. macOS 詢問時，允許使用**麥克風**與**輔助使用**權限。

不需要安裝 Homebrew、Hammerspoon、FFmpeg，也不需要在背景執行終端機程序。

## 使用方式

1. 啟動 App，並讓麥克風圖示留在 macOS 選單列。
2. 將游標放在 Discord 訊息輸入框中。
3. 按一次 `Control + R` 開始錄音。
4. 再按一次即可停止錄音、貼上語音附件，並在 0.2 秒後自動送出。

自動送出功能預設開啟。如果只想先貼上附件、不立即送出，可在選單列取消勾選 **Send Automatically After Paste (0.2s)**。為避免誤送，若 0.2 秒內焦點曾離開原本的 App，程式就不會按下 Enter。

App 先透過 AVFoundation 錄音，再使用 macOS 內建的 `afconvert` 與本機 Ogg 封裝器，送出 **`.ogg` 容器中的 Opus 音訊**。因此 Discord 與支援 Hermes 的 Agent 會收到明確的 `audio/ogg` 附件，不需要安裝 Homebrew 或 FFmpeg。若 macOS 無法完成轉換，App 會保留並送出原始 `.m4a`，避免語音遺失。

### 自訂快捷鍵

點選選單列圖示，再選擇 **Change Shortcut…**，接著按下包含至少一個修飾鍵的任意快捷鍵。新快捷鍵會立即生效，並在重新啟動 App 後保留。更新 App 不會覆蓋你已自訂的快捷鍵。

### 剪貼簿行為

開始錄音前，App 會保存目前的剪貼簿內容。貼上語音檔案後，約 1.5 秒會恢復原本內容。如果你在這段期間複製了新內容，App 會保留新的剪貼簿，不會將它覆蓋。

短於 0.5 秒的錄音會取消。暫存錄音會在 30 分鐘後刪除。

## 搭配 Hermes Agent 使用

這個 App 負責錄音並送出語音檔案。[Hermes Agent](https://github.com/NousResearch/hermes-agent) 可以自動轉錄 Discord 語音附件，並將逐字稿視為一般訊息交給 Agent 處理。

若要了解維護者實測的低延遲流程，包括 fast provisional STT、背景 `large-v3` 核實、語意一致時靜默、只在實質差異時修正、副作用安全與可重用 Hermes skill，請參考 **[優化 Hermes Agent 語音控制](docs/hermes-agent-dual-pass-stt.zh-TW.md)**。

### 推薦的語音轉文字引擎

我們首選並推薦使用本機的 **faster-whisper**。語音會留在執行 Hermes 的主機上，不需要 API key，也不必交給雲端轉錄服務。這也是本專案維護者目前實際採用的設定，使用 `large-v3` 模型來提升繁體中文、英文及中英混合語音的辨識準確度：

```bash
hermes config set stt.enabled true
hermes config set stt.provider local
hermes config set stt.local.model large-v3
```

模型會在 Hermes 主機上執行，該主機可以是你的 Mac，也可以是另一台伺服器。如果 `large-v3` 對目前硬體太慢或太占記憶體，可依序改用 `medium`、`small` 或 `base`。

如果 Hermes 主機無法順暢執行本機模型，或你更重視最低延遲，才建議將 **Groq Whisper API** 當作選用的雲端備援。透過 Hermes 設定加入 `GROQ_API_KEY` 後，選擇 Groq：

```bash
hermes config set stt.enabled true
hermes config set stt.provider groq
```

可執行 `hermes tools` 安裝或設定語音相依套件與憑證。完整支援清單，包括 OpenAI、Mistral、xAI、ElevenLabs 與 DeepInfra，請參考官方的 [Hermes Voice & TTS 文件](https://hermes-agent.nousresearch.com/docs/user-guide/features/tts)。

## 權限

- **麥克風**：透過 AVFoundation 錄音。
- **輔助使用**：向開始錄音時所在的 App 傳送 `Command + V`。

選單列選單會顯示兩項權限的目前狀態，並提供前往相關「系統設定」頁面的連結。

## 系統需求

- macOS 13 Ventura 或更新版本
- Apple Silicon，或 GitHub macOS universal build 環境支援的 Intel Mac

## 在本機建置

```bash
swift test
scripts/build-dmg.sh dev
scripts/smoke-test-app.sh
```

建置腳本會：

- 編譯 release 版 Swift 執行檔
- 建立真正的 `.app` bundle
- 執行 ad-hoc 程式碼簽署與嚴格簽章驗證
- 使用 `hdiutil` 建立並驗證 DMG
- 產生可攜式 SHA-256 校驗檔

## 架構

- **AppKit** 選單列應用程式
- **Carbon** 全域快捷鍵註冊
- **AVFoundation** 原生錄音，透過內建 `afconvert` 轉為 Opus
- **本機 Ogg 封裝器**：不使用 FFmpeg 或網路服務即可封裝 Opus packets
- **NSPasteboard** 剪貼簿保存、檔案貼上與恢復
- **Core Graphics** 在取得輔助使用授權後模擬 `Command + V`
- **Swift Package Manager** 建置與 XCTest 測試套件

## 授權

MIT
