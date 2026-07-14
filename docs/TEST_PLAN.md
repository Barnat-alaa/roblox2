# Test plan

## Purpose

Verify that Project Critter Clash is fun enough to retest, reliable enough to finish matches, safe against client forgery and duplicate grants, usable on PC/mobile, performant on representative hardware, and composed only of approved original/licensed assets.

Testing is risk-based. Projectile authority, terrain synchronization, turn liveness, persistence, receipts, mobile aiming, and release rollback receive deeper coverage than optional content.

## Quality gates

### Private MVP entry

- Build and test tooling is pinned and a clean checkout builds.
- Development Studio place syncs and starts with no critical Output error.
- Test configuration and one deterministic greybox map are available.

### Private MVP exit

- Format, lint, configuration validation, unit tests, and Rojo build pass.
- One-server/two-client 1v1 and player-versus-bot matches finish and rematch.
- PC and mobile emulation complete the whole loop.
- Profile leave/rejoin, match reward idempotency, and failure-mode tests pass.
- No blocker/critical defect, arbitrary-damage path, duplicate reward, or terrain desync is known.
- Published assets are original/licensed and authorized testers complete a live smoke test.

### Limited-beta exit

Private-MVP gate plus real Android and low/mid laptop coverage, four-client tests for any enabled four-player feature, 20–50 match soak, staging migration/restore and rollback rehearsal, security/content/legal review, analytics validation, and commerce matrix if commerce is enabled.

## Severity

| Severity | Definition | Release rule |
| --- | --- | --- |
| Blocker | cannot build/start/join/publish/restore; unsafe production action required | never release |
| Critical | arbitrary outcome/damage, data loss/corruption, reward/purchase duplication, widespread crash/deadlock, major IP/license issue | never release |
| High | common match cannot finish, mobile core control unusable, major desync/exploit with limited impact | fix or disable affected feature |
| Medium | recoverable gameplay/UI defect with workaround | document, prioritize |
| Low | cosmetic/polish issue with negligible outcome impact | may release when recorded |

## Test layers

| Layer | Runs | Focus |
| --- | --- | --- |
| Static/CI | every change | formatting, lint, strict types where supported, config/ID/reference validation, secret/license checks, reproducible Rojo build |
| Pure unit | every change | ballistics, wind, damage, terrain grid, turn transition functions, reward/receipt idempotency, migrations |
| Service integration | every change or release candidate | state machine + projectile + damage + terrain + data/economy adapters with fakes |
| Studio multiplayer | daily/release | replication, camera/UI, physics, disconnects, server/client authority |
| Device/performance | milestone/release | touch, safe areas, input switching, frame/memory/network/terrain effects |
| Staging/live smoke | release | place settings, data namespace, analytics, tester access, receipts if enabled, rollback |
| Exploratory playtest | milestone | first-shot clarity, turn boredom, weapon roles, rematch desire, originality |

CI commands use the repository’s pinned tool configuration. At minimum, CI must perform formatter check, Selene lint, pure tests through the configured runner, configuration/asset/license validation, secret scan, and a Rojo build from default.project.json.

## Deterministic unit suite

| ID | System | Cases | Pass condition |
| --- | --- | --- | --- |
| SIM-001 | ballistics | zero wind, positive/negative wind, gravity scales, min/max angle/power | positions/velocities match known values within documented tolerance |
| SIM-002 | collision | high-speed thin wall, start-near-surface, max lifetime | swept raycast catches first legal collision; projectile terminates |
| SIM-003 | bounce/fuse | zero/max bounce, restitution, fuse before/after bounce | count and timing resolve once and remain bounded |
| SIM-004 | spread | same/different server seeds | same seed reproduces; different seed stays inside spread limits |
| DMG-001 | damage | center/edge/outside, zero distance, self rule, optional line of sight | monotonic falloff, configured bounds, one damage per impact |
| DMG-002 | knockback | direction, zero vector, near/far, mass abstraction | finite direction and capped horizontal/vertical magnitude |
| TER-001 | crater | center, edge, thin floor, overlapping crater, indestructible cells | only legal cells change; result deterministic |
| TER-002 | drill/chunks | path clipping, dirty set, revision gap | bounded edits; only intersected chunks dirty; gap requests resync |
| TURN-001 | ordering | normal sequence, dead actor, last survivor, draw | only legal next state and actor |
| TURN-002 | timeout/race | timeout vs fire, disconnect in each state, duplicate transition | one accepted outcome; match cannot deadlock |
| SEC-001 | request validation | unknown IDs, wrong types, extra/oversized tables, NaN/infinity/extremes | rejected before state mutation/expensive work |
| ECO-001 | rewards | duplicate result, rejoin, shutdown/retry, bot multiplier, ineligible AFK | balance/inventory changes exactly once |
| PAY-001 | receipts | duplicate/delayed/unknown/cancel/data failure/already owned | no lost or duplicate grant; safe retry/pending behavior |
| DATA-001 | migrations | every supported version, corrupt/missing field, repeated migration | valid current schema or explicit safe failure; repeat is stable |
| DATA-002 | sessions | concurrent lease, stale lease, autosave/remove/shutdown race | one writer; no default overwrite; bounded recovery |

