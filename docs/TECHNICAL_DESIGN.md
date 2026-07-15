# Technical design

## Scope and principles

This design supports a seven-day private MVP and a six-to-eight-week limited beta. It favors small, explicit modules, server authority, deterministic configuration, and feature flags over a large framework.

Core invariants:

- The client requests intent; the server owns match state and outcomes.
- Ballistic math is shared for preview/testing, but only server simulation can hit.
- Terrain has one authoritative logical grid; visuals are projections of grid state.
- Match rewards, purchases, and migrations are idempotent.
- Development, staging, and production never share persistent-data keys.
- No secret or production publish credential is committed.
- All important Luau modules use strict mode.

## Architecture decisions

| Area | MVP decision | Why / later path |
| --- | --- | --- |
| Terrain | 2D logical cell grid, dirty chunks, grouped tile/run rendering | Predictable craters and replication without runtime CSG; later evaluate contour/greedy meshing |
| Projectiles | Server fixed-step ballistic solver with swept raycasts; event-driven client visuals | Prevents client hit forgery and tunneling; later optimize batches/pools |
| Camera | Client custom side camera with overview, actor focus, projectile follow, impact, and result modes | Presentation stays responsive without affecting authority |
| Network | Narrow validated intent remotes and server event snapshots | Keeps attack surface reviewable; no client damage/hit/result messages |
| Bot | Server bot that submits legal aim/fire intent through the player rules | No cheat-only combat path; later add terrain-aware search |
| Data | Native DataStoreService behind a DataService adapter with UpdateAsync lease, retries, migrations, and idempotency ledgers; unpublished Studio explicitly uses process-local session memory | Small MVP schema and zero unreviewed runtime dependency; a reviewed pinned profile library may replace the adapter later |
| UI | Roblox GuiObjects plus a small explicit state/view layer | Low setup cost and easy mobile profiling; evaluate React Luau only if UI complexity justifies it |
| Matchmaking | Same-server queue, then bot fill after a short wait | Works without launch population; later MemoryStore and reserved servers |
| Environments | runtime config plus distinct place/universe identifiers and data prefixes | Prevents test data or debug features leaking to production |
| Repository | Rojo split into shared, server, and client; data-driven config; tests alongside pure modules | Clear ownership and fast automated build/test |

## Runtime layers

### Shared

- Immutable definitions: weapons, maps, characters, progression, economy, cosmetics,
  settings, lobby, products, and telemetry.
- Pure simulation: Ballistics, Wind, Damage, and TerrainGrid.
- Types, identifiers, serialization schemas, validation helpers, and network names.
- Shared code must not access client-only UI or server-only data APIs.

### Server

- MatchService: participants, lifecycle, win/draw, cleanup, and match ID.
- TurnService: active player, timer, movement budget, legal transitions, and timeouts.
- ProjectileService: request validation, authoritative simulation, collision, and impact ID.
- TerrainService: grid ownership, crater/path edits, dirty chunks, deltas, support checks.
- DamageService: falloff, line of sight if enabled, once-only damage, knockback, health.
- CharacterService: spawn, plane constraint, movement validation, death/recovery.
- BotService: target/weapon selection, imperfect aim search, and legal action timing.
- LobbyService: same-server Practice/Casual admission, FIFO queue, bot deadline, idempotent
  cancellation, replicated lobby state, Return to Camp, and match-lifecycle reconciliation.
- DataService: implemented profile session, schema migration, ordered operations, autosave,
  shutdown, and read-only/failure state; cloud behavior still needs published Development
  validation.
- EconomyService: implemented authoritative MatchEnd eligibility, reward calculation, and
  idempotent retained-ledger grant enqueue. Receipt processing and a durable crash-recovery
  outbox remain later work.
- CustomizationService: exact request validation, ownership/equip/settings admission,
  per-player and server-wide budgets, authoritative result messages, and telemetry dedupe.
- CosmeticService: generation-guarded code-built appearance that is nonphysical and never
  changes combat state.
- TelemetryService: versioned allowlist, redacted Development diagnostics, and bounded
  Workspace counters; no client-authored event payload path exists.

### Client

