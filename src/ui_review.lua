local _, ns = ...

ns.UI = {}
local UI = ns.UI

local ICON = 18
local FONT = STANDARD_TEXT_FONT
local function fsize() return math.floor(11 * (ns.DB.settings.fontScale or 1) + 0.5) end
local function rowH() return math.max(18, fsize() + 8) end

-- ---- helpers -----------------------------------------------------------------

local function fmtTime(t)
  local neg = t < 0
  local a = math.abs(t)
  local m = math.floor(a / 60)
  local s = math.floor(a % 60)
  local ms = math.floor((a - math.floor(a)) * 1000 + 0.5)
  if ms >= 1000 then ms = 999 end
  return string.format("%s%d:%02d.%03d", neg and "-" or "", m, s, ms)
end

local function specLabel(tape)
  local base
  if tape.specID and GetSpecializationInfoByID then
    local _, name = GetSpecializationInfoByID(tape.specID)
    if name and name ~= "" then base = name end
  end
  base = base or tape.class or "?"
  if tape.heroSpecName and tape.heroSpecName ~= "" then
    base = base .. " · " .. tape.heroSpecName
  end
  return base
end

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- Generic pool: acquire(pool, parent, factory) reuses hidden frames.
local function acquire(pool, parent, factory)
  pool.n = (pool.n or 0) + 1
  local f = pool[pool.n]
  if not f then
    f = factory(parent)
    pool[pool.n] = f
  end
  f:Show()
  return f
end
local function releaseRest(pool)
  for i = (pool.n or 0) + 1, #pool do pool[i]:Hide() end
end
local function resetPool(pool) pool.n = 0 end

-- ---- build -------------------------------------------------------------------

local function makeScroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  return sf
end

