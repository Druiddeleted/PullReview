## 0.0.1

Early work-in-progress (alpha). Expect rough edges; per-spec cooldown defaults are
incomplete and spell IDs may need correcting via the in-game dev editor.

- Records each combat as a reviewable "tape" of your casts (`UNIT_SPELLCAST_SUCCEEDED`), including a few seconds of pre-pull lead-in.
- Manual recording with `/pr start` and `/pr stop`.
- Reviewer window (`/pr`): per-pull cast timeline with relative timestamps, scroll, PRE-PULL/PULL split, and dead-GCD gap highlighting.
- Segment views: Whole pull, Opener (first N seconds), and per-cooldown windows.
- Cooldown windows support dynamic durations (e.g. spenders extending Dark Transformation) and a "did you cast it?" expected-spell check.
- Secondary-resource column (combo points, runes, etc. — the resources still readable in 12.0).
- In-app cooldown editor via `/pr cd` (list / add / remove / extend) on top of shipped per-spec defaults (seeded: Unholy Death Knight).
