local _, ns = ...

-- Records the player's casts into a "tape" during combat (or a manual session).
-- Capture rules are ported from CastHistory (DNT filtering, channel-tick dedup,
-- the PLAYER_ENTERING_WORLD passive-spell flood, on/off-GCD classification),
-- plus a pre-pull ring buffer, spec capture, and a readable secondary-resource
-- snapshot per cast. Everything recorded here is non-Secret in 12.0: own cast
-- spellID/name and secondary resources. Cooldowns/auras/primary resource are
-- Secret in combat and deliberately NOT touched.

ns.Capture = {}

local live = nil          -- active recording: { casts, pullT, manual, class, specID, ... }
local prepull = {}        -- rolling recent casts (absolute t) for lead-in
local suppressUntil = 0
local activeChannelName, channelValidUntil = nil, 0
local run = nil           -- active dungeon/raid/M+ run: { key, label, startT, mapID }

-- Returns (instanceName, mapID) when in a dungeon/raid/scenario, else nil.
local function instanceRunContext()
  local inInstance, itype = IsInInstance()
  if inInstance and (itype == "party" or itype == "raid" or itype == "scenario") then
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    return name or "Instance", mapID
  end
  return nil
end

local function currentSpec()
  local _, class = UnitClass("player")
  local specID
  if GetSpecialization then
    local idx = GetSpecialization()
    if idx and GetSpecializationInfo then
      specID = GetSpecializationInfo(idx)
    end
  end
  return class, specID
end

-- Active hero talent spec (subTreeID + name). Readable out of combat; can't be
-- changed in combat. Cooldown windows can be filtered by this.
local function currentHeroSpec()
  local id
  if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
    local ok, v = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
    if ok then id = v end
  end
  local name
  if id and C_Traits and C_Traits.GetSubTreeInfo and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    local cfg = C_ClassTalents.GetActiveConfigID()
    if cfg then
      local ok, info = pcall(C_Traits.GetSubTreeInfo, cfg, id)
      if ok and info then name = info.name end
    end
  end
  return id, name
end

-- Read a secondary resource WITHOUT ever doing forbidden math on a Secret: the
-- "+ 0" forces evaluation inside pcall, so a Secret (shouldn't happen for
-- secondary resources, but be safe) yields nil instead of a thrown error or an
-- unserializable value in SavedVariables.
-- Count of READY runes. UnitPower(player, Runes) returns total rune slots (a
-- constant 6), not how many are off cooldown — so for runes we count the ready
-- ones via GetRuneCooldown's boolean `runeReady` return (a boolean, not a
-- Secret-prone number). Guarded in case rune cooldowns are Secret in combat.
local function readReadyRunes()
  local ok, n = pcall(function()
    local c = 0
    for i = 1, 6 do
      local _, _, ready = GetRuneCooldown(i)
      if ready == true then c = c + 1 end
    end
    return c
  end)
  if ok then return n end
  return nil
end

local function readSecondary(powerType)
  if powerType == nil then return nil end
  if Enum and Enum.PowerType and powerType == Enum.PowerType.Runes then
    return readReadyRunes()
  end
  local ok, v = pcall(function() return UnitPower("player", powerType) + 0 end)
  if ok then return v end
  return nil
end

-- Best-effort enemy name. Inside instances, enemy unit identity is Secret in
-- 12.0 — UnitName returns a Secret string, so concatenation throws and we fall
-- back to nil. Outside instances it reads normally.
local function readTargetName()
  local ok, name = pcall(function()
    local n = UnitName("target")
    if not n then return nil end
    if UnitIsUnit and UnitIsUnit("target", "player") then return nil end
    return n .. "" -- forces a Secret to error
  end)
  if ok and type(name) == "string" and name ~= "" then return name end
  return nil
end

local function classify(spellID, info)
  local _, gcdMS = GetSpellBaseCooldown(spellID)
  return (gcdMS or 0) > 0 or (info.castTime or 0) > 0 or ns.Const.FORCE_ON_GCD[spellID] == true
end

local function trimPrepull(now)
  local cutoff = now - (ns.DB.settings.prepullSec or 5)
  while prepull[1] and prepull[1].t < cutoff do table.remove(prepull, 1) end
end

-- Build a normalized cast record from a successful cast, applying all filters.
-- Returns the record or nil if it should be dropped.
local function buildCast(spellID)
  if GetTime() < suppressUntil then return nil end
  local info = C_Spell.GetSpellInfo(spellID)
  if not info then return nil end
  if info.name and (info.name:find("%(DNT%)") or info.name:sub(1, 5) == "[DNT]") then
    return nil
  end
  return {
    spellID = spellID,
    name = info.name,
    icon = info.iconID,
    t = GetTime(),
    onGCD = classify(spellID, info),
    res = live and readSecondary(live.secondaryPower) or nil,
  }
end

