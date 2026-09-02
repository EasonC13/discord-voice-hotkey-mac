# 優化 Hermes Agent 語音控制

Discord Voice Hotkey v2.3.1 會送出 Ogg 容器中的單聲道 Opus。這能避開我們在 M4A 上實際遇到的 `video/mp4` MIME 誤判，讓語音轉文字系統收到精簡且明確的音訊格式。

本文記錄維護者實測的 Hermes Agent 工作流程。下列 dual-pass gateway 設定屬於**實驗性 Hermes 整合**，不代表所有 upstream Hermes 版本都已原生支援。

## 為什麼使用 Ogg／Opus

舊版 M4A／AAC 從 Discord 送出後，可能被標記成 `video/mp4`，導致部分 Hermes gateway 將它當成影片或一般文件保存，而沒有自動執行 STT。Discord 也可能將貼上的 Ogg 改名為 `audio_<content-hash>.ogg`，因此 gateway 整合應同時辨識原生 voice note 與這個範圍明確的 hashed-Ogg 格式。

App 目前透過 AVFoundation 錄音，使用 macOS 內建的 `afconvert` 轉碼，再由本機程式將 Opus packets 封裝成符合標準的 Ogg。整個流程不需要 FFmpeg、Homebrew、網路服務或雲端 encoder。

## 兼顧準確度與延遲

較小的 Whisper 模型比較快，但不能未經同意取代使用者已驗證準確度的模型。我們實測的設計採 optimistic dual pass：

1. `small` 先產生**暫定逐字稿**，讓 Hermes 可以立即開始可逆工作。
2. 已經驗證過的 `large-v3` 保持**權威模型**，並在受追蹤的背景 verifier 中執行。
3. 標點、空格、語助詞或同義改寫若不改變意思，完全靜默。
4. 否定、數量、姓名、environment、requested action、路徑、ID 或安全事實若出現實質差異，只產生一次修正。
5. 不重寫既有對話歷史；修正必須 append-only 且綁定正確 session。

在維護者主機上，一段真實的 4.93 秒 Ogg 測試結果如下：

| Pass | 時間 | 結果 |
|---|---:|---|
| `small` 暫定轉錄 | 1.993 秒 | 正確辨識繁體中文意思 |
| `large-v3` 權威轉錄 | 7.134 秒 | 語意一致 |
| Verifier 決定 | — | `matched`；零 correction calls |

若故意提供錯誤的 provisional transcript，同一段真實音訊會得到 `corrected`，而且只注入一次 active-turn correction。

### 重要失敗模式

另一段短音訊中，small model 將設定的 `initial_prompt` 重複當成使用者說話內容；large-v3 則正確恢復真正請求。因此，重複 prompt 文字應視為 verification failure signal，而不是有效語音內容。這也是 large-v3 必須維持權威性的原因。

## 本機設定範例

維護者的整合會讀取以下選用設定：

```yaml
stt:
  provider: local
  language: en                 # 保留既有的權威模型設定
  local:
    model: large-v3            # 權威模型，不可靜默降級
    unload_after_idle_seconds: 0
    dual_pass:
      enabled: true
      fast_model: small
      fast_language: zh        # 與權威模型的語言提示獨立
      similarity_threshold: 0.72
```

若 Hermes schema 尚未認得 `stt.local.dual_pass`，`hermes config set` 可能警告它是 custom key。單純保存這些設定並不會自動新增功能；gateway 必須包含相容的 dual-pass 整合。

## Gateway 整合必須維持的條件

正確實作應符合：

- fresh、busy-steer、interrupt-monitor 與 pending-drain 共用同一個 event-level STT cache；
- 每個 media snapshot 最多排程一次權威轉錄；
- media merge、reset 或 session generation 改變後，取消或淘汰舊 verifier；
- verifier task 必須納入 gateway background-task tracking；
- 語意一致時完全靜默；
- queued event cache 更新為權威逐字稿；
- 只向正確 active turn 注入一次修正；turn 已結束時，最多排一個 internal correction turn；
- 保持嚴格 message-role alternation 與 prompt-cache history；
- 若在意 reload latency，fast 與 authoritative models 應使用分離的 model cache。

## 副作用安全

從 provisional text 開始讀取、搜尋、分析與撰寫草稿是安全的。如果 effect-capable tools 可能在驗證完成前執行，應加入 just-in-time `pre_tool_call` gate：

- 已知 read-only tools 立即執行；
- effect-capable tools 等待共用 verification result；
- 語意一致即放行；
- discrepancy、failure、timeout 或 stale ownership 一律 fail-closed；
- 未知工具、terminal、browser interaction、file write、message 與 external-service tools 預設視為可能有副作用。

這比只依賴 approval prompt 更安全，因為 permissive mode 可能略過 approval，但不應略過 hook block。

## 隨附的 Hermes skill

Repository 內包含維護者版本的 `voice-message-transcription` skill：

```text
integrations/hermes-agent/skills/voice-message-transcription/
```

內容涵蓋 attachment recovery、逐字稿優先回覆、confidence gate、dual-pass verification、correction policy 與長錄音處理。

複製 skill 只會加入程序指引，**不會**自動修改舊版 Hermes gateway runtime。Runtime patch 必須依實際使用的 Hermes 版本重新 review 與測試。

## 驗證清單

本機 Hermes 整合已完成：

- 114 個 gateway／STT focused regression tests 全部通過；
- 真實 Ogg matched path：零 steer、零額外 turn；
- 真實 Ogg 錯誤 provisional path：一次權威 correction；
- Discord hashed Ogg 辨識；
- fast pass 獨立 language override；
- large-v3 仍是權威設定模型。

正式部署前還應另外測試 concurrent sessions、media-merge invalidation、`/reset` 後的 stale generation、model-cache memory pressure 與 side-effect gate。
