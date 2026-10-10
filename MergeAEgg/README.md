# Merge A Egg 🥚

Steal eggs from biome stages, race them home past the guardians, grow and hatch them, and merge 3 matching eggs into a rarer one in the Fuse Machine.

## Gameplay loop

1. You train **Speed** on the two treadmills in your pen.
2. You run past the **SAFE ZONE** into the corridor and steal an egg from a nest. You can only carry one egg at a time, and heavier eggs slow you down.
3. If the guardian animal catches you inside its biome, you drop the egg. A dropped egg goes back to its nest after 60 seconds unless someone picks it up first.
4. To keep the egg, carry it into your pen's nest area. It grows on a timer, and then you hatch it into a random pet. Heavier and BIG eggs roll rarer pets.
5. To get a rarer egg, carry 3 matching eggs into your **Fuse Machine**. They merge into 1 egg of the next rarity (Common → Uncommon → … → Secret).
6. Equipped pets earn money every second and boost your treadmill. You spend the money on pen upgrades, trails, treadmills and rebirths, which let you go further out.

**Biomes** (further out means faster guardians): Forest → Cave (Golem King boss) → Desert → Toxic Wastelands → Farmlands → Enchanted Forest → Candylands → Halloween (Clown, event).

**Stealing from players:** other players can steal eggs that are growing in your pen. You can hit them with your bat to make them drop the egg. After someone robs you, your pen gets a 45-second shield.

## Setup

1. Install [Rojo](https://rojo.space), run `rojo serve` in this folder, and connect from the Rojo plugin in Studio. Or run `rojo build -o MergeAEgg.rbxlx` and open that file.
2. In Studio, go to **Game Settings → Security** and turn on **Enable Studio Access to API Services**. Saving and leaderboards need this.
3. In **Game Settings → Places**, set **Max Players = 6**. There are 6 pens.
4. Create the Game Passes and Developer Products on the Creator Dashboard, then paste their IDs into `src/shared/Config.luau` under `Config.GamePasses` and `Config.Products`. Any item whose ID is `0` shows "not set up yet" when someone tries to buy it.
5. Optional: to let players gift passes, create one Developer Product per pass and put its ID in that pass's `giftProduct` field.

The map, all models (pets, eggs, bat, treadmills, Fuse Machine, stalls) and the UI are built from code when the game starts, so you don't need to import any assets.

## Admin commands

These work for user ID `469657246` and for group `187537803` rank 255. Type them in chat with a `/` prefix, or with `;` as a fallback.

| Command | What it does |
|---|---|
| `/kick <player> <reason>` | Kicks the player and shows them the reason |
| `/ban <player> <30m\|12h\|7d\|perm> <reason>` | Bans the player in every server, using Roblox's ban API. Alt accounts are included. |
| `/unban <userId or name>` | Removes a ban |
| `/money <player> <amount>` | Gives money |
| `/speed <player> <amount>` | Gives speed |
| `/egg <player> <biome> <rarity>` | Gives an egg, for example `/egg corny desert legendary` |
| `/night` | Starts night right away |
| `/boss` | Spawns the Golem King |

## Files

| File | Purpose |
|---|---|
| `src/shared/Config.luau` | Every number in the game: biomes, 106 pets, prices, odds, timers and Robux IDs |
| `src/shared/Models.luau` | Every 3D model, built from parts |
| `src/server/Main.server.luau` | Startup, remotes, player lifecycle and admin commands |
| `src/server/Data.luau` | Session-locked saving and global leaderboards |
| `src/server/World.luau` | Map builder (lobby, pens, biomes, cave) and the day/night cycle |
| `src/server/Economy.luau` | Money, speed, treadmills, pets, shops, Robux purchases and rewards |
| `src/server/Eggs.luau` | Nests, stealing, carrying, dropping, the Fuse Machine and luck events |
| `src/server/Guardians.luau` | Biome animal AI |
| `src/server/Combat.luau` | Bat swings and knockback |
| `src/server/Boss.luau` | The Golem King cave boss and the daily Boss Egg |
| `src/client/HUD.client.luau` | HUD and all client-side effects |
| `src/client/Panels.luau` | Every menu: Shop, Index, Sell, Trails, Treadmills, Eggs, Pets, Gifts and others |

## Tuning

You can rebalance everything in `Config.luau` without changing any code:

- **Speed and biomes:** `Config.walkSpeedFor` converts the Speed stat into walk speed. Each biome's `recommended` value sets how fast its guardians are.
- **Halloween:** set `HalloweenEnabled = false` to remove the event biome when the event ends.
- **Featured egg:** `FeaturedEgg.endsAt` sets the shop countdown, as a Unix timestamp.
