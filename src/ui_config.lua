local _, ns = ...

ns.Options = {}

local function makeCheck(parent, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb.Text:SetText(label)
  cb:SetChecked(get())
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  return cb
end

local function makeSlider(parent, label, key, minV, maxV, step, onChange)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetWidth(240)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  s:SetObeyStepOnDrag(true)
  s:SetValue(ns.DB.settings[key])
  s.Low:SetText(tostring(minV))
  s.High:SetText(tostring(maxV))
  local function txt(v) return label .. ": " .. (step >= 1 and tostring(v) or string.format("%.1f", v)) end
  s.Text:SetText(txt(ns.DB.settings[key]))
  s:SetScript("OnValueChanged", function(self, v)
    if step >= 1 then v = math.floor(v + 0.5) end
    ns.DB.settings[key] = v
    self.Text:SetText(txt(v))
    if onChange then onChange(v) end
  end)
  return s
end

local function refreshUI() if ns.UI.RefreshAll then ns.UI:RefreshAll() end end

function ns.Options:Register()
  local panel = CreateFrame("Frame")
  panel.name = "PullReview"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("PullReview")

  local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  desc:SetWidth(520); desc:SetJustifyH("LEFT")
  desc:SetText("Records each pull as a reviewable cast tape. Open with /pr. Cooldown windows are configured per spec in code and editable with /pr cd (type /pr for help).")

  local cbAuto = makeCheck(panel, "Auto-record each combat",
    function() return ns.DB.settings.autoRecord end,
    function(v) ns.DB.settings.autoRecord = v end)
  cbAuto:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)

  local cbRes = makeCheck(panel, "Show secondary-resource column",
    function() return ns.DB.settings.showResource end,
    function(v) ns.DB.settings.showResource = v; if ns.UI.RefreshAll then ns.UI:RefreshAll() end end)
  cbRes:SetPoint("TOPLEFT", cbAuto, "BOTTOMLEFT", 0, -4)

  local cbDebug = makeCheck(panel, "Debug logging",
    function() return PullReviewDB.debug end,
    function(v) PullReviewDB.debug = v end)
  cbDebug:SetPoint("TOPLEFT", cbRes, "BOTTOMLEFT", 0, -4)

  local sOpener = makeSlider(panel, "Opener length (s)", "openerSec", 3, 60, 1, refreshUI)
  sOpener:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", 4, -28)

  local sGap = makeSlider(panel, "Dead-GCD gap threshold (s)", "gapThreshold", 1.0, 3.0, 0.1, refreshUI)
  sGap:SetPoint("TOPLEFT", sOpener, "BOTTOMLEFT", 0, -34)

  local sMax = makeSlider(panel, "Max stored pulls", "maxTapes", 5, 100, 5)
  sMax:SetPoint("TOPLEFT", sGap, "BOTTOMLEFT", 0, -34)

  local sMin = makeSlider(panel, "Min auto-pull length (s)", "minPullSec", 0, 15, 1)
  sMin:SetPoint("TOPLEFT", sMax, "BOTTOMLEFT", 0, -34)

  local sFont = makeSlider(panel, "Cast-log font scale", "fontScale", 0.7, 2.0, 0.1, refreshUI)
  sFont:SetPoint("TOPLEFT", sMin, "BOTTOMLEFT", 0, -34)

  local cbDev = makeCheck(panel, "Dev mode (edit class/spec cooldown windows)",
    function() return PullReviewDB.devMode end,
    function(v) PullReviewDB.devMode = v end)
  cbDev:SetPoint("TOPLEFT", sFont, "BOTTOMLEFT", -4, -28)

  local devBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  devBtn:SetSize(200, 22)
  devBtn:SetText("Open class/spec editor")
  devBtn:SetPoint("TOPLEFT", cbDev, "BOTTOMLEFT", 4, -8)
  devBtn:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if ns.DevUI then ns.DevUI:Show() end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, "PullReview")
    Settings.RegisterAddOnCategory(cat)
    self.category = cat
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  self.panel = panel
end

function ns.Options:Open()
  if Settings and self.category then
    Settings.OpenToCategory(self.category.ID)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(self.panel)
    InterfaceOptionsFrame_OpenToCategory(self.panel)
  end
end
