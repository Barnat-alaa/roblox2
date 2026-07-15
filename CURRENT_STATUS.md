# Current Status

Last updated: 2026-07-15

## Environment

- Repository: `https://github.com/Barnat-alaa/roblox2.git`.
- Development is file-based through Rojo; generated `.rbxlx` files are used for Studio tests.
- The inspected owner place remains unpublished (`PlaceId = 0`, `UniverseId = 0`).
- No production publication, cloud data, paid product, or Robux action has been performed.
- Current Development build marker: `0.5.0-dev`.

## Phase 1 combat-correctness implementation

Phase 1 is code-complete and awaiting the user-run Studio acceptance pass.

- The server owns active-turn movement. Requests carry an exact match ID, turn token, and
  monotonic sequence and pass a burst-safe token bucket before reaching character state.
- Horizontal movement enforces arena and combat-plane bounds, maximum speed, and a cumulative
  absolute-distance allowance, so reversing direction cannot bypass the turn budget.
- Jumping enforces physical ground evidence, cooldown, per-turn count, R6/R15 foot geometry,
  and explicit server authorization. Off-turn/default Humanoid jumping is disabled.
- Input leases stop a character safely after lost release packets; reaching zero movement
  budget stops the Humanoid without continuous correction jitter.
- The logical terrain grid exposes a bounded, footprint-aware support query that treats
  hazards as terminal support rather than allowing recovery through them.
- Humans and the BotCritter use bounded environmental settling with a minimum observation
  time, consecutive stable samples, a hard timeout, vertical recovery to the first legal
  support, and elimination for hazard/no-support/death-height outcomes.
- Aiming timeout now uses the same settlement path, so a last-second jump cannot reset the
  match or start the next turn while a combatant is airborne.
- BotCritter is a physical, server-owned pawn with massless welded visuals, an independent
  transparent collision hull, and an upright constraint.
- Explosion damage and knockback are restricted to the exact live match roster. Spectators,
  unrelated Humanoids, and stale-match actors cannot be damaged through the combat service.
- Projectile completion uses match-scoped resolution leases and guaranteed finalization;
  stale projectiles cannot mutate terrain, deal damage, or advance a later match.
- Character readiness has a fresh bounded wait whenever any living human or bot is unready.
  Results has a guarded expiry so an abandoned result screen cannot lock the server forever.
- High-frequency movement diagnostics publish at most once per second, and remaining movement
  replication is cadence-limited to reduce avoidable network work.

## Existing playable foundation

- Deterministic ballistics, round wind, four original weapon definitions, radial damage, and
  bounded knockback.
- A revisioned 45 x 24 terrain grid, dirty 8 x 8 chunks, protected supports/bottom cells,
  central hazard, Snapshot/Delta replication, crater damage, and bounded Mole Drill paths.
- Frozen 1v1 rosters, late-join spectators, solo BotCritter, authoritative elimination,
  Results, unanimous rematch, and fresh-match reset.
- Side camera, aim/power/weapon controls, trajectory preview, projectile presentation, combat
  HUD, Results UI, original code-built squirrel, layered backdrop, and restrained lighting.
- Client work bounds for preview raycasts, effects catch-up, HUD cadence, and terrain rebuilds.

## Phase 2 profile and reward implementation

Phase 2 is implemented in source and awaiting combined Studio acceptance plus a separate
owner-run published Development DataStore validation.

- Profile schema v1 strictly validates bounded integer coins, account XP, economy version,
  win/loss/draw statistics, and a dense processed-reward ledger capped at 64 entries. Account
  level and progress-to-next-level are derived from XP rather than persisted independently.
- Missing profiles receive an explicit starter profile. Schema v0 profiles containing coins
  and either `xp` or legacy `experience` migrate to v1; malformed, ambiguous, unsupported, or
  future schemas fail safely instead of being overwritten with defaults.
- Development DataStore access is isolated behind DataService. Writable sessions use an
  UpdateAsync lease with a unique server owner, bounded retry/backoff and budget waits,
  periodic lease-renewing autosave, ordered per-profile operations, PlayerRemoving release,
  and BindToClose draining.
