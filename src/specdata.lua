local _, ns = ...

-- Master cooldown-window config registry. Per-class definitions live in
-- src/classes/<class>.lua and register themselves into here; global (all-spec)
-- windows live in src/classes/global.lua. This file holds only the registry and
-- the lookup the rest of the addon reads through — to add/maintain a class, edit
-- (or create) its file under src/classes/ and add it to the .toc.
--
-- ===================== COOLDOWN ENTRY OPTIONS =========================
--   spellID   = number         anchor: this cast opens a window
--   spellIDs  = {num, ...}      multi-anchor: ANY of these casts opens the window
--   label     = string         display name; entries sharing a label MERGE into one track
--   preCasts  = number         include N casts before the anchor as lead-in
--   preSec    = number         OR include casts within N seconds before the anchor
--   baseSec   = number         base window length (seconds) after the anchor
--   extend    = { spells = {ids}, perCast = sec }
--                               each listed cast while the window is open extends its end
--   expect    = { { spellID = n, count = n, label = "…" }, … }
--                               flags if you cast fewer than `count` of it in the window
--   heroSpec  = number         only apply on tapes recorded with this hero subTreeID;
--                               nil = applies on every hero spec
-- ===================== SPEC-LEVEL OPTIONS =============================
--   secondaryPower = Enum.PowerType.X   resource-column source (label derives automatically)
--   secondaryLabel = string             override the derived resource label
--   openerSec      = number             per-spec opener length override
-- =====================================================================

ns.SpecData = { defaults = {}, globals = {} }

-- specs = { [specID] = { secondaryPower=, openerSec=, cooldowns = { ... } }, ... }
function ns.SpecData:Register(classFile, specs)
  self.defaults[classFile] = specs
end

function ns.SpecData:RegisterGlobals(list)
  self.globals = list
end

function ns.SpecData:Get(class, specID)
  if class == "GLOBAL" then
    return { cooldowns = self.globals }
  end
  local c = self.defaults[class]
  return c and c[specID]
end
