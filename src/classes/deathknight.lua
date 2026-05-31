local _, ns = ...
local PT = Enum and Enum.PowerType or {}

-- ===================== COOLDOWN ENTRY OPTIONS =========================
--   spellID   = number         anchor: this cast opens a window
--   spellIDs  = {num, ...}      multi-anchor: ANY of these casts opens the window
--   label     = string         display name; entries sharing a label MERGE into one track
--   preCasts  = number         include N casts before the anchor as lead-in
--   preSec    = number         OR include casts within N seconds before the anchor
--   baseSec   = number         base window length (seconds) after the anchor
--   extend    = { spells = {ids}, perCast = sec }   casts that extend the window while open
--   expect    = { { spellID = n, count = n, label = "…" }, … }   "did you cast it?" check
--   heroSpec  = number         only on tapes with this hero subTreeID; nil = all hero specs
-- ===================== SPEC-LEVEL OPTIONS =============================
--   secondaryPower = Enum.PowerType.X   resource column (label derives automatically)
--   secondaryLabel = string             override the derived resource label
--   openerSec      = number             per-spec opener length override
-- =====================================================================

ns.SpecData:Register("DEATHKNIGHT", {
  -- 252 = Unholy
  [252] = {
    secondaryPower = PT.Runes, -- ready-rune count; label derives to "Runes"
    cooldowns = {
      {
        spellID = 1233448, label = "Dark Transformation", -- verified from tape
        preCasts = 2, baseSec = 15,
        -- Eternal Agony: Runic Power spenders extend DT by 1s. Necrotic Coil is
        -- the Army-of-the-Dead transformed Death Coil.
        extend = { spells = { 47541, 1242174, 207317 }, perCast = 1 },
        -- TODO add Graveyard (Epidemic during Army) ID once seen in a tape.
      },
      { spellID = 42650, label = "Army of the Dead", preCasts = 1, baseSec = 30 },
    },
  },
})
