# Project Critter Clash

Project Critter Clash is the development codename for an original, turn-based animal
artillery game for Roblox. The project aims for the tactical readability and mischievous
energy of classic browser artillery games while using entirely original characters,
weapons, maps, interface, audio, progression, and branding.

The public release name has not been selected. **Wild Ones** and names implying an official
relationship with another game are prohibited.

## Current development slice

The repository contains the server-authoritative combat, terrain, complete 1v1 match loop,
progression foundation, and the Phase 3/4 lobby and comfort slice:

- deterministic shared ballistics, wind, weapon, and damage rules;
- a server-owned turn/fire boundary with request validation;
- an authoritative 45 × 24 terrain grid using configurable 4-stud cells;
- 8 × 8 dirty chunks for server collision and pooled client rendering;
- revisioned Snapshot/Delta terrain replication with validated, rate-limited resync;
- projectile crater integration, including Acorn impacts and a bounded Mole Drill path that
  clips at the grid boundary and protected terrain;
- protected spawn supports and bottom cells, a small server-lethal central hazard, and
  server-enforced death-height elimination;
- an explicit same-server lobby admission boundary: Practice starts a bot match when the arena
  is free, Casual pairs two FIFO entrants and bot-fills after eight seconds, cancellation is
  idempotent, and queued players/spectators are never silently inserted into an active match;
- a frozen 1v1 roster, with late joiners held as spectators, plus a server-owned BotCritter
  that uses bounded, imperfect aim and the normal authoritative turn/fire path for solo play;
- server-authoritative A/D movement and jumping with turn tokens, sequence validation,
  cumulative distance, speed, ground-state, jump-count, plane, and arena enforcement;
- explicit logical support detection plus bounded consecutive-sample settling and recovery for
  both player characters and the physical BotCritter after terrain loss or turn timeout;
- projectile leases, exact combatant damage whitelists, bounded readiness waits, and expiring
  Results state so stale callbacks cannot damage or advance a later match;
- persistent elimination state that remains authoritative across Roblox character respawns;
- one authoritative match result, a Results interface, unanimous human rematch consent, and
  a fresh-match reset of terrain, bot, characters, wind, turns, and timers;
- a strict schema-v2 profile containing bounded integer coins, XP, match statistics, a
  64-entry processed-reward ledger, cosmetic inventory/equipment, and normalized settings;
  schema-v0 and schema-v1 profiles migrate safely while account level remains server-derived;
- a Development-only persistence adapter with UpdateAsync session leases, bounded retries,
  autosave, shutdown draining, and explicit read-only/unavailable states; unpublished Studio
  uses an explicit process-local session-memory adapter and therefore does not persist across
  Studio sessions;
- server-calculated, idempotent result rewards with stable environment/match/player grant
  identities, plus replicated profile status, balances, levels, and reward feedback in the
  HUD and Results interface; the 64-entry ledger covers reachable live retries, not arbitrary
  replay after an identity has been evicted;
- one free original code-built `Sunset Scout Scarf`, validated owned/equipped state, a Loadout
  preview, and a nonphysical character appearance that never changes combat statistics;
- a responsive field-camp lobby with Practice, Casual, Loadout, Settings, queue status/cancel,
  Results-to-lobby flow, and server-replicated lobby state;
- persisted reduced-effects, camera-shake, and interface-scale settings that apply immediately,
  plus touch sizing and keyboard/gamepad bindings for movement, jump, aim, weapon cycling, and
  fire; representative hardware acceptance is still pending;
- a rate-limited active-projectile snapshot request so a late client can recover the current
  launch presentation without gaining collision or damage authority;
- versioned, allowlisted Development telemetry for session, queue, match, rematch, shot,
  impact, cosmetic, and settings events, emitted as structured diagnostics without raw user
  identifiers or per-frame traffic;
- a side-view client camera, aim controls, trajectory preview, and combat HUD;
- an original code-built red-squirrel rival, layered hill/cloud/sun backdrop, and restrained
  atmosphere, bloom, and colour grading as the first low-cost visual-direction pass;
