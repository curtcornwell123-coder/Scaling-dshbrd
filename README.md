# Crate Rush 📦

A Roblox crate-opening pet simulator. Earn coins, open crates, pull pets, and chase the **red Mythics**.

| Color | Rarity |
|---|---|
| 🟩 Green | Common |
| 🟦 Blue | Rare |
| 🟪 Purple | Epic |
| 🟨 Gold | Legendary |
| 🟥 Red | **Mythic** |

## Gameplay loop

1. You earn coins every second (base income plus the power of your equipped pets).
2. You open crates, either by walking up to the glowing crates in the lobby or from the 🎁 **Crates** menu.
3. A CS:GO-style reel spins and lands on your pet. Legendary and Mythic pulls flash the screen and are **announced to the whole server**.
4. You equip up to 4 pets. They float around you and boost your income, so you can afford better crates.
5. You sell pets you don't need for coins.

### Crates and odds

| Crate | Price | Common | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|---|---|
| Green | 100 | 70% | 22% | 6% | 1.8% | 0.2% |
| Blue | 750 | 40% | 40% | 15% | 4.5% | 0.5% |
| Purple | 4,000 | 10% | 35% | 42% | 11.5% | 1.5% |
| Gold | 20,000 | 0% | 15% | 40% | 40% | **5%** |

The in-game shop shows these odds. All balancing (pets, power, prices, odds, equip slots) lives in `src/shared/Config.luau`.

## Project layout

```
src/shared/Config.luau            rarities, pets, crates, odds, roll logic (ReplicatedStorage.Shared)
src/server/Main.server.luau       data saving, crate opening, income, equip/sell (ServerScriptService)
src/server/WorldBuilder.luau      builds the lobby and the 4 crates
src/server/PetFollower.luau       equipped pets that follow the player
src/client/CrateUI.client.luau    HUD, shop, inventory, opening reel (StarterPlayerScripts)
```

Server code decides every roll and coin change, so exploiters can't spawn pets or coins.

## Running it

1. Install [Rojo](https://rojo.space) (the CLI plus the Roblox Studio plugin).
2. In this folder, run `rojo serve`.
3. Open a new **Baseplate** in Roblox Studio, open the Rojo plugin, and click **Connect**.
4. Press **Play**.

To save progress in Studio, publish the place and turn on
*Game Settings → Security → Enable Studio Access to API Services*.

## Ideas to make it trend

- **Rebirths**: reset coins for a permanent income multiplier.
- **Limited-time event crates**, plus a red Mythic crate unlocked by rebirths.
- **Trading** between players.
- **Gamepasses**: 2x coins, extra equip slots, faster opening, auto-open.
- **Pet models** to replace the glowing orbs, and **daily rewards** / group rewards.

> If you ever sell crates for **Robux**, Roblox requires paid random items to show their odds
> before purchase. This shop already shows them.
