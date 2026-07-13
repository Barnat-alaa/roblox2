# Third-party notices

## Scope

This file records third-party software currently declared by the repository. It does not grant rights beyond each upstream license. Versions come from rokit.toml, wally.toml, wally.lock, and the CI workflow.

No third-party runtime framework is declared in the production place mapping at this checkpoint. TestEZ is a development/test dependency and appears only in test.project.json through DevPackages; default.project.json does not map it into the production place.

## Luau package

### TestEZ 0.4.1

- Purpose: development/test-only BDD-style Roblox Luau test framework.
- Package: roblox/testez@0.4.1.
- Source: https://github.com/Roblox/testez
- License: Apache License 2.0.
- Production distribution: excluded from default.project.json.
- Test distribution: included when building test.project.json.
- Local upstream license evidence after locked Wally restore: DevPackages/_Index/roblox_testez@0.4.1/testez/LICENSE.
- Verified license SHA-256 at documentation time: 43070E2D4E532684DE521B885F385D0841030EFA2B1A20BAFB76133A5E1379C1.

Copyright belongs to the upstream TestEZ contributors as stated in its source and notices. TestEZ is provided under Apache License 2.0. A copy of that license is available from:

https://www.apache.org/licenses/LICENSE-2.0

Any distributed test artifact or source bundle containing TestEZ must retain relevant copyright, patent, trademark, attribution, modification, and NOTICE information and include the Apache 2.0 license as required. If project files modify TestEZ, mark modified files prominently. This project makes no claim to the TestEZ trademark and receives no upstream warranty.

## External developer tools

These pinned tools build, lint, format, resolve packages, or support editing. Their executables are not mapped into either Roblox place artifact. Their upstream licenses apply to installing/using/redistributing the tools; do not bundle a binary without rechecking its exact source and license.

| Tool | Pinned version | License | Purpose | Upstream |
| --- | --- | --- | --- | --- |
| Rojo | 7.7.0 | MPL-2.0 | filesystem-to-Roblox project build/sync | https://github.com/rojo-rbx/rojo |
| Wally | 0.3.2 | MPL-2.0 | Luau package resolution | https://github.com/UpliftGames/wally |
| StyLua | 2.5.2 | MPL-2.0 | Luau formatting | https://github.com/JohnnyMorganz/StyLua |
| Selene | 0.31.0 | MPL-2.0 | Luau linting | https://github.com/Kampfkarren/selene |
| Luau Language Server | 1.68.1 | MIT | editor analysis/type support | https://github.com/JohnnyMorganz/luau-lsp |
| Rokit | 1.2.0 in CI bootstrap | MIT | toolchain installation | https://github.com/rojo-rbx/rokit |

Rokit downloads and installs the manifest-pinned tools for development/CI. The CI workflow verifies the downloaded Rokit archive checksum. Tool binaries must not be copied into a distributable release without adding their exact license and required notices.

## CI actions and hosted services

The GitHub Actions workflow references:

- actions/checkout@v4;
- actions/upload-artifact@v4;
- GitHub-hosted runners and artifact storage.

These support CI and are not part of the Roblox place. Their upstream terms/licenses and GitHub service terms apply. For stronger supply-chain control before production, review and pin actions to approved immutable commit SHAs, then update this notice.

## Roblox platform

Roblox Studio, engine APIs, Creator Dashboard, Open Cloud, DataStoreService, MemoryStoreService, MarketplaceService, platform fonts/assets, analytics, and related services are platform dependencies governed by current Roblox terms and policies. They are not redistributed by this repository. Roblox names and marks belong to their respective owner; use here describes platform compatibility and does not imply endorsement.

## Art, audio, fonts, and marketing

Non-code assets are tracked separately in ASSET_LICENSES.md. As of 2026-07-13, no external production asset ID/import is registered for shipment. A new dependency that includes fonts, textures, icons, sounds, samples, models, animations, or generated media must be added to that registry and, when required, to this notice.

## Update procedure

For every dependency change:

1. Pin the exact version/source and update the lockfile.
2. Review the package tree, source, security posture, maintenance/replacement risk, and production inclusion.
3. Read the exact license and NOTICE files from that version; do not guess from a project name.
4. Record copyright, license, purpose, modifications, source, and required distribution/attribution.
5. Confirm license compatibility with the project and Roblox distribution.
6. Run tests and rebuild both production and test places.
7. Remove notice entries only after the dependency and all copied/derived code are removed.

Before a public or commercial release, legal/owner review must confirm that the source archive, Roblox place artifact, CI artifact, and any downloadable tools each carry the notices their contents require.
