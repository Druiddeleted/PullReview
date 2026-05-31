# PullReview

Records each pull as a reviewable **cast tape** — a scrollable timeline of everything you cast, segmented into the whole pull, your opener, and your cooldown windows. Think of it as a personal, in-game version of the Raidbots / SimulationCraft "Sample Ability Log", built from your *actual* casts so you can eyeball your rotation side-by-side with a sim without uploading to a log site.

Designed to be used alongside [CastHistory](https://github.com/Druiddeleted/CastHistory) (the live overlay); PullReview is the persistent post-combat analyzer.

## What it can and can't show (WoW 12.0 "Midnight")

Patch 12.0's **Secret Values** make spell cooldowns, auras/buffs, and your primary resource unreadable to addons *during combat* — so no addon can show a live "you wasted a proc / had X focus" coach anymore. PullReview deliberately sticks to what stays readable in combat:

- ✅ Your **cast sequence** (spell + timestamp) via `UNIT_SPELLCAST_SUCCEEDED`
- ✅ **Secondary resources** (combo points, runes, holy power, soul shards, chi, …)
- ✅ Everything analyzable **after** the pull: order, timing, dead-GCD gaps, opener, cooldown windows
- ❌ Buff/proc state and cooldown availability during combat (Secret — not shown by design)

Cooldown-window durations and "did you cast it?" checks are *reconstructed* from your cast list and the spec config, not read from the (Secret) buff — accurate as long as the config matches the live talent behavior.

## Usage

- `/pr` — open the reviewer (pick a pull on the left; choose a segment on the right)
- `/pr last` — open the most recent pull
- `/pr start` / `/pr stop` — manual recording (auto-recording per combat is on by default)
- `/pr config` — settings (auto-record, opener length, gap threshold, max stored pulls, …)
- `/pr clear` — delete all stored pulls
- Right-click a pull in the list to **pin** it (pinned pulls are never auto-pruned)

### Cooldown windows

Each spec ships with default major-cooldown definitions (seeded: Unholy Death Knight). Edit them in-game:

- `/pr cd list` — show this spec's cooldown windows
- `/pr cd add <spellID> <label>` — add a window (defaults: 1 cast lead-in, 15s)
- `/pr cd remove <spellID>` — remove one
- `/pr cd extend <anchorID> <spenderID>` — toggle a spender that extends the window (e.g. Death Coil extending Dark Transformation; add the Army-of-the-Dead transformed variants here once you see their spellIDs in a tape)

Tip: record a pull, open the tape, and read the exact spellIDs off each row — then add/extend with confidence.

## License

MIT. See LICENSE.
