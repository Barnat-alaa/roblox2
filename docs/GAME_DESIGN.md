# Game design

## Product statement

Project Critter Clash is a temporary codename for an original, short-session, turn-based animal artillery game on Roblox.

**Player promise:** choose an expressive critter, master ridiculous weapons, reshape the battlefield, and make every shot a story.

The game should evoke the social energy of classic browser artillery games through broad genre conventions—side-view aiming, visible wind, destructible cover, short turns, and comic reactions—without copying any protected name, character, weapon, map, interface, art, animation, sound, text, or progression table.

## Design pillars

1. **Readable tactics:** players understand whose turn it is, what wind will do, why a shot hit or missed, and what changed.
2. **Destruction with consequences:** a crater is damage, a route, lost cover, and potential danger.
3. **Fast social stories:** 1v1 targets three to six minutes and ends with an immediate rematch choice.
4. **Simple input, expressive mastery:** angle and power are approachable on touch; wind, bounce, terrain, and weapon choice create depth.
5. **Identity without power sales:** critters are mechanically equal and purchases are cosmetic.
6. **Original presentation:** silhouettes, palette, UI composition, weapon props, maps, audio, and branding are independently created.

## MVP boundaries

### Included

- Private tester lobby and practice/casual entry.
- 1v1 elimination with player-versus-bot fallback.
- One original placeholder critter base and at least one cosmetic.
- Left/right movement, one bounded jump, angle, power, weapon selection, and fire.
- Four target weapons, with two polished weapons as the reliability fallback.
- Round-based wind, server-authoritative shots, damage, health, knockback, elimination, and terrain craters.
- PC and mobile-emulation controls; gamepad smoke support when hardware is available.
- Results, rematch, coins, account XP, and persistent equipment.

### Excluded from the seven-day critical path

- Four-player release support, teams, ranked play, clans, cross-server skill matchmaking, parties, seasons, quests, character abilities, subscriptions, and a broad paid catalog.
- Live paid products unless the owner explicitly approves their creation and staging tests pass.
- Runtime CSG terrain, complex contour meshing, simultaneous planning, and perfect reconnect.

## Core loop

1. Enter Practice or Casual.
2. Match with another player; after a short wait, fill with a bot.
3. Read the map, health, turn timer, and round wind.
4. Move within the active-turn allowance.
5. Select a weapon and set angle and power.
6. Fire; follow the projectile and react to impact.
7. Re-evaluate new terrain, health, and position.
8. Eliminate the opponent or be eliminated.
9. Collect coins and XP, equip a cosmetic or review progress, then rematch.

The immediate-rematch rate is the most important early product signal.

## Match rules

| Rule | MVP baseline |
| --- | --- |
| Mode | 1v1 elimination |
| Health | 100 per participant |
| Turn duration | 20-second prototype, tuned within 15–20 with a likely 18-second target |
| Movement | Up to 22 horizontal studs in the current prototype; tune downward if turns become evasive, with a bounded jump rule |
| Wind | Signed horizontal acceleration, rerolled at round/match start; one rule is used consistently |
| Fire limit | One accepted shot per turn |
| Timeout | End the turn safely; bot may take a conservative basic shot, player turn may skip |
| Self-damage | Enabled at normal falloff to reward safe positioning |
| Friendly fire | Not applicable in MVP |
| Arena loss | Hazard/kill-plane causes decisive damage; no indefinite falling |
| Win | Last living participant |
| Draw | Simultaneous elimination or hard match timeout uses health, then damage dealt; exact ties are draws |
| Match target | 3–6 minutes |

Numbers are test baselines, not promises. Balance changes must update weapon configuration, tests, and analytics labels together.

## Turn flow

The server advances only through legal transitions:

WaitingForPlayers → Countdown → RoundStart → TurnStart → ActiveTurn → ProjectileFired → ProjectileResolving → EnvironmentalResolution → TurnEnd → RoundEnd or next TurnStart → MatchEnd → Results.

During ActiveTurn the current player may move, jump, select, aim, and fire. After an accepted shot, further movement or fire is rejected. Projectile resolution has a maximum lifetime, terrain/environment resolution has a maximum settle window, and every timeout has a deterministic recovery transition.

### Turn UX

