# Brainrot Heist 🧠💰

A Roblox "steal a brainrot" game. Buy brainrots off the conveyor, let them make you cash in your base, and **steal everyone else's**.

## How it plays

1. **Buy.** Brainrots walk out of a rocky mine cave and ride a conveyor down the middle of the map, disappearing into a cave at the far end. Hold **E** next to one to buy it, and it walks to your base.
2. **Earn.** Each brainrot on a pedestal makes cash every second. The cash piles up on the green **COLLECT** pad, so step on it to bank it.
3. **Steal.** Walk into someone else's base and hold **E** on a brainrot. It goes over your head, you move slower, and you have to run it back to your own base.
4. **Defend.** Everyone has a **Slap** tool. Slap a thief and the brainrot runs back home.
5. **Upgrade your base** at the orange post near the entrance. Press **Open Upgrades** (or tap it on mobile) to get a panel with two upgrades:
   - **Base level:** walls and floors always upgrade **together**, one floor and one wall tier per level, so you can't get ahead on either. Every new floor adds 10 brainrot slots and is reached by stairs inside the base. Lower floors are walled in all the way up, with big, clear blue-tinted picture windows (slim pillars, low sills) so everyone can see the brainrots inside.

     | Level | Floors | Walls | Cost |
     |---|---|---|---|
     | 1 | 1 | Wood Fence (hop-able) | free |
     | 2 | 2 | Brick Wall | $25K |
     | 3 | 3 | Concrete Wall (too tall to jump) | $1M |
     | 4 | 4 | Steel Wall | $40M |
     | 5 | 5 | Diamond Wall | $1.5B |

   - **Lock:** how long your lasers stay on: 30s, 45s ($5K), 60s ($50K), 90s ($500K), 120s ($5M). After rebirthing you can go further: 150s ($25M, 1 rebirth), 180s ($250M, 2 rebirths), 210s ($2B, 4 rebirths), 240s ($40B, 6 rebirths). Lock upgrades are kept when you rebirth. The Longer Lock gamepass doubles it. The **Infinite Laser Door** (100 R$ gamepass, or 250 Diamonds) keeps your lasers on forever: your base locks itself as soon as you join and the lock pad shows LOCKED FOREVER. Admins can also switch it on or off for anyone (or themselves) with the **Infinite Door ON / OFF** buttons in the admin panel.
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

