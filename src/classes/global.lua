local _, ns = ...

-- Global windows: apply to EVERY spec, merged on top of per-spec cooldowns.
-- (See src/specdata.lua for the full COOLDOWN ENTRY OPTIONS reference.)
--   spellID/spellIDs · label · preCasts/preSec · baseSec · extend · expect · heroSpec
--
-- Lust is a BUFF (Secret in combat), so it only registers when YOU cast it
-- (self-provided lust, Drums, potions). Add potions as separate rows all labeled
-- "Potion" — each can have its own baseSec — and they merge into one track.

ns.SpecData:RegisterGlobals({
  { label = "Lust", preCasts = 0, baseSec = 40, spellIDs = ns.Const.LUST_SPELLS },
  -- Placeholder Potion track (greyed until used). Add your DPS potion's effect
  -- spellID + duration here or via /pr dev. Different potions can be separate
  -- rows with their own baseSec.
  { label = "Potion", preCasts = 0, baseSec = 30, spellIDs = {} },
})
