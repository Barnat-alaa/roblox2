# Security design

## Security objective

Protect competitive outcomes, player progression, purchases, production data, and publishing authority while keeping false positives recoverable. Security is based on server authority and bounded state, not secrecy or client trust.

This is an engineering plan, not a guarantee against every exploit. Reassess the threat model before each public release and after any incident.

## Trust boundary

| Trusted only after validation | Never trusted |
| --- | --- |
| server-owned match state, configuration bundled with approved build, DataStore results handled through safe adapters, approved platform receipt callbacks | client position, target, hit, damage, health, reward amount, winner, terrain edits, ownership claim, timer, shot origin, receipt success, UI state |

The client may control local input, camera, approximate trajectory, UI, presentation effects, audio, and animation. The server controls turns, time, movement limits, weapons, shots, collision, damage, knockback, terrain, eliminations, results, rewards, quests, purchases, and saving.

## Protected assets

1. Fair match outcome and availability.
2. Coins, XP, inventory, entitlements, reward and receipt ledgers.
3. Production profile versions, migrations, backups, and environment isolation.
4. Publishing credentials, repository/Creator permissions, and release artifacts.
5. Original source assets and license evidence.
6. Analytics integrity and player privacy.

## Threat model

| Threat | Example | Primary controls |
| --- | --- | --- |
| forged combat action | client asks to damage an enemy or fires off-turn | intent-only remotes, state/actor token, server origin/simulation |
| numeric/payload abuse | NaN power, huge string/table, malformed Instance | strict shape/type/finite/range/length checks; reject extra nesting |
| replay/race | duplicate fire, result, reward, equip, or receipt | request/turn/impact/grant IDs and idempotent state transitions |
| movement/physics exploit | teleport, excess speed/jump, depth escape, fling | server budgets/audit, plane/bounds clamps, bounded network ownership and knockback |
| terrain denial/desync | enormous crater, fake cells, revision spam | server weapon definitions, edit caps, authoritative revisions/chunk resync |
| bot/reward farming | AFK matches or scripted queues | participation eligibility, queue limits, anomaly telemetry, conservative bot multiplier |
| data loss/dupe | concurrent sessions, default overwrite, retry race | UpdateAsync lease, fail-closed write mode, versioned migration, stable grant keys |
| purchase fraud/dupe | trusting prompt callback or replaying receipt | server receipt/ownership path, durable grant ledger, environment product map |
| remote denial of service | event spam or expensive valid-looking requests | token buckets, cheap validation first, cost caps, cooldown/backpressure |
| admin/secret compromise | committed Open Cloud key or unrestricted debug command | least privilege, external secret store, environment allowlists, audit, key rotation |
| content/IP exposure | unlicensed asset ships | asset manifest, provenance evidence, CI/release review |
| analytics/privacy abuse | display names/chat/raw hostile payload in telemetry | allowlisted fields, redaction, aggregation, retention/policy review |

## Remote contract rules

Every client-to-server message:

- maps to one documented action;
- accepts a flat/small allowlisted payload;
- checks Roblox/Luau type and rejects unexpected Instances/tables;
- rejects NaN, infinity, extreme numbers, unknown IDs, long strings, invalid UTF/content, and extra keys where practical;
- checks player membership, character/alive status, expected match state, current turn token, and server clock;
- checks ownership/availability from server profile/configuration;
- derives origins, targets, costs, outcomes, and rewards from server state;
- uses a bounded request ID/sequence where replay matters;
- passes a per-player and per-action rate limiter before expensive work;
- returns a reason class suitable for diagnostics without revealing sensitive internal data.

Validation order is intentionally cheap: payload size/type → rate limit → session/membership → state/token → ownership/bounds → expensive simulation/storage.

### Initial rate limits

Tune from real traffic. These are maximum request budgets, not expected client rates.