Use fixed seeds and fixtures. A tolerance must reflect floating-point behavior, not hide large trajectory drift.

## Service integration scenarios

1. Queue two players → countdown → alternate turns → eliminate → grant → rematch with a fresh match ID.
2. Queue one player → bot deadline → bot uses normal legal shot path → complete/rematch.
3. Fire and timeout occur near-simultaneously → exactly one shot/turn transition.
4. Impact damages two players and three chunks → one health update each and monotonic chunk revisions.
5. Remove support → character falls/lands or reaches hazard/kill plane within settle bound.
6. Disconnect during ActiveTurn, flight, environmental resolution, and Results → deterministic completion/no duplicate.
7. Data adapter fails before/after grant attempt → read-only/safe retry and no default overwrite.
8. Client sends a forged target/damage/origin/terrain/purchase field → ignored/rejected without mutation.
9. Twenty sequential rematches → every match-owned instance, connection, task, timer, and pool returns to baseline.

## Studio multiplayer matrix

| Configuration | MVP | Limited beta | Focus |
| --- | --- | --- | --- |
| 1 server + 1 client + bot | required | required | low population, tutorial, bot timing |
| 1 server + 2 clients | required | required | authority, replication, disconnect, rematch |
| 1 server + 4 clients | smoke if feature off | required for enabled 4P | turn wait, camera, scoring, replication load |
| mobile emulation phone/tablet | required | required | controls, safe area, text, touch overlap |
| keyboard/mouse | required | required | aim/power precision, shortcut focus |
| gamepad emulation/hardware | smoke | required if advertised | focus navigation, glyphs, aim/power |
| high latency/loss simulation | best effort | required where Studio supports | prediction, timeout, duplicate/reorder tolerance |

Current Development evidence (2026-07-14):

- The latest recorded Studio TestEZ run passed 56 tests with 0 failures and 0 skipped tests.
  Current source contains 57 specs; the added tuning spec awaits a user-run Studio rerun.
- A genuine one-server/two-client run completed elimination, authoritative Victory/Defeat
  Results, retained elimination across respawn, unanimous rematch consent, and a clean restart
  under a fresh match ID.
- A solo last-player disconnect returned the server to clean `WaitingForPlayers` state.
- The server-owned bot is implemented with bounded/imperfect aim and the normal authoritative
  turn/fire/projectile/damage/terrain/Result path. A live pre-final-tuning run verified bot
  firing, human elimination, and DEFEAT Results.
- The one-client/bot row is only partially accepted: the final-tuning rematch, clean reset,
  Output review, and runtime/visual-feel pass remain user-run validation.
- Trajectory preview is bounded to at most 48 raycasts per rebuild without the former
  97-point path allocation; effects catch up at most 16 fixed steps per frame and early-out
  while idle; HUD timed state updates at 10 Hz; terrain rebuilds one chunk per Heartbeat.
- BotAim solves were observed at 3.43-5.65 ms. A Studio server snapshot measured 16.65 ms
  p50, 17.72 ms p95, 18.04 ms p99, and 18.37 ms worst frame time. These observations do not
  replace representative-device performance testing.
- Rewards and profile persistence remain out of scope for this implemented slice; Results do
  not grant currency, XP, or items.

Pending M5.2 user acceptance:

1. Run Studio TestEZ from the current source and record all 57 specs passing before changing
   the recorded runtime total.
2. Start one server and one client, allow the BotCritter to take multiple turns, and confirm
   turn label, bot health, camera focus, projectile, impact, damage, and terrain presentation.
3. Finish a match, select Rematch, and confirm a fresh match ID, restored health, reset terrain,
   valid bot identity, fresh turn state, and no unexpected Output error.
4. Record whether aim preview, projectile follow, impacts, HUD updates, and chunk rebuilding
   feel smooth in Studio. Treat this as user visual acceptance, not an automated pass.
5. Capture one wide gameplay screenshot, one bot close-up, and one Results/HUD screenshot;
   note silhouette readability, palette contrast, visual clutter, camera scale, and whether the
   scene feels playful or generic. Use that feedback to drive the next code-art pass.

Repeat with player leaving:

- while queued;
- during countdown;
- before firing;
- while projectile is in flight;
- during terrain settling;
- at MatchEnd before save;
- after selecting Rematch.

## Gameplay acceptance tests

### First-time loop

- A new player can reach a first legal shot within three minutes without verbal instruction.
- They can state wind direction, identify the active player, and distinguish angle from power.
- They hit a training target, create a visible crater, fight a bot, receive rewards, equip a free cosmetic, and enter/rematch.

