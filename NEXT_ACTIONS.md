# Next Actions

## Current checkpoint

Phase 1 combat correctness is implemented in code. The immediate next step is a short Roblox
Studio acceptance pass; screenshots and a description of the feel are enough for the next
iteration. Do not start persistent rewards until this pass is stable.

## Resume commands

```powershell
Set-Location "C:\Users\barna\Desktop\roblox wild ones"
rokit install
wally install
rojo build default.project.json --output build/CritterClash.rbxlx
rojo build test.project.json --output build/CritterClashTests.rbxlx
```

## User-run Phase 1 acceptance

### 1. Automated Studio suite

1. Open `build/CritterClashTests.rbxlx` in Roblox Studio.
2. Press **Play** once.
3. Open **View > Output**.
4. Send the final TestEZ summary and any red error. Current source contains **71 specs**; do
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

## Code follow-up after the evidence

I will use the Studio evidence to tune movement speed, jump height, settlement thresholds,
collision size, camera framing, and visual readability without asking you to debug code.
Once Phase 1 is accepted, the roadmap advances to Phase 2:

1. Versioned player-profile schema and validation.
2. Session locking, bounded retries, autosave, shutdown save, and read-only failure mode.
3. Migration and duplicate-session tests.
4. Stable result grant identity and idempotent server-side coins/XP rewards.
5. Profile/reward HUD integration with no client-authoritative balance changes.

## Owner actions later

- Select or create a private Development experience.
- Grant tester access when a private publish is desired.
- Create separate Staging and Production experiences before cloud-data testing.

No Robux purchase, production key, paid product, or production publication is required now.