| Action | Initial per-player budget | Additional invariant |
| --- | --- | --- |
| Queue/Cancel/Rematch | 4 per 10 seconds | one queue/match membership |
| MoveIntent | 20 per second with small burst | active actor, monotonic sequence, movement/jump budget |
| FireWeapon | 2 per second | one accepted shot per turn token |
| EquipCosmetic | 5 per 5 seconds | owned and compatible |
| TutorialAction | 4 per 5 seconds | expected step plus observable prerequisite |
| Settings save | 3 per 10 seconds | allowlisted normalized values |
| Purchase prompt request | 2 per 30 seconds | eligible product, store context, commerce enabled |

Server-to-client visual events are also bounded by weapon definitions and match state. No client can request arbitrary particle count, sound ID, asset ID, or camera target.

Rate-limit violations are dropped and counted. One noisy sample does not cause a permanent sanction. Escalation considers repeated, high-confidence violations across independent checks and favors session restriction/kick before any durable action. Durable bans require human-reviewable evidence and an appeal/support path.

## Combat protections

### Turns and firing

- Server creates a fresh turn token and deadline.
- The actor can have at most one accepted shot for that token.
- Weapon ID must exist, be enabled in the environment/mode, and be available to the actor.
- Angle and power are finite and clamped within weapon/mode bounds.
- Origin and initial state come from the server character and weapon definition.
- Projectile, bounce, fuse, impact, damage, terrain, and result IDs are server-generated.
- An impact maintains a per-character damage set and can resolve only once.
- Timeouts and disconnects have one deterministic transition.

### Movement and physics

- Server tracks turn-start position, voluntary distance, speed, jump count, ground/support, plane depth, and arena bounds.
- Client input is intent, not an authoritative final transform.
- Server corrects impossible displacement and records confidence-weighted anomalies.
- Server-produced knockback has an impact ID and bounded horizontal/vertical velocity.
- Character collision/network ownership is configured to limit physics abuse; any client-owned simulation is continuously constrained and audited.
- Kill plane/out-of-bounds recovery is deterministic and cannot teleport to an advantageous arbitrary position.

### Terrain

- Only server weapon definitions can edit cells.
- Maximum crater/path radius, cells changed, chunks dirtied, bounces, projectile count, and lifetime are hard-capped.
- Each chunk delta carries a monotonic revision. Gaps cause authoritative resync.
- Spawn pads and boundaries are indestructible in MVP.
- Join/rejoin uses a validated initial snapshot plus revisions, never client merge authority.

## Data safety

### Environment separation

- Development: DEV_CritterClash_Profile_v1.
- Staging: STAGING_CritterClash_Profile_v1.
- Production: PROD_CritterClash_Profile_v1.

Environment is compiled/configured from approved place identity and validated at startup. A production build fails closed when debug rewards, unrestricted commands, or nonproduction product/data IDs are present.

### Profile rules

- Acquire/renew/release an UpdateAsync session lease containing job identity and timestamp.
- Use bounded retries with backoff/jitter and DataStore budget awareness.
- Apply ordered schema migrations before write access.
- Never overwrite an unavailable/corrupt profile with defaults.
- If a safe session cannot be established, use read-only/no-reward behavior or refuse progression play with a clear retry path.
- Autosave, PlayerRemoving, and BindToClose share serialized write logic.
- Stable item IDs are never reused; unknown profile IDs are quarantined and logged.
- Production migration requires staging rehearsal, snapshot/version recovery path, explicit owner approval, and a forward-fix/rollback decision.

### Grant ledger

Match rewards, one-time tutorial grants, quest claims, level rewards, purchases, refunds/revocations where applicable, and manual support grants use distinct reason codes and stable idempotency identities. Currency/inventory mutation is centralized and records before/after, reason, correlation ID, build, and environment.

No generic remote or client-exposed module may call an arbitrary AddCoins/AddItem path.

## Purchase safety

- A client prompt-completion callback is not proof of purchase.
- Receipt/ownership is validated through the current approved Roblox server path.
- Product IDs are allowlisted by environment and expected grant type.
- The durable grant identity is checked before applying any mutation.
- Transient data failure causes a safe retry/pending outcome, not a grant without persistence.
- Unknown products do not receive a guessed fallback grant.
- Duplicate, delayed, cancelled, already-owned, rejoin, shutdown, and migration cases are automated/staging tests.
- A commerce feature flag can disable prompts and processing surfaces without breaking owned cosmetics.