### Match feel

- 1v1 generally finishes in three to six minutes under representative play.
- Inactive time remains watchable through camera/impact feedback.
- The player can explain why representative misses occurred.
- Craters produce route/cover decisions rather than only decoration.
- Acorn Cannon, Fizzy Bomb, Mole Drill, and Bubble Bouncer each have a distinct role; disable any that is unreliable.
- Results makes Rematch the clear primary action and does not pressure a loss purchase.

### Accessibility

- Core state is not communicated by color alone.
- Timer, health, wind, weapon, aim, and Fire are legible at representative phone scale.
- No hover-only action; controls do not overlap system safe areas.
- Camera shake, music/SFX, and reduced effects apply immediately and persist.
- Effects do not cause full-screen flash or obscure projectile/character for an extended period.

## Security/adversarial tests

Using a dedicated development harness, attempt:

- off-turn, dead, nonmember, stale-turn, and duplicate fire;
- forged target Instance, origin, hit, damage, reward, result, terrain cells, and receipt success;
- unknown/unowned/disabled weapon and cosmetic IDs;
- strings at/over limits, deep/large tables, unexpected Instances, NaN/infinity/negative/extreme values;
- movement speed/distance/jump/depth/arena escape and physics fling;
- more bounces/projectiles/crater cells/lifetime than configured;
- stale/out-of-order terrain revisions;
- remote bursts at and beyond each token bucket;
- concurrent profile sessions and wrong environment product/data IDs.

Pass means no unauthorized mutation, bounded server work, expected counter/diagnostic, and no innocent-client desync. Do not use production profiles or real Robux for adversarial testing.

## Persistence and commerce matrix

| Case | Expected |
| --- | --- |
| normal leave/rejoin | current profile and equipment restored |
| transient load/save failure | bounded retry; clear safe state; no default overwrite |
| concurrent server join | one writable lease; other session waits/fails safely |
| server shutdown after result | reward once after recovery |
| migration from every supported schema | current valid schema with ownership preserved |
| duplicate reward key | no second currency/inventory change |
| successful approved staging purchase | exact item once, then equip |
| cancelled/failed prompt | no grant |
| receipt retry after persistence failure | no acknowledgement until durable safe result |
| delayed receipt after rejoin | exact durable grant once |
| unknown/wrong-environment product | no grant, diagnostic emitted |

Production data deletion, paid-product creation, real-Robux tests, and major migration require explicit owner approval.

## Performance and soak

Profile on a representative mid-range Android phone and low-to-mid laptop:

- frame time/FPS during aim, flight, impact, crater rebuild, and camera transitions;
- server simulation and dirty-chunk time;
- part/instance count, physics, draw calls, transparency, particles;
- network receive/send around projectile and terrain events;
- memory and active connections/tasks over repeated matches;
- load time from lobby to first interactive state.

Initial pass targets:

- 60 FPS goal and 30 FPS reduced-effects floor on target mobile;
- no per-frame projectile replication;
- no visible full-map rebuild pause;
- no unbounded catch-up, particles, debris, timers, or pooled instances;
- after 20 MVP or 50 beta repeated matches, match-owned instances return to a stable baseline and memory shows no sustained material rise.

Record device, OS, build, settings, map, participant count, weapon, and profiler capture. A desktop-only result cannot clear the mobile gate.

## Analytics validation

For one known scripted session:

- each once-only funnel event appears once and in legal order;
- match_started has exactly one match_completed or match_abandoned terminal event;
- shot/damage/elimination totals reconcile with server match summary;
- rematch denominator and selection are correct;
- bot/player, input mode, platform, map, weapon, build, environment, and schema fields are correct;
- commerce test events contain no secret or personal data;
- Development events cannot pollute Production dashboards.

Do not emit per-frame trajectories or raw hostile payloads.

## Originality, asset, and listing QA

- Every shipped mesh, image, texture, font, animation, audio, icon, and marketing image has creator/source/license/evidence and approved asset ID.
- Reference-only assets are absent from the build.
- No copied name, logo, character combination, map silhouette, weapon, UI layout/icon family, animation, audio, screenshot, or affiliation claim remains.
- Final public name/logo/roster/store materials receive legal originality review before commercial release.
- Content maturity questionnaire and listing accurately represent cartoon, non-graphic combat.

## Defect and evidence requirements

A defect records build/environment, device/input, place/match/map/weapon IDs, preconditions, minimal reproduction, expected/actual, frequency, severity, redacted logs/screenshots/video, suspected owner, and regression test.

Release evidence records:

- CI run and artifact hash/version;
- unit/integration summary;
- Studio/device matrix;
- Output/error and profiler summary;
- migration/restore and rollback rehearsal;
- analytics validation;
- security/IP/license checks;
- smoke tester/result;
- known issues and explicit approver.

No checklist item is marked complete from assumption.
