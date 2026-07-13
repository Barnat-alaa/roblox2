# Ethical monetization

## Position

Players may spend because they love their critter identity, collection, celebrations, and social presentation—not to repair a competitive disadvantage. Monetization is optional for the private MVP and must remain disabled until purchase safety, asset rights, pricing, and owner approvals pass.

## Non-negotiable rules

- Never sell damage, health, accuracy, wind resistance, movement, stronger exclusive weapons, paid ammunition, favorable matchmaking, or hidden statistical advantages.
- Never interrupt the tutorial/first match, aiming, or a vulnerable post-loss moment with a prompt.
- Never use fake countdowns, misleading discounts, preselected purchases, accidental-click placement, obscured real prices, or repeated nagging.
- Never sell random paid rewards or loot boxes in the initial release.
- Show exactly what the player receives and provide an accurate character/weapon/trail/pose preview.
- A cosmetic may not change combat readability, hitbox, aim origin, projectile timing, or collision.
- Regional/platform pricing and current Roblox policy must be verified in Creator Dashboard before launch.

## MVP plan

### Development

- Implement a purchase adapter, product definitions, receipt idempotency, ownership, equip, preview, and analytics.
- Use a mock development receipt to test success, cancellation, failure, duplicate delivery, retry, shutdown, and rejoin.
- Do not call a live purchase prompt by default.

### Staging/private release

- One durable cosmetic test entitlement may be configured only after explicit owner approval.
- Use a nonessential, original cosmetic with no stat effect.
- Limit access to authorized testers and document whether real Robux can be charged before asking anyone to test.
- If a zero-cost/safe test path is not available, keep commerce disabled and test the adapter only.

### Production

No product is enabled until the activation gate in this document and RELEASE_CHECKLIST.md passes.

## Product catalog

All Robux figures are research hypotheses from the handoff, not final prices. Verify current platform limits, regional display, and value through staged testing.

| Category | Value | Hypothesis | Fairness constraint |
| --- | --- | ---: | --- |
| character skin | visible outfit/recolor/full theme | 79–149 basic; 199–399 elaborate | shared gameplay rig/stats/hitbox |
| weapon skin | model/texture/trail/readable sound | 59–199 | same speed, radius, fuse, bounce, hitbox |
| projectile trail | stars, leaves, bubbles, pixels, ribbon | 39–149 | cannot conceal trajectory or impact |
| victory pose | short results celebration | 79–249 | no gameplay interruption |
| emote/reaction | lobby, spectating, results | 39–149 | rate-limited; no blocking visibility/audio abuse |
| profile item | frame, banner, title, background | test from comparable cosmetics | no impersonation or unrestricted uploads |
| starter pack | one skin, weapon skin, trail, small cosmetic value | test after onboarding | shown only after player understands the game |
| private server | friends, custom casual rules, training | verify current configuration | no ranked advantage/reward exploit |
| season pass | cosmetic track and quests | validate after retention | no premium-only competitive power |

Limited-beta catalog aspiration: 6–10 character skins, 8–12 weapon skins, 6 trails, 6 emotes, 4 victory poses, profile items, one starter-pack hypothesis, and one season-pass hypothesis. This is not a release requirement; fewer original, polished items are better.

## Product mechanism

- **Durable entitlements:** use the current platform mechanism appropriate for one-time ownership, with server ownership verification and local profile cache. Do not assume prompt completion is durable proof.
- **Repeatable products/premium currency:** if later introduced, process only through the authoritative platform receipt callback and an idempotent grant ledger.
- **Subscriptions:** evaluate only after stable retention and a policy/fairness review. Benefits may include a cosmetic allowance, rotating cosmetic, extra saved presentation loadouts, profile frame, or fair private-server options—never combat statistics.
- **Rewarded video:** consider only if currently available, age/policy appropriate, and opt-in. Acceptable tests include a cosmetic-shop reroll, small post-match coin bonus, account XP bonus, or daily quest refresh. Never place an ad during active/ranked combat or make watching necessary to compete.

Current Roblox documentation and Creator Dashboard behavior are the authority at implementation time; this design does not override platform policy.

## Shop experience

The player can:

- rotate the critter and inspect silhouette;
- preview firing animation and weapon projectile;
- preview trail, impact color, emote, and victory pose;
- compare owned/unowned status and exact bundle contents;
- see the actual current price before prompting;
- equip immediately after a confirmed durable grant.

Safe store moments are Lobby, Loadout, Results after neutral reward presentation, and Season screens. Results never targets a loss-specific offer.

Rotations must use genuine availability windows. Avoid artificial scarcity and give adequate notice before any item becomes unavailable. Owned items remain usable after catalog removal.

## Receipt and entitlement safety

The server:

1. Receives platform purchase identity through the approved receipt/ownership path.
2. Validates environment, configured product, expected grant type, and sane player/profile state.
3. Checks the stable purchase/grant ID against durable history.
4. Applies the cosmetic/currency grant idempotently through DataService/EconomyService.
5. Persists before acknowledging completion where the platform contract requires it.
6. Treats retries as normal and returns no second grant.
7. Emits redacted success/failure/retry analytics with correlation ID.

Client purchase-prompt callbacks update presentation only. They never add currency, inventory, XP, or ownership.

Required tests: duplicate receipt, delayed receipt, profile unavailable, server shutdown mid-grant, retry after persistence failure, rejoin, unknown product, wrong environment, already-owned durable item, cancelled prompt, and equip-before-grant.

## Activation gate

- [ ] Owner explicitly approves SKU creation, price, environment, and any Robux charge.
- [ ] Product IDs are environment-specific configuration, not hard-coded secrets.
- [ ] Original asset and license records are approved.
- [ ] Preview exactly matches the granted item.
- [ ] No-pay-to-win and combat-readability review passes.
- [ ] Receipt/entitlement matrix passes in Staging, including duplicate and failure cases.
- [ ] Economy migration and restore plan includes ownership/grants.
- [ ] Tutorial completes before the first optional store prompt.
- [ ] Regional pricing/display and current Roblox policies are verified.
- [ ] Purchase, failure, refund/revocation handling where applicable, and support paths are documented.
- [ ] Monetization analytics is validated without personal data.
- [ ] Commerce kill switch and rollback owner are tested.
- [ ] Production publish receives manual owner approval.

If any item fails, commerce remains disabled while the game stays playable.

## Metrics and guardrails

Track shop opened, item viewed, preview started, prompt started, completed, failed/cancelled where observable, item equipped, season pass opened/purchased, and receipt retry/duplicate state.

Review:

- conversion and revenue only alongside retention, completion, rematch, support complaints, and fairness;
- purchase completion/failure by platform and region when privacy-safe;
- preview-to-purchase and purchase-to-equip;
- payer/nonpayer combat results as a fairness diagnostic;
- refund/revocation/support rate when available;
- prompt frequency per eligible session.

Guardrails:

- no deterioration in tutorial or first-match completion caused by store exposure;
- no statistically credible combat advantage associated with paid cosmetics;
- no repeated prompt loops;
- no unresolved duplicate/lost grant;
- pause the affected SKU or all commerce on critical receipt/data errors.

Revenue is not evidence that pressure is acceptable. Retention must be demonstrated before subscriptions or a large catalog.

## Approval boundaries

The project owner must personally approve:

- creating or changing a paid product/pass/subscription;
- setting or changing production price;
- any test that can spend Robux;
- production commerce activation;
- broad currency conversion or ownership migration;
- refunds/revocations outside documented platform handling;
- third-party paid commerce/analytics services.

No password, two-factor code, unrestricted token, or API key is ever requested or committed.