- LobbyController owns field-camp navigation, queue state/countdown, shortcuts, and gamepad
  focus without deciding admission.
- InputController normalizes keyboard, touch, and gamepad combat actions; MovementController
  adds left-stick/keyboard intent and bounded jump requests.
- CameraController owns presentation modes and applies the local shake multiplier.
- Aim/Trajectory controllers display local intent and approximate preview.
- UIController renders server state and local selection without deciding outcomes.
- Effects/Trajectory controllers bound transient presentation and respect reduced-effects
  settings. Audio fields are reserved, but no audio controller/assets ship in this slice.
- LoadoutController previews owned starter cosmetics and requests equip; SettingsController
  applies local comfort values immediately and reconciles server results.
- ProfileController reads server-owned profile attributes and renders storage/status, balance,
  XP, and derived level; ResultsController presents pending/resolved reward feedback.

## Match state machine

Allowed MVP sequence:

WaitingForPlayers → Countdown → RoundStart → TurnStart → ActiveTurn → ProjectileFired → ProjectileResolving → EnvironmentalResolution → TurnEnd → TurnStart or RoundEnd → MatchEnd → Results.

Every transition checks the current state and transition token. Only the server can advance state.

| State | Entry action | Exit condition | Recovery bound |
| --- | --- | --- | --- |
| WaitingForPlayers | reset arena/participants | required slots or bot deadline | cancel leaves safely |
| Countdown | lock roster, seed match | countdown complete | abort if no valid participant |
| TurnStart | select living actor, reset budgets | initialization complete | skip invalid actor |
| ActiveTurn | enable legal movement/aim/fire | accepted fire or configured 15–20-second timeout (20 in the prototype) | safe skip/basic bot shot |
| ProjectileResolving | simulate one accepted shot | impact/fuse/lifetime | force expire by max lifetime |
| EnvironmentalResolution | apply damage/terrain and settle | stable or settle timeout | clamp/recover/kill-plane |
| TurnEnd | check eliminations and cleanup | next turn or match end | transition exactly once |
| Results | enqueue an idempotent reward and offer rematch | rematch/lobby/expiry | no duplicate reachable retry; abrupt pre-enqueue crash remains documented |

Invariants include one active actor, one accepted shot per turn, one effect application per impact ID, no turn advance while unresolved damage is pending, and bounded state duration.

## Projectile simulation

### Data model

Each weapon definition includes a stable ID, display name, speed range, gravity scale, wind scale, fuse/lifetime, bounce limit/restitution, blast and terrain radii, max/min damage, knockback, projectile count/spread, owner-damage rule, and camera mode.

Stable IDs are never reused after release. Display names and cosmetics may change without changing balance IDs.

### Solver

- Server validates actor, state, request ID, weapon access, angle, power, origin, and rate limit.
- Shot origin is derived from the server character/weapon state.
- Initial velocity is derived from clamped angle and power.
- Acceleration combines configured gravity and signed horizontal wind.
- Use a 1/60-second simulation step for the initial low-projectile-count MVP, with bounded catch-up and a hard lifetime.
- Raycast from previous to next position every step; never rely only on point overlap.
- Bounce reflects velocity along the collision normal, applies restitution, decrements a server count, and uses a small separation offset.
- Spread/cluster behavior uses a server-generated seed included in presentation events.
- Impact receives a unique ID so collision, damage, terrain edit, analytics, and effects can deduplicate.
- Server sends spawn/impact/bounce/expire events and occasional correction snapshots, not per-frame transforms.

The client preview calls the same pure position-step function with last replicated wind and local legal intent. It does not raycast authoritative hidden state or send collision results.

### Projectile tests

Known-value tests cover no wind, positive/negative wind, gravity scale, boundary values, high speed through a thin wall, bounce count, fuse, lifetime, deterministic spread, duplicate fire, and duplicate impact.

## Terrain grid

### Representation

- Initial target: 4-stud logical cells, up to roughly 96 by 48 cells for one compact arena.
- Cell enum: Empty, Solid, Hazard, Indestructible, Decorative.
- Chunks: 8 by 8 cells. Each chunk has revision, dirty flag, and render/collision owner.
- Maps include format version, dimensions, spawn cells, kill plane, hazard data, and an integrity checksum/validation result.

