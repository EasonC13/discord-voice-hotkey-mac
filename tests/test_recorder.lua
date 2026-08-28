package.path = "./src/?.lua;" .. package.path

local Recorder = require("recorder")

local function assertEq(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function newFake()
  local f = {
    now = 100,
    clipboard = "original-rich-clipboard",
    frontApp = "Discord",
    events = {},
    callback = nil,
    pasteChangeCount = 20,
  }

  function f:saveClipboard()
    table.insert(self.events, "saveClipboard")
    return self.clipboard
  end
  function f:restoreClipboard(value)
    table.insert(self.events, "restoreClipboard:" .. tostring(value))
  end
  function f:getFrontApp() return self.frontApp end
  function f:makeOutputPath() return "/tmp/voice.mp3" end
  function f:startRecording(path, callback)
    table.insert(self.events, "start:" .. path)
    self.callback = callback
    return { terminate = function() table.insert(self.events, "terminate") end }
  end
  function f:show(message) table.insert(self.events, "show:" .. message) end
  function f:elapsed(startedAt) return self.now - startedAt end
  function f:deleteFile(path) table.insert(self.events, "delete:" .. path) end
  function f:fileUsable(path) return true end
  function f:activate(app) table.insert(self.events, "activate:" .. app) end
  function f:pasteFile(path)
    table.insert(self.events, "paste:" .. path)
    return self.pasteChangeCount
  end
  function f:restoreLater(saved, expectedChangeCount)
    table.insert(self.events, "restoreLater:" .. tostring(saved) .. ":" .. tostring(expectedChangeCount))
  end
  function f:cleanupLater(path) table.insert(self.events, "cleanupLater:" .. path) end

  return f
end

-- First toggle saves clipboard and starts recording.
do
  local f = newFake()
  local r = Recorder.new(f)
  r:toggle()
  assertEq(r:isRecording(), true, "first toggle should record")
  assertEq(f.events[1], "saveClipboard")
  assertEq(f.events[2], "start:/tmp/voice.mp3")
end

-- Second toggle stops; finalized audio is pasted and clipboard restoration is scheduled.
do
  local f = newFake()
  local r = Recorder.new(f)
  r:toggle()
  f.now = 103
  r:toggle()
  assertEq(r:isRecording(), false, "second toggle should stop")
  f.callback(0, "", "")
  local joined = table.concat(f.events, "|")
  assert(joined:find("terminate", 1, true), "recording task must terminate")
  assert(joined:find("activate:Discord", 1, true), "original app must reactivate")
  assert(joined:find("paste:/tmp/voice.mp3", 1, true), "MP3 must paste")
  assert(joined:find("restoreLater:original%-rich%-clipboard:20"), "clipboard restoration must be scheduled")
  assert(joined:find("cleanupLater:/tmp/voice.mp3", 1, true), "temporary MP3 cleanup must be scheduled")
end

-- Recordings shorter than 0.5 seconds are deleted and never pasted.
do
  local f = newFake()
  local r = Recorder.new(f)
  r:toggle()
  f.now = 100.2
  r:toggle()
  f.callback(0, "", "")
  local joined = table.concat(f.events, "|")
  assert(joined:find("delete:/tmp/voice.mp3", 1, true), "short recording must be deleted")
  assert(not joined:find("paste:/tmp/voice.mp3", 1, true), "short recording must not paste")
  assert(joined:find("restoreClipboard:original%-rich%-clipboard"), "clipboard must be restored on cancellation")
end

-- Failed/empty recording restores the clipboard and does not paste.
do
  local f = newFake()
  function f:fileUsable(path) return false end
  local r = Recorder.new(f)
  r:toggle()
  f.now = 102
  r:toggle()
  f.callback(1, "", "microphone denied")
  local joined = table.concat(f.events, "|")
  assert(not joined:find("paste:", 1, true), "failed recording must not paste")
  assert(joined:find("restoreClipboard:original%-rich%-clipboard"), "clipboard must restore after failure")
end

-- A pasteboard failure must restore immediately and must not claim success.
do
  local f = newFake()
  function f:pasteFile(path)
    table.insert(self.events, "pasteFailed:" .. path)
    return nil
  end
  local r = Recorder.new(f)
  r:toggle()
  f.now = 102
  r:toggle()
  f.callback(0, "", "")
  local joined = table.concat(f.events, "|")
  assert(joined:find("restoreClipboard:original%-rich%-clipboard"), "paste failure must restore clipboard")
  assert(joined:find("delete:/tmp/voice.mp3", 1, true), "paste failure must delete temporary file")
  assert(not joined:find("restoreLater:", 1, true), "paste failure must not schedule restore")
  assert(not joined:find("MP3 已貼上", 1, true), "paste failure must not claim success")
end

print("all recorder tests passed")
