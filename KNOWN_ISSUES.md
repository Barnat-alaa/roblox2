# Known Issues

## Current development slice

- The owner place is unpublished; playtests use generated local `.rbxlx` builds instead of a
  published Development experience.
- Current source contains **137 TestEZ specs**. The latest recorded Studio execution is still
  the older **56 passed, 0 failed, 0 skipped** result, so Phase 1-4 additions require a fresh
  user-run Studio execution before runtime acceptance.
- Phase 1 movement, grounding, physical bot collision, support-loss settlement, projectile
  leases, roster-only damage, readiness recovery, and Results expiry are implemented, but
  final movement/camera/impact feel remains screenshot- and device-tested by the user.
- Phase 3/4 lobby, loadout, settings, touch/gamepad input, Return to Camp, active-projectile
  recovery, and telemetry are implemented in source but have not yet completed the integrated
  Studio acceptance matrix in `NEXT_ACTIONS.md`.
- Match admission is same-server and intentionally supports one active arena. It has no
  MemoryStore cross-server queue, party reservation, teleport, reconnect-to-match, or
  multi-arena scheduler. Practice is immediate when free; Casual pairs two humans in FIFO
  order and otherwise bot-fills after about eight seconds.
- The active-projectile snapshot recovers presentation for at most the one current launch. It
  is not a general mid-match reconnection snapshot and never reconstructs an already-finished
  impact.
- Schema-v2 profiles, schema-v0/v1 migration, session leases, bounded retries/autosave/shutdown,
  read-only fallback, rewards, starter equipment, and settings mutations are implemented, but
  their native DataStore path has not been tested in a published Development place.
- Unpublished Studio deliberately uses process-local SessionMemory. Coins, XP, statistics,
  equipment, and settings may reset after Studio stop/start without indicating a persistence
  defect. Published synthetic users (`UserId <= 0`) also remain on SessionMemory; cloud
  evidence requires an authenticated positive-UserId client showing `CLOUD`/`Persistent`.
- The processed-reward ledger retains 64 identities. That bounds profile size but is not a
  permanent archive against a manually replayed identity after 64 newer grants.
- Orderly shutdown drains already-enqueued work for up to 25 seconds, but there is no durable
  match-result outbox. An abrupt server crash before the reward enqueue/atomic write can lose
  that earned reward.
- Music/SFX values are reserved and validated in schema v2, but original audio assets and an
  audio playback controller are intentionally not shipped yet.
- Development telemetry is an allowlisted structured Output/Workspace diagnostic sink only.
  It is not connected to a Production analytics backend and has not completed scripted event
  reconciliation in Studio.
- Purchase receipt processing, paid products, catalog ownership grants, and monetization UI
  are not implemented. No live SKU or Robux action is enabled.
- Touch layouts and gamepad bindings are implemented, but representative phone/tablet and
  hardware-controller testing is pending. Desktop Studio frame observations do not clear the
  mobile performance gate.
- Client work is cadence/count bounded, including reduced-effects budgets, but final visual
  fluidity and a 20-match memory/instance soak still need representative-device evidence.
- The squirrel rival, field camp, layered backdrop, scarf, icons, and interfaces are original
  code-built programmer art. They still need screenshot-driven silhouette, typography,
  palette, spacing, animation, and production-asset iteration.
- Hosted CI validates source and builds the test place but cannot execute Roblox Studio
  runtime tests without a Windows self-hosted runner.

## Release blockers

- Select and clear a final public name; Project Critter Clash remains an internal codename.
- Pass the current 137-spec Studio run and combined Phase 1-4 lobby/combat/profile/device
  checklist with no blocker or critical error.
- Pass published private Development schema-v2 migration, leave/rejoin, competing-session,
  retry/read-only, autosave, PlayerRemoving, and shutdown validation without Production data.
- Complete exploit, multiplayer/disconnect, representative mobile/gamepad, performance/soak,
  telemetry-reconciliation, and rollback tests.
- Complete original production art/audio and asset-provenance review.
- Implement and stage-test durable receipt processing before enabling any paid product; live
  commerce remains optional and owner-approved.
- Publish only after the owner reviews tester permissions, content-maturity questionnaire,
  release evidence, rollback target, and all Production configuration.