- bounded client fluidity work: no 97-point trajectory allocation, at most 48 preview
  raycasts per rebuild, 16 effect catch-up steps per frame, a 10 Hz HUD cadence, and one
  terrain chunk rebuild per Heartbeat;
- 137 TestEZ specs in source, lint/format configuration, and reproducible Rojo builds;
- a CI workflow with pinned tooling, build validation, and a basic secret scan.

The source contains 137 TestEZ specs. The latest recorded Studio TestEZ run still reports
**56 passed, 0 failed, 0 skipped**, so the new Phase 1-4 specs and runtime paths require an
owner/user-run Studio rerun; source count is not runtime evidence. A live earlier bot match
verified authoritative bot firing, human elimination, and the DEFEAT Results flow. Lobby,
loadout, settings, late-projectile recovery, gamepad/mobile feel, and the final bot/rematch
pass remain runtime acceptance work. Earlier Studio observations measured BotAim solving at
3.43-5.65 ms and a server snapshot at 16.65 ms p50, 17.72 ms p95, 18.04 ms p99, and 18.37 ms
worst frame time. These pre-Phase-3 observations are not production or representative-device
guarantees. Schema-v2 persistence has not been validated against Roblox cloud
DataStoreService; that requires an owner-run published Development-place test with an
authenticated positive UserId.

The current Development build identifies itself as `0.7.0-dev`. Character and environment
art remain editable programmer-art foundations; screenshot feedback will drive the next
silhouette, palette, scale, and readability pass before any production asset work.

See [CURRENT_STATUS.md](CURRENT_STATUS.md), [ROADMAP.md](ROADMAP.md), and
[KNOWN_ISSUES.md](KNOWN_ISSUES.md) before continuing development.

## Prerequisites

- Windows 10/11, macOS, or Linux for file-based development.
- [Roblox Studio](https://create.roblox.com/docs/studio/setup).
- [Rokit](https://github.com/rojo-rbx/rokit) 1.2.0 or newer.
- Git.

On Windows, install Rokit using the official installer command if it is not already present:

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
```

## Bootstrap

```powershell
git clone https://github.com/Barnat-alaa/roblox2.git
Set-Location roblox2
rokit install
wally install
rojo build default.project.json --output build/CritterClash.rbxlx
```

Run the local validation suite:

```powershell
stylua --check src tests scripts
selene src tests scripts
rojo build test.project.json --output build/CritterClashTests.rbxlx
```

For live filesystem synchronisation, open the intended place in Roblox Studio, start:

```powershell
rojo serve default.project.json
```

Then connect the Rojo Studio plugin to `127.0.0.1:34872`. Roblox Studio MCP is used for
DataModel inspection and playtesting; Rojo remains the source-of-truth for code.

## Controls in the greybox slice

- `A` / `D`: move while permitted by the current turn.
- `Space`: jump while grounded and within the turn jump allowance.
- `Up` / `Down`: adjust aim angle.
- `Left` / `Right`: adjust shot power.
- `1`–`4`: select an MVP weapon.
- `F`: request a shot.
- Gamepad: left stick moves, `A` jumps, right stick adjusts aim/power, bumpers cycle weapons,
  and right trigger fires.
- Lobby keyboard shortcuts: `P` Practice, `C` Casual, `L` Loadout, and `S` Settings.

Mobile-safe controls and responsive panels are rendered by the client, but phone/tablet and
physical-gamepad tuning remain owner-run acceptance work.

## Repository policy

- All important Luau modules use `--!strict`.
- The server owns turns, shot origins, projectile collision, damage, and terrain mutations.
- Rewards and balance changes are server-authoritative.
- Clients never report hits or damage.
- No secrets, private keys, ripped assets, or unreviewed third-party assets may be committed.
- Production publication and production data changes require explicit approval.

Third-party components and their licences are recorded in
[docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
