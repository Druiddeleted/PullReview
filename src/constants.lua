local _, ns = ...

-- Shared lookup tables, kept in one place for easy maintenance. Per-class/spec
-- cooldown CONFIG lives in specdata.lua (its own data file); this file is only
-- the generic, cross-cutting constants.

ns.Const = {}

local PT = Enum and Enum.PowerType or {}

-- Localized power-type -> display label. The resource column names itself per
-- spec from this (Runes, Combo Points, …). Distinct negative fallback keys avoid
-- collisions when a given Enum.PowerType is absent on this build.
ns.Const.POWER_LABEL = {
  [PT.ComboPoints or -1] = COMBO_POINTS or "Combo Points",
  [PT.Runes or -2] = RUNES or "Runes",
  [PT.RunicPower or -3] = RUNIC_POWER or "Runic Power",
  [PT.SoulShards or -4] = SOUL_SHARDS or "Soul Shards",
  [PT.LunarPower or -5] = LUNAR_POWER or "Astral Power",
  [PT.HolyPower or -6] = HOLY_POWER or "Holy Power",
  [PT.Maelstrom or -7] = MAELSTROM or "Maelstrom",
  [PT.Chi or -8] = CHI or "Chi",
  [PT.Insanity or -9] = INSANITY or "Insanity",
  [PT.ArcaneCharges or -10] = ARCANE_CHARGES or "Arcane Charges",
  [PT.Essence or -11] = "Essence",
  [PT.Fury or -12] = "Fury",
  [PT.Pain or -13] = "Pain",
}

-- Off-GCD in the spell DB but visually the player's primary inputs (skyriding);
-- forced onto the main timeline row.
ns.Const.FORCE_ON_GCD = {
  [372610] = true, -- Skyward Ascent
  [361584] = true, -- Surge Forward
  [361585] = true, -- Whirling Surge
  [368896] = true, -- Take to the Skies
  [374990] = true, -- Bronze Timelock
  [425951] = true, -- Land
}

-- Lust / Heroism family (+ Drums). Anchors the global "Lust" window. Maintain
-- the list here. NOTE: only detectable when YOU cast it (buffs are Secret in
-- combat) — self-provided lust, Drums, etc.
ns.Const.LUST_SPELLS = {
  2825,    -- Bloodlust (Shaman)
  32182,   -- Heroism (Shaman)
  80353,   -- Time Warp (Mage)
  264667,  -- Primal Rage (Hunter pet)
  390386,  -- Fury of the Aspects (Evoker)
  309658,  -- Drums of Fury (verify; add other drum IDs as needed)
}
