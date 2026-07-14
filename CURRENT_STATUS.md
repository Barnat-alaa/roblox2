# Current Status

Last updated: 2026-07-14

## Environment

- Roblox Studio MCP was verified against generated local `.rbxlx` sessions.
- Reversible MCP verification passed: edit, play, server inspection, Output inspection, stop,
  and cleanup all succeeded.
- The inspected owner place is an unpublished blank place (`PlaceId = 0`,
  `UniverseId = 0`); the repository builds a separate local Development place.
- The match-loop Development build has not been published.
- Git remote: `https://github.com/Barnat-alaa/roblox2.git`.

## Implemented

- Repository, toolchain, and required development documentation.
- Shared deterministic combat math, four original weapon definitions, and a
  server-authoritative turn/fire boundary.
- Authoritative 45 × 24 logical terrain grid with 4-stud cells.
- Protected bottom cells and spawn supports, plus a small server-lethal central hazard and
  server-enforced death-height elimination.
- 8 × 8 dirty chunks that rebuild server collision and pooled client rendering only where
  terrain changed.
- Revisioned Snapshot/Delta replication with client validation, gap detection, and
  rate-limited snapshot resync.
- Acorn/projectile crater integration and a bounded Mole Drill path that clips at grid
  boundaries and protected terrain.
- A frozen 1v1 match roster. A solo human is paired with a server-owned BotCritter, while
  players who join an active match spectate and may fill an open slot at the next boundary.
- BotConfig, bounded/imperfect BotAim solving, and BotService turn handling. Bot shots enter
  the same authoritative projectile, damage, terrain, elimination, Result, and rematch paths
  as human shots without creating a fake Player or a new client remote.
- Authoritative participant lifecycle and elimination state that remains eliminated across
  Roblox character respawns.
- Exactly-once authoritative Result resolution, a Results interface, and unanimous connected-
  human rematch readiness.
- Clean rematch reset of terrain, BotCritter, characters, wind, turn state, and timers
  under a fresh match ID.
- Side-view camera, aim controls, trajectory preview, combat HUD, and predictive projectile
  presentation.
- First visual-direction pass: an original low-part red-squirrel BotCritter, layered distant
  hills/clouds/sun, and named atmosphere, colour-grade, and bloom effects. Decorative parts
  are excluded from physics, touch, and raycast queries.
- Client fluidity bounds: trajectory rebuilds avoid the former 97-point preview allocation
  and perform at most 48 raycasts, effects catch up at most 16 fixed steps per frame and
  early-out while idle, the HUD updates timed display state at 10 Hz, and terrain rebuilds
  one dirty chunk per Heartbeat.
- Automated format, lint, package, Rojo build, and a 57-case TestEZ source project.

## Validation record

Current terrain-enabled build validation on Windows:

- Rokit 1.2.0 restored Rojo 7.7.0, Wally 0.3.2, StyLua 2.5.2, Selene 0.31.0,
  and Luau LSP 1.68.1.
- `stylua --check src tests scripts`: passed.
- `selene src tests scripts`: 0 errors, 0 warnings, 0 parse errors.
- Roblox-aware strict `luau-lsp analyze`: passed.
- Production and test Rojo builds: passed.
- Latest recorded Studio TestEZ run: **56 passed, 0 failed, 0 skipped**. The current source
  contains 57 specs; the added tuning spec awaits a user-run Studio rerun.
- The final terrain-enabled playable build booted clean with matching initial server/client
  terrain revision 0 and an active central hazard collision run.
- A real Acorn request produced Delta 0 → 1 with 9 changed cells; server and client both
  finished at terrain revision 1.
- In a separate clean run, a real Mole Drill request produced Delta 0 → 1 with 10 changed
  cells while the protected boundary runs remained intact.
- A temporary server smoke observed death-height elimination.
- A genuine Studio one-server/two-client run completed an elimination, showed the correct
  Victory/Defeat Results interfaces, retained the eliminated player across respawn, collected
  readiness from both humans, and restarted both clients into a fresh match.
- The two-client rematch reset terrain to revision 1, restored both participants to full
  health at their stable spawn slots, removed the solo TrainingTarget, and resumed in the
  aiming phase under a fresh match ID.
- A solo last-player disconnect returned the server to clean `WaitingForPlayers` state with
  no stale match ID.
- A live pre-final-tuning one-server/one-client/bot run verified that the bot fired through
  the authoritative projectile path, eliminated the human participant, and produced the
  DEFEAT Results interface.
- Studio observations placed a bot aim solve between 3.43 and 5.65 ms. A server snapshot
  measured 16.65 ms p50, 17.72 ms p95, 18.04 ms p99, and 18.37 ms worst frame time. These
  measurements are development evidence, not a production or representative-device budget.
- The final-tuning bot rematch and runtime/visual-feel pass remain user-run validation and
  are not recorded as complete.
- All temporary smoke scripts were removed. After a clean restart, Output contained only the
  expected development startup message.

A published experience, cloud data, monetisation product, and production deployment have not
been created.

## Review findings addressed

- Delayed match transitions are epoch-guarded so stale callbacks cannot overwrite later turns.
- A disconnect during projectile/environment resolution waits for the authoritative shot to
  settle before a new turn.
- Character readiness now retries match scheduling and ordering follows stable user IDs.
- Launch data is validated before entering projectile resolution; a watchdog prevents a stuck
  projectile phase.
- Explosion result queries are not truncated, knockback velocity is capped, and shot seed
  mixing avoids unsafe integer multiplication.
- Terrain edits are bounded, atomic, revisioned, and limited to destructible cells.
- Stale, malformed, or revision-gapped client terrain state requests a rate-limited snapshot
  instead of applying a partial delta.
- Protected cells stop excavation, and Mole Drill endpoints clip to the safe grid path.

## Open development gaps

- M5.2 bot implementation is present, but its final-tuning one-server/one-client rematch,
  57-spec Studio rerun, and visual-feel signoff remain user-run acceptance work.
- Matchmaking, profiles, rewards, cosmetics, and monetisation are not implemented. Results
  currently grant no coins, XP, or persistent progress.
- The next implementation milestone is movement, grounding, and terrain-support hardening:
  accumulated-distance, jump-frequency, grounded-state, explicit support detection, and
  bounded settling still need stronger server enforcement.
- Terrain has snapshot recovery, but late clients do not yet recover active projectile
  presentation state.
- The code-built squirrel and layered backdrop need screenshot-driven silhouette, palette,
  camera-scale, and readability iteration before they can become production art.

## Development environment

This repository currently represents **Development** only. Staging and Production must use
separate experiences and data-store prefixes before either environment is enabled.
