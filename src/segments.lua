local _, ns = ...

-- Pure analysis over a recorded tape. No Secret data involved — everything is
-- index/time math over the cast list (spellIDs + timestamps), so it's all legal
-- and deterministic. A tape's casts are ordered by time (pre-pull casts have
-- t < 0; the pull is t >= 0).

ns.Segments = {}

local function castsInRange(casts, fromT, toT)
  local out = {}
  for _, c in ipairs(casts) do
    if c.t >= fromT and c.t <= toT then out[#out + 1] = c end
  end
  return out
end

-- The opener: casts from the pull (t>=0) up to openerSec.
function ns.Segments:Opener(tape)
  local secs = ns.DB:GetOpenerSec(tape.class, tape.specID)
  return {
    label = "Opener",
    fromT = 0,
    toT = secs,
    casts = castsInRange(tape.casts, 0, secs),
  }
end

local function inList(list, spellID)
  if not list then return false end
  for _, id in ipairs(list) do if id == spellID then return true end end
  return false
end

-- Compute a single cooldown window anchored at casts[anchorIdx].
local function buildWindow(casts, anchorIdx, cd, occurrence)
  local anchor = casts[anchorIdx]
  local anchorT = anchor.t

  -- lead-in start
  local startT = anchorT
  if cd.preSec then
    startT = anchorT - cd.preSec
  elseif cd.preCasts then
    local sIdx = math.max(1, anchorIdx - cd.preCasts)
    startT = casts[sIdx].t
  end

  -- end: base, then dynamic extension (each spender cast while open pushes it out)
  local base = anchorT + (cd.baseSec or 0)
  local endT = base
  if cd.extend and cd.extend.perCast then
    for i = anchorIdx + 1, #casts do
      local c = casts[i]
      if c.t > endT then break end          -- window already closed
      if inList(cd.extend.spells, c.spellID) then
        endT = endT + cd.extend.perCast
      end
    end
  end

  local windowCasts = castsInRange(casts, startT, endT)

  -- expect / "did you cast it?" check
  local missing
  if cd.expect then
    for _, e in ipairs(cd.expect) do
      local got = 0
      for _, c in ipairs(windowCasts) do
        if c.spellID == e.spellID then got = got + 1 end
      end
      local want = e.count or 1
      if got < want then
        missing = missing or {}
        missing[#missing + 1] = { label = e.label or ("spell " .. e.spellID), spellID = e.spellID, got = got, want = want }
      end
    end
  end

  return {
    occurrence = occurrence,
    label = cd.label,
    spellID = cd.spellID,
    anchorT = anchorT,
    startT = startT,
    endT = endT,
    baseSec = cd.baseSec or 0,
    extendedBy = endT - base,   -- seconds added beyond base
    casts = windowCasts,
    missing = missing,
  }
end

-- All cooldown tracks for a tape. Returns a list of groups:
--   { label, spellID, occurrences = { window, ... } }
-- Groups with zero occurrences are included (so the reviewer can surface "you
-- never pressed X this pull").
function ns.Segments:CooldownTracks(tape)
  local cds = ns.DB:GetCooldowns(tape.class, tape.specID)
  local casts = tape.casts
  local groups = {}
  for _, cd in ipairs(cds) do
    local group = { label = cd.label, spellID = cd.spellID, occurrences = {} }
    local occ = 0
    for idx, c in ipairs(casts) do
      if c.spellID == cd.spellID then
        occ = occ + 1
        group.occurrences[#group.occurrences + 1] = buildWindow(casts, idx, cd, occ)
      end
    end
    groups[#groups + 1] = group
  end
  return groups
end

-- Gaps longer than the threshold between consecutive casts (dead GCD time).
-- Returns a set keyed by cast index -> gap seconds (the gap BEFORE that cast).
function ns.Segments:Gaps(casts, threshold)
  local gaps = {}
  for i = 2, #casts do
    local dt = casts[i].t - casts[i - 1].t
    if dt > threshold then gaps[i] = dt end
  end
  return gaps
end
