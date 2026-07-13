# Release checklist

## How to use

Copy this checklist into the release record. Do not mark an item complete from assumption. Record evidence, approver, time, and build/place/version where applicable.

Release types:

- **Private MVP:** authorized testers only; commerce off unless separately approved.
- **Staging candidate:** production-like private build for migrations, devices, receipts, and QA.
- **Limited beta:** controlled public/invite cohort with monitoring and rollback.
- **Production:** broader stable release; always manual approval.

## Release identity

| Field | Value |
| --- | --- |
| Release type | |
| Version/tag/commit | |
| CI run and artifact hash | |
| Environment/place/universe | |
| Profile schema/economy/event schema | |
| Asset registry revision | |
| Feature flags/content IDs | |
| Previous known-good version | |
| Release owner | |
| QA approver | |
| Account/publish approver | |
| Planned publish window/time zone | |
| Monitoring window and owner | |
| Rollback decision owner | |

## 1. Scope and approvals

- [ ] Release scope is frozen and matches ROADMAP.md.
- [ ] Acceptance criteria and test evidence exist for every enabled feature.
- [ ] Disabled/unfinished features are hidden or clearly flagged, not exposed as dead promises.
- [ ] Known issues list has severity, workaround, owner, and release decision.
- [ ] No Blocker/Critical issue remains; High issues are fixed or the feature is disabled.
- [ ] Production publication has explicit account-owner approval.
- [ ] Any paid product, Robux spend, ownership change, private-server price, or major data migration has separate explicit approval.
- [ ] Release does not require a password, 2FA code, private key, or unrestricted token to be pasted into chat/repository.

## 2. Source, CI, and artifact

- [ ] Correct branch and reviewed commit are used; working tree/release inputs are understood.
- [ ] Pinned tool installation succeeds from a clean checkout.
- [ ] Locked Wally restore succeeds.
- [ ] StyLua check passes for source, tests, and scripts.
- [ ] Selene passes for source, tests, and scripts.
- [ ] Strict Luau/type diagnostics have no release-blocking error.
- [ ] Unit/service tests pass and produce retained results.
- [ ] Configuration, duplicate stable ID, unknown reference, environment, and asset-manifest validation pass.
- [ ] Secret scan and third-party license/notice validation pass.
- [ ] Production Rojo build succeeds from default.project.json.
- [ ] Test Rojo build succeeds from test.project.json.
- [ ] Artifact is immutable/identified, retained, and matches the commit.
- [ ] No Development package, debug command, test reward, test SKU, verbose sensitive log, or reference-only asset is mapped into Production.
- [ ] GitHub Actions and external downloads are pinned/reviewed to the release’s supply-chain policy.

Baseline CI equivalents:

- rokit install
- wally install --locked
- stylua --check src tests scripts
- selene src tests scripts
- rojo build default.project.json --output build/CritterClash.rbxlx
- rojo build test.project.json --output build/CritterClashTests.rbxlx

Use the CI workflow as the authority if commands change.

## 3. Gameplay regression

- [ ] Development Output has no critical server/client error on boot or shutdown.
- [ ] Player-versus-bot lobby → match → Results → Rematch completes.
- [ ] One-server/two-client 1v1 completes and rematches.
- [ ] Any enabled four-player mode passes one-server/four-client coverage.
- [ ] Turn ownership, timeout, disconnect in every critical state, and simultaneous fire/timeout race pass.
- [ ] Movement distance/speed/jump/plane/bounds validation passes.
- [ ] Every enabled weapon passes fire, wind, collision, bounce/fuse/lifetime, damage, knockback, and termination tests.
- [ ] Damage applies once and match win/draw is deterministic.
- [ ] Terrain edge, spawn, thin ledge, overlapping crater, hazard, support/fall, revision gap, and join snapshot tests pass.
- [ ] No full-map rebuild or visible unbounded impact stall occurs.
- [ ] Bot uses legal systems, fires before timeout, and has bounded imperfection.
- [ ] Results correctly explains reward and prioritizes Rematch without a loss prompt.
- [ ] Twenty MVP / fifty beta repeated matches do not leak match state, instances, tasks, connections, timers, or rewards.

## 4. Input, UI, accessibility, and devices

- [ ] Keyboard/mouse completes tutorial/practice and full match.
- [ ] Phone and tablet emulation complete the same flow with no safe-area overlap or hover dependency.
- [ ] Real Android phone passes before limited beta.
- [ ] Low-to-mid-range laptop passes before limited beta.
- [ ] Gamepad passes if advertised; otherwise unsupported/known status is clear.
- [ ] Input switching updates focus/glyphs and does not fire accidentally.
- [ ] Timer, wind, health, weapon, angle, power, current actor, and Fire are readable at target sizes.
- [ ] Color is not the only state cue.
- [ ] Music/SFX, camera shake, and reduced-effects settings apply and persist.
- [ ] Camera modes cancel correctly; no late projectile event steals the camera.
- [ ] Effects/audio remain readable, bounded, non-graphic, and comfort-safe.

