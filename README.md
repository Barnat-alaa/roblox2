# Project Critter Clash

Project Critter Clash is the development codename for an original, turn-based animal
artillery game for Roblox. The project aims for the tactical readability and mischievous
energy of classic browser artillery games while using entirely original characters,
weapons, maps, interface, audio, progression, and branding.

The public release name has not been selected. **Wild Ones** and names implying an official
relationship with another game are prohibited.

## Current development slice

The repository contains the server-authoritative combat, terrain, and complete 1v1 match-loop
foundation:

- deterministic shared ballistics, wind, weapon, and damage rules;
- a server-owned turn/fire boundary with request validation;
- an authoritative 45 × 24 terrain grid using configurable 4-stud cells;
- 8 × 8 dirty chunks for server collision and pooled client rendering;
- revisioned Snapshot/Delta terrain replication with validated, rate-limited resync;
- projectile crater integration, including Acorn impacts and a bounded Mole Drill path that
  clips at the grid boundary and protected terrain;
- protected spawn supports and bottom cells, a small server-lethal central hazard, and
  server-enforced death-height elimination;
- a frozen 1v1 roster, with late joiners held as spectators for the active match and eligible
  to fill an open slot at the next boundary, plus a server-owned BotCritter that uses bounded,
  imperfect aim and the normal authoritative turn/fire path for solo matches;
- persistent elimination state that remains authoritative across Roblox character respawns;
- one authoritative match result, a Results interface, unanimous human rematch consent, and
  a fresh-match reset of terrain, bot, characters, wind, turns, and timers;
- a side-view client camera, aim controls, trajectory preview, and combat HUD;
- an original code-built red-squirrel rival, layered hill/cloud/sun backdrop, and restrained
  atmosphere, bloom, and colour grading as the first low-cost visual-direction pass;
- bounded client fluidity work: no 97-point trajectory allocation, at most 48 preview
  raycasts per rebuild, 16 effect catch-up steps per frame, a 10 Hz HUD cadence, and one
  terrain chunk rebuild per Heartbeat;
- 57 TestEZ specs in source, lint/format configuration, and reproducible Rojo builds;
- a CI workflow with pinned tooling, build validation, and a basic secret scan.

Static analysis, strict analysis, and both Rojo builds are clean. The latest recorded Studio
TestEZ run reports **56 passed, 0 failed, 0 skipped**; source now contains 57 specs, so the
added tuning test still needs a user-run Studio rerun. A live pre-final-tuning bot match
verified authoritative bot firing, human elimination, and the DEFEAT Results flow. Final bot
rematch and runtime/visual-feel validation remain user-run acceptance work. In Studio, bot
aim solving was observed at 3.43-5.65 ms, while a server snapshot measured 16.65 ms p50,
17.72 ms p95, 18.04 ms p99, and 18.37 ms worst frame time. These are development observations,
not production or representative-device guarantees. The next implementation milestone is
movement, grounding, and terrain-support hardening.

The current Development build identifies itself as `0.3.0-dev`. Character and environment
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
- `Up` / `Down`: adjust aim angle.
- `Left` / `Right`: adjust shot power.
- `1`–`4`: select an MVP weapon.
- `F`: request a shot.

Mobile-safe controls are rendered by the client, but real-device tuning is still pending.

## Repository policy

- All important Luau modules use `--!strict`.
- The server owns turns, shot origins, projectile collision, damage, and terrain mutations.
- Future rewards must also be server-authoritative.
- Clients never report hits or damage.
- No secrets, private keys, ripped assets, or unreviewed third-party assets may be committed.
- Production publication and production data changes require explicit approval.

Third-party components and their licences are recorded in
[docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