### Editing and rendering

1. Server evaluates a circle, capsule, or drill path against grid cells.
2. Only destructible Solid cells change to Empty.
3. Server increments affected chunk revisions and emits compact cell/range deltas.
4. Server/client visual layer rebuilds only dirty chunks, grouping adjacent cells where practical.
5. Collision uses bounded grouped parts; no per-impact runtime CSG.
6. Characters above edited support enter a server-observed settle phase.

A joining client receives map ID/version plus a compressed snapshot or initial grid and subsequent revisioned deltas. A revision gap requests a chunk resync, not a guessed merge.

Spawn pads, outer shell, and critical boundaries are indestructible in MVP. Crater radius and edits per impact have hard caps.

## Character and movement authority

- Match characters use a custom constrained rig/controller or tightly configured Humanoid on one depth plane.
- The server tracks turn-start position, accepted movement distance, jump count, speed, ground/support state, and arena bounds.
- Client movement messages contain normalized intent and sequence/timestamp, never a final trusted position.
- Physics/network ownership is assigned conservatively; server audits and corrects displacement. Repeated impossible motion is rejected and counted, not immediately punished from one noisy sample.
- Knockback is produced by the server, capped, tagged with an impact ID, and excluded from voluntary movement budget.
- Leaving bounds invokes deterministic recovery or hazard/elimination rules.

## Network contracts

All payloads have strict type/size checks, finite-number checks, match membership, state/token, and rate limits.

| Direction | Message | Minimal payload | Key validation |
| --- | --- | --- | --- |
| C→S | QueueAction | action, requestId | allowed action, membership, cooldown |
| C→S | MoveIntent | direction, jump, sequence | active actor, budget, finite range, monotonic sequence |
| C→S | FireWeapon | weaponId, angle, power, requestId | turn, alive, one-shot token, legal weapon, finite clamps, server origin |
| C→S | EquipCosmetic | slot, itemId, requestId | owned, compatible, sane strings, cooldown |
| C→S | TutorialAction | stepId, requestId | expected step and server-observable prerequisite |
| S→C | MatchSnapshot | state, participants, timer deadline, wind, revisions | server-originated snapshot |
| S→C | ProjectileEvent | event, shot/impact ID, definition ID, seed, position/velocity/time | presentation only |
| S→C | TerrainDelta | map/chunk revision, changed cells | revision-checked application |
| S→C | Player profile attributes | storage/status, coins, XP, derived level/progress | server-owned view; excludes lease and processed-reward ledger |
| S→C | RewardResolved | match ID, status, granted coins/XP, server time | presentation only; client cannot request or alter a grant |

Phase 3/4 extends this contract with exact-shape `SettingsPatch`, payload-free and rate-limited
`CombatSnapshotRequest`, and server-owned `LobbyEvent` state/profile-action results. Equip and
settings requests are rejected before expensive persistence work unless they pass allowlist,
ownership/type/range, nonempty-patch, per-player, and server-wide admission checks. The
projectile snapshot returns only the retained presentation launch and never damage, collision,
terrain, or match authority.

No remote accepts target Instance, damage, health, reward amount, hit position, shot origin, terrain cells, receipt status, or match winner from a client.

## Damage and knockback

- Damage is a pure function of weapon definition and server distance, with optional server line-of-sight.
- Each impact stores damaged character IDs to prevent repeated touches.
- Health change, death, statistics, and result calculation are atomic within the impact resolution path.
- Knockback direction comes from impact-to-character vector with safe fallback for zero distance; magnitude is clamped.
- Self-damage is a weapon rule. Team/friendly-fire rules are server match configuration when teams arrive.

## Bot architecture

The bot reads only information a legal server participant could use: target positions, public terrain, wind, loadout, and time. It samples candidate angle/power pairs through the shared ballistic approximation, scores proximity/terrain utility, applies difficulty error, then calls the same validated internal action path used for player intent. It never invokes DamageService directly.

Search has a time/candidate cap. If no candidate is found, it fires a conservative Acorn Cannon shot before timeout.

