# Next Actions

## Current checkpoint

Phase 1 combat correctness and Phase 2 profiles/rewards are implemented in source. The
immediate next step is one combined Roblox Studio acceptance pass; screenshots, the Output
summary, and a short feel description are enough for the next iteration. The unpublished
place uses session memory, so this pass does not prove cross-session cloud persistence.

## Resume commands

```powershell
Set-Location "C:\Users\barna\Desktop\roblox wild ones"
rokit install
wally install
rojo build default.project.json --output build/CritterClash.rbxlx
rojo build test.project.json --output build/CritterClashTests.rbxlx
```

## User-run Phase 1/2 acceptance

### 1. Automated Studio suite

1. Open `build/CritterClashTests.rbxlx` in Roblox Studio.
2. Press **Play** once.
3. Open **View > Output**.
4. Send the final TestEZ summary and any red error. Current source contains **111 specs**; do
   not update the recorded runtime total unless Studio actually reports the result.

### 2. Movement feel

Open `build/CritterClash.rbxlx`, start a solo match, and test during the human Aiming phase:

- Tap and hold `A`/`D`; movement should start quickly and remain smooth.
- Reverse direction several times; the shared 22-stud allowance must decrease by total path
  distance, not only final displacement.
- Hold a direction until the allowance reaches zero; the character must stop without jitter,
  repeated snapping, or continued walking.
- Tap `Space`; a grounded jump should work. Spam it in the air and attempt more than two jumps
  in one turn; no extra jump should occur.
- Jump just before the 20-second timer ends; the same match and terrain should remain while
  the character lands or receives bounded recovery, then the next turn should begin.

Send one short feel rating: **too slow / good / too fast**, plus whether stopping, jumping,
camera tracking, or input response felt rough.

### 3. Terrain support and bot physics

- Remove terrain directly below the human and later below BotCritter.
- Each actor should fall naturally, land on the first legal support, or be eliminated by the
  hazard/death boundary within about three seconds; the match must never wait forever.
- Confirm the bot body does not fall through intact terrain and still receives explosion
  knockback.
- Finish the match and choose Rematch. Confirm fresh health, terrain, bot, timer, wind, and
  match ID with no red Output error.

Send a wide gameplay screenshot after terrain loss, one bot screenshot, and the Output panel
if anything looks wrong. Describe the symptom and which weapon/turn caused it.

### 4. Session-memory profile and reward flow

Use the unpublished local place for this integration check:

1. On join, confirm the compact profile panel leaves Loading and shows a writable
   session-memory state, 0 coins, 0 XP, and level 1 for a new local user.
2. Finish an eligible bot match. The Results reward should progress from Pending to Granted
   and the profile panel should increase by the deterministic 85%-scaled amount. A normal bot
   win is 51 coins and 127 XP; a loss is 34 coins and 85 XP; a draw is 42 coins and 106 XP.
3. Confirm the Results screen never shows a second grant for the same match and the Output has
   no DataService, migration, queue, or reward error.
4. Select Rematch, finish again, and confirm the fresh match ID receives one separate grant.
5. Stop and restart Studio. The local session-memory balance may reset by design; do not log
   that as data loss. This adapter deliberately provides no cross-session persistence.

Send one screenshot containing the profile panel and Results reward line, plus any red Output
message. The client must never be able to choose its reward amount or edit the balance.

### 5. Published Development persistence (owner-run gate)

This is a later, separate validation in an owner-approved private Development experience; do
not use Production data:

- use an authenticated positive-UserId client and confirm the profile panel reports
  `CLOUD`/`Persistent`; published Studio synthetic users still select SessionMemory and do not
  count as native DataStore evidence;
- leave and rejoin after one eligible match and confirm coins, XP, statistics, level, and the
  processed grant survive;
- retry the same grant identity and confirm no second balance/stat change;
- join the same account through competing sessions and confirm only one writable lease;
- exercise transient DataStore failure/read-only recovery, PlayerRemoving, autosave, and
  server shutdown, then confirm no default overwrite or duplicated reward;
- inspect Output for bounded retry/failure diagnostics and verify the profile returns to Ready
  only when it is safely writable.

Until that owner-run published Development matrix passes, cloud persistence is implemented
but not runtime-accepted.

## Code follow-up after the evidence

I will use the Studio evidence to tune movement speed, jump height, settlement thresholds,
collision size, camera framing, progression feedback, and visual readability without asking
you to debug code. Once this combined acceptance is stable, the roadmap advances to:

1. A compact lobby with clear Practice, Casual, Loadout, and Settings entry points.
2. One free original cosmetic plus strict owned/equipped validation and schema migration.
3. Screenshot-driven character, environment, HUD, and Results polish.
4. Mobile/accessibility, audio, analytics, and late-projectile recovery work.

## Owner actions later

- Select or create a private Development experience for the cloud-persistence gate.
- Grant tester access when a private publish is desired and run the Development-only
  DataStore matrix above.
- Create separate Staging and Production experiences before cloud-data testing.

No Robux purchase, production key, paid product, or production publication is required now.