- Load failures may expose a validated read-only snapshot, while corrupt/future data and
  unavailable storage disable progression writes. Player attributes expose Loading, Ready,
  ReadOnly, Unavailable, and Released status plus storage mode and the latest safe balance/
  derived-level view.
- Because the inspected place is unpublished, Studio explicitly selects a process-local
  session-memory adapter. It exercises the service/reward/UI flow without claiming cloud
  durability and does not persist across Studio stop/start or other server processes.
- Eligible MatchEnd rewards are calculated only from a frozen server result. Abandonment and
  disconnect earn zero; bot rewards use deterministic 85% integer scaling.
- Each reward atomically updates coins, XP, statistics, and its ledger entry. The stable grant
  ID contains Development environment, match ID, and user ID but deliberately excludes the
  economy version, preventing a balance-table change from regranting the same completion.
- Results can show Pending, Granted, Duplicate, Ineligible, ReadOnly, or Unavailable reward
  state. A compact profile panel reads server-owned Player attributes; the client cannot
  submit a balance, reward amount, outcome, or grant ID.

## Validation record

Latest local validation for the Phase 1 source:

- `stylua --check src tests scripts`: passed.
- `selene src tests scripts`: 0 errors, 0 warnings, 0 parse errors.
- Roblox-aware `luau-lsp analyze`: passed.
- Production and TestEZ Rojo builds: passed.
- `git diff --check`: passed.
- Source contains **111 TestEZ specs**, including profile validation/migration, derived-level,
  reward eligibility/calculation/idempotency, ledger-bounding, and session-rule cases.

Runtime truth is intentionally separate: the latest recorded Studio TestEZ execution remains
**56 passed, 0 failed, 0 skipped** from the earlier build. The 111-spec Phase 1/2 source,
Phase 1 physics behavior, and Phase 2 service/UI integration have not yet been accepted in
Studio; the user will provide screenshots or feel reports after testing.

Earlier Studio evidence still includes authoritative human and bot shots, terrain deltas,
elimination, Victory/Defeat Results, two-human rematch, solo disconnect recovery, and a clean
startup. Earlier performance observations were 3.43-5.65 ms BotAim time and 16.65 ms p50 /
17.72 ms p95 / 18.04 ms p99 / 18.37 ms worst server frame time. These measurements predate
Phase 1 and are not representative-device guarantees.

## Review findings addressed

- Turn movement is cumulative, atomic, sequence-scoped, and knockback-aware.
- Grounding requires logical support, low vertical velocity, and physical Humanoid evidence
  for player characters.
- Zero-budget movement, diagnostic replication, and mobile/keyboard input cadence are bounded.
- Bot collision does not depend on HumanoidRootPart collision behavior.
- Support loss, timeout recovery, readiness failure, projectile failure, stale callbacks,
  result expiry, rematch races, and roster-only damage have bounded server-owned outcomes.

## Open development gaps

- Phase 1 still needs the user-run 111-spec Studio execution and movement/support/bot/rematch
  feel pass described in `NEXT_ACTIONS.md`.
- Phase 2 profile/reward integration needs a local session-memory runtime pass. Native
  DataStore persistence, lease contention, retry, leave/rejoin, and shutdown durability need
  owner-run validation in a published private Development place.
- Schema v1 intentionally has no inventory, owned/equipped cosmetic, settings, receipt, quest,
  mastery, or season fields yet.
- There is no real lobby or cross-server matchmaking; Results expiry currently returns to the
  waiting scheduler.
- Late clients can recover terrain snapshots but not an active projectile presentation.
- Mobile controls need real-device safe-area/accessibility tuning; gamepad is not complete.
- Character/environment visuals remain original programmer art awaiting screenshot-driven
  silhouette, palette, animation, effects, audio, and production-asset passes.
- Hosted CI builds the test place but cannot execute Roblox Studio runtime tests without an
  appropriate self-hosted Studio runner.

## Next implementation phase

First complete the combined Phase 1/2 Studio acceptance and owner-run published Development
persistence checks in `NEXT_ACTIONS.md`. The next code milestone is a compact lobby and one
free original cosmetic with validated ownership/equip persistence. Production data remains
disabled; no Production migration, publication, or currency operation is authorized.
