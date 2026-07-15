# Project Critter Clash roadmap

Project Critter Clash is a temporary internal codename. This plan targets an original Roblox animal-artillery game; it is not a remake and must not reuse protected names, characters, layouts, artwork, audio, or code.

## Planning basis

- **MVP target:** a private, published vertical slice after seven focused development days.
- **Team model:** one full-time Roblox engineer who also owns design and production, with part-time art, QA, and product/account-owner support. Parallel roles describe hats, not assumed headcount.
- **Time convention:** estimates are focused work time and include a small verification allowance. One day is about six productive hours.
- **Release rule:** combat reliability, mobile usability, data safety, and originality outrank content count.
- **Account gates:** the owner must approve production publication, paid products, Robux spending, ownership changes, and production credentials.
- **MVP fallback:** 1 player versus bot is sufficient when a second tester is unavailable. Four-player free-for-all is not an MVP dependency.

### Roles

| Code | Responsibility |
| --- | --- |
| ENG | Roblox/Luau implementation and integration |
| NET | multiplayer, simulation, and security engineering |
| GD | game design and balance |
| UI | interface, input, camera, and accessibility |
| ART | original visual/audio asset production |
| QA | test design, device testing, and release verification |
| DATA | persistence, economy, analytics, and migrations |
| OPS | repository, CI, environments, publishing, and rollback |
| OWNER | account-holder approvals and Creator Dashboard actions |

## Implementation checkpoint — 2026-07-15

The authoritative 1v1 loop, solo bot, Phase 1 combat correctness, Phase 2 progression, and
Phase 3/4 lobby/comfort slice are implemented in the local `0.7.0-dev` Development build:

- movement is turn-token and sequence scoped, speed/arena/plane constrained, and charged by
  cumulative path distance with bounded grounded jumps;
- terrain exposes explicit footprint support, while humans and the physical BotCritter use a
  stable-sample settlement/recovery path after impacts, support loss, and turn timeout;
- explosion damage is restricted to the current roster, projectile finalization is leased to
  the exact match resolution, and readiness/results waits have bounded recovery;
- client and server high-frequency work remains cadence- or count-bounded;
- schema-v2 profiles validate bounded integer coins, XP, win/loss/draw statistics, a bounded
  64-entry processed-reward ledger, cosmetic inventory/equipment, and normalized settings;
  account level is derived from XP and schema v0/v1 profiles have strict migration paths;
- Development persistence uses UpdateAsync session leases, bounded retries, autosave,
  shutdown draining, and explicit read-only/unavailable states; unpublished Studio selects a
  deliberate process-local session-memory adapter with no cross-session persistence;
- result rewards are server-derived and applied atomically with their ledger entry. Stable
  grant IDs include environment, match, and player identity but deliberately exclude economy
  version, so retuning cannot regrant an already processed match;
- profile status/balances/derived level and pending/resolved reward feedback are presented by
  the client without accepting client-authored currency values;
- a compact field-camp lobby owns admission: Practice is immediate bot play when available,
  Casual is same-server FIFO with human pairing and an eight-second bot fill, Results can
  return to lobby, and rematch cannot import spectators;
- one original free Sunset Scout Scarf is owned/equipped by default, previewed in Loadout,
  persisted through schema v2, and applied as nonphysical appearance only;
- reduced-effects, camera-shake, and UI-scale settings apply immediately and persist; touch,
  responsive layouts, and gamepad bindings are implemented in source;
- late clients can request one rate-limited active projectile launch snapshot after their
  handlers connect, without receiving outcome authority;
- versioned allowlisted Development telemetry covers the implemented session/queue/match,
  rematch, shot/impact, cosmetic, and settings events without raw user identifiers;
- source contains 137 TestEZ specs. The latest recorded Studio TestEZ execution remains the
  earlier 56-pass run, so Phase 1-4 runtime/device behavior still requires user-run
  acceptance. Published Development DataStore behavior has not been validated.

**Immediate acceptance step:** run the 137-spec suite and the combined movement/support/bot,
profile/reward, lobby/loadout/settings, late-projectile, and input/device checklist in
`NEXT_ACTIONS.md`, then return screenshots or a feel description. The unpublished place can
verify the session-memory path only; cloud persistence requires an owner-run published
Development-place test.

