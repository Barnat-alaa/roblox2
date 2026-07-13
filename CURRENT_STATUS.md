# Current Status

Last updated: 2026-07-13

## Environment

- Roblox Studio MCP connected to the local `Place1` session.
- Reversible MCP verification passed: edit, play, server inspection, Output inspection, stop,
  and cleanup all succeeded.
- The inspected owner place is an unpublished blank place (`PlaceId = 0`,
  `UniverseId = 0`); the repository builds a separate local Development place.
- The terrain-enabled Development build has not been published.
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
- Side-view camera, aim controls, trajectory preview, combat HUD, and predictive projectile
  presentation.
- Automated format, lint, package, Rojo build, and a 37-case TestEZ project setup.

## Validation record

Current terrain-enabled build validation on Windows:

- Rokit 1.2.0 restored Rojo 7.7.0, Wally 0.3.2, StyLua 2.5.2, Selene 0.31.0,
  and Luau LSP 1.68.1.
- `stylua --check src tests scripts`: passed.
- `selene src tests scripts`: 0 errors, 0 warnings, 0 parse errors.
- Roblox-aware strict `luau-lsp analyze`: passed.
- Production and test Rojo builds: passed.
- Studio TestEZ: **37 passed, 0 failed, 0 skipped**.
- The final terrain-enabled playable build booted clean with matching initial server/client
  terrain revision 0 and an active central hazard collision run.
- A real Acorn request produced Delta 0 → 1 with 9 changed cells; server and client both
  finished at terrain revision 1.
- In a separate clean run, a real Mole Drill request produced Delta 0 → 1 with 10 changed
  cells while the protected boundary runs remained intact.
- A temporary server smoke observed death-height elimination.
- All temporary smoke scripts were removed. After a clean restart, Output contained only the
  expected development startup message.
- This validation did not include a separately recorded two-client run.

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

- Eliminations are not retained independently of Roblox respawns; MatchEnd, results, and
  rematch flow are not implemented.
- Bot fill, matchmaking, profiles, rewards, cosmetics, and monetisation are not implemented.
- Terrain support loss currently relies on Roblox physics plus hazard/death-height checks;
  explicit support detection and bounded settling need a stronger design.
- Movement still needs accumulated-distance, jump-frequency, and grounded-state validation.
- Terrain has snapshot recovery, but late clients do not yet recover active projectile
  presentation state.

## Development environment

This repository currently represents **Development** only. Staging and Production must use
separate experiences and data-store prefixes before either environment is enabled.
