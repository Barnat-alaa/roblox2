# Project Critter Clash

Project Critter Clash is the development codename for an original, turn-based animal
artillery game for Roblox. The project aims for the tactical readability and mischievous
energy of classic browser artillery games while using entirely original characters,
weapons, maps, interface, audio, progression, and branding.

The public release name has not been selected. **Wild Ones** and names implying an official
relationship with another game are prohibited.

## Current development slice

The repository contains the first server-authoritative combat foundation:

- deterministic shared ballistics, wind, weapon, and damage rules;
- a server-owned turn/fire boundary with request validation;
- a generated 2.5D greybox arena and combat-plane enforcement;
- a side-view client camera, aim controls, trajectory preview, and combat HUD;
- TestEZ specifications, lint/format configuration, and reproducible Rojo builds;
- a CI workflow with pinned tooling, build validation, and a basic secret scan.

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
- The server owns turns, shot origins, projectile collision, damage, and rewards.
- Clients never report hits or damage.
- No secrets, private keys, ripped assets, or unreviewed third-party assets may be committed.
- Production publication and production data changes require explicit approval.

Third-party components and their licences are recorded in
[docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
