local _, ns = ...

-- Per-spec cooldown-window configuration. This is the "configure from code"
-- layer; users can override/extend any of it in-game (stored in DB.specConfig,
-- edited via /pr cd ...). Each cooldown entry:
--
--   spellID   anchor: the cooldown cast that opens a window
--   label     display name
--   preCasts  include this many casts immediately BEFORE the anchor (lead-in)
--   preSec    OR include casts within this many seconds before the anchor
--   baseSec   base window length after the anchor
--   extend    optional dynamic length: { spells = {ids...}, perCast = seconds }
--             each listed spell cast while the window is open pushes its end out
--             (chains: a late spender can be inside the already-extended window)
--   expect    optional "should have cast" check: { {spellID=, count=, label=} }
--             the reviewer flags it if you cast fewer than `count` in the window
--
-- IMPORTANT on spellIDs: verify against your spellbook. The easy way — record one
-- pull, open the tape, and read the exact spellID off each row (the reviewer
-- shows it), then `/pr cd extend add <id>` etc. Hero-talent transforms (e.g.
-- Death Coil -> Necrotic Coil, Epidemic -> Graveyard during Army of the Dead)
-- fire under DIFFERENT spellIDs, so add those variants to the extend list once
-- you've seen them in a tape.

local PT = Enum and Enum.PowerType or {}

ns.SpecData = {}

local defaults = {
  DEATHKNIGHT = {
    -- 252 = Unholy
    [252] = {
      secondaryPower = PT.Runes,   -- ready-rune count (readable); Runic Power is primary/secret
      secondaryLabel = "Runes",
      cooldowns = {
        {
          spellID = 1233448, label = "Dark Transformation", -- verified from tape
          preCasts = 2, baseSec = 15,
          -- Eternal Agony: each Runic Power spender extends DT by 1s. Necrotic
          -- Coil / Graveyard are the Army-of-the-Dead transformed variants.
          extend = {
            spells = {
              47541,    -- Death Coil
              1242174,  -- Necrotic Coil (Death Coil during Army) — verified from tape
              207317,   -- Epidemic
              -- TODO add Graveyard (Epidemic during Army) once seen in a tape
            },
            perCast = 1,
          },
        },
        {
          spellID = 42650, label = "Army of the Dead",  -- confirmed working in testing
          preCasts = 1, baseSec = 30, -- fixed duration
        },
      },
    },
  },

  -- Example schema reference (not active unless a HUNTER/253 tape is recorded).
  -- Shows the `expect` "did you cast it?" check — BM's single allowed cast inside
  -- Bestial Wrath, lost if the 15s expires first. Fill in the real IDs from a tape.
  -- HUNTER = {
  --   [253] = {
  --     secondaryPower = nil,
  --     cooldowns = {
  --       { spellID = 19574, label = "Bestial Wrath", preCasts = 1, baseSec = 15,
  --         expect = { { spellID = 0 --[[Wind Arrow id]], count = 1, label = "Wind Arrow" } } },
  --     },
  --   },
  -- },
}

function ns.SpecData:Get(class, specID)
  local c = defaults[class]
  return c and c[specID]
end

ns.SpecData.defaults = defaults