- **502 copies total.** 500 are in the shop for **50 Robux** (one per player), sold as gamepass `2021528297` (`GamePassId` in `Config.LimitedItems`; a developer product `ProductId` works too). Anyone who owns the pass but doesn't have her yet (e.g. bought it on the website) gets her when they join, plus 2 spare. **Only Corny** can gift her: in the admin panel's **FOUNDER** tab, the **GIFT CIGNA GLAMOURINA** box shows how many are left; type anyone's Roblox username and press **GIFT**. It works even if they aren't in the server: they get her as soon as they join (right away if they're in another server). Each gift comes out of the shop's 500, so the count goes down just like a sale; once those are gone, the 2 spares are used. Ace and other admins don't see the row, and the server refuses them (`Config.LimitedGiver`).
- Every copy has a **serial number** (#1–#500 from the shop stock, #501–#502 the spares), shown on her name tag.
- Stock is shared by **every server** through a DataStore. When someone clicks Buy, a copy is reserved for 5 minutes before the Robux prompt opens, so the game can never sell more than 500. Cancelling releases it.
- She **can't be stolen or sold** and **stays through rebirths**. If your base is full when you buy her, she appears as soon as a slot opens.
- **Income: $2.5K/s, doubling with every rebirth** ($5K at rebirth 1, $10K at 2, … $640K at 8), on top of the rebirth multiplier. In economy simulations she makes about a third of a typical owner's income: progression is roughly 2x faster early on and about 1.4x later, without letting buyers skip the game.

- **Event statue:** a compact spinning statue of her stands right beside the shop tent, with a stock sign above her head that counts down to the next stock update (every server re-checks the shared stock every 5 minutes, `Config.LimitedRefreshSeconds`; sales and gifts in your own server show right away) ("487 / 500 LEFT"), shown even before she goes on sale. Tap or click it to buy her right there.
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

Admins get a red **ADMIN** button on the left. The **Player** box at the top picks who the buttons act on: type `me`, `all`, or the start of someone's name. Below it, the panel is split into tabs, and each job has its own labelled box:

- **PLAYERS:** Money & Currency (give/set cash, set rebirths, give Shards or Diamonds; amounts accept `5000`, `25k`, `2m` or `-500`), Base (base level, lock level, Infinite Door ON/OFF, Clear Base), and Shop Items (Free): give any gamepass (lasts until they leave) or any Robux shop item.
- **EVENTS:** Admin Abuse (minutes + START/END), Drops (Brainrot Rain, Cash Rain with its own cash-per-bag box), Server Luck, and Announce to All Servers.
- **BRAINROTS:** the mutation picker and every brainrot with Give / Spawn / Drop.
- **FOUNDER** (only Corny and Ace see this tab): **CODES** (Corny only) makes codes in-game: a name, Cash / Shards / Diamonds (Diamonds up to 50, Shards up to 5,000) and how many hours it lasts (0 = forever). They save in a DataStore and work in every server, once per player; the list shows each code with a DELETE button. Also: start or end your founder event (with its own minutes box), and pick your event giant's look.

The panel shrinks to fit smaller screens.

Who is an admin: the game's owner (or the group owner, for group games), anyone listed in `Config.AdminUserIds`, and everyone while testing in Studio. The server checks every admin action, so nobody else can use it even with exploits.

### Admin abuse and drops

The admin panel can drop any brainrot (with any mutation) from the sky, start a **Brainrot Rain** of 10 lucky brainrots, or start a **Cash Rain** of 30 cash drops (each worth the amount box). First player to grab a drop keeps it.

There's a weekly **admin abuse** event. Everyone sees a countdown during the hour before it starts and a LIVE banner while it runs. It's set to **Saturday 2:00 PM Central time (Oklahoma)**, and daylight saving is handled automatically. Change it in `Config.AdminAbuse`. Admins can also start or end it any time: type how many minutes in the **Minutes** box in the admin panel, then press **Start Admin Abuse**.

When it starts, everyone gets a huge intro: two white flashes and a red flash over the world, a camera shake, a pulsing rainbow border, spinning light rays, a giant rainbow **ADMIN ABUSE!** title that slams in (with the admin's name if one started it), the boosts popping in one by one (x3 CASH, x3 LUCK, SUPER SPEED, SUPER JUMP, FREE GIFT, GIANT FOUNDERS), lots of confetti and a volley of fireworks over the map. While it runs, the lighting gently cycles party colors and fireworks keep popping. An "ADMIN ABUSE IS OVER" card shows when it ends. (All of it is in `src/client/AdminAbuse.client.luau`.)

**Admin abuse boosts and gift** (tune them in `Config.AdminAbuseBoosts` and `Config.AdminAbuseGift`):
- While it's live, everyone gets **3x cash**, **3x luck** (rare spawns and mutations), walks faster (24 instead of 16) and jumps higher. Carrying a stolen brainrot stays slow so stealing stays fair.
- **Giant founders** (Corny and Ace, in their normal Roblox avatars, about 125 studs tall) stand just outside the fence on opposite sides of the map, like the devs in Grow a Garden. They appear in a puff of sparkles and just stand there doing one Roblox emote after another (wave, cheer, laugh, point), over and over, without moving around.
- Everyone online gets a gift, shown on a pop-up card: **3 Diamonds, 150 Shards and a free brainrot** (rolled with Brainrot Rain luck). It's once per player per week, so starting admin abuse again the same week doesn't hand out more. Players who join while it's live still get theirs.
- Why 3 Diamonds: weekly quests give up to 3 a week, so admin abuse doubles that for anyone who shows up, while the Diamond skins (12 to 120) still take real saving.

### Founders and founder events

The founders are set in `Config.Founders`: **Corny** (Roblox username `Cornywell10`, UserId `469657246`) and **Ace** (`Meishappy2341`). Their giants wear their current Roblox avatars during admin abuse, labelled with their founder names. A UserId (the number in a profile link, `roblox.com/users/<UserId>/profile`) can be used instead of a username. Once a founder has a UserId, only that exact account counts as them, even if someone else later takes their old username; until then the username is used.

To find an outfit id for `OutfitId`: open `https://avatar.roblox.com/v1/users/<UserId>/outfits?itemsPerPage=50` in a browser, find the costume's `"name"`, and copy the `"id"` just before it.

Each founder also has their own event, starring only them in a special event outfit (not their normal avatar). **Each founder can only start their own event** (Corny's or Ace's; the FOUNDER tab shows just theirs as START MY EVENT), and only founders can end them; other admins don't even see the tab. Start one from the admin panel's **FOUNDER** tab (**START CORNY EVENT**, and **END FOUNDER EVENT** to stop it early). It runs for the number of minutes in that tab's **Minutes** box.

### Loading screen

When players join they see the **Corny Games** loading screen (`src/first/LoadingScreen.client.luau`): the Corny Games emblem (gold ring, corn cob, green leaves) drawn from shapes, "CORNY — GAMES —", and a gold loading bar with the percentage, which fills as the game, the map and its images and sounds actually load (at least 2.5 seconds so it doesn't flash, at most 30 so nobody gets stuck), then fades away. To show the real emblem image instead, upload it to Roblox and put its id in `LOGO_IMAGE` at the top of that file.

### Game music

Background music for normal play is set in `Config.GameMusic` (a list of audio ids; shuffled if there are several). It loops quietly, fades out while a founder event plays its own song and back in afterwards, and players can switch it off with the **MUSIC: ON / OFF** button in the bottom right. `assets/music/brainrot_theme.mp3` is the game's own original, copyright-free theme (bouncy marimba melody, plucky chords, bass, claps; 68 seconds, loops): upload it and put its id in `Config.GameMusic`. Until an id is set, there's no music and no button.

### Boost badges

The bottom right of the screen lists every boost that's on right now and how long it has left: admin abuse (x3 cash, x3 luck, speed + jump), x2 luck from Ace's event, Server Luck, your own 2x Cash boost from the Diamond Shop, and the 2x Cash gamepass (forever).

### Announcements to every server

Admins can type **`/announce your message`** (or **`/a your message`**) in chat, or use the **Announce** box in the admin panel. The message drops in as a big card at the top of the screen, and shows in chat, in **every server** of the game. Founders' announcements say "ANNOUNCEMENT FROM CORNY" (or ACE). Messages go through Roblox's text filter first, as Roblox requires, and there's a 5-second cooldown.

- **Corny Event** (5 minutes): an **alien intro** (green flashes, a glitchy sci-fi title, scanlines, INCOMING TRANSMISSION and a UFO flying across, in neon green, lime, teal and alien purple instead of rainbow), **night falls** (the sky becomes a dim neon green glow) and the map goes into **alien chaos**: green searchlights sweep over it from all around the edge, green lights pulse around the map (a slow glow, never a fast strobe), little UFOs zip around the sky and green abduction beams zap random spots. **Night mutation:** each night one mutation is picked at random by percentage (Galaxy 30%, Radioactive 25%, Electric 20%, Void 12%, Cursed 10%, Divine 3%) and is 5 to 8 times more likely on everything that spawns or drops until Corny leaves (day comes back when his event ends); it's announced to everyone and shown as a badge that says UNTIL CORNY LEAVES instead of a timer. The FOUNDER tab's Minutes box starts at 5. Tune it in `NightMutations` in `Config.FounderEvents.Corny`. Morning comes back when the event ends. Its theme song (`MusicId`, Roblox library track 1836281845) fades in and loops until the event ends. `assets/music/alien_invasion.mp3` is an original, copyright-free alien-invasion track made for it (theremin lead, pulsing synth bass, arpeggios, drums and laser zaps, 66 seconds, loops): upload it and put its id in Corny's `MusicId` to use it instead. Then **two UFOs** fly in, one on each side of the map, and hover over the grass just behind the bases; a glowing tractor beam shines down from each, and Corny appears inside both, about 120 studs tall, **floating in the beam** in a wise sage pose (legs folded back, hands together in front) with a glowing rainbow outline (no sparkles), gently bobbing. Every second or two he throws something in a big arc onto the map: cash bags, or brainrots with a 45% Candy and 8% Rainbow mutation chance (a beam shows where each one will land). When it ends he's beamed back up, the beams switch off, the UFOs fly away and the sky goes back to normal. (A different pose can be used by putting an animation id in `PoseAnimationId`.)
- **Ace's Event** (5 minutes): "ACE'S ADMIN EVENT!" intro in pinks, then the sky turns soft neon pink, **knee-deep water** flows out over the whole map and **lily pads** (some with pink water lilies), each with a glowing pink aura, drop flat into it and bob, and **pink sparkly dust** drifts everywhere. A giant Ace (about 120 studs, in his event look) appears on each side of the map standing in the water, slowly spinning on the spot like a pirouette, while **Cigna Glamourina flies around him spinning ballet pirouettes and leaps**. The whole server gets **x2 luck** while it runs, and a **Ballerina Capuchina with a rare mutation** (Smiley or rarer) is guaranteed to come down the conveyor. **Theme song:** `assets/music/ballet_action.mp3` is an original, copyright-free ballet-style waltz made for this game (music-box celesta, pizzicato strings, light percussion, 44 seconds, loops). For now Ace's event plays Roblox library track 1836281845 (the same as Corny's). To use the ballet track instead, upload it to Roblox (Creator Hub > Creations > Audio, or Studio's Asset Manager), then put its id in `MusicId` in `Config.FounderEvents.Ace` (e.g. `"rbxassetid://1234567890"`); it fades in and out with the event. (`compose_ballet_action.py` next to it is the script that made it.)
- **Event music:** in the **FOUNDER** tab, paste an uploaded sound's ID into **MY EVENT MUSIC** and press **SET**; it plays during your event in every server (empty + SET goes back to the default). Corny's event plays "Tractor Beam" (`assets/music/alien_abduction_1_tractor_beam.mp3`) by default, and the lobby plays "Chill Plaza" (`Config.GameMusic`).
- **Event look:** in the admin panel's **FOUNDER** tab, either put on your event outfit in game and press **USE WHAT I'M WEARING NOW**, or paste a costume's outfit ID (or its whole link) into the box and press **USE OUTFIT**. **RESET TO MY NORMAL AVATAR** forgets the saved look. With **USE WHAT I'M WEARING NOW**, the event giant becomes an exact copy of how your character looks right then, and it's saved for good (change it any time by saving again). Until a look is saved, the giant copies your character if you're in the server, then your outfit id (`OutfitId` in `Config.FounderEvents`), then your Roblox avatar, and for Corny last of all a look-alike built from parts.
- **Ace's event** comes next: it slots into `Config.FounderEvents` the same way.

## Quests, Shards, Diamonds and the Diamond Shop

Fair progression for free-to-play players. None of this can be bought with Robux.

- **Daily quests:** 3 a day, the same for everyone, and new ones at midnight Oklahoma time. Each pays **10 Shards**.
- **Weekly quests:** 3 a week, new every Monday, and much harder. Each pays **1 Diamond + 100 Shards**. Diamonds only come from weekly quests and the weekly admin abuse gift.
- **Wall skins:** open the **QUESTS** button to see them. They're a ladder: you have to own the one before to buy the next. Shard skins: Red Brick 250 → Candy Pink 600 → Frozen Ice 1,200 → Jungle Stone 2,000 → Cyber Neon 3,500 (about 11 weeks of Shards in all). Diamond skins: Royal Gold 12 → Galaxy 25 → Crystal Palace 45 → Lava Core 75 → Celestial 120, the long-term flex. **Corny Gold** is Corny's own skin, free for him and hidden from everyone else: navy walls, gold trim, corn cobs on every pillar, and the Corny Games logo on the windows. The server checks it's really Corny (`Config.Founders`) before he can claim or wear it, and takes it off any other base. Skins only change the look; your base level still sets the wall height. Every floor of your base matches your skin. With Classic, floors are the same grey in your walls' material (wood, brick, concrete, steel or diamond).
- **Shop tent:** a blue-and-cream striped circus-style tent (like Bee Swarm's) past the bases near the cave the brainrots come out of, with a little spinning diamond on top.
  - The left counter spends Diamonds: Shard Pouch (2 for 400 Shards), 2x Cash for 30 min (3), Server Luck for everyone for 15 min (5), 2x Cash for 3 hours (12), the **Infinite Laser Door** (250, one-time, the same as the gamepass), plus the Diamond wall skins.
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

- **Passes**: create `2x Cash`, `VIP`, `Longer Lock` and `Infinite Laser Door`.
- **Developer Products**: create `Cash Bag`, `Cash Vault`, `Server Luck`, and `Instant Lock`.

Paste each ID into `Config.GamePasses` / `Config.Products` in `src/shared/Config.luau`. Items left at `Id = 0` show as **SOON** in the shop.

Suggested prices:

| Item | Type | Price |
|---|---|---|
| 2x Cash | Pass | 299 R$ |
| VIP (+2 base slots, VIP tag) | Pass | 399 R$ |
| Longer Lock (2x lock time) | Pass | 149 R$ |
| Infinite Laser Door (lasers never turn off) | Pass | 100 R$ (or 250 Diamonds in the Diamond Shop) |
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
