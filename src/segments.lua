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

-- A cooldown's anchor matches a cast by its single spellID or its spellIDs list
-- (multi-anchor, e.g. all the lust variants -> one "Lust" window).
local function anchorMatches(cd, spellID)
  return (cd.spellID and cd.spellID == spellID) or inList(cd.spellIDs, spellID)
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
  local casts = tape.casts

  -- per-spec cooldowns, filtered by the tape's hero spec, then global windows
  -- (lust/potion) which apply to every spec.
  local cds = {}
  for _, cd in ipairs(ns.DB:GetCooldowns(tape.class, tape.specID)) do
    if cd.heroSpec == nil or cd.heroSpec == tape.heroSpec then
      cds[#cds + 1] = cd
    end
  end
  for _, cd in ipairs(ns.DB:GetCooldowns("GLOBAL", 0)) do
    cds[#cds + 1] = cd
  end

  -- Group entries by label so multiple entries (e.g. several potions, each with
  -- its own pre/post window) merge into one time-ordered track that greys out
  -- when unused. One "Potion" track, one "Lust" track, etc.
  local byLabel, order = {}, {}
  for _, cd in ipairs(cds) do
    local g = byLabel[cd.label]
    if not g then
      g = { label = cd.label, spellID = cd.spellID or (cd.spellIDs and cd.spellIDs[1]), occurrences = {} }
      byLabel[cd.label] = g
      order[#order + 1] = g
    end
    for idx, c in ipairs(casts) do
      if anchorMatches(cd, c.spellID) then
        g.occurrences[#g.occurrences + 1] = buildWindow(casts, idx, cd, 0)
      end
    end
  end
  for _, g in ipairs(order) do
    table.sort(g.occurrences, function(a, b) return a.anchorT < b.anchorT end)
    for i, w in ipairs(g.occurrences) do w.occurrence = i end
  end
  return order
end

-- ---- run-level (a whole dungeon/M+ as a group of segments) ------------------

local function sortByOffset(tapes)
  local s = {}
  for _, t in ipairs(tapes) do s[#s + 1] = t end
  table.sort(s, function(a, b) return (a.runOffset or 0) < (b.runOffset or 0) end)
  return s
end

-- One continuous timeline for the whole run: casts placed at runOffset + cast.t,
-- with a "segment" marker before each combat (rendered as a yellow divider).
function ns.Segments:RunItems(tapes)
  local items = {}
  for _, t in ipairs(sortByOffset(tapes)) do
    items[#items + 1] = { segment = true, label = t.label or "Pull" }
    local off = t.runOffset or 0
    local gaps = self:Gaps(t.casts, ns.DB.settings.gapThreshold or 1.6)
    for i, c in ipairs(t.casts) do
      items[#items + 1] = { t = off + c.t, icon = c.icon, name = c.name, spellID = c.spellID, onGCD = c.onGCD, res = c.res, gapBefore = gaps[i] }
    end
  end
  return items
end

-- Distinct cooldown-track labels that actually fired somewhere in the run.
function ns.Segments:RunTrackLabels(tapes)
  local seen, order = {}, {}
  for _, t in ipairs(tapes) do
    for _, g in ipairs(self:CooldownTracks(t)) do
      if #g.occurrences > 0 and not seen[g.label] then
        seen[g.label] = true
        order[#order + 1] = g.label
      end
    end
  end
  return order
end

-- Every occurrence of one cooldown across the whole run, each re-zeroed to its
-- anchor and separated by a divider naming the segment + occurrence.
function ns.Segments:RunCDItems(tapes, label)
  local items = {}
  for _, t in ipairs(sortByOffset(tapes)) do
    for _, g in ipairs(self:CooldownTracks(t)) do
      if g.label == label then
        for _, w in ipairs(g.occurrences) do
          items[#items + 1] = { divider = true, label = string.format("%s — %s #%d", t.label or "Pull", label, w.occurrence) }
          for _, c in ipairs(w.casts) do
            items[#items + 1] = { t = c.t - w.anchorT, icon = c.icon, name = c.name, spellID = c.spellID, onGCD = c.onGCD, res = c.res }
          end
        end
      end
    end
  end
  return items
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
