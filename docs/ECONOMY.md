# Economy design

## Goals

- Reward completing short, fair matches and choosing Rematch.
- Let free players obtain every essential combat option at a reasonable pace.
- Make cosmetics and expression the long-term collection layer.
- Keep the MVP understandable: coins and account XP only.
- Prevent duplicated grants, AFK farming, cross-environment contamination, and hidden price conversion.
- Tune from observed cohorts, not from an assumed viral population.

All values below are explicit test hypotheses. Change them through versioned configuration and record the effective version in analytics.

## Fairness invariants

- Normal weapons, ammunition, health, damage, accuracy, wind response, movement, and competitive loadouts are never sold for Robux.
- Critters are mechanically identical in the MVP.
- Weapon mastery and character affinity grant cosmetics/status only.
- Losing still earns meaningful completion rewards; winning is a bonus, not a progression gate.
- A paid cosmetic cannot alter hitbox, aim origin, collision clarity, fuse readability, or combat statistics.
- Ranked play, if added, uses freely obtainable and standardized/balanced options.

## MVP units

| Unit | Earned from | Used for | Tradable? |
| --- | --- | --- | --- |
| Coins | completed matches, wins, tutorial, later quests/levels | free cosmetics and profile presentation | No |
| Account XP | completed matches, wins, tutorial, later quests | account level and free unlock path | No |

Premium cosmetic currency and Season XP are not visible in the seven-day MVP. Add each only when its catalog/season has real utility and an understandable UI.

## Provisional match rewards

| Verified outcome | Coins | Account XP |
| --- | ---: | ---: |
| Eligible match completion | 40 | 100 |
| Win bonus | 20 | 50 |
| Draw bonus | 10 | 25 |
| First tutorial completion, once | 200 | 150 |
| First cosmetic-equipping tutorial step | 0 | 25 |
| Player-versus-bot multiplier after tutorial | 0.85 | 0.85 |
| Abandonment/AFK | 0 | 0 |

Rounding is deterministic on the server. A short legitimate win still qualifies. An ordinary loss should not feel wasted.

### Eligibility

A match reward is eligible when the server records a valid MatchEnd and the participant met one of:

- completed at least two legal turns;
- was eliminated after participating in a legal turn;
- won a legitimate short match.

Tutorial rewards are keyed separately and granted once. Network loss is handled through the documented abandonment/reconnect policy; the client never chooses eligibility or amount.

### Idempotency

Every grant uses a stable key containing environment, reward version, match or tutorial identity, player identity, and grant type. The profile stores/records the key before exposing the new balance through the same safe update path. Repeated Results events, reconnects, retries, and server shutdown cannot grant twice.

## Account levels

Initial threshold hypothesis for the XP needed from level L to L+1:

**150 + 50 × (L − 1)**, with a configured cap and later curve review.

Early levels should arrive quickly enough to teach progression. Suggested cosmetic/free milestones:

| Level | Reward hypothesis |
| ---: | --- |
| 2 | original profile frame |
| 3 | free horizontal weapon unlock or weapon trial after balance approval |
| 4 | coin cosmetic |
| 5 | second loadout presentation slot |
| 7 | original trail |
| 10 | mastery/profile badge |

Do not advertise locked modes or weapons until they exist and are balanced. Level grants are server-derived and exactly-once.

## Coin sinks and pacing

MVP ships one free starter cosmetic and at least one coin-priced item. Limited-beta price hypotheses:

| Cosmetic category | Coin range | Target effort at 40–60 coins/match |
| --- | ---: | --- |
| profile frame/background | 250–500 | roughly 5–10 matches |
| simple trail | 600–900 | roughly 10–20 matches |
| weapon color/material skin | 700–1,200 | roughly 12–25 matches |
| character recolor/outfit | 1,000–1,800 | roughly 18–35 matches |
| elaborate earnable cosmetic | 2,000–3,000 | longer aspiration |

Do not charge coins to fire a weapon, enter normal matchmaking, repair gear, reroll wind, restore health, or avoid a competitive disadvantage.

