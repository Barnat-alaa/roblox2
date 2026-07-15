# Changelog

All notable project changes are recorded here.

## [Unreleased]

### Added

- Initial Project Critter Clash repository.
- Roblox Studio MCP connection and reversible playtest verification.
- Rojo, Rokit, Wally, StyLua, Selene, Luau LSP, and TestEZ configuration.
- Server-authoritative greybox combat foundation and shared simulation modules.
- Scriptable side camera, cross-platform aim controls, combat HUD, trajectory preview, and
  event-driven projectile/impact presentation.
- Authoritative 45 × 24 logical terrain grid with 4-stud cells, protected bottom cells, and
  protected spawn supports.
- 8 × 8 dirty-chunk projection for server collision and pooled client rendering.
- Revisioned Snapshot/Delta terrain replication with atomic application, revision-gap
  detection, and rate-limited resync.
- Acorn/projectile craters and a bounded Mole Drill excavation path that clips at grid
  boundaries and protected terrain.
- Small server-lethal central hazard and server-enforced death-height elimination.
- Frozen 1v1 participant rosters, with a server-owned BotCritter filling the solo opponent
  slot and late joiners held as spectators for the active match, then considered for open
  slots at the next boundary.
- BotConfig, bounded and imperfect BotAim solving, BotService turn execution, and BotAim
  TestEZ coverage. The bot uses the ordinary authoritative projectile and match services
  without a fake Player or bot-only client remote.
- Authoritative participant lifecycle and persistent elimination state across Roblox
  character respawns.
- Exactly-once authoritative match Results, a responsive Victory/Defeat interface, unanimous
  connected-human rematch readiness, and fresh match IDs.
- Clean rematch reset of terrain, BotCritter, characters, wind, turn state, and timers.
- Pure match-rule coverage for winner/draw resolution, retained elimination, readiness, and
  match ID validation.
- Pure movement rules and TestEZ coverage for cumulative path distance, speed, arena bounds,
  knockback exemptions, monotonic samples, grounded jumps, cooldown, and jump rejection.
- Footprint-aware terrain support queries and TestEZ coverage for solid, protected, hazard,
  edge-overlap, destroyed, invalid, and outside-grid cases.
- Server-authoritative movement requests with match/turn/sequence validation, input leases,
  cumulative movement allowance, bounded jumping, and keyboard/touch controls.
- Bounded environmental settlement and recovery for player characters and the physical bot.
- Terrain TestEZ coverage for compact deltas, ordering, atomic updates, overlap, protected
  cells, world conversion, dirty chunks, and snapshots.
- Required product, technical, security, economy, analytics, testing, and release documents.
- GitHub Actions validation workflow with pinned Rokit download checksum.

### Changed

- Replaced legacy static ground/shelf collision with the logical terrain projection.
- Impact events now report terrain cells changed and the resulting terrain revision.
- Bot identity, health, turns, camera focus, shooter filtering, and Results now flow through
  the existing client presentation instead of legacy solo-target handling.
- Trajectory preview rebuilds no longer allocate a 97-point simulation path and are bounded
  to 24 dots with two collision substeps each, for at most 48 raycasts per rebuild.
- Projectile effects catch up at most 16 fixed steps per frame and early-out while idle; the
  combat HUD updates timed display state at 10 Hz; terrain rendering rebuilds one dirty chunk
  per Heartbeat.
- Added the first original visual-direction pass: a low-part red-squirrel BotCritter with a
  scarf and launcher, layered background hills/clouds/sun, and restrained atmosphere,
  colour-grade, and bloom. Decorative geometry is non-queryable and non-physical.
- Hardened match admission so a missing or dead human character is reloaded instead of being
  promoted into a new match as an ineligible participant.
- Made BotCritter a server-owned physics pawn with welded massless visuals, an independent
  collision hull, and upright stabilization.
- Routed aiming timeout through environmental settlement and gave each readiness failure a
  fresh bounded deadline.
- Throttled movement/correction diagnostics and remaining-distance replication.
- Added a guarded Results expiry so abandoned result state cannot stall the server forever.
- Advanced the local Development build marker to `0.4.0-dev`.

### Security

- Client fire requests are treated as intent only; the server derives origins and outcomes.
- Projectile/disconnect transitions use guarded epochs and a wall-clock resolver watchdog.
- Terrain edits are capped and bounded, preserve indestructible cells, and rebuild only dirty
  chunks.
- Result and rematch requests validate bounded payloads, reject stale match IDs, and keep
  authoritative readiness idempotent.
- Bot turns are initiated entirely by the server and pass through the same weapon, turn-token,
  projectile, damage, terrain, elimination, and Result validation as human intent.
- Movement requests are exact-shape validated, token-bucket limited, match/turn scoped, and
  committed atomically only after requested jump validation succeeds.
- Projectile impact/finalization uses an exact match-resolution lease; explosion targets are
  restricted to the current registered combatant roster.
- Malformed, stale, or revision-gapped client terrain state triggers rate-limited snapshot
  recovery instead of partial mutation.
- Production publishing remains a manual, owner-approved operation.

### Validation

- StyLua, Selene, Roblox-aware Luau analysis, and both Rojo builds passed.
- Latest recorded Studio TestEZ run: 56 passed, 0 failed, 0 skipped. Current source contains
  71 specs; the Phase 1 additions await a user-run Studio rerun.
- The final terrain-enabled playable build booted clean with matching initial server/client
  terrain revision 0 and an active central hazard collision run.
- A real Acorn request produced Delta 0 → 1 with 9 changed cells and matching server/client
  terrain revision 1.
- In a separate clean run, a real Mole Drill request produced Delta 0 → 1 with 10 changed
  cells while protected boundary runs remained intact.
- A temporary server smoke observed death-height elimination.
- A genuine Studio one-server/two-client run passed the complete elimination, Results, and
  unanimous-rematch loop. The defeated participant remained eliminated across respawn, and
  the fresh match restored both players, terrain, and turn state.
- A solo last-player disconnect returned the server to clean `WaitingForPlayers` state.
- A live pre-final-tuning bot run verified authoritative bot firing, human elimination, and
  the DEFEAT Results interface. Final-tuning rematch and runtime/visual-feel acceptance remain
  user-run validation.
- Studio observations measured BotAim solving at 3.43-5.65 ms and a server snapshot at
  16.65 ms p50, 17.72 ms p95, 18.04 ms p99, and 18.37 ms worst frame time. These are not
  production or representative-device guarantees.
- All temporary smoke scripts were removed; a clean restart produced only the expected
  development startup message.
