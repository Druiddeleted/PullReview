local addonName, ns = ...
ns.addonName = addonName

local f = CreateFrame("Frame", "PullReviewCore", UIParent)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    ns.DB:Init()
  elseif event == "PLAYER_LOGIN" then
    ns.Capture:Register()   -- start recording pulls immediately
    ns.Options:Register()
    ns.Commands:Register()
    -- the reviewer window (ns.UI) builds lazily on first /pr
  end
end)
