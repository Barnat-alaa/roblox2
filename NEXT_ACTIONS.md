# Next Actions

## Resume command

```powershell
Set-Location "C:\Users\barna\Desktop\roblox wild ones"
rokit install
wally install
rojo serve default.project.json
```

## Highest priority

1. Finish the user-run M5.2 acceptance pass.
   - Run Studio TestEZ against the current source and record the expected 57-spec result.
   - Complete a final-tuning one-server/one-client/bot match and rematch, checking turn
     ownership, bot identity/health, projectile and terrain presentation, Results, clean
     reset, Output, and visual feel.
2. Implement the next roadmap milestone: movement, grounding, and terrain-support hardening.
   - Validate accumulated movement distance, jump frequency, grounded state, and explicit
     knockback exceptions.
   - Detect support removal, apply bounded settling, and resolve hazard/death outcomes before
     handing off the turn.
3. Add profiles and rewards only after the bot acceptance and movement/support pass are stable.
   - Implement session locking, migrations, autosave, shutdown handling, and a read-only
     fallback.
   - Grant idempotent rewards from a stable MatchEnd result identity.
4. Add late-projectile state recovery, then complete mobile and accessibility tuning.

Do not add rewards to Results until profiles, stable result identities, and idempotent grants
are implemented and tested.

## M5.2 implementation evidence

- The server-owned BotCritter uses bounded, imperfect aim and enters the normal authoritative
  turn, fire, damage, terrain, elimination, Result, and rematch paths.
- Static analysis, strict analysis, and both Rojo builds are clean.
- The latest recorded Studio TestEZ run completed with 56 passed, 0 failed, and 0 skipped.
  Source now contains 57 specs; the new tuning spec awaits the user-run runtime pass.
- The final playable build booted clean. Initial server/client terrain revision 0 matched;
  real Acorn and Mole Drill requests produced the expected 0 → 1 deltas, protected terrain
  remained, the hazard run existed, and death-height elimination was observed.
- A genuine Studio one-server/two-client run completed the authoritative elimination and
  Results flow, retained the defeated participant's elimination across respawn, accepted
  unanimous rematch consent, and cleanly restarted both players under a fresh match ID.
- A solo last-player disconnect returned the match service to clean `WaitingForPlayers`
  state.
- A live pre-final-tuning bot run fired through the authoritative projectile path, eliminated
  the human participant, and showed the DEFEAT Results interface.
- Bot aim solving was observed at 3.43-5.65 ms in Studio. A server snapshot measured 16.65 ms
  p50, 17.72 ms p95, 18.04 ms p99, and 18.37 ms worst frame time. Treat these as Studio
  observations, not production or representative-device guarantees.
- Temporary smoke scripts were removed, and a clean restart produced only the expected
  development startup message.

Bot code is implemented, but the final-tuning rematch and runtime/visual-feel pass are not
complete until the user records them in Studio. After that acceptance pass, continue with
movement, grounding, and terrain-support hardening.

## Owner actions eventually required

- Choose or create the Development experience in Creator Dashboard.
- Publish the local development place privately.
- Grant tester access.
- Create separate Staging and Production experiences before cloud-data testing.

No Robux purchase, API key, or production publication is required for the current slice.