## Persistence

### MVP profile

- Current schema v2 stores schema/economy version, bounded integer coins and XP, integer
  matches/wins/losses/draws, a dense processed-match-reward ledger capped at 64 entries,
  bounded owned/equipped cosmetic state, and normalized comfort/settings state.
- Level is derived from XP with `150 + 50 x (level - 1)` per next level and a level-100 cap;
  it is not a second persisted source of truth.
- Each reward entry stores its stable key, coins, XP, grant time, outcome, and player/bot mode.
- Missing data receives the explicit starter profile and Sunset Scout Scarf. Schema v0 accepts
  bounded coins plus exactly one of `xp` or legacy `experience`; schema v1 preserves economy,
  statistics, and retained grants while adding default inventory/settings. Corrupt,
  ambiguous, unsupported, and future schemas fail safely.
- Music/SFX values are persisted for forward-compatible original audio, but playback is not
  implemented. Receipts, mastery, quests, and seasons still require reviewed migrations.

### Session and write behavior

- The only active configuration is Development store `DEV_CritterClash_Profile_v1` with
  `Player_` keys. Staging and Production require separate reviewed place/configuration work.
- Acquire a 120-second lease with UpdateAsync containing a unique server owner and timestamp;
  renew on autosave and release after the profile operation queue drains.
- Retry transient failures up to five attempts with bounded exponential backoff, jitter, and
  DataStore request-budget waits.
- Autosave every 45 seconds plus bounded jitter, with PlayerRemoving release and a bounded
  25-second BindToClose drain.
- Migrations are ordered, pure where possible, version-tested, and applied before the profile is writable.
- If a safe writable session cannot be acquired, enter read-only/no-reward mode or deny progression play; never overwrite with defaults.
- Grant operations carry stable idempotency keys. A match reward key is derived from
  environment, match, and player identity and deliberately excludes economy/reward version;
  changing reward configuration must not regrant the same completion. A future commerce key
  uses the platform purchase identity.
- Equip/settings mutations share the per-profile serialized worker and lease-protected
  UpdateAsync path. The pending mutation queue is capped, adjacent settings patches coalesce,
  conflicting equips retain order, no-op writes are skipped only when safe, and ambiguous
  failures reconcile against the authoritative stored profile before reporting success.
- In an unpublished Studio place, DataService deliberately selects a process-local
  session-memory adapter. This is useful for integration tests but has no cross-session or
  cross-server durability and is never described as a cloud persistence pass.
- Production migrations require backup/snapshot, staging rehearsal, explicit owner approval, and rollback/forward-fix plan.

The DataService interface isolates callers from the storage implementation so a reviewed and pinned profile library can be adopted later without changing game systems.

## Economy and purchase processing

- Server derives rewards from verified match/quest state and configured tables.
- Current MatchEnd grants atomically update coins, XP, outcome statistics, economy version,
  and the processed-reward ledger. Duplicate keys return the original recorded grant without
  changing balances or statistics.
- Ownership/equipment is checked on every request and load; unknown IDs are quarantined/logged.
- Durable cosmetic and repeatable product types have separate product definitions.
- Receipt processing is the sole grant authority for receipt-based purchases; prompt completion is UI feedback, not proof of payment.
- Receipt handler checks existing grant, writes/grants idempotently, and returns the appropriate outcome only after durable success.
- Commerce is feature-flagged per environment and disabled by default in Development.

## Matchmaking and rematch

LobbyService is the only normal match-admission owner. Practice starts one human with a bot
as soon as the single arena is available. Casual maintains an in-server FIFO: the oldest two
eligible Casual players receive a human 1v1; otherwise an entry bot-fills after approximately
eight seconds. A Practice entry is not held behind a lone Casual search. Token-scoped cancel,
disconnect, invalid-character pruning, and failed admission requeue/remove entries
idempotently.

The selected roster is frozen into MatchService. Rematch requires the exact original
connected human roster and creates a fresh match ID, turn seed, arena, reward key, projectile
state, terrain revision, timer, health, and bot. Return to Camp opts that participant out and
cannot import a spectator or newly queued player.

