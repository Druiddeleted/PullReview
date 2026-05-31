local _, ns = ...

-- Dev-mode editor: edit any class/spec's cooldown-window config in-game. Edits
-- write to PullReviewDB.specConfig (an override on top of the shipped defaults in
-- specdata.lua). "Export" dumps the current spec as a Lua snippet (to chat and to
-- PullReviewDB.lastExport) so the edits can be baked back into specdata.lua.

ns.DevUI = {}
local Dev = ns.DevUI

-- ---- class/spec enumeration --------------------------------------------------

local function classChoices()
  local out = {}
  for i = 1, GetNumClasses() do
    local name, file = GetClassInfo(i)
    if file then out[#out + 1] = { id = i, file = file, name = name } end
  end
  return out
end

local function specChoices(classID)
  local out = {}
  if not classID then return out end -- dropdown init can run before a class is picked
  local getN = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) or GetNumSpecializationsForClassID
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID) or GetSpecializationInfoForClassID
  if not (getN and getInfo) then return out end
  local n = getN(classID) or 0
  for i = 1, n do
    local id, name = getInfo(classID, i)
    if id then out[#out + 1] = { id = id, name = name } end
  end
  return out
end

local function currentClassSpec()
  local _, file = UnitClass("player")
  local classID
  for i = 1, GetNumClasses() do
    local _, f = GetClassInfo(i)
    if f == file then classID = i; break end
  end
  local specID
  if GetSpecialization then
    local idx = GetSpecialization()
    if idx and GetSpecializationInfo then specID = GetSpecializationInfo(idx) end
  end
  return file, classID, specID
end

local function currentHero()
  local id
  if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
    local ok, v = pcall(C_ClassTalents.GetActiveHeroTalentSpec); if ok then id = v end
  end
  local name
  if id and C_Traits and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    local cfg = C_ClassTalents.GetActiveConfigID()
    if cfg then local ok, info = pcall(C_Traits.GetSubTreeInfo, cfg, id); if ok and info then name = info.name end end
  end
  return id, name
end

-- ---- csv parse/format helpers ------------------------------------------------

local function parseIDList(str)
  local t = {}
  for n in tostring(str):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end
local function fmtIDList(list)
  return list and table.concat(list, ",") or ""
end
local function parseExpect(str)
  local t = {}
  for id, cnt in tostring(str):gmatch("(%d+):(%d+)") do
    t[#t + 1] = { spellID = tonumber(id), count = tonumber(cnt) }
  end
  return (#t > 0) and t or nil
end
local function fmtExpect(list)
  if not list then return "" end
  local parts = {}
  for _, e in ipairs(list) do parts[#parts + 1] = e.spellID .. ":" .. (e.count or 1) end
  return table.concat(parts, ",")
end

-- ---- serialize one spec entry to a Lua snippet -------------------------------

local function serialize(classFile, specID, entry)
  local lines = {}
  local function w(s) lines[#lines + 1] = s end
  w(string.format("[\"%s\"] = {", classFile))
  w(string.format("  [%d] = {", specID))
  if entry.secondaryPower ~= nil then w(string.format("    secondaryPower = %s,", tostring(entry.secondaryPower))) end
  if entry.secondaryLabel then w(string.format("    secondaryLabel = %q,", entry.secondaryLabel)) end
  if entry.openerSec then w(string.format("    openerSec = %d,", entry.openerSec)) end
  w("    cooldowns = {")
  for _, cd in ipairs(entry.cooldowns or {}) do
    local idpart
    if cd.spellIDs and #cd.spellIDs > 0 then idpart = string.format("spellIDs = {%s}", fmtIDList(cd.spellIDs))
    else idpart = string.format("spellID = %d", cd.spellID or 0) end
    local parts = { idpart, string.format("label = %q", cd.label or "") }
    if cd.preCasts then parts[#parts + 1] = "preCasts = " .. cd.preCasts end
    if cd.preSec then parts[#parts + 1] = "preSec = " .. cd.preSec end
    if cd.baseSec then parts[#parts + 1] = "baseSec = " .. cd.baseSec end
    if cd.heroSpec then parts[#parts + 1] = "heroSpec = " .. cd.heroSpec end
    local extra = ""
    if cd.extend and cd.extend.spells and #cd.extend.spells > 0 then
      extra = extra .. string.format(", extend = { spells = {%s}, perCast = %s }", fmtIDList(cd.extend.spells), tostring(cd.extend.perCast or 1))
    end
    if cd.expect then
      local es = {}
      for _, e in ipairs(cd.expect) do es[#es + 1] = string.format("{ spellID = %d, count = %d }", e.spellID, e.count or 1) end
      extra = extra .. string.format(", expect = { %s }", table.concat(es, ", "))
    end
    w(string.format("      { %s%s },", table.concat(parts, ", "), extra))
  end
  w("    },")
  w("  },")
  w("},")
  return table.concat(lines, "\n")
end

-- ---- widgets -----------------------------------------------------------------

local function makeEdit(parent, width, onCommit)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 18)
  e:SetAutoFocus(false)
  e:SetScript("OnEnterPressed", function(self) onCommit(self:GetText()); self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self) onCommit(self:GetText()) end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

local function dropdown(parent, width, getItems, getSelText, onSelect)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width)
  UIDropDownMenu_Initialize(dd, function(_, level)
    for _, it in ipairs(getItems()) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = it.text
      info.func = function() onSelect(it.value); UIDropDownMenu_SetText(dd, it.text) end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  dd.refresh = function() UIDropDownMenu_SetText(dd, getSelText()) end
  return dd
end

-- ---- build -------------------------------------------------------------------

function Dev:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "PullReviewDevFrame", UIParent, "BackdropTemplate")
  f:SetSize(800, 470)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG") -- above the Settings panel it's launched from
  f:SetToplevel(true)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12); title:SetText("PullReview — Class/Spec Editor")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  -- class + spec pickers ("Global (all specs)" edits the lust/potion window set)
  self.classDD = dropdown(f, 150,
    function()
      local items = { { text = "Global (all specs)", value = { file = "GLOBAL", id = 0, name = "Global (all specs)" } } }
      for _, c in ipairs(classChoices()) do items[#items + 1] = { text = c.name, value = c } end
      return items
    end,
    function() return self.selClassName or "Class" end,
    function(c)
      self.selClass = c.file; self.selClassID = c.id; self.selClassName = c.name
      if c.file == "GLOBAL" then
        self.selSpec = 0; self.selSpecName = "(all specs)"
      else
        local specs = specChoices(c.id); self.selSpec = specs[1] and specs[1].id; self.selSpecName = specs[1] and specs[1].name
      end
      self:Load()
    end)
  self.classDD:SetPoint("TOPLEFT", 4, -32)

  self.specDD = dropdown(f, 150,
    function()
      local items = {}
      for _, s in ipairs(specChoices(self.selClassID)) do items[#items + 1] = { text = s.name, value = s } end
      return items
    end,
    function() return self.selSpecName or "Spec" end,
    function(s) self.selSpec = s.id; self.selSpecName = s.name; self:Load() end)
  self.specDD:SetPoint("LEFT", self.classDD, "RIGHT", 4, 0)

  self.heroInfo = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.heroInfo:SetPoint("LEFT", self.specDD, "RIGHT", 12, 0)

  -- spec-level fields
  local function specLabelFS(text, anchor, dx)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", anchor, "RIGHT", dx, 0); fs:SetText(text); return fs
  end
  local openLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  openLbl:SetPoint("TOPLEFT", self.classDD, "BOTTOMLEFT", 16, -6); openLbl:SetText("Opener s:")
  self.openEdit = makeEdit(f, 36, function(v) self:Entry().openerSec = tonumber(v); self:Apply() end)
  self.openEdit:SetPoint("LEFT", openLbl, "RIGHT", 6, 0)
  local powLbl = specLabelFS("Secondary power #:", self.openEdit, 12)
  self.powEdit = makeEdit(f, 40, function(v) self:Entry().secondaryPower = tonumber(v); self:Apply() end)
  self.powEdit:SetPoint("LEFT", powLbl, "RIGHT", 6, 0)
  local plLbl = specLabelFS("Label:", self.powEdit, 12)
  self.powLabelEdit = makeEdit(f, 80, function(v) self:Entry().secondaryLabel = (v ~= "" and v) or nil; self:Apply() end)
  self.powLabelEdit:SetPoint("LEFT", plLbl, "RIGHT", 6, 0)

  -- column headers for the cooldown rows
  local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hdr:SetPoint("TOPLEFT", openLbl, "BOTTOMLEFT", -12, -10)
  hdr:SetText("spellID(s)      label              pre base  extend(ids)         expect(id:n)   hero")
  self.hdr = hdr

  -- scroll of cooldown rows
  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
  sf:SetPoint("BOTTOMRIGHT", -30, 40)
  local child = CreateFrame("Frame", nil, sf); child:SetSize(10, 10)
  sf:SetScrollChild(child); sf.child = child
  self.scroll = sf

  -- bottom buttons
  local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  addBtn:SetSize(110, 22); addBtn:SetText("Add cooldown"); addBtn:SetPoint("BOTTOMLEFT", 12, 10)
  addBtn:SetScript("OnClick", function()
    local e = self:Entry(); e.cooldowns[#e.cooldowns + 1] = { spellID = 0, label = "New", preCasts = 1, baseSec = 15 }
    self:Apply(); self:Refresh()
  end)
  local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  resetBtn:SetSize(120, 22); resetBtn:SetText("Reset to default"); resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
  resetBtn:SetScript("OnClick", function()
    ns.DB:ResetSpecOverride(self.selClass, self.selSpec); self:Load()
  end)
  local expBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  expBtn:SetSize(130, 22); expBtn:SetText("Export to chat"); expBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
  expBtn:SetScript("OnClick", function() self:Export() end)

  self.rowPool = {}
  self.frame = f
end

-- ---- data plumbing -----------------------------------------------------------

function Dev:Entry()
  return ns.DB:EnsureSpecOverride(self.selClass, self.selSpec)
end

function Dev:Apply()
  if ns.UI.RefreshAll then ns.UI:RefreshAll() end
end

local function makeCDRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(760, 24)
  row.id = makeEdit(row, 92, function() end); row.id:SetPoint("LEFT", 2, 0)
  row.label = makeEdit(row, 120, function() end); row.label:SetPoint("LEFT", row.id, "RIGHT", 6, 0)
  row.pre = makeEdit(row, 30, function() end); row.pre:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
  row.base = makeEdit(row, 34, function() end); row.base:SetPoint("LEFT", row.pre, "RIGHT", 6, 0)
  row.extend = makeEdit(row, 120, function() end); row.extend:SetPoint("LEFT", row.base, "RIGHT", 6, 0)
  row.expect = makeEdit(row, 96, function() end); row.expect:SetPoint("LEFT", row.extend, "RIGHT", 6, 0)
  row.hero = makeEdit(row, 46, function() end); row.hero:SetPoint("LEFT", row.expect, "RIGHT", 6, 0)
  row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.del:SetSize(22, 18); row.del:SetText("X"); row.del:SetPoint("LEFT", row.hero, "RIGHT", 6, 0)
  return row
end

function Dev:Refresh()
  local f = self.frame
  if not f then return end
  self.classDD.refresh(); self.specDD.refresh()
  local hid, hname = currentHero()
  self.heroInfo:SetText(hid and ("active hero: " .. (hname or "?") .. " (" .. hid .. ")") or "no hero spec")
  local entry = self:Entry()
  self.openEdit:SetText(tostring(entry.openerSec or ""))
  self.powEdit:SetText(tostring(entry.secondaryPower or ""))
  self.powLabelEdit:SetText(entry.secondaryLabel or "")

  -- (re)bind cooldown rows
  local pool = self.rowPool
  pool.n = 0
  local y = 0
  for idx, cd in ipairs(entry.cooldowns) do
    pool.n = pool.n + 1
    local row = pool[pool.n]
    if not row then row = makeCDRow(self.scroll.child); pool[pool.n] = row end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:Show()
    row.id:SetText(cd.spellID and tostring(cd.spellID) or fmtIDList(cd.spellIDs))
    row.label:SetText(cd.label or "")
    row.pre:SetText(tostring(cd.preCasts or cd.preSec or ""))
    row.base:SetText(tostring(cd.baseSec or 0))
    row.extend:SetText(cd.extend and fmtIDList(cd.extend.spells) or "")
    row.expect:SetText(fmtExpect(cd.expect))
    row.hero:SetText(tostring(cd.heroSpec or ""))
    -- commit handlers capture this cd. The id field accepts one ID (single
    -- anchor) or a comma list (multi-anchor, e.g. all lust variants).
    local function commitID(s)
      local ids = parseIDList(s:GetText())
      if #ids > 1 then cd.spellIDs = ids; cd.spellID = nil
      elseif #ids == 1 then cd.spellID = ids[1]; cd.spellIDs = nil
      else cd.spellID, cd.spellIDs = nil, nil end
      Dev:Apply()
    end
    row.id:SetScript("OnEnterPressed", function(s) commitID(s); s:ClearFocus() end)
    row.id:SetScript("OnEditFocusLost", commitID)
    row.hero:SetScript("OnEditFocusLost", function(s) cd.heroSpec = tonumber(s:GetText()); Dev:Apply() end)
    row.label:SetScript("OnEditFocusLost", function(s) cd.label = s:GetText(); Dev:Apply() end)
    row.pre:SetScript("OnEditFocusLost", function(s) cd.preCasts = tonumber(s:GetText()); Dev:Apply() end)
    row.base:SetScript("OnEditFocusLost", function(s) cd.baseSec = tonumber(s:GetText()) or 0; Dev:Apply() end)
    row.extend:SetScript("OnEditFocusLost", function(s)
      local ids = parseIDList(s:GetText())
      if #ids > 0 then cd.extend = { spells = ids, perCast = (cd.extend and cd.extend.perCast) or 1 } else cd.extend = nil end
      Dev:Apply()
    end)
    row.expect:SetScript("OnEditFocusLost", function(s) cd.expect = parseExpect(s:GetText()); Dev:Apply() end)
    row.del:SetScript("OnClick", function()
      table.remove(entry.cooldowns, idx); Dev:Apply(); Dev:Refresh()
    end)
    y = y + 26
  end
  for i = pool.n + 1, #pool do pool[i]:Hide() end
  self.scroll.child:SetHeight(math.max(y, 1))
  self.scroll.child:SetWidth(self.scroll:GetWidth())
end

function Dev:Load()
  self:Refresh()
end

function Dev:Export()
  local entry = self:Entry()
  local str = serialize(self.selClass, self.selSpec, entry)
  PullReviewDB.lastExport = str
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffPullReview|r export (also saved to PullReviewDB.lastExport):")
  for line in str:gmatch("[^\n]+") do DEFAULT_CHAT_FRAME:AddMessage(line) end
end

function Dev:Show()
  self:Build()
  if not self.selClass then
    local file, classID, specID = currentClassSpec()
    self.selClass, self.selClassID, self.selSpec = file, classID, specID
    self.selClassName = GetClassInfo(classID or 1) -- localized name is the FIRST return
    if specID and GetSpecializationInfoByID then local _, sname = GetSpecializationInfoByID(specID); self.selSpecName = sname end
  end
  self.frame:Show()
  self.frame:Raise()
  self:Refresh()
end
