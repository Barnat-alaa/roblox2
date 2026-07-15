# Next Actions

## Current checkpoint

Phase 1 combat correctness, Phase 2 profiles/rewards, Phase 3 lobby/loadout, and Phase 4
comfort/recovery/diagnostics are implemented in the `0.7.0-dev` source. The immediate next
step is one combined Roblox Studio acceptance pass. Send screenshots, the final Output
summary, and a short description of how the game feels; that evidence will drive the next
visual and fluidity tuning pass.

The unpublished place uses process-local session memory. It can validate the complete UI and
mutation path inside one server process, but it cannot prove cloud persistence across joins.

## Resume commands

```powershell
Set-Location "C:\Users\barna\Desktop\roblox wild ones"
rokit install
wally install
rojo build default.project.json --output build/CritterClash.rbxlx
rojo build test.project.json --output build/CritterClashTests.rbxlx
```

## User-run Phase 1-4 acceptance

### 1. Automated Studio suite

1. Open `build/CritterClashTests.rbxlx` in Roblox Studio.
2. Press **Play** once.
3. Open **View > Output**.
4. Send the final TestEZ summary and every red error.

Current source contains **137 specs**. The last recorded Studio result is still **56 passed,
0 failed, 0 skipped** from an older build; do not replace that recorded runtime result until
Studio actually executes the current suite.

### 2. Lobby and queue journey

Use `build/CritterClash.rbxlx` and verify the field-camp screen appears before combat:

- **Practice** should start one human against BotCritter immediately when the arena is free.
- **Casual** should show queue position and an approximately eight-second countdown before a
  bot fill when no second player arrives.
- **Cancel** should return cleanly to Lobby, including when pressed repeatedly or near the bot
  deadline.
- In a one-server/two-client test, two Casual players should enter the same human 1v1 in FIFO
  order; a third client must remain in the lobby as a spectator/queued player.
- On both left and right spawn sides, the default aim and every aim adjustment must point
  inward toward the arena; repeat after Rematch in case the local side changes.
- `P`, `C`, `L`, and `S` should open Practice, Casual, Loadout, and Settings on keyboard.
- Lobby buttons should remain navigable with gamepad selection and fit phone/tablet
  emulation without clipped text or safe-area overlap.

Send one wide lobby screenshot and report whether entry feels **instant / acceptable / slow**.

### 3. Loadout, cosmetic, and settings

- Open Loadout and confirm **Sunset Scout Scarf** is shown as owned and equipped with its
  original code-built preview.
- Start a match and confirm the scarf appears on the critter without changing collision,
  movement, health, aim origin, or knockback.
- Respawn/rematch once and confirm the equipped appearance reapplies without duplicates.
- Change UI scale, camera shake, and reduced effects. Each should change the local
  presentation immediately, then reconcile to the server-owned value without flicker.
- Change one setting, then change it again while the first save is still pending. The newest
  edit must remain visible and become the saved value after the older acknowledgement.
- Leave and reopen both panels in the same server session; the selected values should remain.
- Loadout and Settings must close/refuse to open while `LobbyState` is `InMatch`.
- Music/SFX profile fields are reserved for future original audio; the current build is
  intentionally silent and exposes no fake audio implementation.

Send one loadout screenshot, one in-match scarf screenshot, and note any panel that feels
crowded, small, or visually flat.

### 4. Fluidity and input

During the human Aiming phase:

- Hold and reverse `A`/`D`. Movement should begin quickly, remain smooth, stop cleanly at the
  shared 22-stud path allowance, and never jitter or keep walking after release.
- Tap `Space`; grounded jumps should work, while airborne spam and attempts beyond the
  per-turn limit should not.
- On touch emulation, movement/jump controls must stay on the left and aim/fire controls on
  the right with no overlap. Combat controls should disappear outside the active turn.
