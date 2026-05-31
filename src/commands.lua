local _, ns = ...

ns.Commands = {}

local function pr(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffPullReview|r: " .. msg)
end

local function spellName(id)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
  return (info and info.name) or ("spell " .. tostring(id))
end

local function curSpec()
  local _, class = UnitClass("player")
  local specID
  if GetSpecialization then
    local idx = GetSpecialization()
    if idx and GetSpecializationInfo then specID = GetSpecializationInfo(idx) end
  end
  return class, specID
end

-- ---- cooldown editor ---------------------------------------------------------

local function cdList()
  local class, specID = curSpec()
  local cds = ns.DB:GetCooldowns(class, specID)
  if #cds == 0 then pr("no cooldown windows configured for this spec. Add one: /pr cd add <spellID> <label>"); return end
  pr(string.format("cooldown windows for %s/%s:", tostring(class), tostring(specID)))
  for _, cd in ipairs(cds) do
    local ext = ""
    if cd.extend and cd.extend.spells then
      local names = {}
      for _, sid in ipairs(cd.extend.spells) do names[#names + 1] = spellName(sid) .. "(" .. sid .. ")" end
      ext = "  ext+" .. (cd.extend.perCast or 0) .. "s: " .. table.concat(names, ", ")
    end
    pr(string.format("  %s (%d): pre=%s base=%ds%s", cd.label or spellName(cd.spellID), cd.spellID,
      cd.preCasts and (cd.preCasts .. " casts") or (cd.preSec and (cd.preSec .. "s") or "0"),
      cd.baseSec or 0, ext))
  end
end

local function cdFind(list, id)
  for i, cd in ipairs(list) do if cd.spellID == id then return i, cd end end
end

local function cdAdd(id, label)
  local class, specID = curSpec()
  if not (class and specID) then pr("can't determine your spec right now."); return end
  local list = ns.DB:EnsureUserCooldowns(class, specID)
  if cdFind(list, id) then pr(spellName(id) .. " is already a cooldown window."); return end
  list[#list + 1] = { spellID = id, label = (label ~= "" and label) or spellName(id), preCasts = 1, baseSec = 15 }
  pr(string.format("added %s (%d) — base 15s, pre 1 cast. Tweak in code or remove with /pr cd remove %d.", spellName(id), id, id))
  if ns.UI.RefreshAll then ns.UI:RefreshAll() end
end

local function cdRemove(id)
  local class, specID = curSpec()
  local list = ns.DB:EnsureUserCooldowns(class, specID)
  local i = cdFind(list, id)
  if not i then pr("no cooldown window with spellID " .. id); return end
  table.remove(list, i)
  pr("removed cooldown window " .. id)
  if ns.UI.RefreshAll then ns.UI:RefreshAll() end
end

-- /pr cd extend <anchorID> <spenderID> : toggle a spender on a cooldown's extend list
local function cdExtend(anchorID, spenderID)
  local class, specID = curSpec()
  local list = ns.DB:EnsureUserCooldowns(class, specID)
  local _, cd = cdFind(list, anchorID)
  if not cd then pr("no cooldown window with spellID " .. anchorID .. " (add it first)"); return end
  cd.extend = cd.extend or { spells = {}, perCast = 1 }
  cd.extend.spells = cd.extend.spells or {}
  for i, sid in ipairs(cd.extend.spells) do
    if sid == spenderID then
      table.remove(cd.extend.spells, i)
      pr(string.format("%s no longer extends %s", spellName(spenderID), cd.label or anchorID))
      if ns.UI.RefreshAll then ns.UI:RefreshAll() end
      return
    end
  end
  cd.extend.spells[#cd.extend.spells + 1] = spenderID
  pr(string.format("%s (%d) now extends %s by %ds each", spellName(spenderID), spenderID, cd.label or tostring(anchorID), cd.extend.perCast or 1))
  if ns.UI.RefreshAll then ns.UI:RefreshAll() end
end

local function handleCD(rest)
  local sub, a, b = rest:match("^(%S+)%s*(%S*)%s*(.*)$")
  sub = (sub or ""):lower()
  if sub == "list" or sub == "" then cdList()
  elseif sub == "add" then cdAdd(tonumber(a), (b or ""):match("^%s*(.-)%s*$"))
  elseif sub == "remove" or sub == "rem" then cdRemove(tonumber(a))
  elseif sub == "extend" then cdExtend(tonumber(a), tonumber(b))
  else
    pr("cd commands: list | add <spellID> <label> | remove <spellID> | extend <anchorID> <spenderID>")
  end
end

-- ---- main dispatch -----------------------------------------------------------

function ns.Commands:Register()
  SLASH_PULLREVIEW1 = "/pr"
  SLASH_PULLREVIEW2 = "/pullreview"
  SlashCmdList["PULLREVIEW"] = function(input)
    input = (input or ""):match("^%s*(.-)%s*$")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "show" or cmd == "open" then
      ns.UI:Show()
    elseif cmd == "last" then
      ns.UI:OpenLatest()
    elseif cmd == "hide" then
      ns.UI:Hide()
    elseif cmd == "toggle" then
      ns.UI:Toggle()
    elseif cmd == "start" then
      if ns.Capture:IsRecording() then pr("already recording.") else ns.Capture:StartPull(true); pr("manual recording started — /pr stop to finish.") end
    elseif cmd == "stop" then
      local tape = ns.Capture:Stop()
      pr(tape and ("saved a tape: " .. #tape.casts .. " casts.") or "nothing was recording.")
    elseif cmd == "config" or cmd == "options" then
      ns.Options:Open()
    elseif cmd == "dev" then
      local sub = (rest or ""):lower()
      if sub == "export" then
        if ns.DevUI.selClass then ns.DevUI:Export() else pr("open the editor first: /pr dev") end
      else
        PullReviewDB.devMode = true
        ns.DevUI:Show()
      end
    elseif cmd == "cd" then
      handleCD(rest)
    elseif cmd == "clear" then
      ns.DB:ClearTapes(); ns.UI.sel = nil
      if ns.UI.RefreshAll then ns.UI:RefreshAll() end
      pr("cleared all stored pulls.")
    elseif cmd == "debug" then
      local v = (rest or ""):lower()
      if v == "on" then PullReviewDB.debug = true; pr("debug ON")
      elseif v == "off" then PullReviewDB.debug = false; pr("debug OFF")
      else pr("usage: /pr debug on|off") end
    else
      pr("commands: (blank)=open, last, start, stop, toggle, hide, config, clear, cd, dev")
    end
  end
end