Creating SKUs, changing prices, spending Robux, or enabling production commerce requires explicit owner approval.

## Administrative and operational security

- No password, 2FA code, personal access token, Open Cloud key, webhook secret, or unrestricted system token is requested in chat or committed.
- Use least-privilege scoped credentials, environment separation, approved CI secret storage, short validity/rotation where supported, and repository protections.
- Production publish is a manual approval after CI and staging QA.
- Debug commands are Development-only, explicit allowlist, server-side, audited, and absent/disabled in Production.
- Repository, Creator group/experience, asset, and analytics permissions follow least privilege; remove departed collaborators promptly.
- Third-party dependencies are pinned, licensed, source-reviewed, and recorded. Avoid broad frameworks for one helper.
- Secret scanning and dependency/license validation run in CI.

## Player-generated content and social safety

The MVP has no custom text, image upload, trading, or clans. Emotes are curated and rate-limited. If text/social systems arrive:

- use platform filtering/moderation APIs correctly;
- never expose unfiltered text;
- add report/block/mute paths appropriate to the feature;
- constrain names, icons, and clan permissions;
- threat-model impersonation, harassment, scams, and privacy before launch.

## Logging and analytics

Allowlist fields such as build, environment, anonymous platform/session correlation, match ID, state, action/reason code, weapon/map ID, and aggregate counts.

Do not log:

- passwords, tokens, receipt secrets, email, chat contents, unnecessary user-generated text;
- raw hostile payloads that may contain sensitive or huge content;
- exact personal identifiers in custom analytics when platform-level aggregation suffices.

Security diagnostics have retention/access controls and are not used to shame players. Use server timestamps and correlation IDs to reconstruct state transitions and grant attempts.

## Security verification

Automated tests cover:

- off-turn and dead-player actions;
- unknown/disabled/unowned weapon and cosmetic IDs;
- NaN/infinite/extreme angle, power, direction, and nested/oversized payloads;
- duplicate/reordered MoveIntent, FireWeapon, impact, reward, and receipt;
- teleport/speed/jump/depth and physics-fling attempts;
- crater/bounce/projectile/lifetime caps and terrain revision gaps;
- concurrent profile session, migration failure, retry, shutdown, and default-overwrite prevention;
- unknown product, cancelled/delayed/duplicate receipt, already-owned grant, and data failure;
- production configuration containing debug flags, test product, wrong prefix, or secret-like data.

Studio tests use one server with two and four clients, latency simulation when available, disconnects in every critical state, mobile/gamepad emulation, and repeated-match soak.

## Incident response

1. **Detect and classify:** exploit/fairness, commerce, data, privacy, availability, IP/content.
2. **Contain:** disable affected feature/SKU, restrict access, stop publishing, or roll back to known-good build. Do not delete evidence.
3. **Preserve evidence:** build/config/schema, redacted correlation IDs, timestamps, affected grants/profiles, deploy history.
4. **Protect players:** fail closed on rewards/commerce, communicate known impact, and avoid speculative accusations.
5. **Recover:** restore/forward-fix using rehearsed procedure; reconcile grants idempotently.
6. **Review:** root cause, detection gap, tests, owner, deadline, and documented prevention.
7. **Rotate/revoke:** any potentially exposed credential using the owning platform, without pasting it into chat.

Critical triggers include arbitrary server damage/result control, reproducible item/currency/receipt duplication, cross-environment production write, widespread profile corruption/loss, exposed publish credentials, or shipped unlicensed/protected content.

## Release security gate

- [ ] Threat model reviewed for changed systems.
- [ ] No critical/high finding remains without explicit documented risk acceptance.
- [ ] Remote schema/rate/idempotency tests pass.
- [ ] Data migration and restore rehearsal pass on Staging.
- [ ] Commerce matrix passes or commerce remains disabled.
- [ ] Production config contains no debug rewards, unrestricted admin, test IDs, or secrets.
- [ ] Asset/license and third-party notices are complete.
- [ ] Known-good artifact, rollback owner, feature kill switches, and monitoring are ready.
- [ ] Production publication has manual owner approval.