- On gamepad, left stick moves, `A` jumps, right stick changes angle/power, bumpers cycle
  weapons, and right trigger fires. No mouse should be required for a full turn.
- Reduced Effects should visibly reduce trajectory/effect density. Camera Shake at zero
  should remove impact shake. UI scale should remain readable at 0.8, 1.0, and 1.2.

Send one phone-emulation screenshot and rate movement, aim, camera, and impact presentation
individually as **rough / okay / fluid**.

### 5. Combat, terrain, and late-projectile recovery

- Remove terrain below the human and later below BotCritter. Each actor should fall, land on
  legal support, or reach bounded recovery/elimination within about three seconds; the match
  must never wait forever.
- Fire all four weapons at least once. Damage, craters/drill edits, camera follow, and turn
  advance must happen once with no red Output error or long frame hitch.
- Join/start a second client while a projectile is already in flight if Studio timing allows.
  The late client should recover the one active launch presentation from its original server
  timestamp; it must not spawn duplicate impacts or alter the outcome.
- Finish the match and choose **Rematch**. Health, terrain, BotCritter, wind, timer, turn state,
  projectile state, and match ID should all be fresh.
- In Results, choose **Return to Camp** on one client. That player must return to Lobby and be
  excluded from the old rematch roster; remaining players must not import a lobby spectator.

Send a wide gameplay screenshot, a Results screenshot, and the Output panel if anything is
wrong. Include the weapon and turn that produced the symptom.

### 6. Profile, reward, and schema-v2 session path

In the unpublished local place:

1. Confirm the profile panel leaves Loading and reports `SESSION`/`SessionMemory` for a local
   user, with a valid level, starter scarf, and normalized settings.
2. Finish an eligible bot match. Reward feedback should progress from Pending to Granted once.
   A normal bot win grants 51 coins/127 XP, loss 34/85, and draw 42/106.
3. Confirm a duplicate result cannot grant a second balance/stat/ledger update.
4. Rematch and finish again; the fresh match ID should receive one independent grant.
5. Change a setting and equip the owned cosmetic while the profile is Ready. The attributes
   and visible presentation should update only after a valid server mutation result.
6. Stop/restart Studio. A reset SessionMemory balance/settings is expected and is not cloud
   data loss.

Send one screenshot containing the profile panel and Results reward line. The client must
never be able to author coins, XP, ownership, reward amount, damage, or match outcome.

### 7. Published Development persistence gate (owner-run later)

Use a private owner-approved Development experience, never Production data:

- use an authenticated positive-UserId client and require `CLOUD`/`Persistent`; synthetic or
  unpublished users that select SessionMemory do not count as DataStore evidence;
- validate schema-v0 and schema-v1 migration into schema v2 without losing coins, XP,
  statistics, the retained reward ledger, starter ownership/equipment, or normalized settings;
- leave and rejoin after rewards, cosmetic equip, and settings changes and confirm all survive;
- retry the same grant identity and confirm no duplicate mutation;
- test competing sessions, transient failure/read-only recovery, autosave, PlayerRemoving,
  and BindToClose without a default overwrite or duplicated reward.

Cloud persistence remains implemented but not runtime-accepted until this matrix passes.

## Evidence to send

The fastest useful handoff is:

1. final TestEZ and Output summary;
2. lobby, loadout, in-match, phone-emulation, and Results screenshots;
3. one sentence each for movement, aiming, camera, impacts, UI readability, and queue speed;
4. exact red error text, if any.

## What follows acceptance

I will use that evidence to tune pacing, movement response, camera framing, effect budgets,
panel hierarchy, typography, palette, and character/environment presentation. After the
current loop feels good, the next milestone is the private release-candidate pass: original
audio/assets with recorded provenance, onboarding clarity, representative-device profiling,
security/exploit testing, and rollback evidence.

Purchase receipt plumbing, paid SKUs, analytics activation, public publication, Robux spend,
and Production credentials remain separate owner-approved work.
