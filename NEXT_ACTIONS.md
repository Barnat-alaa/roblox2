# Next Actions

## Resume command

```powershell
Set-Location "C:\Users\barna\Desktop\roblox wild ones"
rokit install
wally install
rojo serve default.project.json
```

## Highest priority

1. Complete MatchEnd, results, and rematch first.
   - Retain a participant/elimination roster independently of Roblox character respawns.
   - Resolve winner or draw exactly once, show results, collect rematch consent, and reset
     participants, projectiles, terrain revision/state, and timers for the next match.
2. Add the same-server bot.
   - Fill an otherwise empty opponent slot through the normal authoritative turn, fire,
     damage, elimination, MatchEnd, and rematch paths.
   - Keep aim bounded, imperfect, and deterministic enough to test.
3. Strengthen movement and terrain-support settling.
   - Validate accumulated movement distance, jump frequency, grounded state, and explicit
     knockback exceptions.
   - Detect support removal, apply bounded settling, and resolve hazard/death outcomes before
     handing off the turn.
4. Add profiles only after the complete match loop is stable.
   - Implement session locking, migrations, autosave, shutdown handling, and a read-only
     fallback.
   - Grant idempotent rewards from a stable MatchEnd result identity.
5. Add late-projectile state recovery, then complete mobile and accessibility tuning.

## Completed terrain validation

- Studio TestEZ completed with 37 passed, 0 failed, and 0 skipped.
- The final playable build booted clean. Initial server/client terrain revision 0 matched;
  real Acorn and Mole Drill requests produced the expected 0 → 1 deltas, protected terrain
  remained, the hazard run existed, and death-height elimination was observed.
- Temporary smoke scripts were removed, and a clean restart produced only the expected
  development startup message.

## Remaining multiplayer validation

A separate one-server, two-client run has not yet been recorded. Complete it alongside the
MatchEnd/results/rematch work before treating the multiplayer slice as validated.

## Owner actions eventually required

- Choose or create the Development experience in Creator Dashboard.
- Publish the local development place privately.
- Grant tester access.
- Create separate Staging and Production experiences before cloud-data testing.

No Robux purchase, API key, or production publication is required for the current slice.
