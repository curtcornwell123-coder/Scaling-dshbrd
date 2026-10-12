# Ultimate Golf ⛳

Multiplayer chaos mini-golf for Roblox, where **you are the ball**. A fully enclosed, Rivals-style lobby you navigate on foot (no menus), 12 procedurally built courses, Ranked 1v1 / Classic / 8-player Race, chaos abilities and knockouts, four cosmetic crates, a 14-day login calendar, rotating practice minigames and live leaderboards.

- Design: [`docs/GDD.md`](docs/GDD.md)
- Economy and the Robux price sheet: [`docs/Monetization.md`](docs/Monetization.md)
- Art: [`assets/`](assets/) (ball mesh, icons for every crate, pass and product)

## Run it

1. Install [Rojo](https://rojo.space) 7.4+ and its Studio plugin.
2. In this folder run `rojo serve`. In Studio, open a new **Baseplate**, delete the `Baseplate` part, and click **Connect** in the Rojo plugin.
   - Or build a place file: `rojo build default.project.json -o UltimateGolf.rbxlx`, then open it.
3. **Game Settings → Security → Enable Studio Access to API Services** (saving, leaderboards, global Mythic stock). Without it the game still runs on a temporary profile and prints a warning.
4. Press **Play**. In Studio a single player can start any mode alone (`Config.StudioSoloMatches`), so you can test matches solo.

The whole world (lobby, dome, fountain, rooms, courses) is built by code at server start, so there's nothing to place by hand.

## Before publishing

1. **Ball mesh**: import `assets/mesh/golfball.obj` (Studio → 3D Importer), then paste its mesh id into `Config.Ball.MeshId` (see `assets/mesh/README.md`). Until then balls are smooth spheres.
2. **Passes and products**: create them in the Creator Dashboard using the icons in `assets/icons/` and the prices in `docs/Monetization.md`, then paste the ids into `Config.GamePasses` and `Config.DevProducts`. Unset ids show "Coming soon".
3. **Creator codes**: add codes to `Config.CreatorCodes`.
4. Turn off `Config.StudioSoloMatches` if you want Studio to behave like a live server.

## Testing with Claude + Roblox Studio (your PC)

The repo's `.mcp.json` registers the Roblox Studio MCP (`%LOCALAPPDATA%\Roblox\mcp.bat`). Open this repo in Claude Code **on your Windows PC** (Desktop app, or `claude remote-control` in a terminal) with Studio running, and Claude can inspect and play-test the place directly.

## Development

```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src
```

`globalTypes.d.luau` comes from the luau-lsp repo (`scripts/globalTypes.d.luau`). Every file is `--!strict` and type-checks clean.

Tests (need the standalone `luau` binary from the Luau releases):

```
python3 tests/run.py path/to/luau                                  # shared logic: odds, pity, daily, ranks, maps, catalog
tests/boot/run.sh path/to/luau path/to/globalTypes.d.luau forward  # boots the whole game headlessly and plays every flow
```

### Where things live

| Want to change… | Edit |
|---|---|
| Prices, rewards, physics, modes, product ids | `src/shared/Config.luau` |
| Ball skins | `src/shared/Skins.luau` |
| Trails, knockout effects, arrow skins | `src/shared/Cosmetics.luau` |
| Crates and odds | `src/shared/Crates.luau` |
| 14-day login rewards | `src/shared/DailyRewards.luau` |
| Maps and themes | `src/shared/Maps.luau` |
| Shop tabs and what they list | `src/shared/ShopCatalog.luau` |
| UI look (colours, corners, buttons) | `src/shared/UIKit.luau` |