**Next implementation milestone after acceptance:** tune the current original presentation
from screenshots and device feel, add only provenance-cleared original audio/assets, and run
the private release-candidate gates. Purchase plumbing, paid SKUs, analytics activation, and
publication remain separate owner-approved work. No Development or Production place has been
published.

## Seven-day private MVP

The critical path is repository and Studio sync → combat plane → turn authority → ballistic shot → damage and elimination → terrain deltas → complete match → persistence → private publish.

### Day 1 — foundation and greybox

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M1.1 | Verify Studio MCP, inspect the DataModel and Output, and remove the temporary connection object | Studio open | 0.5 h / ENG, OWNER | Read, create, play, inspect, stop, and delete operations all succeed; no temporary object remains | If MCP fails, use the documented file-only Rojo flow and record the limitation |
| M1.2 | Establish strict-Luau repository, Rojo mapping, pinned tools, lint/format/build/test CI, and environment config | M1.1 | 2 h / ENG, OPS | A clean checkout builds a place; CI runs without secrets; development config is selected | If package tooling blocks work, pin Rojo plus formatter/linter first and defer optional packages |
| M1.3 | Create server, shared, and client bootstraps with a small service lifecycle | M1.2 | 1 h / ENG | One server and two clients start once with no critical Output error; duplicate startup is rejected | Use explicit module initialization rather than a framework |
| M1.4 | Greybox one original arena, one placeholder critter, fixed combat plane, and side-view camera | M1.3 | 2.5 h / ENG, UI, GD | Two avatars spawn in bounds, remain near the fixed depth plane, and stay readable in overview and focus views | Replace custom character art with an original capsule/primitive rig; use one static camera mode |

**Day 1 gate:** a two-client Studio session loads a readable, original greybox and the automated build is green.

### Day 2 — turns, movement, aiming, and input

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M2.1 | Implement the server-owned match/turn state machine and 20-second prototype timer; tune toward 18 from playtests | M1.3 | 2 h / NET | Only the active participant can act; timeout advances exactly once; disconnect does not deadlock | Collapse Movement and Aiming into one ActiveTurn state while retaining explicit transition guards |
| M2.2 | **IMPLEMENTED; STUDIO ACCEPTANCE PENDING:** enforce bounded left/right movement and jump with plane, accumulated-distance, speed, jump-frequency, grounded-state, and arena validation | M1.4, M2.1 | 1.5 h / NET | Server rejects off-turn, over-speed, excess-distance, excess-jump, airborne-jump, and out-of-bounds movement in two-client tests | Disable jumping and use a fixed movement-distance budget |
| M2.3 | Add angle, power, weapon selection, round wind, active-player HUD, health, and timer | M2.1 | 1.5 h / UI, GD | PC input reaches min/max values predictably; HUD clearly identifies actor, wind, weapon, and time | Use buttons/keys with discrete angle and power steps |
| M2.4 | **IMPLEMENTED IN SOURCE; DEVICE ACCEPTANCE PENDING:** mobile input layout, responsive scaling, and safe-area-aware panels | M2.3 | 1 h / UI, QA | Core controls work at representative phone and tablet sizes with no overlap or hover requirement | Ship separate angle/power controls; defer drag-to-aim comparison |

**Day 2 gate:** a player and bot/test client alternate legal turns, including safe timeout, on keyboard and mobile emulation.

