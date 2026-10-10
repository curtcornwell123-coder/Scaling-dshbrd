# Ultimate Golf — build status

## Complete
- Shared configs, server services, client/UI, lobby (LobbyBuilder), 12 procedural courses + tutorial (CourseBuilder), ball mesh + full icon set, docs.
- Verification:
  - `luau-lsp analyze` (strict, Roblox definitions): 0 diagnostics; `rojo build`: OK.
  - `python3 tests/run.py <luau>`: shared logic (odds, pity over 20k rolls, daily streak, ranks, maps, catalog).
  - `tests/boot/run.sh <luau> <globalTypes.d.luau> [forward|reverse|deferred]`: headless boot of the whole game against a Roblox API mock — 43 flows (tutorial, Ranked/Classic/Race matches, abilities, knockouts, shop, crates, daily, creator code, practice, voting, receipts, leavers, client modules), 0 runtime errors.

## Not verifiable here (needs Studio)
- Real physics feel (rails, bumpers, spinners, pushers, ramps), GUI layout sizes, DataStore save/load against live services, multi-client play.

## Next ideas
- Play-test in Studio and tune `Config.Physics` (MaxShotSpeed, RollResistance, Drag) to taste.
- Upload the mesh + icons, create passes/products, paste ids into Config.
