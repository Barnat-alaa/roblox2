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
- Logical terrain grid with protected cells, compact deltas, snapshots, and crater edge tests.
- Required product, technical, security, economy, analytics, testing, and release documents.
- GitHub Actions validation workflow with pinned Rokit download checksum.

### Security

- Client fire requests are treated as intent only; the server derives origins and outcomes.
- Projectile/disconnect transitions use guarded epochs and a wall-clock resolver watchdog.
- Production publishing remains a manual, owner-approved operation.

### Validation

- TestEZ in Roblox Studio: 30 passed, 0 failed, 0 skipped.
- StyLua, Selene, Roblox-aware Luau analysis, and both Rojo builds passed.
- Clean Studio playtest booted the arena and advanced a server-authoritative shot to the next
  round without game-script errors.
