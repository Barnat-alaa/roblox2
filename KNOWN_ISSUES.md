# Known Issues

## Current development slice

- The inspected owner place is unpublished; verified playtests currently use generated local
  `.rbxlx` builds rather than a published Development place.
- Static analysis, strict analysis, and both Rojo builds pass. The latest recorded Studio
  TestEZ run completed with 56 passed, 0 failed, and 0 skipped; source contains 111 specs, so
  the Phase 1/2 additions still need a user-run Studio rerun.
- Phase 1 movement, grounding, physical bot collision, support-loss settling, projectile
  leases, roster-only damage, readiness recovery, and Results expiry are implemented, but
  their final runtime/visual-feel signoff remains user-run validation.
- Schema-v1 profiles, session leases, bounded retries/autosave/shutdown handling, read-only
  fallback, idempotent coins/XP rewards, and profile/results presentation are implemented in
  source, but their service/UI runtime path has not yet received Studio acceptance.
- The unpublished Studio build deliberately uses process-local session memory. It cannot prove
  cross-session persistence and balances may reset after Studio stop/start without indicating
  a defect.
- Native DataStore leave/rejoin, lease contention, retry, read-only recovery, autosave, and
  BindToClose durability have not been run against a published Development place. Cloud data
  safety therefore remains a release blocker even though the adapter and pure rules exist.
- Published Studio synthetic users (`UserId <= 0`) intentionally remain on SessionMemory;
  cloud acceptance requires an authenticated positive-UserId client showing
  `CLOUD`/`Persistent` storage.
- Schema v1 persists coins, XP, match statistics, and a bounded reward ledger only. Inventory,
  owned/equipped cosmetics, settings, receipts, quests, mastery, and seasons are not yet
  represented.
- The processed-reward ledger retains 64 identities. That covers the ordered live match and
  retry lifecycle, but it is not a permanent archive against manually replaying an identity
  after 64 newer grants.
- Orderly shutdown drains already-enqueued rewards for up to 25 seconds, but there is no
  durable match-result outbox. An abrupt crash before the atomic profile grant begins can lose
  that earned reward; durable recovery is still required before production claims.
- Matchmaking, a dedicated lobby, cosmetics, and monetisation are not implemented.
- Results expiry returns to the waiting scheduler because a dedicated lobby is not yet built.
- Mobile controls require device testing and accessibility tuning.
- Client fluidity has explicit trajectory, effects, HUD, and terrain-work bounds, but its
  visual feel and representative-device performance have not been accepted. The current
  16.65 ms p50 / 17.72 ms p95 / 18.04 ms p99 / 18.37 ms worst server snapshot is Studio-only
  evidence.
- Terrain replication has snapshot recovery, but predictive projectile visuals still need a
  late-client state-recovery path.
- The new squirrel rival, layered backdrop, and colour grade establish an original direction,
  but they remain code-built programmer art rather than production character/environment
  assets; silhouette, scale, palette, and readability need screenshot-driven iteration.
- Hosted CI validates TestEZ source and the test-place build but cannot execute Studio runtime
  tests without a Windows self-hosted runner.

## Release blockers

- Select and clear a final public name.
- Complete original production art, audio, and asset-licence review.
- Complete the user-run 111-spec rerun and combined Phase 1 movement/support/bot/rematch plus
  Phase 2 profile/reward presentation validation.
- Complete owner-run published Development DataStore leave/rejoin, migration, duplicate
  session, transient failure, autosave, and shutdown validation without using Production.
- Complete multiplayer, exploit, mobile, performance, and rollback testing.
- Publish only after the Creator Dashboard maturity questionnaire and tester permissions are
  reviewed by the owner.
