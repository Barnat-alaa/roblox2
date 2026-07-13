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
- Terrain TestEZ coverage for compact deltas, ordering, atomic updates, overlap, protected
  cells, world conversion, dirty chunks, and snapshots.
- Required product, technical, security, economy, analytics, testing, and release documents.
- GitHub Actions validation workflow with pinned Rokit download checksum.

### Changed

- Replaced legacy static ground/shelf collision with the logical terrain projection.
- Impact events now report terrain cells changed and the resulting terrain revision.

### Security

- Client fire requests are treated as intent only; the server derives origins and outcomes.
- Projectile/disconnect transitions use guarded epochs and a wall-clock resolver watchdog.
- Terrain edits are capped and bounded, preserve indestructible cells, and rebuild only dirty
  chunks.
- Malformed, stale, or revision-gapped client terrain state triggers rate-limited snapshot
  recovery instead of partial mutation.
- Production publishing remains a manual, owner-approved operation.

### Validation

- StyLua, Selene, Roblox-aware Luau analysis, and both Rojo builds passed.
- Studio TestEZ: 37 passed, 0 failed, 0 skipped.
- The final terrain-enabled playable build booted clean with matching initial server/client
  terrain revision 0 and an active central hazard collision run.
- A real Acorn request produced Delta 0 → 1 with 9 changed cells and matching server/client
  terrain revision 1.
- In a separate clean run, a real Mole Drill request produced Delta 0 → 1 with 10 changed
  cells while protected boundary runs remained intact.
- A temporary server smoke observed death-height elimination.
- All temporary smoke scripts were removed; a clean restart produced only the expected
  development startup message.
- A separate two-client run was not part of this validation.
