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
- Strict schema-v1 player profiles with bounded integer coins/XP, win/loss/draw statistics,
  a 64-entry processed-reward ledger, derived account levels, and validated schema-v0
  migration.
- A Development DataService with UpdateAsync session leases, bounded retry/backoff and budget
  waits, per-profile operation ordering, autosave, PlayerRemoving release, BindToClose drain,
  and explicit Loading/Ready/ReadOnly/Unavailable/Released states.
- An explicit process-local session-memory adapter for unpublished Studio places; it exercises
  integration without pretending to provide cross-session persistence.
- Server-derived eligible-match rewards with deterministic bot scaling and atomic
  balance/stat/ledger application. Stable environment/match/player grant IDs exclude economy
  version so configuration changes cannot regrant a completed match.
- A compact client profile panel and Results reward feedback for Pending, Granted, Duplicate,
  Ineligible, ReadOnly, and Unavailable outcomes using server-owned state only.
- Pure TestEZ coverage for profile validation/migration/level derivation, reward eligibility,
  calculation/idempotency/ledger bounds, and session lease/state rules.
- Strict schema-v2 profiles with bounded starter cosmetic ownership/equipment and normalized
  music, SFX, camera-shake, reduced-effects, and UI-scale settings; valid schema-v0/v1 data
  migrates without losing economy statistics or the retained reward ledger.
- Lease-protected queued profile mutations for cosmetic equip and settings, including bounded
  queues, settings coalescing, no-op write avoidance, exact validation, safe ambiguous-write
  reconciliation, and server-owned profile attributes.
- A compact field-camp lobby with immediate Practice, same-server FIFO Casual pairing,
  eight-second bot fill, idempotent cancellation, queue state/countdown, Return to Camp, and
  exact-roster rematch isolation.
- An original code-built Sunset Scout Scarf starter cosmetic with loadout preview and
  nonphysical character presentation.
- Responsive Loadout and Settings panels plus immediate reduced-effects, camera-shake, and UI
  scale application across the lobby, profile, HUD, Results, trajectory, and effects layers.
- Keyboard lobby shortcuts, touch control separation, and complete gamepad movement, jump,
  aim, weapon-cycle, and fire bindings for the current match loop.
- Rate-limited active-projectile presentation recovery for clients that finish loading after
  the launch broadcast, retaining the authoritative launch timestamp without sharing outcome
  authority.
- Versioned, allowlisted Development telemetry and bounded Workspace diagnostics for session,
  queue, match/rematch, shot/impact, cosmetic, and settings events without raw user IDs.
- Pure TestEZ coverage for schema-v2 migration, cosmetic ownership/equip, settings patches,
  lobby parsing/FIFO/bot-fill selection, and telemetry schema validation.

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
- Advanced the local Development build marker to `0.7.0-dev`.
- Match admission now belongs to LobbyService instead of automatically starting every
  connected player; the HUD and combat controls remain hidden for lobby users and spectators.
- Results now supports Return to Camp and waits for authoritative lobby state before closing,
  preventing stale result/lobby races.
- Reduced-effects mode lowers trajectory and projectile-effect density, while impact shake is
  multiplied by the persisted comfort setting.
- Aim direction now mirrors from the authoritative `MatchSpawnX` whenever a match/rematch
  changes sides, preventing a lobby spectator position from locking shots away from rivals.
- Settings saves serialize one in-flight request and retain newer dirty edits across delayed
  acknowledgements; lobby and Results restore explicit gamepad focus on activation.

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
- Profile mutations are serialized behind a server DataService, corrupt/future data is not
  replaced by defaults, and read-only/unavailable profiles cannot receive progression grants.
- Result rewards are derived from frozen authoritative MatchEnd state and applied with their
  processed-grant ledger entry in one safe update path; no client supplies a reward or balance.
- Lobby, equip, settings, and projectile-snapshot remotes use exact-shape/type validation and
  bounded rate limits; customization additionally has a shared per-player window and a
  server-wide token budget.
- Lobby and customization ingress silently drop cooldown bursts and bound malformed/rate-limit
  feedback, preventing a rejected-packet flood from amplifying attribute and RemoteEvent work.
- Cosmetics are allowlisted and ownership-checked on the server; generated parts are massless,
  noncolliding, non-touching, non-queryable, and cannot alter combat statistics or aim origins.
- Telemetry rejects unknown events/fields, caps field count/text length/event diagnostics,
  omits raw user identifiers, and never accepts client-authored analytics payloads.
- Malformed, stale, or revision-gapped client terrain state triggers rate-limited snapshot
  recovery instead of partial mutation.
- Production publishing remains a manual, owner-approved operation.

### Validation

- StyLua, Selene, Roblox-aware Luau analysis, and both Rojo builds passed.
- Latest recorded Studio TestEZ run: 56 passed, 0 failed, 0 skipped. Current source contains
  137 specs; the Phase 1-4 additions await a user-run Studio rerun.
- Phase 2 native DataStore behavior has not been validated in a published Development place;
  the unpublished Studio fallback is intentionally session-memory-only and is not evidence of
  cross-session durability.
- Phase 3/4 lobby/loadout/settings, gamepad/mobile feel, active-projectile recovery, telemetry
  event reconciliation, and schema-v2 persistence have not yet received integrated Studio or
  representative-device acceptance.
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
