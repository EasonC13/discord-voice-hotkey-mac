local Recorder = {}
Recorder.__index = Recorder

function Recorder.new(runtime)
  assert(runtime, "runtime is required")
  return setmetatable({ runtime = runtime, session = nil }, Recorder)
end

function Recorder:isRecording()
  return self.session ~= nil
end

function Recorder:_finish(session, exitCode, stdErr)
  if session.finished then return end
  session.finished = true

  if session.tooShort then
    self.runtime:deleteFile(session.path)
    self.runtime:restoreClipboard(session.clipboard)
    self.runtime:show("已取消：錄音太短")
    return
  end

  if exitCode ~= 0 and not session.userStopped then
    self.runtime:deleteFile(session.path)
    self.runtime:restoreClipboard(session.clipboard)
    self.runtime:show("錄音失敗，請檢查麥克風權限")
    return
  end

  if not self.runtime:fileUsable(session.path) then
    self.runtime:deleteFile(session.path)
    self.runtime:restoreClipboard(session.clipboard)
    self.runtime:show("沒有錄到聲音，剪貼簿已還原")
    return
  end

  self.runtime:activate(session.app)
  local pasteChangeCount = self.runtime:pasteFile(session.path)
  if pasteChangeCount == nil then
    self.runtime:deleteFile(session.path)
    self.runtime:restoreClipboard(session.clipboard)
    self.runtime:show("貼上失敗，剪貼簿已還原")
    return
  end

  self.runtime:restoreLater(session.clipboard, pasteChangeCount)
  self.runtime:cleanupLater(session.path)
  self.runtime:show("MP3 已貼上，剪貼簿將自動還原")
end

function Recorder:toggle()
  if self.session then
    local session = self.session
    self.session = nil
    session.userStopped = true
    session.tooShort = self.runtime:elapsed(session.startedAt) < 0.5
    session.task:terminate()
    self.runtime:show("正在完成 MP3…")
    return
  end

  local session = {
    clipboard = self.runtime:saveClipboard(),
    app = self.runtime:getFrontApp(),
    path = self.runtime:makeOutputPath(),
    startedAt = self.runtime.now,
    userStopped = false,
    tooShort = false,
    finished = false,
  }

  local callback = function(exitCode, stdOut, stdErr)
    if self.session == session then self.session = nil end
    self:_finish(session, exitCode, stdErr)
  end

  session.task = self.runtime:startRecording(session.path, callback)
  if not session.task then
    self.runtime:restoreClipboard(session.clipboard)
    self.runtime:show("無法啟動錄音器")
    return
  end

  self.session = session
  self.runtime:show("🔴 錄音中，再按一次停止")
end

return Recorder