- Outline/focus the active critter and show a clear portrait/state label.
- Keep timer, wind direction/strength, weapon, angle, power, and both health values readable at phone scale.
- Follow the projectile, frame impact briefly, then reveal the changed battlefield.
- Use a distinct warning at five seconds and a short turn-change stinger.
- Keep camera shake mild and user-adjustable; reduced-effects mode removes nonessential flashes/debris.

## Movement and aiming

- Combat occurs on a fixed 2.5D plane: horizontal movement and vertical terrain, with depth used only for presentation.
- Server clamps plane depth, speed, movement budget, jump count, arena bounds, and valid match/turn state.
- Keyboard baseline: A/D movement, Space jump, arrows or pointer for aim, hold/release or discrete control for power, number/weapon tray selection, and explicit fire.
- Mobile baseline: large left/right and jump controls, separate angle and power controls, weapon button, Fire confirmation, and Cancel/Reset Aim. No hover dependency.
- Gamepad baseline: left stick movement, right stick aim, shoulder weapon selection, trigger power, confirm/cancel.
- A trajectory preview is approximate guidance, not a hit guarantee. It uses the same shared ballistic rules but the server outcome remains authoritative.

## Wind

- Wind is a horizontal acceleration displayed as direction and normalized strength.
- MVP wind changes once per round/match, not every turn, so both players can learn it.
- Initial tuning range is modest enough that a basic shot remains controllable. Heavy or special wind responses are configured per weapon.
- The HUD must say when a selected projectile is weakly or strongly affected.
- Random wind uses a server seed recorded with the match for diagnostics; clients never choose it.

## Terrain

The arena is a logical 2D grid containing solid, empty, hazardous, indestructible, and decorative cells.

- Explosions remove only destructible cells inside their crater/path.
- Changed regions are replicated; the full map is not rebuilt after every shot.
- Safe spawn pads and outer boundaries are indestructible.
- Characters above removed support fall and can land, take hazard damage, or cross a kill plane.
- Craters should open routes and remove cover without routinely deleting half the map.
- Map layouts must be independently designed and must pass edge, thin-ledge, overlapping-crater, spawn, and hazard tests.

## Initial weapons

All values are provisional balance baselines. Cosmetic variants never change them.

| Weapon | Role | Distinct behavior | Initial balance intent |
| --- | --- | --- | --- |
| Acorn Cannon | Reliable direct shot | Moderate arc, wind response, crater, and damage | 38 center / 12 edge damage, 12-stud blast |
| Fizzy Bomb | Behind-cover grenade | Short fuse, up to two bounces, foamy impact | 32 center / 10 edge damage, 11-stud blast |
| Mole Drill | Terrain utility | Travels through a bounded terrain path, makes a tunnel | 20 center damage, high terrain removal, low knockback |
| Bubble Bouncer | Trick shot | Up to three elastic bounces before impact | 30 center / 10 edge damage, 10-stud blast |

Every weapon must have a readable silhouette, understandable trajectory, unique utility, clear counterplay, bounded lifetime, mobile-friendly use, and instrumentation. If all four are not reliable by release, ship Acorn Cannon and Mole Drill and keep the others disabled.

Expansion weapons are added in small batches after the four foundations feel good. Original candidates include Magnet Mine, Chili Comet, Prism Splitter, Cloud Hook, Honey Pot Trap, Boomerang Biscuit, Storm Kite, Snowball Cluster, Paint Splash Cannon, Moon Pebble, Firefly Swarm, and Rubber Duck Torpedo.

## Damage, knockback, and elimination

- Damage falls from a configured maximum near impact to a configured minimum at the blast edge.
- The server evaluates distance, optional line of sight, weapon rules, self-damage, and a once-per-impact damage ledger.
- Knockback points away from impact and is capped by horizontal/vertical speed and arena recovery rules.
- Health, eliminations, and match results never accept client-supplied values.
- No gore is used. Hit reactions use squash/stretch, expression, dust, stars, health motion, and restrained vibration.

## Critters and cosmetics