local function isDup(list, rec)
  local last = list[#list]
  return last and last.name == rec.name and (rec.t - last.t) < 0.25
end

local function onCast(spellID)
  local rec = buildCast(spellID)
  if not rec then return end

  -- Always feed the pre-pull buffer (dedup against it too).
  if not isDup(prepull, rec) then
    table.insert(prepull, rec)
  end
  trimPrepull(rec.t)

  if live then
    if not isDup(live.casts, rec) then
      table.insert(live.casts, rec)
    end
  end
end

function ns.Capture:IsRecording() return live ~= nil end
function ns.Capture:IsManual() return live ~= nil and live.manual end

function ns.Capture:StartPull(manual)
  if live then return end
  local class, specID = currentSpec()
  local heroSpec, heroSpecName = currentHeroSpec()
  local pullT = GetTime()
  live = {
    casts = {},
    pullT = pullT,
    manual = manual or false,
    class = class,
    specID = specID,
    heroSpec = heroSpec,
    heroSpecName = heroSpecName,
    secondaryPower = ns.DB:GetSecondaryPower(class, specID),
    resLabel = ns.DB:GetSecondaryLabel(class, specID),
    zone = (GetSubZoneText and GetSubZoneText() ~= "" and GetSubZoneText()) or (GetZoneText and GetZoneText()) or "",
    targetHint = readTargetName(),
    encounterName = nil,
  }
  -- Fold in the pre-pull lead-in (re-snapshot resource isn't possible after the
  -- fact, so prepull casts keep whatever res they had; resource may be nil if it
  -- was recorded before we knew the spec's power type — acceptable for lead-in).
  trimPrepull(pullT)
  for _, c in ipairs(prepull) do
    table.insert(live.casts, c)
  end
  wipe(prepull)
end

function ns.Capture:Stop()
  if not live then return end
  local pullT = live.pullT
  local endT = GetTime()
  local casts = live.casts

  -- Normalize timestamps to be relative to the pull (t=0). Pre-pull casts are
  -- negative. Drop a tape that captured nothing.
  if #casts == 0 then live = nil; return nil end
  for _, c in ipairs(casts) do c.t = c.t - pullT end

  local durationSec = endT - pullT
  -- Auto pulls shorter than minPullSec are noise (a stray mob tag); skip them.
  if not live.manual and durationSec < (ns.DB.settings.minPullSec or 3) then
    live = nil; return nil
  end

  -- If a boss frame is up at the end and we still have no label, try it (boss
  -- frame names may be readable even when target names weren't).
  local label = live.encounterName or live.targetHint or live.zone
  if not label or label == "" then label = "Pull" end

  local tape = {
    char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"),
    class = live.class,
    specID = live.specID,
    heroSpec = live.heroSpec,
    heroSpecName = live.heroSpecName,
    manual = live.manual,
    startedReal = date("%Y-%m-%d %H:%M"),
    zone = live.zone,
    label = label,
    resLabel = live.resLabel,
    encounterName = live.encounterName,
    groupKey = run and run.key,
    groupLabel = run and run.label,
    runOffset = run and (pullT - run.startT) or nil,
    durationSec = durationSec,
    casts = casts,
  }
  live = nil
  ns.DB:AddTape(tape)
  if ns.UI and ns.UI.OnTapeAdded then ns.UI:OnTapeAdded(tape) end
  return tape
end

function ns.Capture:Register()
  local f = CreateFrame("Frame", "PullReviewCapture")
  f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
  f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("ENCOUNTER_START")
  f:RegisterEvent("CHALLENGE_MODE_START")

  f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    -- a1/a2/a3 are the first three event payload args. For spellcast events
    -- that's (unit, castGUID, spellID); for ENCOUNTER_START it's
    -- (encounterID, encounterName, difficultyID).
    local unit, spellID = a1, a3
    if event == "PLAYER_ENTERING_WORLD" then
      suppressUntil = GetTime() + 1.5
      -- Start/clear an instance run. M+ relabels it via CHALLENGE_MODE_START.
      local name, mapID = instanceRunContext()
      if name then
        if not run or run.mapID ~= mapID then
          run = { key = ns.DB:NextRunId(), label = name, startT = GetTime(), mapID = mapID }
        end
      else
        run = nil
      end
      return
    elseif event == "CHALLENGE_MODE_START" then
      -- a1 = challenge map ID. Enrich (or start) the run with the key label.
      local mapID = a1
      local mapName = (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)) or (run and run.label) or "Mythic+"
      local level = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo and (C_ChallengeMode.GetActiveKeystoneInfo())
      if not run then run = { key = ns.DB:NextRunId(), startT = GetTime() } end
      run.mapID = mapID
      run.label = mapName .. (level and (" +" .. level) or "")
      return
    elseif event == "ENCOUNTER_START" then
      -- encounterName (a2) is provided by the event, not a unit query, so it's
      -- readable even in instances where unit names are Secret.
      if live then live.encounterName = a2 end
      return
    elseif event == "PLAYER_REGEN_DISABLED" then
      if ns.DB.settings.autoRecord and not live then
        ns.Capture:StartPull(false)
      end
      return
    elseif event == "PLAYER_REGEN_ENABLED" then
      -- Manual recordings span across combats; only auto pulls end here.
      if live and not live.manual then ns.Capture:Stop() end
      return
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
      local info = C_Spell.GetSpellInfo(spellID)
      activeChannelName = info and info.name
      channelValidUntil = math.huge
      onCast(spellID)
      return
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
      channelValidUntil = GetTime() + 0.5
      return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if activeChannelName and GetTime() < channelValidUntil then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name == activeChannelName then return end
      end
      onCast(spellID)
    end
  end)

  self.frame = f
end
