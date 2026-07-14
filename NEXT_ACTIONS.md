# Next Actions

## Resume command

```powershell
Set-Location "C:\Users\barna\Desktop\roblox wild ones"
rokit install
wally install
rojo serve default.project.json
```

## Highest priority

1. Add the same-server bot.
   - Fill an otherwise empty opponent slot through the normal authoritative turn, fire,
     damage, elimination, MatchEnd, and rematch paths.
   - Keep aim bounded, imperfect, and deterministic enough to test.
2. Strengthen movement and terrain-support settling.
   - Validate accumulated movement distance, jump frequency, grounded state, and explicit
     knockback exceptions.
   - Detect support removal, apply bounded settling, and resolve hazard/death outcomes before
     handing off the turn.
3. Add profiles only after the bot-enabled match loop is stable.
   - Implement session locking, migrations, autosave, shutdown handling, and a read-only
     fallback.
   - Grant idempotent rewards from a stable MatchEnd result identity.
4. Add late-projectile state recovery, then complete mobile and accessibility tuning.

Do not add rewards to Results until profiles, stable result identities, and idempotent grants
are implemented and tested.

## Completed match-loop validation

- Studio TestEZ completed with 47 passed, 0 failed, and 0 skipped.
- The final playable build booted clean. Initial server/client terrain revision 0 matched;
  real Acorn and Mole Drill requests produced the expected 0 → 1 deltas, protected terrain
  remained, the hazard run existed, and death-height elimination was observed.
- A genuine Studio one-server/two-client run completed the authoritative elimination and
  Results flow, retained the defeated participant's elimination across respawn, accepted
  unanimous rematch consent, and cleanly restarted both players under a fresh match ID.
- A solo last-player disconnect returned the match service to clean `WaitingForPlayers`
  state.
- Temporary smoke scripts were removed, and a clean restart produced only the expected
  development startup message.

The passive solo TrainingTarget validates lifecycle behavior but is not the planned bot. The
next validation target is a one-server/one-client/bot match and rematch through the same
authoritative paths.

## Owner actions eventually required

- Choose or create the Development experience in Creator Dashboard.
- Publish the local development place privately.
- Grant tester access.
- Create separate Staging and Production experiences before cloud-data testing.

No Robux purchase, API key, or production publication is required for the current slice.
