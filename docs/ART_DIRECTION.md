# Art direction

## Creative target

Build a cheerful, chaotic, handcrafted 2.5D cartoon world with early-browser-game energy and modern Roblox readability. The tone is mischievous rather than aggressive: compact critters overreact to ridiculous gadgets, craters alter the stage, and impacts feel punchy without gore.

The desired reaction is “this recalls the artillery games I loved,” never “this copies a specific game.”

## Originality boundary

Do not use, trace, extract, imitate one-for-one, or publish:

- the Wild Ones name, logo, character names, exact animal/color combinations, distinctive blue rabbit, weapon names/models, maps/silhouettes, UI panels/icons/layouts, animations, audio, music, dialogue, textures, promotional artwork, code, or progression tables;
- screenshots or ripped assets as production textures, marketing art, or mesh-generation inputs;
- “remake,” “official continuation,” or other affiliation language.

Reference gathering is for broad analysis only: composition, camera distance, contrast, information hierarchy, rhythm, and genre conventions. Create concepts from written briefs, not by painting over screenshots. Keep reference files segregated and marked reference-only.

The final public name, logo, character roster, store page, screenshots, and side-by-side similarity review require qualified legal review before commercial release.

## Visual pillars

1. **Chunky silhouettes:** every critter, weapon, and terrain edge reads at phone size.
2. **Controlled color:** bright focal characters/projectiles over quieter backgrounds.
3. **Physical comedy:** anticipation, recoil, elastic reactions, and expressive faces.
4. **Tactical clarity:** solid/empty terrain, danger, wind, health, and current turn are unmistakable.
5. **Layered depth:** 3D assets and parallax support a mechanically flat combat plane.
6. **Purposeful imperfection:** hand-painted gradients, asymmetry, and oversized props create warmth without visual noise.

## Palette

| Token | Hex | Primary use |
| --- | --- | --- |
| Deep Teal | #0F6B6D | major UI panels, calm world accents |
| Warm Coral | #F26B5E | active state, warnings, comic accents |
| Cream | #FFF1D5 | readable surfaces, labels, highlights |
| Golden Yellow | #F6C447 | timer emphasis, rewards, friendly energy |
| Dark Navy | #14283D | outlines, text, shadows |
| Mint | #76D9B1 | confirmation, trajectory support, secondary highlights |
| Hazard Orange | #F28C28 | lava/danger, never the sole danger cue |
| Impact White | #FFFDF6 | very brief impact core only |

Each map adds a limited local palette while preserving projectile/character contrast. Validate contrast and grayscale silhouettes; color alone cannot identify player, danger, or selected state.

## Shape language

- Critters: round/soft body masses with one species-specific angular or elongated feature.
- Friendly UI: clipped rounded rectangles, uneven sticker-like borders, and clear internal spacing.
- Weapons: oversized toy/tool proportions with one unmistakable functional shape.
- Hazards: sharper triangles, downward rhythm, dark base, and animated warning detail.
- Terrain: broad readable masses and stable ledges, not noisy micro-geometry.
- Effects: circles, arcs, leaves, foam, dirt spirals, and squash/stretch forms rather than realistic fireballs.

Avoid a blue beveled panel system or any recognizable interface arrangement from a reference title.

## Critter design

### Shared construction

- Large expressive head and brows, compact torso, readable hands/feet.
- Strong side silhouette at overview camera distance.
- Aim line and weapon remain visible without clipping through the face/body.
- Neutral proportions support one common gameplay rig where practical.
- Mechanical stats are identical; silhouette and cosmetic slots do not alter hitbox or aim origin.

### Differentiation

Use a three-part silhouette test: head/ears, body posture, and tail/limb rhythm. A black silhouette should identify the species without color or costume.

Candidate species include capybara, raccoon, otter, gecko, boar, axolotl, pigeon, fennec fox, hedgehog, and red panda. Before approving one, compare the full combination of species, hue, markings, proportions, accessory, pose, and personality against major references. Change multiple dimensions when similarity is plausible.

### Required animation set

- idle and blink;
- move, jump/fall, land;
- aim up/down and weapon hold;
- fire anticipation, release, recoil, and impact-watching;
- light/heavy hit reactions;
- victory, defeat, and results idle.

Use nonverbal vocalizations only. No copied catchphrases or recognizable voice samples.

## Weapon visual briefs

| Weapon | Silhouette | Motion/effect vocabulary |
| --- | --- | --- |
| Acorn Cannon | chunky wood-and-brass seed compressor | glowing acorn, leaf ribbon, woody pop and leaf burst |
| Fizzy Bomb | wobbling capsule with cap/pressure gauge | foam trail, squashy bounce, carbonation rings |
| Mole Drill | compact mechanical mole profile and spiral nose | dirt corkscrew, short spark, tunneled dust puffs |
| Bubble Bouncer | elastic orb in a ring-shaped launcher | stretch on bounce, iridescent rings, soft pop |

Weapons must remain identifiable in grayscale and in the bottom/side inventory icon. Cosmetic skins may change model, texture, trail, impact color, and fair/readable sound, but not hitbox, timing readability, or combat statistics.

## Environments

MVP uses one original arena built from a reusable kit. Production themes may include:

- **Ember Crater:** volcanic slabs, lava hazard, dark red sky, bright orange rim.
- **Picnic Peaks:** grass cliffs and giant original picnic props under warm daylight.
- **Crystal Night:** purple moonlit cavern with cyan crystals and low-reflection materials.
- **Frozen Pantry:** ice shelves and whimsical food shapes in pale blue/pink.
- **Rooftop Rumble:** stylized rooftops, signs, water towers, dusk skyline, fall hazard.
- **Moon Cheese:** lunar shapes and distant planets with humorous geological motifs.

These are broad themes only; every layout, terrain silhouette, prop, and texture must be newly designed.

### 2.5D layer stack

1. Foreground decorative silhouettes that never cover aiming/impacts.
2. Combat terrain and characters.
3. Midground props with restrained motion.
4. Distant background with low contrast.
5. Sky/atmosphere.

Parallax is subtle and disabled/reduced with comfort settings. Background edges cannot resemble projectile trajectories.

## Interface direction

Design a new responsive layout around:

- large active-turn timer;
- signed wind arrow/meter with numeric or stepped strength;
- participant portraits and health;
- angle and power feedback;
- compact weapon tray suited to thumb reach;
- explicit Fire and Cancel/Reset Aim actions;
- clear Results → Rematch hierarchy.

Use the palette tokens above, a licensed readable sans-serif available in the production pipeline, bold numerals, and original icons. Do not reproduce a reference screenshot’s panel positions, proportions, borders, or icon shapes.

Mock phone, tablet, desktop, and gamepad-focus states in Figma before production. Keep safe areas, localization expansion, touch targets, and text contrast in component specifications.

## Effects and animation feel

Every important action follows anticipation → action → recovery:

- fire: face change, body load, charge/prep, launch, recoil, projectile watch;
- hit: fast flash, squash/stretch, bounded knockback, expression, dust/stars, health motion;
- explosion: 1–2 frame core flash, expanding graphic shape, readable smoke, bounded debris, layered original sound, mild shake;
- final elimination: stronger framing is allowed, but slow motion is rare and brief.

Do not fill the whole screen with transparent particles. Effects must leave the projectile, terrain edge, character, timer, and health readable. Reduced-effects mode removes secondary debris, extra smoke, parallax motion, and shake.

## Sound direction

Create or license original:

- turn start and five-second warning;
- aim/power ticks and weapon selection;
- launch, flight, bounce, fuse, impact, terrain break;
- light/heavy damage, elimination, victory, defeat;
- coin, XP, equip, purchase;
- separate lobby and battle ambience/music.

Music uses playful percussion, light action energy, a memorable but unobtrusive motif, and clean loops. Never use music, effects, melodies, or samples from the reference game.

## Production pipeline

1. Write a brief containing purpose, silhouette, palette, camera distance, animation needs, budgets, and originality exclusions.
2. Create at least three independent thumbnails from the written brief.
3. Review silhouette, tactical readability, and similarity before detail work.
4. Model/rig in Blender or prototype simple props in Blockbench.
5. Paint original textures/effects in Krita and interface components in Figma.
6. Name source files and export IDs consistently; retain editable sources.
7. Import to a Development place, configure pivots/collision/materials, and profile.
8. Test phone-scale readability, animation, reduced effects, and color/contrast.
9. Register source, creator, license/ownership, evidence, modifications, asset ID, and approved build in ASSET_LICENSES.md.
10. Promote to Staging only after art, technical, originality, and license approval.

Roblox Assistant/procedural generation may support greybox geometry, temporary props, or repetitive prototype work. AI-generated images/meshes may be editable starting points only after commercial terms, privacy, retention, source inputs, and export rights are verified. Retopologize, retexture, redesign, and review every generated result. Never publish an unreviewed generated asset.

## Starting technical budgets

Profile and revise these per target device:

| Asset | Starting target |
| --- | --- |
| Gameplay critter | about 10k–15k triangles, one common rig where possible |
| Held weapon | about 1k–3k triangles |
| Major prop | about 1k–5k triangles with simple collision |
| Character texture | one 1024 set maximum; prefer 512 where readable |
| Weapon/prop texture | 256–512, atlased where useful |
| Explosion | no more than about 8 coordinated emitters; hard lifetime |
| Active physical debris | about 24 bounded pieces across the current impact |
| Transparent layers | minimize overlap; avoid full-screen quads |
| Collision | primitives or authored low-cost meshes, never visual mesh by default |

Budgets are not permission to spend the maximum. Validate actual render, memory, physics, and network cost on a real mid-range Android device.

## Approval checklist

- [ ] Silhouette reads at phone overview scale and in grayscale.
- [ ] Combat state remains clear over every map layer.
- [ ] Asset is independently created or has documented commercial rights.
- [ ] Reference-only material is not included in the export.
- [ ] No protected name, logo, character combination, map, icon, UI layout, animation, audio, or marketing composition is reproduced.
- [ ] Editable source, exporter settings, Roblox asset ID, creator, and license evidence are recorded.
- [ ] Mesh, texture, collision, particles, and animation meet budget/profile targets.
- [ ] Cosmetic variant does not change hitbox, aim origin, timing readability, or stats.
- [ ] Reduced-effects and camera-shake settings behave correctly.
- [ ] Final public-facing material receives originality/legal review before commerce.
