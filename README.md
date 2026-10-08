# Brainrot Heist 🧠💰

A Roblox "steal a brainrot" game. Buy brainrots off the conveyor, let them make you cash in your base, and **steal everyone else's**.

## How it plays

1. **Buy.** Brainrots ride a conveyor down the middle of the map. Hold **E** next to one to buy it, and it walks to your base.
2. **Earn.** Each brainrot on a pedestal makes cash every second. The cash piles up on the green **COLLECT** pad, so step on it to bank it.
3. **Steal.** Walk into someone else's base and hold **E** on a brainrot. It goes over your head, you move slower, and you have to run it back to your own base.
4. **Defend.** Everyone has a **Slap** tool. Slap a thief and the brainrot runs back home.
5. **Upgrade your base** at the orange post near the entrance. Press **Open Upgrades** (or tap it on mobile) to get a panel with three upgrades, each with a big **UPGRADE** button:
   - **Walls:** you start with a low wood fence thieves can hop. Upgrade to Brick ($1K), Concrete ($25K, too tall to jump), Steel ($500K) and Diamond ($10M). Walls are solid grey with blue tinted windows.
   - **Floors:** build a 2nd floor ($50K) and a 3rd floor ($2M), each with 10 more brainrot slots and reached by stairs inside your base. Floors with another floor above are walled in all the way up, and the entrance becomes a doorway.
   - **Lock:** how long your lasers stay on: 30s, 45s ($5K), 60s ($50K), 90s ($500K), 120s ($5M). The Longer Lock gamepass doubles it.
   - **Stair carpets** come from rebirths: plain wood at first, then a new carpet every 5 rebirths: Red (5), Royal (10), Golden (15), Diamond (20) and Rainbow (25).
6. **Lock.** Step on the red **LOCK** pad. Red laser beams cross your entrance and zap anyone else who walks through. After the lock ends it recharges for 30s, and that's when you're vulnerable.
7. **Sell** your own brainrots for half price (hold **F**).
8. **Rebirth.** Reset your cash and brainrots (walls stay) for a permanent income multiplier (+0.5x each time).

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
| 💖 Event Special | not on the conveyor | | Robux | see below |

### Launch event: Cigna Glamourina (limited)

- **502 copies total.** 500 are sold in the shop for **50 Robux** (one per player), and 2 are reserved for admins. Admins hand them out with **Give** in the admin panel.
- Every copy has a **serial number** (#1–#500 sold, #501–#502 reserved), shown on her name tag.
- Stock is shared by **every server** through a DataStore. When someone clicks Buy, a copy is reserved for 5 minutes before the Robux prompt opens, so the game can never sell more than 500. Cancelling releases it.
- She **can't be stolen or sold** and **stays through rebirths**. If your base is full when you buy her, she appears as soon as a slot opens.
- **Income: $2.5K/s, doubling with every rebirth** ($5K at rebirth 1, $10K at 2, … $640K at 8), on top of the rebirth multiplier. In economy simulations she makes about a third of a typical owner's income: progression is roughly 2x faster early on and about 1.4x later, without letting buyers skip the game.

To put her on sale: create a Developer Product named "Cigna Glamourina" priced at **50 Robux**, and paste its ID into `Config.LimitedItems.CignaGlamourina.ProductId`.

### Mutations

Any brainrot on the conveyor can roll a mutation. A mutation multiplies both its price and its income and changes how it looks. Server Luck doubles these chances.

| Mutation | Chance | Income & price | Look |
|---|---|---|---|
| ✨ Gold | 5% | x2 | Shiny gold foil |
| 💎 Diamond | 2% | x3 | See-through ice-blue glass |
| ⭐ Sparkle | 1.5% | x4 | Its own colors, brighter, covered in twinkling stars |
| 🔥 Lava | 0.8% | x5 | Cracked lava rock, on fire |
| 🌈 Rainbow | 0.3% | x10 | Cycles through every color |

Lava and Rainbow spawns are announced to the whole server.

### Using real 3D models

Every brainrot has its own built-in design. To swap one for a 3D model:

1. In Studio, create a **Folder** in **ServerStorage** named `BrainrotModels`.
2. Find a model in the **Toolbox** and drag it into that folder.
3. Rename it to the brainrot's Id, for example `BananitoBandito` or `MeatballoSupremo`. The Ids are in `Config.luau`.
4. Press Play. The game sizes and places it automatically, applies mutations to it, and strips out any scripts hidden inside it, which is a common way free models carry viruses.

If it faces the wrong way, rotate the model in the folder.

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

## Admin panel

Admins get a red **ADMIN** button on the left. From it you can give or set cash, set rebirths, give any brainrot, set wall levels, clear a base, spawn any brainrot on the conveyor, and start or stop server luck. In the **Player** box, type `me`, `all`, or the start of someone's name. Amounts accept `5000`, `25k`, `2m` or `-500`.

Who is an admin: the game's owner (or the group owner, for group games), anyone listed in `Config.AdminUserIds`, and everyone while testing in Studio. The server checks every admin action, so nobody else can use it even with exploits.

### Admin abuse and drops

The admin panel can drop any brainrot (with any mutation) from the sky, start a **Brainrot Rain** of 10 lucky brainrots, or start a **Cash Rain** of 30 cash drops (each worth the amount box). First player to grab a drop keeps it.

There's a weekly **admin abuse** event. Everyone sees a countdown during the hour before it starts and a LIVE banner while it runs. It's set to **Saturday 2:00 PM Central time (Oklahoma)**, and daylight saving is handled automatically. Change it in `Config.AdminAbuse`. Admins can also start or end it any time.

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
| Longer Lock (2x lock time) | Pass | 149 R$ |
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
src/server/BrainrotModel.luau     15 hand-built brainrot designs, mutations, custom-model support
src/client/Effects.client.luau    idle bobbing + rainbow color cycling (visual only)
src/client/HUD.client.luau        cash HUD, shop, rebirth menu, announcements, prompts
```

The server decides every purchase, steal and cash change, so exploiters can't spawn cash or brainrots. Steals also have a server-side speed check, so teleporting home doesn't work.

## Next ideas

- **Real models**: swap the blocky brainrots for meshes (only `BrainrotModel.luau` needs to change).
- **Thumbnail + icon**: the biggest driver of clicks.
- **Sounds**: purchase, steal, slap, laser zap.
- **Limited-time event brainrots**, an **Index** of everything you've owned, **daily rewards**, **group rewards**.
- **Offline earnings** and **trading**.