function UI:Build()
  if self.frame then return end
  local s = ns.DB.settings

  local f = CreateFrame("Frame", "PullReviewFrame", UIParent, "BackdropTemplate")
  f:SetSize(s.width or 760, s.height or 480)
  f:SetPoint(s.point or "CENTER", UIParent, s.relPoint or "CENTER", s.x or 0, s.y or 0)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(560, 320) end
  f:EnableMouse(true)
  f:Hide()

  -- title bar (drag handle)
  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT", 8, -8)
  title:SetPoint("TOPRIGHT", -8, -8)
  title:SetHeight(22)
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() f:StartMoving() end)
  title:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, relPoint, x, y = f:GetPoint()
    s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
  end)
  local tt = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tt:SetPoint("LEFT", 4, 0)
  tt:SetText("PullReview")
  f.titleText = tt

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() UI:Hide() end)

  -- resize grip
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    s.width, s.height = f:GetWidth(), f:GetHeight()
    UI:RefreshLayout()
  end)

  -- left: pull list
  local leftHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  leftHdr:SetPoint("TOPLEFT", 14, -34)
  leftHdr:SetText("PULLS")
  f.leftHdr = leftHdr

  local left = makeScroll(f)
  left:SetPoint("TOPLEFT", 12, -50)
  left:SetPoint("BOTTOMLEFT", 12, 28)
  left:SetWidth(210)
  f.left = left

  -- right: segment bar + summary + cast log
  local segBar = CreateFrame("Frame", nil, f)
  -- +34 clears the left list's scrollbar, which overflows past the list's right edge.
  segBar:SetPoint("TOPLEFT", left, "TOPRIGHT", 34, -18)
  segBar:SetPoint("TOPRIGHT", -28, -68)
  segBar:SetHeight(24)
  f.segBar = segBar

  -- pull name above the detail pane (helps with long dungeon-pull labels)
  local detailTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  detailTitle:SetPoint("BOTTOMLEFT", segBar, "TOPLEFT", 0, 3)
  detailTitle:SetPoint("RIGHT", segBar, "RIGHT", 0, 0)
  detailTitle:SetJustifyH("LEFT")
  detailTitle:SetWordWrap(false)
  f.detailTitle = detailTitle

  local stepper = CreateFrame("Frame", nil, f)
  stepper:SetPoint("TOPLEFT", segBar, "BOTTOMLEFT", 0, -4)
  stepper:SetPoint("RIGHT", segBar, "RIGHT", 0, 0)
  stepper:SetHeight(20)
  f.stepper = stepper

  local prevBtn = CreateFrame("Button", nil, stepper, "UIPanelButtonTemplate")
  prevBtn:SetSize(24, 18); prevBtn:SetText("<"); prevBtn:SetPoint("LEFT", 0, 0)
  prevBtn:SetScript("OnClick", function() UI:StepOccurrence(-1) end)
  local nextBtn = CreateFrame("Button", nil, stepper, "UIPanelButtonTemplate")
  nextBtn:SetSize(24, 18); nextBtn:SetText(">"); nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 60, 0)
  local stepLbl = stepper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  stepLbl:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
  nextBtn:ClearAllPoints(); nextBtn:SetPoint("LEFT", stepLbl, "RIGHT", 6, 0)
  stepper.prev, stepper.next, stepper.label = prevBtn, nextBtn, stepLbl
  nextBtn:SetScript("OnClick", function() UI:StepOccurrence(1) end)

  local summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("TOPLEFT", stepper, "BOTTOMLEFT", 0, -4)
  summary:SetPoint("RIGHT", stepper, "RIGHT", 0, 0)
  summary:SetJustifyH("LEFT")
  summary:SetHeight(16)
  f.summary = summary

  -- column header
  local colhdr = CreateFrame("Frame", nil, f)
  colhdr:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -4)
  colhdr:SetPoint("RIGHT", summary, "RIGHT", 0, 0)
  colhdr:SetHeight(14)
  colhdr.time = colhdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  colhdr.time:SetPoint("LEFT", 2, 0); colhdr.time:SetWidth(78); colhdr.time:SetJustifyH("RIGHT")
  colhdr.time:SetText("Time")
  colhdr.name = colhdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  colhdr.name:SetPoint("LEFT", colhdr.time, "RIGHT", 8 + ICON + 6, 0)
  colhdr.name:SetText("Spell")
  colhdr.res = colhdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  colhdr.res:SetPoint("RIGHT", -6, 0); colhdr.res:SetJustifyH("RIGHT")
  colhdr.res:SetText("Res")
  f.colhdr = colhdr

  local log = makeScroll(f)
  log:SetPoint("TOPLEFT", colhdr, "BOTTOMLEFT", 0, -2)
  log:SetPoint("BOTTOMRIGHT", -28, 28)
  f.log = log

  local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  empty:SetPoint("CENTER", log, "CENTER", 0, 0)
  empty:SetText("No pull selected")
  f.empty = empty

  -- pools
  self.tapePool = {}
  self.castPool = {}
  self.segPool = {}

  self.frame = f
  self.view = { mode = "whole" }
  self:RefreshLayout()
end

function UI:RefreshLayout()
  local f = self.frame
  if not f then return end
  f.left.child:SetWidth(f.left:GetWidth())
  f.log.child:SetWidth(f.log:GetWidth())
  self:RefreshAll()
end

-- ---- tape list ---------------------------------------------------------------

local function makeTapeRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(34)
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(0.3, 0.5, 0.9, 0.3)
  b.sel:Hide()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 1, 1, 0.08)
  b.line1 = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.line1:SetPoint("TOPLEFT", 4, -3)
  b.line2 = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.line2:SetPoint("TOPLEFT", 4, -17)
  b.pin = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.pin:SetPoint("TOPRIGHT", -4, -3)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  return b
end

