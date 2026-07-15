# Current Status

Last updated: 2026-07-15

## Environment

- Repository: `https://github.com/Barnat-alaa/roblox2.git`.
- Development is file-based through Rojo; generated `.rbxlx` files are used for Studio tests.
- The inspected owner place remains unpublished (`PlaceId = 0`, `UniverseId = 0`).
- No production publication, cloud data, paid product, or Robux action has been performed.
- Current Development build marker: `0.4.0-dev`.

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

## Validation record

Latest local validation for the Phase 1 source:

- `stylua --check src tests scripts`: passed.
- `selene src tests scripts`: 0 errors, 0 warnings, 0 parse errors.
- Roblox-aware `luau-lsp analyze`: passed.
- Production and TestEZ Rojo builds: passed.
- `git diff --check`: passed.
- Source contains **71 TestEZ specs** (14 new movement/support cases).

Runtime truth is intentionally separate: the latest recorded Studio TestEZ execution remains
**56 passed, 0 failed, 0 skipped** from the earlier build. The 71-spec Phase 1 source and its
physics behavior have not yet been accepted in Studio; the user will provide screenshots or
feel reports after testing.

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

- Phase 1 still needs the user-run 71-spec Studio execution and movement/support/bot/rematch
  feel pass described in `NEXT_ACTIONS.md`.
- Profiles, session locking, migrations, rewards, coins, XP, inventory, and persistent
  progression are not implemented. Results currently grant nothing.
- There is no real lobby or cross-server matchmaking; Results expiry currently returns to the
  waiting scheduler.
- Late clients can recover terrain snapshots but not an active projectile presentation.
- Mobile controls need real-device safe-area/accessibility tuning; gamepad is not complete.
- Character/environment visuals remain original programmer art awaiting screenshot-driven
  silhouette, palette, animation, effects, audio, and production-asset passes.
- Hosted CI builds the test place but cannot execute Roblox Studio runtime tests without an
  appropriate self-hosted Studio runner.

## Next implementation phase

After Phase 1 runtime acceptance, begin Phase 2: versioned session-safe profiles, migrations,
autosave/shutdown handling, read-only failure behavior, stable result identities, and
idempotent server-side coins/XP rewards. Production data remains disabled until those systems
and their failure tests are complete.
