local _, ns = ...

-- PullReview stores per-pull "tapes" (cast logs) plus UI settings and any
-- user overrides to the per-spec cooldown-window config. Account-wide so every
-- alt's tapes live in one list; each tape is tagged with its character.

ns.DB = {}

local settingsDefaults = {
  -- reviewer window geometry
  point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
  width = 760, height = 480,
  -- recording behavior
  autoRecord = true,      -- auto-capture each combat as a tape
  minPullSec = 3,         -- discard auto pulls shorter than this
  prepullSec = 5,         -- seconds of pre-pull casts to fold into a tape
  maxTapes = 25,          -- prune to this many (pinned tapes never pruned)
  -- analysis defaults
  openerSec = 12,         -- "opener" = first N seconds of the pull
  gapThreshold = 1.6,     -- highlight a cast gap longer than this (dead GCD)
  showResource = true,    -- show the secondary-resource column
  fontScale = 1.0,        -- cast-log font scale
}

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, val in pairs(v) do t[k] = deepcopy(val) end
  return t
end
ns.deepcopy = deepcopy

function ns.DB:Init()
  PullReviewDB = PullReviewDB or {}
  PullReviewDB.settings = PullReviewDB.settings or {}
  for k, v in pairs(settingsDefaults) do
    if PullReviewDB.settings[k] == nil then PullReviewDB.settings[k] = v end
  end
  PullReviewDB.tapes = PullReviewDB.tapes or {}
  PullReviewDB.specConfig = PullReviewDB.specConfig or {} -- [class][specID] = {cooldowns=..., openerSec=...}
  PullReviewDB.nextId = PullReviewDB.nextId or 1
  PullReviewDB.debug = PullReviewDB.debug or false
  PullReviewDB.devMode = PullReviewDB.devMode or false

  self.settings = PullReviewDB.settings
  self.defaults = settingsDefaults
end

function ns.DB:NextId()
  local id = PullReviewDB.nextId
  PullReviewDB.nextId = id + 1
  return id
end

-- Newest first.
function ns.DB:Tapes()
  return PullReviewDB.tapes
end

function ns.DB:GetTape(id)
  for _, t in ipairs(PullReviewDB.tapes) do
    if t.id == id then return t end
  end
end

function ns.DB:AddTape(tape)
  tape.id = self:NextId()
  table.insert(PullReviewDB.tapes, 1, tape) -- newest at front
  self:Prune()
  return tape
end

function ns.DB:Prune()
  local tapes = PullReviewDB.tapes
  local max = self.settings.maxTapes
  -- Walk newest->oldest counting unpinned; remove unpinned beyond the cap.
  local kept = 0
  local i = 1
  while i <= #tapes do
    local t = tapes[i]
    if t.pinned then
      i = i + 1
    else
      kept = kept + 1
      if kept > max then
        table.remove(tapes, i)
      else
        i = i + 1
      end
    end
  end
end

function ns.DB:DeleteTape(id)
  for i, t in ipairs(PullReviewDB.tapes) do
    if t.id == id then table.remove(PullReviewDB.tapes, i); return true end
  end
end

function ns.DB:ClearTapes()
  wipe(PullReviewDB.tapes)
end

-- --- per-spec cooldown config (defaults from SpecData, overridable here) ------

-- Effective cooldown list for a spec: the user's override if present, else a
-- deep copy of the shipped default. Returns (list, isUserOverride).
function ns.DB:GetCooldowns(class, specID)
  if not (class and specID) then return {}, false end
  local user = PullReviewDB.specConfig[class] and PullReviewDB.specConfig[class][specID]
  if user and user.cooldowns then return user.cooldowns, true end
  local def = ns.SpecData:Get(class, specID)
  return def and deepcopy(def.cooldowns) or {}, false
end

local function override(class, specID)
  return class and specID and PullReviewDB.specConfig[class] and PullReviewDB.specConfig[class][specID]
end

-- Ensure a writable user override entry exists (seeded from default), return it.
function ns.DB:EnsureSpecOverride(class, specID)
  PullReviewDB.specConfig[class] = PullReviewDB.specConfig[class] or {}
  local entry = PullReviewDB.specConfig[class][specID]
  if not entry then
    local def = ns.SpecData:Get(class, specID)
    -- Note: openerSec is intentionally NOT seeded. A nil here means "use the
    -- global settings slider"; the user sets a per-spec opener only by typing
    -- one into the dev editor.
    entry = {
      cooldowns = def and deepcopy(def.cooldowns) or {},
      secondaryPower = def and def.secondaryPower,
      secondaryLabel = def and def.secondaryLabel,
    }
    PullReviewDB.specConfig[class][specID] = entry
  end
  entry.cooldowns = entry.cooldowns or {}
  return entry
end

-- Back-compat helper used by the slash editor.
function ns.DB:EnsureUserCooldowns(class, specID)
  return self:EnsureSpecOverride(class, specID).cooldowns
end

function ns.DB:ResetSpecOverride(class, specID)
  if PullReviewDB.specConfig[class] then PullReviewDB.specConfig[class][specID] = nil end
end

-- Precedence: explicit per-spec override (dev editor) > global settings slider.
-- The shipped per-spec value is no longer used here so the slider always works.
function ns.DB:GetOpenerSec(class, specID)
  local u = override(class, specID)
  if u and u.openerSec then return u.openerSec end
  return self.settings.openerSec
end

function ns.DB:GetSecondaryPower(class, specID)
  local u = override(class, specID)
  if u and u.secondaryPower ~= nil then return u.secondaryPower end
  local def = ns.SpecData:Get(class, specID)
  return def and def.secondaryPower
end

function ns.DB:GetSecondaryLabel(class, specID)
  local u = override(class, specID)
  if u and u.secondaryLabel then return u.secondaryLabel end
  local def = ns.SpecData:Get(class, specID)
  return (def and def.secondaryLabel) or "Res"
end