### Day 3 — authoritative projectile combat

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M3.1 | Implement shared fixed-step ballistics with gravity, signed horizontal wind, and raycast sweeps | M2.3 | 2 h / NET | Unit cases match known no-wind and wind trajectories; a fast projectile cannot tunnel through test walls | Use one fixed projectile speed range and cap lifetime at eight seconds |
| M3.2 | Add validated FireWeapon request and server shot ownership, origin, angle, power, and weapon lookup | M2.1, M3.1 | 1 h / NET | Forged origin, weapon, power, repeat fire, and off-turn requests cause no shot or damage | Allow only Acorn Cannon until validation is stable |
| M3.3 | **IMPLEMENTED; LATE-JOIN ACCEPTANCE PENDING:** pooled client projectile presentation, approximate preview, follow camera, and rate-limited active-launch recovery | M3.1 | 1 h / ENG, UI | Visual path follows server events closely, a late client recovers the active launch, and effects never decide hits | Use a single server-replicated visual and omit dotted preview |
| M3.4 | Add explosion falloff, bounded knockback, health, elimination, match result, and next-turn settling | M3.2 | 2 h / NET, GD | One complete match can be won; damage occurs once; self/friendly-fire rule is consistent; velocities remain bounded | Disable knockback and line-of-sight attenuation; keep radial server damage |

**Day 3 gate:** the server alone can resolve a full 1v1 elimination match with Acorn Cannon.

### Day 4 — destructible terrain

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M4.1 | Build an authoritative 2D cell grid with solid, empty, hazardous, and indestructible states | M1.4 | 1.5 h / NET | Map data loads deterministically; bounds and indestructible shell are validated | Use a small fixed map encoded as rows |
| M4.2 | Render destructible grouped cells and replicate only changed cell batches | M4.1 | 2 h / ENG, NET | Both clients converge after a crater; unchanged regions are not rebuilt | Use coarser visible tiles and no meshing |
| M4.3 | **IMPLEMENTED; STUDIO ACCEPTANCE PENDING:** apply circular crater masks, explicit support loss, bounded falling/settling, hazard/out-of-world resolution, and spawn protection | M3.4, M4.2 | 2 h / NET | Edge, thin ledge, overlapping crater, spawn, and hazard tests resolve without desync or endless falling | Use kill-plane recovery/damage and indestructible spawn pads |
| M4.4 | Add Mole Drill as a terrain-first second weapon using the same request and simulation path | M3.2, M4.3 | 0.5 h / GD, ENG | Drill removes a bounded path and has lower direct damage; duplicate requests remain harmless | Convert it to a straight low-damage projectile with a larger crater |

**Day 4 gate:** an explosion visibly and consistently reshapes the battlefield without a full-map rebuild.

### Day 5 — weapon set, bot, rewards, and save

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M5.1 | Configure Fizzy Bomb and Bubble Bouncer with fuse/bounce limits, completing four original weapons | M3.1, M4.3 | 1.5 h / GD, ENG | Each weapon has a distinct legal trajectory and readable role; all terminate within lifetime bounds | Ship two polished weapons and show the other two as unavailable previews |
| M5.2 | **IMPLEMENTED; USER VALIDATION PENDING:** an imperfect bot selects a target, solves a bounded shot with difficulty error, and uses normal fire validation | M3.2 | 1.5 h / ENG, GD | Bot fires before timeout and can finish/rematch a match without hidden damage or perfect information; final-tuning runtime signoff remains open | Bot uses Acorn Cannon/Mole Drill through a bounded deterministic search |
| M5.3 | **IMPLEMENTED; RUNTIME ACCEPTANCE PENDING:** Results/rematch use unique session-scoped match identities and enqueue server-derived, idempotent coins/XP grants before Results replication; profile and Results UI show pending/resolved status | M3.4 | 1 h / DATA, UI | Win/loss and reward are clear; rematch begins cleanly; reachable result/retry calls resolve once within the retained ledger | Disable a grant when its profile is not safely writable |
| M5.4 | **IMPLEMENTED; PUBLISHED DEVELOPMENT VALIDATION PENDING:** schema-v2 profile validation, schema-v0/v1 migration, session leases, bounded retry/autosave/shutdown behavior, read-only failure handling, a 64-entry reward ledger, inventory/equipment, and settings | M5.3 result identity | 2 h / DATA, NET | Current 137-spec source covers pure profile/reward/session/cosmetic/settings/lobby/telemetry rules; owner-run published Development tests must still prove migration, leave/rejoin, concurrent session, retry, and shutdown against DataStoreService | Unpublished Studio uses session memory; keep mutations disabled for read-only/unavailable profiles |

**Day 5 gate:** pending owner-run published Development proof that a new player can finish and
rematch a bot match, then rejoin with rewards intact.