Limited beta may add MemoryStore queues and reserved match servers only after expiry, duplicate assignment, teleport failure, party, reconnection, and low-population behavior are load-tested.

## Camera, UI, and effects

- Camera is local and never informs collision. Modes have cancellable transition tokens so late projectile events cannot steal the camera.
- The server retains at most one active launch presentation payload. A late client may request
  that payload once per second; the original server timestamp lets the bounded client solver
  catch up without per-frame replication or outcome authority.
- Server timer is a deadline timestamp; clients display remaining time and correct drift rather than owning a countdown.
- UI state is derived from the latest versioned snapshot plus local uncommitted aim/input.
- Effects use bounded instances, lifetime cleanup, and reduced-effects budgets. Audio is not
  shipped until original, provenance-cleared assets exist.
- Responsive layout covers phone, tablet, desktop, and safe areas. Input glyphs follow the active input mode.
- UI scale, camera shake, and reduced effects apply locally immediately, then reconcile to the
  server-owned schema-v2 settings snapshot. Combat HUD/touch controls are hidden in Lobby.

## Environments and feature flags

| Environment | Purpose | Data | Publishing |
| --- | --- | --- | --- |
| Development | MCP, verbose logs, test currency, experimental content | DEV prefix only | local/private development place |
| Staging | production-like migration, receipt, device, and release candidate tests | STAGING prefix only | private tester place |
| Production | approved content and stable data | PROD prefix only | manual approval required |

Configuration validation fails builds with duplicate IDs, unknown references, invalid balance bounds, missing environment identifiers, or production debug flags. Secrets are supplied through approved CI/Open Cloud secret storage, never repository files.

## Repository shape

- src/shared/Config, Simulation, Types, Network, Utilities
- src/server/Services and Main.server.luau
- src/client/Controllers and Main.client.luau
- tests for pure simulation, turn/lobby order, idempotency, profiles/migrations, cosmetics,
  settings, and telemetry schemas
- assets for editable sources, concepts, approved exports, and manifests
- docs for design, security, analytics, licensing, and release evidence

Build artifacts are reproducible and are not the editable source of truth.

## Performance budgets

These are profiling targets, not platform guarantees:

- Client target 60 FPS on representative mid-range mobile, with a 30 FPS reduced-effects floor.
- No per-frame projectile network replication.
- One impact rebuilds only intersecting terrain chunks and completes without a visible multi-frame freeze.
- Projectile, debris, audio, and particle instances return to bounded pools or are destroyed by hard lifetime.
- Twenty repeated matches show no sustained growth in match-owned instances and no material memory trend after cleanup.
- Server simulation has bounded catch-up; a lag spike cannot create an unbounded step loop.
- Maps and cosmetics use controlled texture, mesh, transparency, collision, and particle budgets recorded in the asset manifest.

Profile projectile steps, dirty-chunk rebuilds, character physics, part count, draw calls, particles, network traffic, and memory on real hardware.

## Failure handling and observability

- Every match/projectile/impact/reward has a correlation ID.
- Logs include build, environment, state, IDs, reason code, and redacted context; never passwords, tokens, chat, email, or unnecessary personal data.
- Invalid remote attempts increment rate/anomaly counters without echoing hostile payloads.
- Data, state timeout, revision gap, and cleanup errors emit structured diagnostics. Current
  telemetry is a Development-only allowlisted JSON/Workspace sink, not a Production backend.
- Feature flags can disable commerce, experimental weapons, four-player mode, or analytics without corrupting profiles.
- A known-good build/place version, production data snapshot/version path, smoke test, and rollback owner are required before release.

## Technical release gate

- Format, lint, configuration validation, unit tests, Rojo build, and secret/license checks pass.
- Two-client 1v1, player-versus-bot, timeout, disconnect, duplicate fire, terrain resync, persistence, migration, and receipt-idempotency tests pass.
- Mobile emulation completes the full loop; representative real-device testing is required for limited beta.
- No critical Output error, arbitrary-damage path, reward/purchase duplication path, cross-environment data reference, or unbounded state remains.
- Manual production publication is the final step and requires explicit owner approval.