- MVP critters are mechanically identical. Species, outfit, weapon skins, trails, emotes, and victory poses communicate identity only.
- Character language: large expressive head, compact body, strong hands/feet, distinct outline, exaggerated eyebrows, visible anticipation, comic recoil, strong nonverbal reactions.
- Candidate species include capybara, raccoon, otter, gecko, boar, axolotl, pigeon, fennec fox, hedgehog, and red panda, subject to originality review.
- Do not pair species, colors, proportions, accessories, or poses in a combination strongly associated with a reference title.
- The current starter identity item is the original Sunset Scout Scarf: free, owned/equipped
  by default, code-built, and presentation-only. It establishes the loadout path without
  implying that the final launch catalog or production character art is complete.

## Bot behavior

The MVP bot:

1. Selects a living target from server state.
2. Uses the same legal loadout and fire request path as a player.
3. Samples/estimates an angle and power using wind and simple terrain information.
4. Adds visible, difficulty-bounded error.
5. Fires before timeout and never reads a future collision result.

Easy, Normal, and Hard differ through error and search effort, not hidden damage, health, or perfect aim. Normal is the only required MVP difficulty.

## Onboarding: first ten minutes

| Time | Player action |
| --- | --- |
| 0–1 min | Select a free original critter and enter a training arena |
| 1–3 min | Move, jump, set angle, and set power |
| 3–5 min | Fire Acorn Cannon, hit a target, and create a crater |
| 5–7 min | Learn wind and finish a simple bot match |
| 7–9 min | Receive coins/XP and equip a free cosmetic |
| 9–10 min | Enter casual or bot-filled play with a clear next objective |

Teach through required actions and immediate feedback, not long dialogue. A player must always be able to retry a training shot.

## Lobby and player journey

MVP lobby actions are Practice, Casual Queue, Loadout, Settings, and later Store. Friends, parties, quests, progression, private matches, and seasons appear only when implemented; do not show dead buttons as promises.

The current field-camp lobby implements Practice, Casual, Loadout, and Settings. Practice is
immediate bot play when the arena is free. Casual is same-server FIFO: two humans pair first;
a lone search bot-fills after about eight seconds. This is a clear low-population MVP path,
not cross-server ranked matchmaking. Return to Camp is explicit, while rematch retains only
the exact connected roster that just finished.

The results screen prioritizes:

1. Clear winner and the decisive moment.
2. Earned coins and XP with exactly-once grant state.
3. One understandable next unlock.
4. Rematch as the primary action.
5. Lobby as a secondary action.

Never show a purchase prompt during aiming, immediately after a loss, before tutorial completion, or through repeated pop-ups.

## Accessibility and comfort

- Respect safe areas, scalable text, touch target size, and contrast; do not encode state with color alone.
- Provide camera-shake strength, music/SFX volume, reduced effects, UI scale, and input labels
  that change with current device. The current slice applies shake/reduced-effects/UI-scale;
  volume fields are reserved until original audio exists.
- Avoid full-screen flashes, excessive particles, prolonged forced camera motion, and high-frequency audio.
- Keep projectiles and critters visually distinct from every background.
- Validate on real Android hardware and a low-to-mid-range laptop before limited beta.

## Progression and fairness

- Account levels unlock free weapons, modes, cosmetics, and profile features.
- Weapon mastery grants skins, colors, frames, effects, titles, or badges, never combat statistics.
- Character affinity, quests, seasons, and rating are post-MVP systems.
- All essential competitive tools are freely obtainable. Ranked, if later justified by population and stability, uses balanced/standardized loadouts.
- Details and provisional reward values live in ECONOMY.md; purchase guardrails live in MONETIZATION.md.

## Originality gate

Before any commercial or public release:

- Replace the temporary codename with a searched, legally reviewed name.
- Review final logo, critter roster, silhouettes, UI, maps, weapons, screenshots, audio, and store copy against major references.
- Maintain source/provenance for every shipped asset.
- Do not trace screenshots, extract assets, reproduce recognizable layouts, or describe the experience as an official remake/continuation.
- Seek qualified intellectual-property counsel for the final name, logo, character set, marketing, and side-by-side similarity review.

## Playtest questions

- Can a first-time player fire within three minutes without verbal help?
- Can they explain wind and why the shot missed?
- Does the first crater create an obvious tactical choice?
- Does inactive time feel short and watchable?
- Are all four weapons understandable and horizontally useful?
- Can a mobile player make a precise correction without covering the target?
- Does the player choose Rematch?
- Does any visual, name, or layout feel like copied rather than genre-inspired work?