### Day 6 — lobby, cosmetic, polish, and instrumentation

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M6.1 | **IMPLEMENTED; STUDIO ACCEPTANCE PENDING:** compact lobby with Practice, Casual Queue, Loadout, Settings, FIFO admission, safe cancel, and Return to Lobby | M5.2 | 1 h / UI | Queue starts a player match when available and a bot match after a short wait; queued players never enter another roster | Present Practice and immediate bot play only |
| M6.2 | **IMPLEMENTED; PERSISTENCE ACCEPTANCE PENDING:** free original Sunset Scout Scarf, ownership/equip validation, preview, appearance, and persistent loadout | M5.4 | 1 h / ART, DATA, UI | Owned cosmetic equips and persists; unowned IDs are rejected; appearance never changes stats | Use an original color/pattern material on the placeholder critter |
| M6.3 | Implement purchase receipt plumbing and one development-only cosmetic test SKU | M5.4, M6.2 | 1 h / DATA, OWNER | Duplicate receipt tests grant once; cancelled/failed prompts grant nothing; no live SKU is enabled without owner approval | Use a mock receipt adapter in Development and ship no paid product |
| M6.4 | **PARTIALLY IMPLEMENTED; DEVICE/AUDIO ACCEPTANCE PENDING:** camera-shake, reduced-effects, UI-scale settings, responsive mobile controls, and gamepad bindings; original audio remains unshipped | M3.3 | 1.5 h / ART, UI, QA | Effects remain readable; settings apply immediately; keyboard/mobile/gamepad complete a match on tested hardware | Keep the build silent until provenance-cleared original audio is ready |
| M6.5 | **DEVELOPMENT SINK IMPLEMENTED; EVENT QA PENDING:** emit versioned allowlisted session, queue, match/rematch, shot/impact, cosmetic, and settings diagnostics | M5.3 | 0.5 h / DATA | One scripted session reconciles starts/completions and contains no personal data or per-frame spam | Keep structured Development logging until a reviewed analytics backend is enabled |

**Day 6 gate:** source implementation is present; the lobby-to-match-to-results loop, mobile/
gamepad behavior, persistent cosmetic/settings equipment, projectile recovery, and telemetry
sequence still require the owner/user-run acceptance matrix.

### Day 7 — private publication

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Principal risk / fallback |
| --- | --- | --- | --- | --- | --- |
| M7.1 | Run lint, build, unit, two-client, bot, persistence, exploit, mobile, and 10-match soak suites | Days 1–6 | 2 h / QA, ENG | No blocker or critical issue; no unbounded memory/instance growth; known noncritical issues are recorded | Cut weapons/effects/features causing failures instead of patching around unsafe behavior |
| M7.2 | Complete original temporary icon/thumbnail, content questionnaire, asset/license registry, tester access, and private settings | M7.1 | 1 h / ART, OPS, OWNER | Every shipped asset has provenance; listing makes no remake/official claim; authorized testers can access it | Use clearly original text-and-shape key art; keep experience owner-only if approvals are incomplete |
| M7.3 | Publish the approved private build, tag it, retain the prior artifact/place version, and run a live smoke test | M7.2, OWNER approval | 1.5 h / OPS, OWNER, QA | Authorized tester joins, completes tutorial/practice and bot/casual match, earns/persists rewards, rematches, and sees no critical server error | Deliver a local/Studio release candidate and defer publication |
| M7.4 | Capture baseline analytics, known issues, rollback trigger/owner, and first tester feedback | M7.3 | 0.5 h / DATA, QA, GD | Release record contains version, place, time, approver, smoke evidence, metrics, and rollback command/process | Collect structured manual test notes if analytics is not available |

**MVP release criteria**

- One-versus-one or player-versus-bot elimination is complete in roughly three to six minutes.
- Active-turn ownership, shot resolution, damage, terrain, rewards, and purchases are server-authoritative.
- At least two weapons are excellent; four are required only if all pass the release gate.
- PC and mobile-emulation controls complete the whole loop; no hover-only action exists.
- A profile can leave and return without lost or duplicated progression.
- A free cosmetic can be equipped. Live monetization is optional and requires owner approval.
- No critical Output error, duplication path, arbitrary-damage path, or known remote bypass remains.
- All published visuals/audio are original or documented as licensed.