### Pacing targets

- Tutorial gives a free equip action and meaningful progress toward the cheapest second item.
- First optional coin purchase is reachable in approximately 15–30 minutes for a new engaged player.
- Win bonus remains at or below half the completion reward.
- A returning free player can make visible progress in one short session.
- New content prices are compared to median earn rates, not only top players.

## Later units

### Premium cosmetic currency

If introduced, it is used only for cosmetics/bundles and is never required for normal weapons or competitive access. Real-money bundle value and effective item price must be clear; avoid awkward leftovers and intentionally obscured conversion. Small grants may come from free season tiers or rare events, but never imply a purchase is necessary to compete.

### Season XP

Season XP advances free and optional premium cosmetic tracks. Earn it from matches, daily/weekly quests, and seasonal challenges. It has no exchange value, no trading, and no effect on account combat power. Publish start/end dates plainly and provide a fair late-season policy before selling a pass.

## Quests and mastery

Post-MVP daily/weekly quests should reward varied normal play:

- complete matches;
- deal damage;
- use weapon categories;
- destroy terrain cells;
- land a bounce shot;
- play with a friend;
- complete a weekly challenge map.

Avoid quests that require owning a paid item, griefing, intentional losing, excessive daily time, or a very rare random outcome.

Weapon mastery is earned from valid use and can unlock a skin, projectile color, icon frame, elimination effect, title, or badge. It never increases damage, radius, ammunition, speed, wind resistance, or accuracy.

## Source and sink controls

| Risk | Control |
| --- | --- |
| AFK/bot farming | eligibility checks, bounded bot reward multiplier, timeout/behavior telemetry |
| Duplicate rewards | stable grant keys, transaction/update retry tests, Results dedupe |
| Inflation | versioned source/sink dashboard, price-to-earn review, no emergency balance deletion |
| New-player poverty | free starter cosmetic, tutorial grant, low first price |
| Excessive grind | time-to-item cohorts and loss-player progress review |
| Whale advantage | cosmetic-only products and no player trading |
| Cross-environment pollution | DEV/STAGING/PROD key prefixes and environment in idempotency keys |
| Negative balances | integer validation, nonnegative clamps only after investigating root cause |

No player-to-player trading or gifting is planned initially; these add fraud, scams, moderation, and duplication risk.

## Data model requirements

Persist:

- schema and economy configuration version;
- integer coins, account XP, and level;
- owned/equipped cosmetic stable IDs;
- completed one-time grant IDs;
- bounded/idempotent match reward and purchase ledger data;
- weapon mastery/quest/season state only when those systems ship;
- aggregate match statistics needed for progression.

Stable item IDs are never reused. A removed item remains recognized for ownership/migration. Unknown IDs are logged and quarantined rather than silently converted. Currency mutation is exposed only through a server EconomyService with reason code, source ID, before/after value, and correlation ID.

## Economy telemetry

Track by build, environment, platform, mode, opponent type, and economy version:

- coins/XP earned per completed match and per session;
- source and sink totals by reason;
- median time and matches to first coin spend;
- balance percentiles and inactive hoarding;
- item ownership/equip rates;
- match completion, abandonment, and rematch by reward cohort;
- quest/mastery completion when introduced;
- rejected/duplicate grant attempts;
- payer versus nonpayer combat outcomes only as a fairness audit, never as targeting for power sales.

Small cohorts are directional. Do not rebalance from a single tester, and do not use average balance alone.

## Change process

1. State the problem and affected cohort.
2. Capture current earn/spend, completion, rematch, and time-to-item baselines.
3. Change one versioned table behind a staged rollout when possible.
4. Run grant, cap, migration, reconnect, negative/overflow, and idempotency tests.
5. Monitor at least one relevant play cycle.
6. Roll forward or revert configuration without deleting earned legitimate items.

Production currency grants, wipes, conversions, and major schema changes require explicit owner approval and a backup/restore plan.