function UI:RefreshTapeList()
  local f = self.frame
  resetPool(self.tapePool)
  local tapes = ns.DB:Tapes()
  local y = 0
  for _, tape in ipairs(tapes) do
    local row = acquire(self.tapePool, f.left.child, makeTapeRow)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
    local r, g, b = classColor(tape.class)
    row.line1:SetText((tape.label or tape.zone or "Pull") .. (tape.manual and "  |cffffd100(manual)|r" or ""))
    row.line1:SetTextColor(1, 1, 1)
    row.line2:SetFormattedText("|cff%02x%02x%02x%s|r · %ds · %d casts",
      r * 255, g * 255, b * 255, specLabel(tape), math.floor(tape.durationSec or 0), #tape.casts)
    row.pin:SetText(tape.pinned and "|cffffd100*|r" or "")
    row.sel:SetShown(tape.id == self.selectedTapeId)
    row:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        tape.pinned = not tape.pinned
        UI:RefreshTapeList()
      else
        UI.selectedTapeId = tape.id
        UI.view = { mode = "whole" }
        UI:RefreshAll()
      end
    end)
    y = y + 36
  end
  releaseRest(self.tapePool)
  f.left.child:SetHeight(math.max(y, 1))
end

-- ---- segment bar -------------------------------------------------------------

local function makeSegBtn(parent)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetHeight(20)
  return b
end

function UI:SelectedTape()
  return self.selectedTapeId and ns.DB:GetTape(self.selectedTapeId)
end

