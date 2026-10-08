# Brainrot Heist 🧠💰

A Roblox "steal a brainrot" game. Buy brainrots off the conveyor, let them make you cash in your base, and **steal everyone else's**.

## How it plays

1. **Buy.** Brainrots walk out of a rocky mine cave and ride a conveyor down the middle of the map, disappearing into a cave at the far end. Hold **E** next to one to buy it, and it walks to your base.
2. **Earn.** Each brainrot on a pedestal makes cash every second. The cash piles up on the green **COLLECT** pad, so step on it to bank it.
3. **Steal.** Walk into someone else's base and hold **E** on a brainrot. It goes over your head, you move slower, and you have to run it back to your own base.
4. **Defend.** Everyone has a **Slap** tool. Slap a thief and the brainrot runs back home.
5. **Upgrade your base** at the orange post near the entrance. Press **Open Upgrades** (or tap it on mobile) to get a panel with two upgrades:
   - **Base level:** walls and floors always upgrade **together**, one floor and one wall tier per level, so you can't get ahead on either. Every new floor adds 10 brainrot slots and is reached by stairs inside the base. Lower floors are walled in all the way up, with blue tinted windows.

     | Level | Floors | Walls | Cost |
     |---|---|---|---|
     | 1 | 1 | Wood Fence (hop-able) | free |
     | 2 | 2 | Brick Wall | $25K |
     | 3 | 3 | Concrete Wall (too tall to jump) | $1M |
     | 4 | 4 | Steel Wall | $40M |
     | 5 | 5 | Diamond Wall | $1.5B |

   - **Lock:** how long your lasers stay on: 30s, 45s ($5K), 60s ($50K), 90s ($500K), 120s ($5M). After rebirthing you can go further: 150s ($25M, 1 rebirth), 180s ($250M, 2 rebirths), 210s ($2B, 4 rebirths), 240s ($40B, 6 rebirths). Lock upgrades are kept when you rebirth. The Longer Lock gamepass doubles it.
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
| ⬛ Secret | 0.1% | 0.14% | $25M – $50M | $120K–250K/s |
| 💖 Event Special | not on the conveyor | | Robux | see below |

### Launch event: Cigna Glamourina (limited)

