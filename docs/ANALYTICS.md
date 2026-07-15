# Analytics plan

## Product question

The primary early question is: **after a complete, understandable match, does the player choose an immediate rematch?**

Supporting questions:

- Can a new player move, aim, fire, hit, destroy terrain, and finish the tutorial?
- Do mobile players time out or cancel aim more often?
- Do matches finish in the intended duration without abandonment?
- Are weapons understandable and horizontally useful?
- Are bot matches a healthy bridge to player matches?
- Do rewards and cosmetics motivate return without affecting fairness?
- Are data, receipt, server, or client errors harming completion?

## Principles

- Server emits authoritative match, damage, reward, inventory, and purchase-grant facts.
- The current slice has no client-authored analytics path. Future client-only presentation
  interactions require a strict allowlisted server adapter before activation.
- Use stable snake_case event names, integer schema version, and documented enumerations.
- Never send passwords, tokens, email, chat, display names, raw hostile payloads, or unnecessary personal data.
- Do not emit per-frame position, aim, trajectory, camera, or input events.
- Separate Development, Staging, and Production in event fields and dashboards.
- Verify current Roblox event quotas, field limits, retention, and policy before activation.

## Phase 4 implementation checkpoint

`TelemetryService` currently emits version-1, server-authored Development diagnostics only.
It sanitizes each payload against an exact event/field schema, rejects unknown or control-text
fields, caps text at 64 characters and payloads at eight fields, and exposes bounded event,
dropped-event, version, and last-event counters as Workspace attributes. Valid events print a
JSON envelope containing only version, environment, event name, server time, and sanitized
payload. No raw UserId, display name, client payload, per-frame position, aim sample, receipt,
or secret is included.

Implemented event allowlist:

| Event | Current fields |
| --- | --- |
| `session_started` | optional storage class |
| `queue_joined` | Practice/Casual mode |
| `queue_cancelled` | mode and bounded wait seconds |
| `queue_matched` | mode, Bot/Player opponent, bounded wait seconds |
| `match_started` | Practice/Casual/Rematch mode, versus-bot flag, participant count |
| `match_completed` | bounded reason, versus-bot flag, bounded duration |
| `rematch_selected` | versus-bot flag |
| `shot_fired` | bounded weapon ID and Bot/Player actor |
| `projectile_impacted` | weapon ID and bounded changed-cell count |
| `cosmetic_equipped` | bounded cosmetic ID |
| `settings_changed` | reduced-effects, camera-shake, and UI-scale snapshot |
| `telemetry_error` | bounded source and code |

The broader funnel, economy, reliability, dashboards, and Production sink below remain the
target design. They are not claimed as implemented until a reviewed backend, retention/access
policy, sampling plan, and scripted Studio reconciliation pass exist.

## Common event envelope

Every event should include only applicable allowlisted fields:

| Field | Meaning |
| --- | --- |
| schema_version | integer schema for this event |
| build_version | immutable build/release identifier |
| environment | development, staging, or production |
| session_id | ephemeral project-generated correlation ID |
| match_id | random server match correlation ID, when applicable |
| platform | normalized Roblox-reported platform class |
| input_mode | touch, keyboard_mouse, or gamepad |
| mode | tutorial, practice, casual_1v1, casual_4p, private, etc. |
| opponent_type | player, bot, mixed, none |
| map_id | stable original map identifier |
| weapon_id | stable balance definition identifier |
| economy_version | reward/pricing configuration version |
| duration_ms | nonnegative bounded integer |
| reason_code | allowlisted outcome/failure/abandon reason |

Do not add raw UserId to custom fields unless a documented platform need and privacy review require it; use platform-native user/cohort aggregation where available. IDs used for diagnostics are random/correlated, bounded, and access-controlled.

## Onboarding funnel

Once-only events are deduplicated per profile or tutorial attempt as noted.