function UI:RefreshSegments()
  local f = self.frame
  resetPool(self.segPool)
  local tape = self:SelectedTape()
  if not tape then releaseRest(self.segPool); return end

  local specs = {}
  specs[#specs + 1] = { mode = "whole", text = "Whole" }
  specs[#specs + 1] = { mode = "opener", text = "Opener" }
  self.tracks = ns.Segments:CooldownTracks(tape)
  for i, tr in ipairs(self.tracks) do
    local n = #tr.occurrences
    specs[#specs + 1] = { mode = "cd", cdIndex = i, text = string.format("%s (%d)", tr.label, n), dim = (n == 0) }
  end

  local x = 0
  for _, spec in ipairs(specs) do
    local b = acquire(self.segPool, f.segBar, makeSegBtn)
    b:SetText(spec.text)
    b:SetWidth(math.max(60, b:GetFontString():GetStringWidth() + 18))
    b:SetPoint("LEFT", x, 0)
    local active = (self.view.mode == spec.mode and (spec.mode ~= "cd" or self.view.cdIndex == spec.cdIndex))
    b:SetEnabled(not spec.dim)
    b:GetFontString():SetTextColor(active and 1 or 0.8, active and 0.82 or 0.8, active and 0 or 0.8)
    b:SetScript("OnClick", function()
      UI.view = { mode = spec.mode, cdIndex = spec.cdIndex, occIndex = 1 }
      UI:RefreshDetail()
      UI:RefreshSegments()
    end)
    x = x + b:GetWidth() + 4
  end
  releaseRest(self.segPool)
end

function UI:StepOccurrence(delta)
  if self.view.mode ~= "cd" then return end
  local tr = self.tracks and self.tracks[self.view.cdIndex]
  if not tr or #tr.occurrences == 0 then return end
  local i = (self.view.occIndex or 1) + delta
  if i < 1 then i = #tr.occurrences elseif i > #tr.occurrences then i = 1 end
  self.view.occIndex = i
  self:RefreshDetail()
end

-- ---- cast log ----------------------------------------------------------------

local function makeCastRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if not self.spellID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(self.spellID)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row.time = row:CreateFontString(nil, "OVERLAY")
  row.time:SetPoint("LEFT", 2, 0); row.time:SetWidth(78); row.time:SetJustifyH("RIGHT")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON); row.icon:SetPoint("LEFT", row.time, "RIGHT", 8, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = row:CreateFontString(nil, "OVERLAY")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.name:SetJustifyH("LEFT")
  row.gap = row:CreateFontString(nil, "OVERLAY")
  row.gap:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.res = row:CreateFontString(nil, "OVERLAY")
  row.res:SetPoint("RIGHT", -6, 0); row.res:SetJustifyH("RIGHT")
  -- section/divider label (reuses the row, hiding the cast columns)
  row.hdr = row:CreateFontString(nil, "OVERLAY")
  row.hdr:SetPoint("LEFT", 6, 0)
  -- red anchor line for cooldown windows (the "0s" mark)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetColorTexture(1, 0.25, 0.25, 0.95)
  row.line:SetHeight(2)
  row.line:SetPoint("BOTTOMLEFT", 2, 1); row.line:SetPoint("BOTTOMRIGHT", -6, 1)
  row.line:Hide()
  return row
end

-- Render a flat list of items: { header=str } | { divider=true, label=str } | cast.
function UI:RenderItems(items)
  local f = self.frame
  resetPool(self.castPool)
  local sz = fsize()
  local rh = rowH()
  local y = 0
  for _, item in ipairs(items) do
    local row = acquire(self.castPool, f.log.child, makeCastRow)
    row:SetHeight(rh)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
    if item.divider or item.header then
      row.spellID = nil
      row.time:Hide(); row.icon:Hide(); row.name:Hide(); row.gap:Hide(); row.res:Hide()
      row.hdr:SetFont(FONT, sz, "OUTLINE")
      row.hdr:SetText(item.label or item.header)
      if item.divider then
        row.hdr:SetTextColor(1, 0.45, 0.45); row.line:Show()
      else
        row.hdr:SetTextColor(1, 0.82, 0); row.line:Hide()
      end
      row.hdr:Show()
    else
      row.spellID = item.spellID
      row.hdr:Hide(); row.line:Hide()
      row.time:SetFont(FONT, sz); row.name:SetFont(FONT, sz)
      row.gap:SetFont(FONT, sz); row.res:SetFont(FONT, sz)
      row.icon:SetSize(sz + 7, sz + 7)
      row.time:Show(); row.icon:Show(); row.name:Show()
      row.time:SetText(fmtTime(item.t)); row.time:SetTextColor(0.8, 0.8, 0.8)
      row.icon:SetTexture(item.icon)
      row.name:SetText(item.name or ("spell " .. (item.spellID or "?")))
      row.name:SetTextColor(item.onGCD and 1 or 0.6, item.onGCD and 1 or 0.85, item.onGCD and 1 or 0.6)
      if item.gapBefore then
        row.gap:SetText(string.format("|cffff6666+%.1fs gap|r", item.gapBefore)); row.gap:Show()
      else
        row.gap:Hide()
      end
      if item.res ~= nil and ns.DB.settings.showResource then
        row.res:SetText(tostring(item.res)); row.res:SetTextColor(0.6, 0.85, 1); row.res:Show()
      else
        row.res:Hide()
      end
    end
    y = y + rh
  end
  releaseRest(self.castPool)
  f.log.child:SetHeight(math.max(y, 1))
end

-- Build display items. opts:
--   split        insert PRE-PULL / PULL section headers
--   zeroT        re-zero displayed time to this anchor (cooldown windows)
--   dividerLabel insert a red anchor line right before the first cast at >= zero
local function buildItems(casts, opts)
  opts = opts or {}
  local items = {}
  local gaps = ns.Segments:Gaps(casts, ns.DB.settings.gapThreshold or 1.6)
  local zero = opts.zeroT or 0
  local wrotePre, wrotePull, wroteDiv = false, false, false
  for i, c in ipairs(casts) do
    local dt = c.t - zero
    if opts.split then
      if c.t < 0 and not wrotePre then
        items[#items + 1] = { header = "PRE-PULL" }; wrotePre = true
      elseif c.t >= 0 and not wrotePull then
        items[#items + 1] = { header = "PULL" }; wrotePull = true
      end
    elseif opts.dividerLabel and not wroteDiv and dt >= 0 then
      items[#items + 1] = { divider = true, label = opts.dividerLabel }; wroteDiv = true
    end
    items[#items + 1] = { t = dt, icon = c.icon, name = c.name, spellID = c.spellID, onGCD = c.onGCD, res = c.res, gapBefore = gaps[i] }
  end
  if opts.dividerLabel and not wroteDiv then
    items[#items + 1] = { divider = true, label = opts.dividerLabel }
  end
  return items
end

function UI:RefreshDetail()
  local f = self.frame
  local tape = self:SelectedTape()
  if not tape then
    f.empty:Show(); f.summary:SetText(""); f.stepper:Hide()
    if f.detailTitle then f.detailTitle:SetText("") end
    self:RenderItems({})
    return
  end
  f.empty:Hide()
  if f.detailTitle then f.detailTitle:SetText(tape.label or "Pull") end
  if f.colhdr then
    local hasRes = false
    for _, c in ipairs(tape.casts) do if c.res ~= nil then hasRes = true; break end end
    f.colhdr.res:SetText(hasRes and (tape.resLabel or "Resource") or "")
  end

  local mode = self.view.mode
  if mode == "whole" then
    f.stepper:Hide()
    f.summary:SetText(string.format("Whole pull — %d casts, %ds", #tape.casts, math.floor(tape.durationSec or 0)))
    self:RenderItems(buildItems(tape.casts, { split = true }))
  elseif mode == "opener" then
    f.stepper:Hide()
    local op = ns.Segments:Opener(tape)
    f.summary:SetText(string.format("Opener — first %ds, %d casts", math.floor(op.toT), #op.casts))
    self:RenderItems(buildItems(op.casts, { split = true }))
  elseif mode == "cd" then
    local tr = self.tracks and self.tracks[self.view.cdIndex]
    if not tr or #tr.occurrences == 0 then
      f.stepper:Hide()
      f.summary:SetText((tr and tr.label or "Cooldown") .. " — not pressed this pull")
      self:RenderItems({})
      return
    end
    local occIdx = math.min(self.view.occIndex or 1, #tr.occurrences)
    self.view.occIndex = occIdx
    local w = tr.occurrences[occIdx]
    f.stepper:Show()
    f.stepper.label:SetText(string.format("%s  %d/%d", tr.label, occIdx, #tr.occurrences))
    local dur = w.endT - w.startT
    local extra = w.extendedBy > 0.05 and string.format("  |cff66ccff(+%.0fs extended)|r", w.extendedBy) or ""
    local miss = ""
    if w.missing then
      for _, m in ipairs(w.missing) do
        miss = miss .. string.format("  |cffff4444MISSED %s (%d/%d)|r", m.label, m.got, m.want)
      end
    end
    f.summary:SetText(string.format("%s @ %s — window %.0fs, %d casts%s%s",
      tr.label, fmtTime(w.anchorT), dur, #w.casts, extra, miss))
    self:RenderItems(buildItems(w.casts, {
      zeroT = w.anchorT,
      dividerLabel = string.format("%s  (0s)", tr.label),
    }))
  end
end

function UI:RefreshAll()
  if not (self.frame and self.frame:IsShown()) then return end
  self:RefreshTapeList()
  self:RefreshSegments()
  self:RefreshDetail()
end

-- Called by capture when a tape is finalized.
function UI:OnTapeAdded(tape)
  if self.frame and self.frame:IsShown() then
    self:RefreshTapeList()
  end
end

-- ---- show / hide -------------------------------------------------------------

function UI:Show()
  self:Build()
  -- default selection: newest tape
  if not self.selectedTapeId then
    local tapes = ns.DB:Tapes()
    if tapes[1] then self.selectedTapeId = tapes[1].id end
  end
  self.frame:Show()
  self:RefreshLayout()
end

function UI:Hide()
  if self.frame then self.frame:Hide() end
end

function UI:Toggle()
  if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function UI:OpenLatest()
  local tapes = ns.DB:Tapes()
  if tapes[1] then self.selectedTapeId = tapes[1].id; self.view = { mode = "whole" } end
  self:Show()
end
