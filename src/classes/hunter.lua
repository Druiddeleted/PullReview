local _, ns = ...

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

ns.SpecData:Register("HUNTER", {
  -- 253 = Beast Mastery. No readable secondary (Focus is primary/Secret), so the
  -- resource column auto-hides for these tapes.
  [253] = {
    -- Cobra Shot / Barbed Shot / Black Arrow each set the (single) "next Kill
    -- Command" buff; Kill Command consumes it. Unbuffed KC is a mistake, so flag
    -- it red. (Black Arrow only exists on Dark Ranger; harmless otherwise.)
    buffs = {
      {
        label = "Kill Command",
        grantedBy = { 193455, 217200, 466930 }, -- Cobra Shot, Barbed Shot, Black Arrow
        consumedBy = { 34026 },                  -- Kill Command
        maxStacks = 1, stacksPerGrant = 1, flagUnbuffed = true,
      },
    },
    cooldowns = {
      -- Wailing Arrow: 1 allowed cast inside Bestial Wrath, lost if the 15s
      -- expires first — flagged by the expect check.
      {
        spellID = 19574, label = "Bestial Wrath", preCasts = 1, baseSec = 15,
        expect = { { spellID = 392060, count = 1, label = "Wailing Arrow" } },
      },
      -- Add Call of the Wild here (or via /pr dev) once you confirm its ID.
      -- Dark Ranger windows (Black Arrow 466930, Wailing Arrow 392060) can be
      -- added with heroSpec set so they only show on Dark Ranger tapes.
    },
  },
})
