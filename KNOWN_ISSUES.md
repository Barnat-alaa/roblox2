# Known Issues

## Current development slice

- The inspected owner place is unpublished; verified playtests currently use generated local
  `.rbxlx` builds rather than a published Development place.
- Static analysis and both Rojo builds pass. Studio TestEZ completed with 37 passed, 0 failed,
  and 0 skipped; the final playable terrain smoke also booted and restarted cleanly.
- A separate one-server, two-client validation has not yet been recorded.
- Bot turns, persistent profiles, rewards, matchmaking, cosmetics, and monetisation are not
  yet implemented.
- Eliminations are not retained independently of Roblox respawns, so MatchEnd, results, and
  rematch cannot complete reliably.
- Terrain collision and client rendering now follow terrain edits, but support loss relies on
  Roblox physics; explicit support detection and bounded settling remain incomplete.
- Movement is plane/distance constrained, but accumulated movement, jump frequency, and ground
  state still need stronger server validation before competitive testing.
- Mobile controls require device testing and accessibility tuning.
- Terrain replication has snapshot recovery, but predictive projectile visuals still need a
  late-client state-recovery path.
- The initial terrain and character presentation are programmer art, not release assets.
- Hosted CI validates TestEZ source and the test-place build but cannot execute Studio runtime
  tests without a Windows self-hosted runner.

## Release blockers

- Select and clear a final public name.
- Complete original production art, audio, and asset-licence review.
- Complete MatchEnd, results, rematch, and same-server bot flow.
- Add session-locked persistent data with migrations and shutdown tests.
- Complete multiplayer, exploit, mobile, performance, and rollback testing.
- Publish only after the Creator Dashboard maturity questionnaire and tester permissions are
  reviewed by the owner.