| Event | Authority / when | Required fields |
| --- | --- | --- |
| session_started | server, player session accepted | session_id, platform, input_mode |
| tutorial_started | server, first tutorial match begins | tutorial_version |
| movement_tutorial_completed | server, required movement observed | elapsed_ms |
| aim_tutorial_completed | server, legal angle/power action completed | aim_method, elapsed_ms |
| first_shot_fired | server, first accepted tutorial/account shot | weapon_id, elapsed_ms |
| first_target_hit | server, first verified target damage | weapon_id, shot_number |
| terrain_destroyed | server, first legal cell removal | weapon_id, cells_changed |
| tutorial_match_completed | server, tutorial reaches Results | outcome, duration_ms |
| first_reward_collected | server, durable tutorial/match grant | reward_type, amount_band |
| first_cosmetic_equipped | server, owned item equip persists | cosmetic_category |
| casual_queue_joined | server, valid queue entry | wait_source |
| first_casual_match_completed | server, first non-tutorial result | opponent_type, outcome, duration_ms |

Suggested funnel:

session_started → tutorial_started → movement_tutorial_completed → aim_tutorial_completed → first_shot_fired → first_target_hit → terrain_destroyed → tutorial_match_completed → first_reward_collected → first_cosmetic_equipped → casual_queue_joined → first_casual_match_completed.

Record the first missing step and elapsed time. A retry does not restart lifetime once-only events, but attempt IDs may support tutorial diagnosis.

## Match events

| Event | Authority / cardinality | Key properties |
| --- | --- | --- |
| match_started | server, once | mode, opponent_type, map_id, participant_count, wind_band |
| match_completed | server, once terminal | outcome, duration_ms, turns, shots, rematch_eligible |
| match_abandoned | server, once terminal instead of completed | state, reason_code, duration_ms |
| turn_started | server, once per turn | turn_index, actor_type, time_limit_ms |
| turn_timed_out | server, at timeout | state, actor_type, had_valid_aim |
| weapon_selected | server or validated client, on changed selection | weapon_id, turn_index |
| shot_fired | server, one per accepted shot | weapon_id, angle_band, power_band, wind_band |
| shot_hit_player | server, per shot/player summary | weapon_id, hit_type, distance_band |
| shot_hit_terrain | server, per shot summary | weapon_id, cells_changed, crater_band |
| damage_dealt | server, aggregated per impact | weapon_id, amount, self_damage, target_count |
| player_eliminated | server, per elimination | weapon_id, cause, turn_index |
| rematch_selected | server, valid selection | seconds_after_results, same_opponent_available |
| queue_cancelled | server, valid cancellation | wait_ms, reason_code |

Every match_started must reconcile to exactly one match_completed or match_abandoned. Damage and elimination totals must reconcile with a server match summary. If volume limits require reduction, keep start/terminal/shot summary/rematch events and aggregate turn details server-side; never sample terminal failures silently.

## Economy and monetization events

| Event | Authority / when | Key properties |
| --- | --- | --- |
| reward_granted | server, durable exactly-once grant | reason_code, coins_band, xp_band, economy_version |
| reward_duplicate_rejected | server | grant_type, reason_code |
| item_equipped | server, validated/persisted | item_id, cosmetic_category, acquisition_type |
| shop_opened | client interaction validated/contextualized | entry_point, tutorial_complete |
| product_viewed | client | product_id, category, owned |
| preview_started | client | product_id, preview_type |
| purchase_prompted | server/client adapter | product_id, category, displayed_price_band |
| purchase_completed | server, durable grant only | product_id, category, purchase_type |
| purchase_failed | server/adapter | product_id, reason_code, retryable |
| receipt_duplicate_rejected | server | product_id, purchase_type |
| season_pass_opened | client | season_id, entry_point |
| season_pass_purchased | server, durable grant | season_id, purchase_type |

Do not treat a client prompt-close callback as purchase_completed. Prices and revenue reporting should use platform monetization analytics where available rather than custom sensitive payloads.

## Reliability and security diagnostics

Use a separate, access-controlled diagnostic stream or bounded custom events:

- server_error by allowlisted subsystem/reason;
- match_state_timeout by state/recovery;
- terrain_revision_gap and chunk resync;
- invalid_remote by action/reason bucket, rate-limited and never containing raw payload;
- profile_load/save/lease/migration outcome and latency band;
- reward/receipt pending, retry, duplicate, and permanent-safe failure;
- client_error by controller/reason/build, with redacted bounded context;
- performance_sample for approved sampled sessions: frame/server/impact/terrain/memory bands.

