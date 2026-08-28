local base = hs.configdir .. "/discord-voice-hotkey"
package.path = base .. "/?.lua;" .. package.path

local Recorder = require("recorder")

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new()
  local self = setmetatable({}, Runtime)
  self.recordScript = base .. "/record.sh"
  self.cacheDir = os.getenv("HOME") .. "/Library/Caches/DiscordVoiceHotkey"
  self.now = hs.timer.secondsSinceEpoch()
  hs.fs.mkdir(self.cacheDir)
  return self
end

function Runtime:show(message)
  hs.alert.closeAll(0)
  hs.alert.show(message, 1.2)
end

function Runtime:saveClipboard()
  self.now = hs.timer.secondsSinceEpoch()
  local name = hs.pasteboard.uniquePasteboard()
  local data = hs.pasteboard.readAllData()
  local hadData = data ~= nil
  if hadData then hs.pasteboard.writeAllData(name, data) end
  return { name = name, hadData = hadData }
end

function Runtime:restoreClipboard(saved)
  if not saved then return end
  if saved.hadData then
    local data = hs.pasteboard.readAllData(saved.name)
    if data then hs.pasteboard.writeAllData(nil, data) end
  else
    hs.pasteboard.clearContents()
  end
  hs.pasteboard.deletePasteboard(saved.name)
end

function Runtime:getFrontApp()
  return hs.application.frontmostApplication()
end

function Runtime:makeOutputPath()
  local stamp = os.date("%Y%m%d-%H%M%S")
  local suffix = tostring(math.random(1000, 9999))
  return self.cacheDir .. "/voice-" .. stamp .. "-" .. suffix .. ".mp3"
end

function Runtime:startRecording(path, callback)
  local task = hs.task.new(self.recordScript, callback, { path })
  if not task then return nil end
  if not task:start() then return nil end
  return task
end

function Runtime:elapsed(startedAt)
  return hs.timer.secondsSinceEpoch() - startedAt
end

function Runtime:deleteFile(path)
  os.remove(path)
end

function Runtime:fileUsable(path)
  local size = hs.fs.attributes(path, "size")
  return type(size) == "number" and size > 512
end

function Runtime:activate(app)
  if app then app:activate(true) end
end

function Runtime:pasteFile(path)
  -- Give Electron time to restore the original Discord text field focus.
  hs.timer.usleep(250000)
  local escaped = path:gsub("\\", "\\\\"):gsub('"', '\\"')
  local ok = hs.osascript.applescript('set the clipboard to POSIX file "' .. escaped .. '"')
  if not ok then
    return nil
  end
  local changeCount = hs.pasteboard.changeCount()
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  return changeCount
end

function Runtime:restoreLater(saved, expectedChangeCount)
  hs.timer.doAfter(1.5, function()
    -- Restore only if nothing newer was copied during the upload delay.
    if hs.pasteboard.changeCount() == expectedChangeCount then
      self:restoreClipboard(saved)
    else
      hs.pasteboard.deletePasteboard(saved.name)
      self:show("偵測到新的剪貼簿內容，因此沒有覆蓋它")
    end
  end)
end

function Runtime:cleanupLater(path)
  hs.timer.doAfter(1800, function() os.remove(path) end)
end

local runtime = Runtime.new()
local recorder = Recorder.new(runtime)
local hotkey = hs.hotkey.bind({ "ctrl", "alt" }, "R", function()
  recorder:toggle()
end)

hs.notify.new({
  title = "Discord Voice Hotkey",
  informativeText = "⌃⌥R：開始／停止錄音",
}):send()

return {
  recorder = recorder,
  hotkey = hotkey,
  runtime = runtime,
}