## 5. Performance

- [ ] Representative device, OS, settings, map, player count, and capture are recorded.
- [ ] Mobile reaches the documented FPS/frame-time goal or acceptable reduced-effects floor.
- [ ] Projectile simulation, terrain chunk rebuild, character physics, parts, draw calls, transparency, particles, network, and memory are profiled.
- [ ] No per-frame projectile network replication exists.
- [ ] Effects, debris, projectiles, connections, and pools have hard lifetimes/bounds.
- [ ] Repeated-match memory/instance trend returns to a stable baseline.
- [ ] Lobby-to-interactive and match-start load time are acceptable for the test cohort.

## 6. Security

- [ ] SECURITY.md threat model is reviewed for every changed system.
- [ ] Client cannot submit trusted target, origin, hit, damage, health, terrain cells, reward, winner, ownership, or receipt success.
- [ ] Remote payload shape, finite/range/length, membership, state/token, ownership, idempotency, and rate tests pass.
- [ ] Forged/replayed/reordered and burst requests cause no unauthorized mutation or unbounded work.
- [ ] Movement, physics ownership, knockback, and out-of-bounds exploit tests pass.
- [ ] Debug/admin paths are absent/disabled in Production and least-privilege access is reviewed.
- [ ] Environment product IDs/data prefixes are validated.
- [ ] Security/diagnostic logs contain no secrets, personal data, chat, or raw hostile payload.
- [ ] Feature kill switches and incident owner are known.

## 7. Persistent data and economy

- [ ] Exact Development/Staging/Production data prefix and place identity are verified.
- [ ] Profile schema and every supported migration have automated tests.
- [ ] Session lease, stale/concurrent session, retry/backoff, budget, autosave, PlayerRemoving, and shutdown behavior pass.
- [ ] Load/save failure cannot overwrite a real profile with defaults.
- [ ] Match/tutorial/quest/level grants are server-derived and idempotent.
- [ ] Leave/rejoin preserves balances, ownership, equipment, settings, and supported progression.
- [ ] Economy source/sink/reward version and price hypotheses match documentation/config.
- [ ] Free players retain access to all essential competitive options.
- [ ] Production backup/snapshot/version recovery path is verified and owner recorded.
- [ ] Migration is rehearsed on production-like Staging data.
- [ ] Restore/forward-fix/rollback decision is rehearsed; production migration has explicit approval.

## 8. Commerce, if enabled

- [ ] If any item fails below, commerce feature flag remains OFF.
- [ ] Owner approves every SKU, type, price, environment, and real-Robux test.
- [ ] Product IDs are allowlisted by environment and grant type.
- [ ] Preview exactly matches the approved original/licensed item.
- [ ] No-pay-to-win, hitbox, trajectory/readability, and purchase-pressure review passes.
- [ ] Tutorial/first match completes before optional store promotion.
- [ ] Successful, cancelled, delayed, duplicate, unknown, already-owned, data-failure, shutdown, retry, and rejoin cases pass on Staging.
- [ ] Server receipt/entitlement path is grant authority; client prompt callback grants nothing.
- [ ] Ownership/grant restore and reconciliation procedure is documented.
- [ ] Current Roblox policy, content/audience rules, regional pricing/display, and support/refund/revocation handling are verified.
- [ ] Commerce analytics and kill switch pass.

## 9. Analytics and diagnostics

- [ ] Build, environment, event schema, economy version, mode, input/platform, map, weapon, and reason enumerations are correct.
- [ ] Scripted onboarding funnel appears once and in legal order.
- [ ] Every match_started reconciles to one match_completed or match_abandoned.
- [ ] Shots, damage, eliminations, terrain, rewards, and purchase grants reconcile with server summaries/ledgers.
- [ ] Rematch eligibility denominator and selection are correct.
- [ ] Development/Staging events do not pollute Production dashboards.
- [ ] No per-frame telemetry, personal data, secrets, raw chat, or hostile payload is emitted.
- [ ] Error, state timeout, profile, receipt, terrain revision, and performance dashboards/queries are available to the monitoring owner.
- [ ] Platform analytics quotas/field/policy limits are verified for current release.

## 10. Originality, licenses, and content

