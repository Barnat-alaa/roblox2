# Known Issues

## Current development slice

- The inspected owner place is unpublished; verified playtests currently use generated local
  `.rbxlx` builds rather than a published Development place.
- Static analysis, strict analysis, and both Rojo builds pass. The latest recorded Studio
  TestEZ run completed with 56 passed, 0 failed, and 0 skipped; source contains 71 specs, so
  the Phase 1 additions still need a user-run Studio rerun.
- Phase 1 movement, grounding, physical bot collision, support-loss settling, projectile
  leases, roster-only damage, readiness recovery, and Results expiry are implemented, but
  their final runtime/visual-feel signoff remains user-run validation.
- Persistent profiles, rewards, matchmaking, cosmetics, and monetisation are not implemented.
- Results currently grant no coins, XP, items, or persistent progress.
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
- Complete the user-run 71-spec rerun and Phase 1 movement/support/bot/rematch validation.
- Add session-locked persistent data with migrations and shutdown tests.
- Complete multiplayer, exploit, mobile, performance, and rollback testing.
- Publish only after the Creator Dashboard maturity questionnaire and tester permissions are
  reviewed by the owner.