## Weeks 2–4 — limited-alpha foundation

### Week 2 — combat feel and resilience

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W2.1 | Tune aim, wind readability, turn pacing, camera, reactions, and hit feedback from observed sessions | MVP telemetry | 2 d / GD, UI, ART | First-shot miss reasons are understandable; median match target and rematch baseline are measured | Keep one camera style and reduce effects |
| W2.2 | Harden crater edges, projectile settling, reconnect/leave behavior, and repeated-match cleanup | MVP core | 1.5 d / NET, QA | 50-match automated/manual soak has no match deadlock or material instance growth | Reload a fresh arena per match |
| W2.3 | Bring four MVP weapons to quality and add two horizontal weapons only after balance review | W2.1 | 1.5 d / GD, ENG | Every weapon has a use case, counterplay, mobile control, and telemetry; no dominant paid path | Retain four weapons |
| W2.4 | Improve bot aim model, three error bands, terrain awareness, and turn speed | W2.1 | 1 d / GD, ENG | Easy/normal bot completion and hit rates fall inside documented bands; bot uses player rules | One normal-difficulty bot |

### Week 3 — original production art and onboarding

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W3.1 | Produce one original rigged critter base and a second silhouette/color variant | approved concepts | 2 d / ART | Silhouette, topology, rig, expressions, mobile cost, and originality review pass | Polish one base plus cosmetic variants |
| W3.2 | Produce one polished map kit, weapon silhouettes, impacts, UI icon family, and original audio set | art direction | 2 d / ART, UI | Combat remains readable on phone; asset manifest and source files are complete | Polish only the core map and four weapons |
| W3.3 | Replace prototype HUD/lobby/results with responsive original UI tokens and accessibility states | W2.1, W3.2 | 1 d / UI | Phone/tablet/desktop safe-area matrix passes; color is not the only state cue | Retain functional HUD and polish match screens first |
| W3.4 | Implement action-led tutorial through movement, first shot, crater, wind, bot win, reward, equip, and queue | W2.4, W3.3 | 1 d / GD, UI, DATA | At least 80% of internal testers complete without verbal help; funnel is valid | Use a four-step practice overlay and bot match |

### Week 4 — multiplayer and social alpha

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W4.1 | Prototype four-player free-for-all, turn wait UX, scoring, spawn rules, and camera framing | stable 1v1 | 2 d / NET, GD, UI | Four-client Studio matches finish without desync; inactive players remain engaged in tests | Keep 1v1 public and four-player behind a feature flag |
| W4.2 | Add party/private-match join flow and friend invite affordance using platform-supported APIs | W4.1 | 1.5 d / NET, UI | A party joins the same private match; rejection and teleport failure recover cleanly | Support same-server private matches only |
| W4.3 | Add second map and data-driven map validation/rotation | W3.2 | 1 d / ART, ENG | Both maps satisfy bounds, spawn, indestructible shell, hazard, and mobile readability tests | Add a variant layout from the same kit |
| W4.4 | Closed internal alpha, balance pass, abandonment handling, and security review | W4.1–W4.3 | 1.5 d / QA, NET, GD | No critical exploit/deadlock; match completion and rematch rates are reviewed by platform/input | Keep experimental social/four-player features disabled |

**Week 4 exit:** a polished 1v1 alpha is stable; four-player/social features ship only when their own gates pass.

## Weeks 5–8 — limited beta

### Week 5 — progression and content

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W5.1 | Add capped account levels and free horizontal unlock path | stable data | 1 d / DATA, GD | Migration, grant, reconnect, and cap tests pass; essential tools remain free | Cosmetic-only account rewards |
| W5.2 | Add cosmetic-only weapon mastery and daily/weekly quest framework | W5.1, analytics | 2 d / DATA, GD | Progress grants once, resets correctly, and cannot change combat stats | Ship mastery only; postpone weekly quests |
| W5.3 | Expand to 8–10 balanced weapons, 3 critter bases/variants, and 2–3 maps | content pipeline | 2 d / ART, GD, ENG | Each asset passes performance, originality, role, and mobile-readability review | Six weapons, two bases, two maps |
| W5.4 | Improve collection, profile, loadout, and results motivation | W5.1–W5.3 | 1 d / UI | Players understand next unlock and can equip without leaving the social flow | Keep loadout and results only |

