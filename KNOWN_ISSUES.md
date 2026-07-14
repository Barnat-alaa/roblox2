# Known Issues

## Current development slice

- The inspected owner place is unpublished; verified playtests currently use generated local
  `.rbxlx` builds rather than a published Development place.
- Static analysis, strict analysis, and both Rojo builds pass. The latest recorded Studio
  TestEZ run completed with 56 passed, 0 failed, and 0 skipped; source contains 57 specs, so
  the added tuning spec still needs a user-run Studio rerun.
- Bot turns are implemented. A pre-final-tuning live run verified authoritative firing,
  human elimination, and DEFEAT Results, but the final-tuning bot rematch and visual-feel
  signoff remain user-run validation.
- Persistent profiles, rewards, matchmaking, cosmetics, and monetisation are not implemented.
- Results currently grant no coins, XP, items, or persistent progress.
- Terrain collision and client rendering now follow terrain edits, but support loss relies on
  Roblox physics; explicit support detection and bounded settling remain incomplete.
- Movement is plane/distance constrained, but accumulated movement, jump frequency, and ground
  state still need stronger server validation before competitive testing.
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
- Complete the user-run 57-spec rerun and final-tuning bot rematch/visual validation.
- Harden movement, grounding, support loss, and bounded settling.
- Add session-locked persistent data with migrations and shutdown tests.
- Complete multiplayer, exploit, mobile, performance, and rollback testing.
- Publish only after the Creator Dashboard maturity questionnaire and tester permissions are
  reviewed by the owner.