- [ ] Temporary codename is not used publicly without name/trademark clearance.
- [ ] Final public name/logo/character roster/listing/screenshots receive legal originality review before commercial launch.
- [ ] No Wild Ones name, logo, character design, distinctive animal/color combination, weapon, map, UI layout/icon, animation, audio, music, texture, dialogue, screenshot, code, or affiliation claim is used.
- [ ] Every shipped/marketing mesh, image, texture, animation, audio, font, icon, sample, and generated asset maps to APPROVED status in ASSET_LICENSES.md.
- [ ] Reference-only, PENDING, BLOCKED, and prototype assets are absent unless private-scope approval explicitly permits the prototype.
- [ ] Third-party versions, licenses, copyright/NOTICE/attribution, and modifications are complete in THIRD_PARTY_NOTICES.md.
- [ ] Editable sources, export hashes, Roblox asset IDs/owners, moderation state, and evidence references are retained.
- [ ] AI-assisted asset terms, inputs, human redesign, and originality review are recorded where applicable.
- [ ] Cartoon violence is non-graphic and content maturity answers/listing are accurate.

## 11. Creator Dashboard and access

Use the official Creator Dashboard: https://create.roblox.com/dashboard/creations

- [ ] Correct owner/group, experience, place, environment, and universe are selected.
- [ ] Collaborator/tester permissions follow least privilege.
- [ ] Development remains private; Staging is authorized-testers only.
- [ ] Release access/cohort matches the approved release type.
- [ ] Experience name, description, icon, thumbnails, genre, device support, content maturity, localization, and social links are accurate/original.
- [ ] API/DataStore/Studio access settings are only as broad as required.
- [ ] Private-server and monetization settings are off unless explicitly approved/tested.
- [ ] Production publishing credential has least privilege and is stored outside the repository.
- [ ] Previous known-good place version/artifact and exact rollback route are confirmed before publish.

Publishing guidance: https://create.roblox.com/docs/production/publishing/publish-games-and-places

## 12. Publish and live smoke

- [ ] Release owner announces start of approved maintenance/monitoring window.
- [ ] Final artifact/version is published to the intended place—never Production by inference.
- [ ] Published place/version/time/approver are recorded.
- [ ] Authorized clean-account tester joins through the Roblox client, not only Studio.
- [ ] Tester completes practice/tutorial and a bot/casual match, receives/persists reward, equips cosmetic, and rematches.
- [ ] A second tester completes 1v1 when available.
- [ ] Commerce smoke uses only the separately approved safe plan.
- [ ] Production analytics/error events arrive in the correct environment.
- [ ] Server/client Output/logs and dashboards show no new critical issue.
- [ ] Tester access and public availability match the intended cohort.

## 13. Monitoring and decision

During the planned monitoring window review:

- [ ] join/session and tutorial funnel;
- [ ] match start/completion/abandonment, duration, timeout, and rematch;
- [ ] mobile/input failures;
- [ ] server/client errors and state timeouts;
- [ ] profile load/save/lease/migration and reward duplicates;
- [ ] terrain revision/resync and performance;
- [ ] purchase/receipt health if enabled;
- [ ] moderation, support, IP/license, and fairness reports.

Record sample size and avoid declaring retention/balance success from a tiny private cohort.

## Rollback triggers

Rollback or immediately disable the affected feature for:

- arbitrary client-controlled damage/result/reward;
- reproducible currency/item/receipt duplication or lost paid entitlement;
- widespread profile corruption/loss or wrong-environment writes;
- common match deadlock/crash or severe mobile unplayability;
- exposed production credential;
- shipped protected/unlicensed content;
- material policy/content maturity/access misconfiguration.

The decision owner may also roll back for multiple High issues whose combined impact is unsafe.

## Rollback procedure

1. Stop rollout/restrict access and disable commerce/experimental features where safe.
2. Record detection time, current build/place/schema/config, affected cohort, and decision owner.
3. Preserve redacted logs, grant IDs, data versions, and artifact evidence; do not delete production data or receipts.
4. Republish/select the verified previous known-good place version using the approved manual publishing path.
5. Do not reverse a schema change blindly. Keep compatible code, restore only through the rehearsed data procedure, or forward-fix after owner approval.
6. Run live smoke on join, match, save/rejoin, analytics, and owned cosmetics; test commerce only if it remains enabled.
7. Reconcile legitimate rewards/purchases idempotently.
8. Communicate status to testers/players as appropriate.
9. Open an incident record with root cause, affected data/content, remediation, regression test, owner, and re-release gate.

Production data deletion, bulk currency correction, key rotation, ownership change, paid action, or major migration needs explicit owner approval.

## Release result

| Field | Value |
| --- | --- |
| Published version/time | |
| Live smoke result/evidence | |
| Monitoring result | |
| Known issues accepted | |
| Commerce state | |
| Data/schema state | |
| Rollback performed/target | |
| Follow-up owners/deadlines | |
| Final decision: hold / roll back / continue | |