### Week 6 — fair commerce and season prototype

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W6.1 | Build cosmetic catalog, preview, ownership, purchase adapter, and regional-price-safe display | receipt tests, owner SKUs | 2 d / DATA, UI, OWNER | Successful/cancelled/pending/duplicate/rejoin receipts pass staging tests; previews are accurate | Ship earnable catalog with commerce disabled |
| W6.2 | Create small original launch catalog and starter-pack hypothesis | W3 assets | 1.5 d / ART, GD | Every item is cosmetic, licensed, readable, and has an explicit value proposition | Fewer higher-quality items; no starter pack |
| W6.3 | Prototype free and premium cosmetic season tracks with auditable grant ledger | W5 quests, W6.1 | 1.5 d / DATA, GD | Free track is useful; purchases never grant stats; season rollover and late purchase tests pass | Free event track only |
| W6.4 | Conduct no-pay-to-win, age-appropriate presentation, pricing, and purchase-pressure review | W6.1–W6.3 | 1 d / GD, QA, OWNER | Written sign-off: no power sale, loss prompt, hidden price, deceptive timer, or first-match interruption | Keep monetization disabled |

### Week 7 — closed alpha with external testers

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W7.1 | Recruit consented private testers and observe onboarding across phone and PC | W3.4 | 1 d / QA, OWNER | Notes and funnel cover new/returning users without collecting unnecessary personal data | Internal testers only |
| W7.2 | Balance weapons/bots and fix top abandonment, aim, and terrain issues | W7.1 analytics | 2 d / GD, ENG, NET | Critical funnel loss has an identified fix; balance report has confidence bands/sample caveats | Disable weak content and focus on 1v1 |
| W7.3 | Profile terrain, effects, memory, physics, and network on low/mid devices | release candidate | 1.5 d / QA, ENG | Budget table passes on representative hardware; reduced-effects mode materially helps | Coarser terrain, fewer particles/debris, lower asset sizes |
| W7.4 | Threat-model review, data restore rehearsal, receipt audit, and moderation/content pass | W6 | 1.5 d / NET, DATA, QA | Restore and rollback are rehearsed; no critical finding remains | Commerce and affected feature stay disabled |

### Week 8 — limited-beta release

| ID | Task | Depends on | Estimate / owner | Acceptance and test | Risk / fallback |
| --- | --- | --- | --- | --- | --- |
| W8.1 | Freeze scope, complete legal/name/asset review, content maturity, store listing, and support copy | W7 | 1 d / OWNER, ART, GD | Final public name/logo/listing have explicit approval; every asset has provenance | Retain a private codename build; postpone public listing |
| W8.2 | Run full regression, migration rehearsal, multi-client/device matrix, soak, and rollback drill | W8.1 | 2 d / QA, DATA, OPS | Release checklist passes; data snapshot and known-good artifact are available | Private/staged candidate only |
| W8.3 | Manually approve and stage controlled limited-beta rollout | W8.2, OWNER approval | 1 d / OPS, OWNER | Cohort can join; live smoke, purchases if enabled, analytics, and alerts work | Invite-only test or zero-commerce release |
| W8.4 | Monitor errors, completion, rematch, retention, data, economy, and commerce; hotfix or roll back | W8.3 | 2 d / DATA, QA, ENG | Daily release log records thresholds and decisions; critical triggers cause prompt rollback | Reduce traffic/access and disable features with flags |

**Week 8 exit:** 10–15 weapons and 5–6 critter bases are aspiration targets, not a release blocker. A smaller balanced catalog is preferable. Cross-server ranking, clans, and subscriptions are not required for beta.

## Post-launch backlog

