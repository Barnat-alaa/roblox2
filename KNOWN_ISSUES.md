# Known Issues

## Current development slice

- The inspected owner place is unpublished; verified playtests currently use generated local
  `.rbxlx` builds rather than a published Development place.
- The logical terrain grid is implemented and tested, but the greybox renderer/projectile
  service does not yet apply and replicate its crater deltas.
- Bot turns, persistent profiles, matchmaking, results/rematch, cosmetics, and monetisation are
  not yet implemented.
- Eliminations are not yet retained in a match roster, so Roblox respawning prevents a complete
  winner/MatchEnd loop in this slice.
- Movement is plane/distance constrained, but accumulated movement, jump frequency, and ground
  state still need stronger server validation before competitive testing.
- Mobile controls require device testing and accessibility tuning.
- Projectile visuals are predictive; late clients need a state-recovery path.
- The initial terrain and character presentation are programmer art, not release assets.
- TestEZ specifications run successfully in Studio; hosted CI validates their source and test
  place build but cannot launch Studio without a Windows self-hosted runner.

## Release blockers

- Select and clear a final public name.
- Complete original production art, audio, and asset-licence review.
- Add session-locked persistent data with migrations and shutdown tests.
- Complete multiplayer, exploit, mobile, performance, and rollback testing.
- Publish only after the Creator Dashboard maturity questionnaire and tester permissions are
  reviewed by the owner.