High-frequency invalid traffic is aggregated per player/session/window rather than emitted for every request.

## Metric definitions

| Metric | Definition |
| --- | --- |
| tutorial completion | unique tutorial_match_completed ÷ unique tutorial_started |
| first-shot success | players with first_target_hit ÷ players with first_shot_fired |
| first casual completion | first_casual_match_completed ÷ casual_queue_joined among eligible new players |
| match completion | match_completed ÷ (match_completed + match_abandoned) |
| abandonment | match_abandoned ÷ match_started, segmented by state/reason |
| average/median match duration | duration of completed matches; report median and percentiles, not average alone |
| shots per match | accepted shot_fired count ÷ completed matches |
| turn timeout | turn_timed_out ÷ turn_started |
| mobile aim failure | touch turns timed out in ActiveTurn with no accepted shot ÷ touch turns started |
| rematch rate | completed results with rematch_selected ÷ completed results where rematch_eligible is true |
| bot/player rematch | rematch rate segmented by opponent_type |
| item equip after grant | item_equipped within session/window ÷ durable item grant |
| purchase completion | durable purchase_completed ÷ purchase_prompted, with platform caveats |
| D1/D7 retention | use official Creator Analytics cohort definitions; do not reinvent from custom IDs |

Rematch eligibility excludes forced server shutdown, unavailable opponent, tutorial-only results without rematch, and versions where the button was unavailable. Record those exclusions explicitly.

## Dashboards and review cadence

### Daily during private test

- sessions, tutorial funnel, match starts/terminals, abandonment reasons;
- match duration, turns, shots, timeout, first-hit, rematch;
- server/client errors, state timeout, profile and terrain failures;
- device/input breakdown with sample counts.

### Weekly during alpha/beta

- D1/D7 retention and session duration;
- bot versus player completion/rematch/retention;
- weapon selection, hit, damage, win contribution, terrain utility, and timeout;
- economy source/sink, time to first spend, ownership/equip;
- store funnel and receipt health only when enabled;
- performance by device/input;
- cohort sizes and confidence caveats.

Never optimize purchase conversion in isolation from retention, fairness, support, and match quality.

## Balance analysis

For each weapon review:

- selection and availability;
- accepted shots, player-hit rate, terrain-hit rate, self-hit rate;
- damage and eliminations per use;
- win contribution conditioned on player skill/progression where possible;
- turn timeout/cancel behavior by input;
- crater cells/utility proxy;
- bot versus player use.

Small samples do not justify nerfs. Combine telemetry with observed play and weapon role. Cosmetic ownership must not correlate with configured combat stats; audit if payer/nonpayer outcomes diverge.

## Experiments

Experiments are post-MVP and require:

- one written hypothesis and primary metric;
- fairness/comfort guardrails;
- mutually exclusive stable assignment where platform support permits;
- minimum duration/sample plan and stop condition;
- no price pressure during tutorial or after losses;
- environment/build/variant in events;
- a documented decision and cleanup date.

Good early candidates are 15 versus 18 second turns, separate versus drag mobile aim, and Results layout. Do not simultaneously change rewards, timer, and weapon balance when measuring rematch.

## Data quality checks

Before each release:

- event name/schema registry has no duplicate or undeclared field;
- one scripted session produces the expected ordered funnel;
- match starts equal completed + abandoned after allowed late-event window;
- accepted shots reconcile with projectile/impact summaries;
- rewards/purchases reconcile with durable ledger counts;
- Development/Staging do not appear in Production views;
- enum/ID values match versioned configuration;
- duration and amount fields are finite, bounded, and correctly unit-labeled;
- no personal data, secret, raw chat, or hostile payload is present;
- dashboards show sample size and updated-at timestamp.

Schema changes increment event schema_version and keep dashboards compatible or deliberately migrate them. Never silently change a field’s units or meaning.

## Decision thresholds

Do not hard-code launch success from guesses. Before limited beta, establish baselines from internal/closed testing and set release-specific guardrails for:

- tutorial and first-match completion;
- critical error/data/receipt rate;
- mobile aim failure;
- match abandonment and duration;
- rematch rate;
- real-device performance.

A critical data/commerce/security defect overrides favorable engagement metrics and triggers containment or rollback.