| Priority | Work package | Dependency | Rough duration / role | Acceptance and test | Fallback |
| --- | --- | --- | --- | --- | --- |
| P0 | Live-ops health: error triage, economy anomalies, restore/rollback, moderation response | beta | ongoing / OPS, DATA, QA | Published SLOs and incident runbook are met | Restrict access/disable affected feature |
| P1 | Cross-server casual queues with MemoryStore and reserved matches | healthy population | 2–3 wk / NET | Load, expiry, duplicate assignment, teleport failure, party, and region tests pass | Same-server queues plus bots |
| P1 | Rejoin/reconnect and safe abandonment policy | reserved matches | 1–2 wk / NET | No reward duplication or hostage match; reconnection window is understandable | Loss-safe bot takeover |
| P1 | Parties, private servers, spectating reactions, and tournament rules | social demand | 2–3 wk / NET, UI | End-to-end party lifecycle and privacy tests pass | Private matches only |
| P1 | Seasonal live-ops tooling, catalog scheduling, and experiment controls | stable content pipeline | 2 wk / DATA, OPS | Rollout/rollback and grant audit work without code deploy | Manual curated events |
| P2 | Ranked mode and rating bands | balance, population, anti-cheat | 3–4 wk / GD, NET | Calibration, smurf/leave, queue quality, standardized loadout, and season reset tests pass | Unranked score mode |
| P2 | Team mode and larger arenas | stable four-player | 2–3 wk / GD, NET, ART | Friendly-fire, spawn, camera, wait time, and mobile performance pass | Four-player free-for-all |
| P2 | Character affinity and cosmetic social profiles | content capacity | 1–2 wk / DATA, UI, ART | Rewards are cosmetic and migration-safe | Weapon mastery only |
| P3 | Clans and clan cosmetics | demonstrated social retention | 4+ wk / NET, DATA, UI | Permissions, naming/moderation, privacy, and abuse tests pass | Platform groups/community links |
| P3 | Subscription and rewarded-video experiments | retention and policy review | 2+ wk / GD, DATA, OWNER | Fairness, policy, regional, analytics, and opt-in reviews pass | Do not ship |

## Cross-phase risk register

| Risk | Early signal | Mitigation | Scope fallback |
| --- | --- | --- | --- |
| Terrain cost/desync | crater latency, divergent cells, rising parts/memory | authoritative grid, bounded crater, delta batches, chunk ownership, soak tests | coarser cells, one small map, fewer simultaneous effects |
| Projectile disagreement | preview misses server path, tunneling, duplicate impacts | shared math, fixed/bounded step, swept raycasts, server seeds and event IDs | one non-bouncing projectile and server visual |
| Persistence/receipt loss or duplication | concurrent sessions, retry storms, reward mismatch | session lease, idempotency keys, append-only grant ledger, migration/restore tests | disable rewards/commerce while profile is read-only |
| Mobile aiming confusion | timeouts, cancelled aim, first-shot misses | large controls, safe areas, two-method prototype, tutorial telemetry | separate angle and power buttons |
| Low concurrency | long queues and abandonment | bot fill, practice, short timeout | bot-first matchmaking |
| Turn boredom | low completion/rematch, long inactive time | 15–20-second tuned turns, camera follow, emotes/reactions later, short matches | 1v1 only and shorter timer |
| Content overreach | unfinished weapons/art delay core | content gates and reusable kit | four weapons, one critter, one map |
| IP similarity | side-by-side confusion, copied silhouettes/UI | independent concepts, provenance log, originality review, legal review before commerce | primitive prototype art and delay branding |
| Pay-to-win perception | purchase-linked win rate or complaints | cosmetics-only catalog and standardized competitive stats | disable commerce |
| Solo-developer throughput | critical-path slip | daily vertical gates and feature flags | private Studio build instead of premature publication |

## Change control

- A task may enter the release branch only with its acceptance evidence and relevant tests.
- Any new feature that threatens a day/week gate replaces an equal or larger item; it does not silently expand scope.
- Production publishing, paid SKU creation, data deletion, ownership changes, and irreversible migrations always require explicit OWNER approval.
- Each release records build/version, environment, schema version, asset manifest revision, approver, smoke-test result, known issues, and rollback target.
