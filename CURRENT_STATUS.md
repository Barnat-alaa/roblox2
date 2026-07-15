# Current Status

Last updated: 2026-07-15

## Environment

- Repository: `https://github.com/Barnat-alaa/roblox2.git`.
- Development is file-based through Rojo; generated `.rbxlx` files are used for Studio tests.
- The inspected owner place remains unpublished (`PlaceId = 0`, `UniverseId = 0`).
- No production publication, cloud data, paid product, or Robux action has been performed.
- Current Development build marker: `0.7.0-dev`.

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

- Profile schema v2 strictly validates bounded integer coins, account XP, economy version,
  win/loss/draw statistics, a dense processed-reward ledger capped at 64 entries, cosmetic
  inventory/equipment, and normalized settings. Account level and progress-to-next-level are
  derived from XP rather than persisted independently.
- Missing profiles receive an explicit starter profile. Schema v0 profiles containing coins
  and either `xp` or legacy `experience` migrate directly to v2; valid schema-v1 economy,
  statistics, and reward history migrate to v2 with default inventory/settings. Malformed,
  ambiguous, unsupported, or future schemas fail safely instead of being overwritten.
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

## Phase 3 lobby and identity implementation

Phase 3 is implemented in source and awaits the integrated Studio acceptance matrix.

- `LobbyService` is the sole normal match-admission owner. Practice starts one human against
  BotCritter when the arena is free; Casual uses a same-server FIFO, pairs two humans, and
  bot-fills the oldest Casual entrant after an eight-second deadline.
- Queue cancellation is idempotent and accepts an optional generation token, so a delayed
  token-bearing cancel cannot remove a newer queue entry. Disconnect cleanup and queue state
  are bounded and server-owned.
- MatchService no longer auto-admits every connected player from join, respawn, removal, or a
  waiting poll. Rematch retains only connected humans from the completed roster and never
  promotes spectators or queued players.
- `LobbyState`, queue mode/deadline/position/token, and match ID replicate as Player
  attributes. The responsive field-camp UI exposes Practice, Casual, Loadout, Settings, and
  cancel with no placeholder store or monetization action.
- Results offers Return to Lobby. Returning explicitly opts that participant out of rematch
  membership while leaving the immutable result and already-enqueued reward intact.
- Every schema-v2 profile owns and equips the original code-built `sunset_scout_scarf` starter
  item. Equip requests are exact-shape/rate validated, checked against owned inventory, saved
  through the serialized profile lane, and applied as massless noncolliding presentation.

## Phase 4 comfort, recovery, and diagnostics implementation

Phase 4 is implemented in source and awaits representative-device and Studio acceptance.

- Reduced effects, camera-shake strength, and interface scale apply optimistically on the
  client and persist through validated server settings mutations. Schema v2 also reserves
  normalized music/SFX volume values, but no production audio assets or volume UI ship yet.
- Camera impact shake, effect density/lifetime, lobby/loadout/settings/profile/HUD scale, and
  touch controls read the local comfort view. Responsive constraints protect compact layouts.
- Keyboard/touch remain supported; gamepad bindings cover left-stick movement, `A` jump,
  right-stick aim/power, bumper weapon cycling, and right-trigger fire. Hardware signoff is
  not inferred from source bindings.
- A newly connected client requests a combat snapshot after handlers are ready. The server
  rate-limits the request and replays only the retained active launch; impact, collision,
  damage, terrain, and turn state remain authoritative and duplicate visuals are deduplicated.
- Telemetry uses a versioned allowlist and bounded fields for session, queue, match/rematch,
  shot/impact, cosmetic, and settings facts. Development emits structured diagnostics only;
  no production analytics backend, dashboard, raw UserId, hostile payload, or per-frame event
  stream has been enabled.

## Validation record

Final local Phase 3/4 repository validation on 2026-07-15:

- `stylua --check src tests scripts`: passed.
- `selene src tests scripts`: 0 errors, 0 warnings, 0 parse errors.
- Roblox-aware `luau-lsp analyze`: passed.
- Production and TestEZ Rojo builds: passed.
- `git diff --check`: passed.
- Configuration/licence registry checks and the common-secret-pattern scan: passed.
- Source contains **137 TestEZ specs**, including schema-v2 migration, cosmetics, settings,
  lobby request/FIFO selection, and telemetry allowlist cases in addition to prior combat,
  terrain, profile, reward, and session coverage.

Runtime truth is intentionally separate: the latest recorded Studio TestEZ execution remains
**56 passed, 0 failed, 0 skipped** from the earlier build. The 137-spec Phase 1-4 source and
new integrated service/UI paths have not yet been accepted in Studio; the user will provide
screenshots, Output, and feel reports after testing. Static success is not substituted for a
Roblox Studio runtime or representative-device result.

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
- Aim facing now follows the authoritative match spawn side on every match/rematch instead of
  retaining a lobby-spectator direction.
- Settings serialize one in-flight save and preserve a newer local edit across delayed older
  acknowledgements and attribute replication.
- Lobby/customization ingress and rejection feedback are bounded before parsing/outbound work;
  persistence writes retain per-player plus server-wide admission budgets.
- Lobby and Results restore explicit gamepad focus when their panels become active.

## Open development gaps

- Phase 1 still needs the user-run 137-spec Studio execution and movement/support/bot/rematch
  feel pass described in `NEXT_ACTIONS.md`.
- Phase 2 profile/reward integration needs a local session-memory runtime pass. Native
  DataStore persistence, lease contention, retry, leave/rejoin, and shutdown durability need
  owner-run validation in a published private Development place.
- Schema v2 has bounded starter inventory/equipment and settings, but no receipt, tutorial
  grant, quest, mastery, season, broad catalog, or durable match-result outbox.
- Lobby admission is same-server and supports only one arena match at a time. It does not use
  MemoryStore, reserved servers, parties, skill matching, or reconnect-to-match.
- The active-projectile snapshot recovery path exists in source but needs a deliberate
  late-join Studio test during flight and an impact-race test.
- Responsive touch/gamepad code exists, but representative phone/tablet safe-area,
  performance, accessibility, and physical-controller acceptance are outstanding.
- Allowlisted telemetry currently writes Development diagnostics only; no production event
  sink, dashboard, quota review, retention policy, or live data-quality reconciliation exists.
- No original production audio assets are shipped; persisted music/SFX volume fields are
  reserved data only.
- Character/environment visuals remain original programmer art awaiting screenshot-driven
  silhouette, palette, animation, effects, audio, and production-asset passes.
- Hosted CI builds the test place but cannot execute Roblox Studio runtime tests without an
  appropriate self-hosted Studio runner.

## Next implementation phase

First complete the combined Phase 1-4 Studio acceptance and owner-run published Development
schema-v2 persistence checks in `NEXT_ACTIONS.md`. Use screenshots and feel reports to tune
the lobby, scarf silhouette, input, camera, effects, and UI scale before expanding content.
Production data remains disabled; no paid product, private/public publication, Production
migration, or Production currency operation is authorized.
