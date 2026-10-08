# Brainrot Heist 🧠💰

A Roblox "steal a brainrot" game. Buy brainrots off the conveyor, let them make you cash in your base, and **steal everyone else's**.

## How it plays

1. **Buy.** Brainrots ride a conveyor down the middle of the map. Hold **E** next to one to buy it, and it walks to your base.
2. **Earn.** Each brainrot on a pedestal makes cash every second. The cash piles up on the green **COLLECT** pad, so step on it to bank it.
3. **Steal.** Walk into someone else's base and hold **E** on a brainrot. It goes over your head, you move slower, and you have to run it back to your own base.
4. **Defend.** Everyone has a **Slap** tool. Slap a thief and the brainrot runs back home.
5. **Lock.** Step on the red **LOCK** pad. A laser closes your entrance for 60s and zaps anyone else who walks through. After that it recharges for 30s, and that's when you're vulnerable.
6. **Sell** your own brainrots for half price (hold **F**).
7. **Rebirth.** Reset your cash and brainrots for a permanent income multiplier (+0.5x each time).

Rare spawns (Legendary and up), big buys, big steals, rebirths and Server Luck purchases are announced to the whole server.

### Rarities and conveyor odds

| Rarity | Chance | Server Luck | Price range | Income |
|---|---|---|---|---|
| 🟩 Common | 60% | 42.8% | $25 – $120 | $1–4/s |
| 🟦 Rare | 25% | 35.6% | $500 – $1.5K | $10–25/s |
| 🟪 Epic | 10% | 14.4% | $5K – $15K | $60–150/s |
| 🟨 Legendary | 4% | 5.7% | $75K – $200K | $500–1.2K/s |
| 🟥 Mythic | 0.9% | 1.3% | $1.5M – $4M | $6K–15K/s |
| ⬛ Secret | 0.1% | 0.14% | $50M | $250K/s |

All balancing lives in `src/shared/Config.luau`: brainrots, prices, odds, lock times, slap power, rebirth costs, and Robux items. **Add new brainrots there every week**, since frequent updates are what keep games like this trending.

## Run it

You need [Roblox Studio](https://create.roblox.com) and [Rojo](https://rojo.space).

```bash
# 1. Install Rojo (pick one)
#    Download from https://github.com/rojo-rbx/rojo/releases
#    ...or with aftman/foreman/rokit, e.g.:
rokit add rojo-rbx/rojo

# 2. Get the code
git clone https://github.com/curtcornwell123-coder/Scaling-dshbrd.git
cd Scaling-dshbrd

# 3. Start syncing
rojo serve
```

Then in Roblox Studio:

1. **New → Baseplate**.
2. Install the Rojo plugin (Toolbox/Creator Store, search "Rojo"). Click **Rojo → Connect**.
3. Press **Play**.

**To test stealing**, go to the **Test** tab, set **Clients and Servers** to 2 players, and click **Start**. You get two windows, so you can steal from yourself.

To build a place file without Studio sync: `rojo build -o BrainrotHeist.rbxl`.

## Publish

1. **File → Publish to Roblox**.
2. **Game Settings → Security → Enable Studio Access to API Services** (needed for saving in Studio).
3. **Game Settings → Places → Max Players = 8**. There are 8 bases.
4. Set up the Robux items below.

## Make money (Robux)

On the [Creator Dashboard](https://create.roblox.com/dashboard/creations), open your experience, then **Monetization**:

- **Passes**: create `2x Cash`, `VIP`, and `Longer Lock`.
- **Developer Products**: create `Cash Bag`, `Cash Vault`, `Server Luck`, and `Instant Lock`.

Paste each ID into `Config.GamePasses` / `Config.Products` in `src/shared/Config.luau`. Items left at `Id = 0` show as **SOON** in the shop.

Suggested prices:

| Item | Type | Price |
|---|---|---|
| 2x Cash | Pass | 299 R$ |
| VIP (+2 base slots, VIP tag) | Pass | 399 R$ |
| Longer Lock (120s) | Pass | 149 R$ |
| Cash Bag (10 min of income) | Product | 49 R$ |
| Cash Vault (1 hr of income) | Product | 199 R$ |
| Server Luck (15 min, whole server) | Product | 149 R$ |
| Instant Lock | Product | 25 R$ |

Purchases are only confirmed after they're saved, and each one is recorded, so players are never charged without getting the item or granted it twice.

## Project layout

```
src/shared/Config.luau            brainrots, odds, prices, locks, rebirths, Robux items
src/server/Main.server.luau       saving, bases, conveyor, buying, stealing, slapping, purchases
src/server/WorldBuilder.luau      builds the map, conveyor and 8 bases from parts
src/server/BrainrotModel.luau     builds each brainrot model + name tag
src/client/HUD.client.luau        cash HUD, shop, rebirth menu, announcements, prompts
```

The server decides every purchase, steal and cash change, so exploiters can't spawn cash or brainrots. Steals also have a server-side speed check, so teleporting home doesn't work.

## Next ideas

- **Real models**: swap the blocky brainrots for meshes (only `BrainrotModel.luau` needs to change).
- **Thumbnail + icon**: the biggest driver of clicks.
- **Sounds**: purchase, steal, slap, laser zap.
- **Limited-time event brainrots**, an **Index** of everything you've owned, **daily rewards**, **group rewards**.
- **Offline earnings** and **trading**.