- **502 copies total.** 500 are sold in the shop for **50 Robux** (one per player), and 2 are reserved for admins. Admins hand them out with **Give** in the admin panel.
- Every copy has a **serial number** (#1–#500 sold, #501–#502 reserved), shown on her name tag.
- Stock is shared by **every server** through a DataStore. When someone clicks Buy, a copy is reserved for 5 minutes before the Robux prompt opens, so the game can never sell more than 500. Cancelling releases it.
- She **can't be stolen or sold** and **stays through rebirths**. If your base is full when you buy her, she appears as soon as a slot opens.
- **Income: $2.5K/s, doubling with every rebirth** ($5K at rebirth 1, $10K at 2, … $640K at 8), on top of the rebirth multiplier. In economy simulations she makes about a third of a typical owner's income: progression is roughly 2x faster early on and about 1.4x later, without letting buyers skip the game.

- **Event statue:** a compact spinning statue of her stands right beside the shop tent, with a live stock sign. Tap or click it to buy her right there.
- **Mutation roll:** every copy rolls a mutation when you get it (normal odds), plus a **1% chance of MAGIC**, an event-only mutation (x8 income, purple-to-teal shimmer, swirling stars, floating orbs). Admins can also turn a player's Cigna Magic with **Give MAGIC (event)** in the admin panel (it needs the player to own her). Change the featured event with `Config.CurrentEvent`.

To put her on sale: create a Developer Product named "Cigna Glamourina" priced at **50 Robux**, and paste its ID into `Config.LimitedItems.CignaGlamourina.ProductId`.

### Mutations

Any brainrot on the conveyor can roll a mutation. A mutation multiplies both its price and its income and changes how it looks. Server Luck doubles these chances.

| Mutation | Chance | Income & price | Look |
|---|---|---|---|
| ✨ Gold | 4% | x2 | Shiny gold foil |
| 🍬 Candy | 2.5% | x2.5 | Pastel candy colors, sprinkles |
| 💎 Diamond | 2% | x3 | See-through ice-blue glass |
| ❄️ Frozen | 2% | x3 | Ice, falling snowflakes |
| ⭐ Sparkle | 1.5% | x4 | Its own colors, brighter, twinkling stars |
| ⚡ Electric | 1.2% | x4.5 | Yellow charge, crackling sparks |
| 😊 Smiley | 1% | x5 | Sunny yellow, little smiley faces floating around it |
| ☢️ Radioactive | 0.9% | x5.5 | Toxic green, glowing spots, green fumes |
| 🔥 Lava | 0.8% | x5 | Cracked lava rock, on fire |
| 🌌 Galaxy | 0.6% | x7 | Deep-space glass, drifting stars |
| 💀 Cursed | 0.5% | x8 | Blood-dark stone, black smoke, embers |
| 🌈 Rainbow | 0.3% | x10 | Cycles through every color |
| 🕳️ Void | 0.2% | x12 | Pitch black, purple outline, dark matter pulled in |
| 😇 Divine | 0.1% | x15 | White marble, golden halo, holy light |
| ✨🔮 Magic | 1% when you get the event brainrot (event only) | x8 | Purple-teal shimmer, swirling stars, floating orbs |

Galaxy and rarer spawns are announced to the whole server. About 1 in 6 conveyor brainrots is mutated (1 in 3 with Server Luck).

### Using real 3D models

Every brainrot has its own built-in design. To swap one for a 3D model:

1. In Studio, create a **Folder** in **ReplicatedStorage** named `BrainrotModels` (so followers can use it too).
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

When it starts, everyone gets a huge intro: a white flash and red camera flash, a camera shake, spinning red and gold light rays, a giant rainbow **ADMIN ABUSE!** title that slams in (with the admin's name if one started it), falling confetti and a volley of fireworks over the map. While it runs, the lighting gently cycles party colors and fireworks keep popping. An "ADMIN ABUSE IS OVER" card shows when it ends. (All of it is in `src/client/AdminAbuse.client.luau`.)

**Admin abuse boosts and gift** (tune them in `Config.AdminAbuseBoosts` and `Config.AdminAbuseGift`):
- While it's live, everyone gets **2x cash**, **Server Luck** and walks faster (22 instead of 16; carrying stays slow so stealing stays fair).
- Everyone online gets a gift, shown on a pop-up card: **3 Diamonds, 150 Shards and a free brainrot** (rolled with Brainrot Rain luck). It's once per player per week, so starting admin abuse again the same week doesn't hand out more. Players who join while it's live still get theirs.
- Why 3 Diamonds: normally the only way to get Diamonds is 1 a week from weekly quests. 3 a week from admin abuse makes it a big reward worth showing up for, while Gold walls (4) and Galaxy walls (9) still take some effort.

## Quests, Shards, Diamonds and the Diamond Shop

Fair progression for free-to-play players. None of this can be bought with Robux.

- **Daily quests:** 3 a day, the same for everyone, and new ones at midnight Oklahoma time. Each pays **10 Shards**.
- **Weekly quests:** 3 a week, new every Monday, and much harder. Each pays **1 Diamond + 100 Shards**. Weekly quests are the only way to earn Diamonds.
- **Wall skins:** open the **QUESTS** button to see them. Most cost Shards (Red Brick 50, Candy 100, Ice 150, Jungle 200, Cyber Neon 300). The best two cost Diamonds (Royal Gold 4, Galaxy 9). Skins only change the look; your base level still sets the wall height. Every floor of your base matches your skin. With Classic, floors are the same grey in your walls' material (wood, brick, concrete, steel or diamond).
- **Shop tent:** a blue-and-cream striped circus-style tent (like Bee Swarm's) past the bases near the cave the brainrots come out of, with a little spinning diamond on top.
  - The left counter spends Diamonds: Shard Pouch (1), 2x Cash for 30 min (2), Server Luck for everyone for 15 min (3), plus the Diamond wall skins.
  - The right counter opens the **Robux shop**: the limited event brainrot, gamepasses and boosts.

Quest pools, goals, rewards, skins and shop items are all in `Config.luau`.

## Followers

Press **FOLLOW** to pick up to 3 brainrots from your base to follow you around as minis. **PICK MY 3 RAREST** does it in one tap. If one gets stolen, sold or reset by a rebirth, its mini disappears. Limited event brainrots can't be stolen, so theirs stay.

## The map

- No mountains: the map is wide-open, flat bright grass with lots of room between the bases. A wooden fence runs around the edge, with an invisible wall behind it so nobody can leave. Round leafy trees, firs and two cartoon ponds fill the open grass, and a light haze fades the distance.
- Stone paths: a walkway along each side of the conveyor, with a branch to every base's door, the shop tent and the event statue. Gentle color grading, bloom and sun rays make it all a bit richer.
- The conveyor's caves are rugged, mossy rock outcrops with pine trees on top. Each has a dark tunnel with a wooden mine-shaft entrance, hanging lanterns, glowing crystals and stalactites.
- All floating text (name tags, signs) is sized in the world, so it shrinks with distance like a real sign instead of covering the screen.

## Base looks

- Stairs are open (steps on side beams), so you can see brainrots behind and under them.
- Every floor gets lights: ceiling panels under each floor, or lamp posts on an open top floor.
- A fully upgraded base (level 5) gets walls all the way up and a peaked roof with a gold ridge and a glowing star.

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
src/shared/BrainrotModel.luau     hand-built brainrot designs, mutations, minis, custom-model support
src/client/Effects.client.luau    idle bobbing, rainbow cycling, spinning shop diamond (visual only)
src/client/Followers.client.luau  draws everyone's mini followers
src/server/LimitedStock.luau      global stock + serials for limited Robux brainrots
src/client/HUD.client.luau        cash HUD, shop, rebirth menu, announcements, prompts
```

The server decides every purchase, steal and cash change, so exploiters can't spawn cash or brainrots. Steals also have a server-side speed check, so teleporting home doesn't work.

## Next ideas

- **Real models**: swap the blocky brainrots for meshes (only `BrainrotModel.luau` needs to change).
- **Thumbnail + icon**: the biggest driver of clicks.
- **Sounds**: purchase, steal, slap, laser zap.
- **Limited-time event brainrots**, an **Index** of everything you've owned, **daily rewards**, **group rewards**.
- **Offline earnings** and **trading**.
