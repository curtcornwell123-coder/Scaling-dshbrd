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
     | 2 | 2 | Brick Wall | $50K |
     | 3 | 3 | Concrete Wall (too tall to jump) | $2.5M |
     | 4 | 4 | Steel Wall | $100M |
     | 5 | 5 | Platinum Wall (and the roof) | $4B |
     | 6 | 6 | Royal Marble Wall (**VIP only**) | $150B |
     | 7 | 7 | Golden Palace Wall (**VIP only**) | $6T |

     The roof goes on at level 5 and moves up with the VIP floors.

   - **Lock:** how long your lasers stay on: 30s, 45s ($5K), 60s ($50K), 90s ($500K), 120s ($5M). After rebirthing you can go further: 150s ($25M, 1 rebirth), 180s ($250M, 2 rebirths), 210s ($2B, 4 rebirths), 240s ($40B, 6 rebirths). Lock upgrades are kept when you rebirth. The Longer Lock gamepass doubles it. The **Infinite Laser Door** (gamepass, or 12,500 Shards in the Shard Shop) keeps your lasers on forever: your base locks itself as soon as you join and the lock pad shows LOCKED FOREVER. Admins can also switch it on or off for anyone (or themselves) with the **Infinite Door ON / OFF** buttons in the admin panel.
   - **Stair carpets** come from rebirths: plain wood at first, then a new carpet every 5 rebirths: Red (5), Royal (10), Golden (15), Crystal (20) and Rainbow (25).
6. **Lock.** Step on the red **LOCK** pad. Red laser beams cross your entrance and zap anyone else who walks through. After the lock ends it recharges for 30s, and that's when you're vulnerable.
7. **Sell** your own brainrots for half price (hold **F**).
8. **Rebirth.** Reset your cash, floors (base level) and base brainrots for a permanent income multiplier (+0.5x each time; the first rebirth costs $2.5M and each one after costs 6x more). Your **vault** and its brainrots, lock upgrades, skins, passes and limited brainrots all stay.

Rare spawns (Legendary and up), big buys, big steals, rebirths and Server Luck purchases are announced to the whole server.

### Rarities and conveyor odds

| Rarity | Chance | Server Luck | Price range | Income |
|---|---|---|---|---|
| 🟩 Common | 60% | 42.8% | free – $250 | $1–9/s |
| 🟦 Rare | 25% | 35.6% | $400 – $3.3K | $8–50/s |
| 🟪 Epic | 10% | 14.4% | $5K – $40K | $60–340/s |
| 🟨 Legendary | 4% | 5.7% | $75K – $700K | $500–3.8K/s |
| 🟥 Mythic | 0.9% | 1.3% | $1.2M – $15M | $4.8K–50K/s |
| ⬛ Secret | 0.1% | 0.14% | $25M – $200M | $120K–900K/s |
| 🌟 Celestial | 0.025% (1 in 4,000) | 0.036% | $300M – $1B | $1.3M–4M/s |
| 💖 Event Special | not on the conveyor | | Robux | see below |

### Launch event: Cigna Glamourina (limited)

- **502 copies total.** 500 are in the shop for **50 Robux** (one per player), sold as gamepass `2021528297` (`GamePassId` in `Config.LimitedItems`; a developer product `ProductId` works too). Anyone who owns the pass but doesn't have her yet (e.g. bought it on the website) gets her when they join, plus 2 spare. **Only Corny** can gift her: in the admin panel's **FOUNDER** tab, the **GIFT CIGNA GLAMOURINA** box shows how many are left; type anyone's Roblox username and press **GIFT**. It works even if they aren't in the server: they get her as soon as they join (right away if they're in another server). Each gift comes out of the shop's 500, so the count goes down just like a sale; once those are gone, the 2 spares are used. Ace and other admins don't see the row, and the server refuses them (`Config.LimitedGiver`).
- Every copy has a **serial number** (#1–#500 from the shop stock, #501–#502 the spares), shown on her name tag.
- Stock is shared by **every server** through a DataStore. When someone clicks Buy, a copy is reserved for 5 minutes before the Robux prompt opens, so the game can never sell more than 500. Cancelling releases it.
- She **can't be stolen or sold** and **stays through rebirths**. If your base is full when you buy her, she appears as soon as a slot opens.
- **Income: $2.5K/s, doubling with every rebirth** ($5K at rebirth 1, $10K at 2, … $640K at 8), on top of the rebirth multiplier. In economy simulations she makes about a third of a typical owner's income: progression is roughly 2x faster early on and about 1.4x later, without letting buyers skip the game.

- **Event statue:** a compact spinning statue of her stands right beside the shop tent (the next event's statue stands next to hers), with a stock sign above her head that counts down to the next stock update (every server re-checks the shared stock every 5 minutes, `Config.LimitedRefreshSeconds`; sales and gifts in your own server show right away) ("487 / 500 LEFT"), shown even before she goes on sale. Tap or click it to buy her right there.
- **Mutation roll:** every copy rolls a mutation when you get it (normal odds), plus a **1% chance of MAGIC**, an event-only mutation (x8 income, purple-to-teal shimmer, swirling stars, floating orbs). Admins can also turn a player's Cigna Magic with **Give MAGIC (event)** in the admin panel (it needs the player to own her). Change the featured event with `Config.CurrentEvent`.

To put her on sale: create a Developer Product named "Cigna Glamourina" priced at **50 Robux**, and paste its ID into `Config.LimitedItems.CignaGlamourina.ProductId`.

### Next event: 67 Nights Deer (limited)

- A skinny dark-brown forest deer with a huge round head, staring saucer eyes, a pink muzzle and gaping mouth, branching antlers, and freakishly long arms that end in fanned-out claws.
- **1,002 copies** (1,000 for **50 Robux** + 2 spares Corny can gift). Otherwise it works like Cigna: serial numbers, can't be stolen or sold, stays through rebirths, rolls a normal mutation when you get it (MAGIC stays Cigna's).
- **Income: $3K/s, doubling with every rebirth.**
- **Its own statue** spins right beside Cigna's, with its own live stock sign ("NEXT EVENT … 1000 / 1000 LEFT … Coming soon!"). The Sell Stand moved a little further along to make room. `Config.NextEvent` picks which brainrot stands there.
- **On sale** as gamepass `2023520328` (50 Robux): the sign shows "LIMITED EVENT" and tapping the statue buys it. To also give it the shop's FEATURED spot, set `Config.CurrentEvent = "SixtySevenNights"`. Corny can also give it from the admin panel.

### Mutations

Any brainrot on the conveyor can roll a mutation, and **mutations stack**: after one rolls there's a 12% chance another lands on top (up to 3, e.g. "Gold Galaxy"). Each mutation adds a percentage of the brainrot's base income and price, and a stack adds them all up (Gold +100% and Galaxy +600% make +700%, so 8x the base). The rarest one in the stack leads the look; the others add their particles. Server Luck doubles these chances. Corny's admin panel can stack up to 3 mutations on any brainrot it gives, spawns or drops, and add them onto an event brainrot someone already owns (see Admin panel).

| Mutation | Chance | Bonus (income & price) | Look |
|---|---|---|---|
| ✨ Gold | 4% | +100% | Shiny gold foil |
| 🍬 Candy | 2.5% | +150% | Pastel candy colors, sprinkles |
| 🔷 Crystal | 2% | +200% | See-through ice-blue glass |
| ❄️ Frozen | 2% | +200% | Ice, falling snowflakes |
| ⭐ Sparkle | 1.5% | +300% | Its own colors, brighter, twinkling stars |
| ⚡ Electric | 1.2% | +350% | Yellow charge, crackling sparks |
| 😊 Smiley | 1% | +400% | Sunny yellow, little smiley faces floating around it |
| ☢️ Radioactive | 0.9% | +450% | Toxic green, glowing spots, green fumes |
| 🔥 Lava | 0.8% | +400% | Cracked lava rock, on fire |
| 🌌 Galaxy | 0.6% | +600% | Deep-space glass, drifting stars |
| 💀 Cursed | 0.5% | +700% | Blood-dark stone, black smoke, embers |
| 🌈 Rainbow | 0.3% | +900% | Cycles through every color |
| 🕳️ Void | 0.2% | +1100% | Pitch black, purple outline, dark matter pulled in |
| 😇 Divine | 0.1% | +1400% | White marble, golden halo, holy light |
| ✨🔮 Magic | 1% when you get the event brainrot (event only) | +700% | Purple-teal shimmer, a full magic circle with runes, orbs, pink glitter and a star fountain |

The rarer the mutation, the bigger the show: rare ones (Radioactive to Cursed) add a glowing aura ring and rising motes; ultra rare ones (Rainbow, Void, Divine) add a second ring, a column of light and a sparkle crown; Magic gets the whole spell. Galaxy and rarer spawns are announced to the whole server. About 1 in 6 conveyor brainrots is mutated (1 in 3 with Server Luck).

### Using real 3D models

Every brainrot has its own built-in design, built smooth and rounded (rounded boxes, soft domed cylinders, smooth cones). To swap one for a 3D model:

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

## Corny's Ban Hammer

Only Corny (`Config.HammerOwner`) gets a **Ban Hammer** in his backpack every time he spawns. While it's in his hand he also has three powers, with controls that switch to whatever he's using (a hint bar shows the keys or buttons; phones and tablets get on-screen buttons):

| Power | Keyboard | Controller | Phone / tablet |
|---|---|---|---|
| **FLY** (on/off; fly where you move) | F (Space / Q = up / down) | Y (A / B = up / down) | FLY button (▲ ▼ buttons) |
| **ZOOM** super sprint (on/off) | G | X | ZOOM button |
| **SLAM**: a shockwave across the whole map flings every other player sky-high, with a camera shake for everyone (15s recharge) | R | R1 | SLAM button |

Swinging it sends a red shockwave and flings everyone in front of him into the air, tumbling and spinning with a burst of sparks (anyone carrying a stolen brainrot drops it and it runs home), and cracks a glowing line straight along the ground for 70 studs: anyone standing on the line takes 35 damage and gets knocked off it. It doesn't ban anyone. Range, cooldown and force are in `Config.Hammer*`.

## Walking home

Brainrots you buy off the conveyor (or grab from a drop) **walk** to your base instead of zipping there: across the grass to your door, inside, up the stairs floor by floor, and onto their pedestal (`WALK_SPEED` in Main). Nobody can steal or sell one while it's still walking.

## Door lock button

Just inside every base's door, on the right, there's a big round button (owner only). Press it to **lock** the base right away (same as the lock pad, with the same recharge), or press it while locked to **open the door early** (for friends); opening early starts the recharge, so it can't stretch a lock out. With the Infinite Laser Door it simply opens and closes. The button glows red when you can lock and green while locked.

## Sprint

Hold **Shift** on a keyboard, tap the round **SPRINT** button on a phone or tablet (just left of the jump button; tap again to stop), or **click the left stick** on a controller (click again to stop). Sprinting is 1.45x faster (`Config.SprintMultiplier`), on top of admin abuse's speed boost, but you can't sprint while carrying a stolen brainrot. On phones and tablets the music button and boost badges sit at the top right, out of the way.

### Brainrots (100)

- **Free brainrots:** every 5th brainrot on the conveyor is a free **Patatino Piccolino** that anyone can take for **$0** (the prompt says *Take (FREE)*), so new players can start earning right away. Free ones never come from drops or gifts, sell for $0 and don't count toward buying quests.
- **40 new ones this update**, each with its own model:
  - Common: Cipollino Piangino, Carotino Corridore, Pomodorino Rimbalzo, Biscottino Ballerino, Fungo Funghetto, Uovo Sbadiglio, Peperone Piccante, Cuscinetto Ronfone.
  - Rare: Pretzelino Annodato, Melanzana Mafiosa, Avocadino Palestrato, Ananasso Surfista, Lumacone Turbo, Polpetto Ottopodo, Zucchino Zombie, Fragolina Ninja.
  - Epic: Gelato Vulcano, Panda Bambucco, Robo Moka, Cocco Bello, Spaghettosauro, Fenicottero Flamenco, Gufo Professore.
  - Legendary: Leone Lasagnone, Squalo Scarpone, Granchio Corazzato, Unicornino Arcobaleno, Pinguino Pilota, Polipo Pianista, Tigre Tiramisù.
  - Mythic: Fenice Focaccia, Kraken Carbonara, Golem Gorgonzola, Cerbero Calzone, Leviatano Linguine.
  - Secret: Re Ravioli Supremo, Fantasma Fettuccine, Galassia Gnocchi; Imperatore Pizzone and Omega Brainrotto ($600M, $2.5M/s) are now Celestial.
- **32 meme classics** (the famous Italian brainrot characters, built in the game's own smooth style):
  - Common: Lirilì Larilà, Tim Cheese, Pipi Kiwi, Talpa di Ferro, Svinino Bombondino.
  - Rare: Trippi Troppi, Bandito Bobritto, Cacto Hipopotamo, Ta Ta Ta Sahur, Perochello Lemonchello, Brr Brr Patapim.
  - Epic: Cappuccino Assassino, Brri Brri Bicus Dicus Bombicus, Trulimero Trulicina, Chimpanzini Bananini, Salamino Penguino, Zibra Zubra Zibralini.
  - Legendary: Burbaloni Loliloli, Chef Crabracadabra, Glorbo Fruttodrillo, Blueberrinni Octopusini, Orangutini Ananassini, Lionel Cactuseli.
  - Mythic: Bombardiro Crocodilo, Bombombini Gusini, Frigo Camelo, Rhino Toasterino, Cocofanto Elefanto.
  - Secret: La Vacca Saturno Saturnita, Trenostruzzo Turbo 3000, Graipuss Medussi, and **La Grande Combinasion** ($1B, $4M/s, now the top Celestial).
- **Tung Tung Tung Sahur** (Legendary, $350K, $2K/s): the wooden log with a big grin and a baseball bat.
- **Bubblegummo Blobbo** (Common, $150, $5/s), **Gelatino Gigante** (Rare, $2K, $32/s), **Donutto Dynamo** (Epic, $25K, $220/s), **Sushito Samurai** (Legendary, $500K, $2.8K/s), **Tacoraptor Supremo** (Mythic, $8M, $28K/s), **Astronauto Panino** (Secret, $120M, $550K/s): each the new top of its rarity, priced like the rest of the economy.

## Admin panel

Admins get a red **ADMIN** button on the left. The **Player** box at the top picks who the buttons act on: type `me`, `all`, or the start of someone's name. Below it, the panel is split into tabs, and each job has its own labelled box:

- **PLAYERS:** **Reset Player** at the top (Corny only): type a name (or `me`) in its own box and tap RESET twice; it wipes that player in this server back to a new save (money, base, vault, rebirths, stats; their Robux purchases stay). **Moderation** (Kick with an optional reason; Ban, tapped twice, kicks them and keeps them out of the game for good in every server, even if they're offline; Unban lets them back. Nobody can kick or ban Corny or themselves; only Corny can act on a founder, and only founders on another admin. Roblox's own chat commands don't work in this game, so use these), Money & Currency (give/set cash, set rebirths, give Shards; amounts accept `5000`, `25k`, `2m` or `-500`), Base (base level, lock level, Infinite Door ON/OFF, Clear Base), and Shop Items (Free): give any gamepass (lasts until they leave) or any Robux shop item.
- **EVENTS:** Admin Abuse (minutes + START/END), Drops (Brainrot Rain, Cash Rain with its own cash-per-bag box), Server Luck, and Announce to All Servers.
- **BRAINROTS:** every brainrot with Give / Spawn / Drop. Corny also gets a **🧬** button on each row: tap it, pick up to 3 mutations (the button shows how many and takes the rarest one's color), and they go with that row's Give, Spawn and Drop (CLEAR resets them). The event brainrots (Cigna, 67 Nights Deer) are listed for Corny too, with **ADD** instead: it stacks the picked mutations onto the copy the player already owns, same serial, no new copy (Cigna can pick MAGIC here). New picks go first, so on a full stack of 3 they replace the commonest old ones. **Give MAGIC (event)** is still at the top.
- **FOUNDER** (only Corny and Ace see this tab): **SECURITY** (Corny only): **LOCK ALL ADMIN PANELS** takes the admin panel away from everyone but Corny (Ace and mods too), in every server, until he unlocks it; **CODES** (Corny only) makes codes in-game: a name, Cash / Shards (Shards up to 5,000) and how many hours it lasts (0 = forever). They save in a DataStore and work in every server, once per player; the list shows each code with a DELETE button. Also: start or end your founder event (with its own minutes box), and pick your event giant's look.

The panel shrinks to fit smaller screens.

Who is an admin: the founders, the game's owner (or the group owner, for group games), and everyone while testing in Studio. **Mods** (Roblox user IDs in `Config.AdminUserIds`, e.g. `3272219254`) get a small blue **MOD** button instead: the **MOD PANEL** has just Kick, Ban (tap twice), Unban and Announce, and the server refuses anything else from a mod. The server checks every admin action, so nobody else can use it even with exploits.

### Admin abuse and drops

The admin panel can drop any brainrot (with any mutation) from the sky, start a **Brainrot Rain** of 5 lucky brainrots, or start a **Cash Rain** of 10 cash drops (each worth the amount box). First player to grab a drop keeps it.

**Economy pace:** every brainrot earns 60% of its listed income (`Config.IncomeScale`; prices stay the same, so everything takes longer to afford), base levels and rebirths cost more (rebirth starts at $2.5M and grows 6x each time), and drops are smaller: founder-event throws come about half as often, are brainrots only 15% of the time (with less luck), and their cash bags are worth 8 seconds of the grabber's own income (at least $200) instead of a flat amount. Income is capped far past anything reachable (`Config.MaxIncome`), so even a huge admin-set rebirth count can't overflow cash or the collect pad to ∞.

There's a weekly **admin abuse** event. Everyone sees a countdown during the hour before it starts and a LIVE banner while it runs. It's set to **Saturday 2:00 PM Central time (Oklahoma)**, and daylight saving is handled automatically. Change it in `Config.AdminAbuse`. Admins can also start or end it any time: type how many minutes in the **Minutes** box in the admin panel, then press **Start Admin Abuse**.

When it starts, everyone gets a huge intro: two white flashes and a red flash over the world, a camera shake, a pulsing rainbow border, spinning light rays, a giant rainbow **ADMIN ABUSE!** title that slams in (with the admin's name if one started it), the boosts popping in one by one (x3 CASH, x3 LUCK, SUPER SPEED, SUPER JUMP, FREE GIFT, GIANT FOUNDERS), lots of confetti and a volley of fireworks over the map. While it runs, the lighting gently cycles party colors and fireworks keep popping. An "ADMIN ABUSE IS OVER" card shows when it ends. (All of it is in `src/client/AdminAbuse.client.luau`.)

**Admin abuse boosts and gift** (tune them in `Config.AdminAbuseBoosts` and `Config.AdminAbuseGift`):
- While it's live, everyone gets **3x cash**, **3x luck** (rare spawns and mutations), walks faster (24 instead of 16) and jumps higher. Carrying a stolen brainrot stays slow so stealing stays fair.
- **Giant founders** (Corny and Ace, in their normal Roblox avatars, about 125 studs tall) stand just outside the fence on opposite sides of the map, like the devs in Grow a Garden. They appear in a puff of sparkles and just stand there doing one Roblox emote after another (wave, cheer, laugh, point), over and over, without moving around.
- Everyone online gets a gift, shown on a pop-up card: **100 Shards and a free brainrot** (rolled with a little extra luck). It's once per player per week, so starting admin abuse again the same week doesn't hand out more. Players who join while it's live still get theirs.

### Founders and founder events

The founders are set in `Config.Founders`: **Corny** (Roblox username `Cornywell10`, UserId `469657246`) and **Ace** (`Meishappy2341`, UserId `8504983999`). Their giants wear their current Roblox avatars during admin abuse, labelled with their founder names. A UserId (the number in a profile link, `roblox.com/users/<UserId>/profile`) can be used instead of a username. Once a founder has a UserId, only that exact account counts as them, even if someone else later takes their old username; until then the username is used.

To find an outfit id for `OutfitId`: open `https://avatar.roblox.com/v1/users/<UserId>/outfits?itemsPerPage=50` in a browser, find the costume's `"name"`, and copy the `"id"` just before it.

Each founder also has their own event, starring only them in a special event outfit (not their normal avatar). **Each founder starts their own event** (the FOUNDER tab shows START MY EVENT), and **Corny, the head founder (`Config.HeadFounder`), can also start Ace's**; Ace can't start Corny's, and only founders can end them; other admins don't even see the tab. Start one from the admin panel's **FOUNDER** tab (**START CORNY EVENT**, and **END FOUNDER EVENT** to stop it early). It runs for the number of minutes in that tab's **Minutes** box.

### 99 Nights (any founder)

A shared founder event any founder can start from the FOUNDER tab (**START 99 NIGHTS**). It plays differently from the other events: **nothing is thrown**, and there's no night mutation.

- **The setting:** night falls, a cold blue fog rolls in, snow drifts down and fireflies glow around you. Five **campfires** burn around the lobby, each with a glowing ring showing the safe zone. A creepy intro (no fireworks or confetti).
- **The hunt:** a giant 67 Nights Deer (about 105 studs tall) prowls each side of the map. Every 40 seconds it **screams and hunts**: the screen edges pulse red with an 8-second countdown, "RUN TO A CAMPFIRE!", and the deer races around glowing bright red. When it strikes, anyone **inside a campfire ring** survives the night and gets **5 Shards**; anyone caught in the dark gets a jump scare ("THE DEER GOT YOU!") and is thrown, dropping anything they were carrying (nothing is lost from their base).
- **Luck grows every night:** each night survived gives the whole server **+0.25x luck**, up to **x3**. The event label counts the nights ("99 NIGHTS · NIGHT 3"), and a banner announces each night survived.
- **Supply chests:** glowing wooden chests appear around the map (up to 6 at once). Hold to open: the first player to open one gets **15 seconds of their own income** (at least $300) or, 1 time in 5, a **lucky brainrot straight into their base**.
- When it ends: "MORNING CAME! YOU SURVIVED!" Tune it in `Config.Nights99`.

### Loading screen

When players join they see the **Corny Games** loading screen (`src/first/LoadingScreen.client.luau`): the Corny Games emblem (gold ring, corn cob, green leaves) drawn from shapes, "CORNY — GAMES —", and a gold loading bar with the percentage, which fills as the game, the map and its images and sounds actually load (at least 2.5 seconds so it doesn't flash, at most 30 so nobody gets stuck), then fades away. To show the real emblem image instead, upload it to Roblox and put its id in `LOGO_IMAGE` at the top of that file.

### Game music

Background music for normal play is set in `Config.GameMusic` (a list of audio ids; shuffled if there are several). It loops quietly, fades out while a founder event plays its own song and back in afterwards, and players set its volume (0–100%, saved) in **Settings** (the ⚙️ button in the corner). `assets/music/brainrot_theme.mp3` is the game's own original, copyright-free theme (bouncy marimba melody, plucky chords, bass, claps; 68 seconds, loops): upload it and put its id in `Config.GameMusic`. Until an id is set, there's no music and no button.

### Money bars

Your cash (with income per second), Shards, and base slots / steals sit in slim bars in the top-left corner, so the middle of the screen stays clear.

### Game updates

When a server closes for an update, everyone sees a **GAME UPDATING!** screen (starry backdrop, rainbow title, spinning gear and a filling bar) while their progress saves, then gets a friendly "just got updated, rejoin to play the new version" message instead of a plain "server shut down".

### Event labels and boost badges

Small pills at the top of the screen show what's on in the server, with time left: admin abuse (and its countdown in the last hour), a founder event ("until Corny leaves" for his long runs), its night mutation, and Server Luck. The bottom right lists every boost you have and how long it lasts: admin abuse (x3 cash, x3 luck, speed + jump), x2 luck from Ace's event, Server Luck, your own 2x Cash boost from the Shard Shop, and the 2x Cash gamepass (forever).

### Settings

The ⚙️ button (bottom right; top right on phones) opens Settings: a **music volume** slider (game and event music) and, for VIPs, a switch to **hide the VIP crown and tag**. Both are saved.

### Announcements to every server

Admins can type **`/announce your message`** (or **`/a your message`**) in chat, or use the **Announce** box in the admin panel. The message drops in as a big card at the top of the screen, and shows in chat, in **every server** of the game. Founders' announcements say "ANNOUNCEMENT FROM CORNY" (or ACE). Messages go through Roblox's text filter first, as Roblox requires, and there's a 5-second cooldown.

- **Corny Event** (5 minutes): an **alien intro** (green flashes, a glitchy sci-fi title, scanlines, INCOMING TRANSMISSION and a UFO flying across, in neon green, lime, teal and alien purple instead of rainbow), **night falls** (the sky becomes a dim neon green glow) and the map goes into **alien chaos**: green searchlights sweep over it from all around the edge, green lights pulse around the map (a slow glow, never a fast strobe), little UFOs zip around the sky and green abduction beams zap random spots. **Night mutation:** each night one mutation is picked at random by percentage (Galaxy 30%, Radioactive 25%, Electric 20%, Void 12%, Cursed 10%, Divine 3%) and is 5 to 8 times more likely on everything that spawns or drops until Corny leaves (day comes back when his event ends); it's announced to everyone and shown as a badge that says UNTIL CORNY LEAVES instead of a timer. The FOUNDER tab's Minutes box starts at 5. Tune it in `NightMutations` in `Config.FounderEvents.Corny`. Morning comes back when the event ends. Its theme song (`MusicId`, Roblox library track 1836281845) fades in and loops until the event ends. `assets/music/alien_invasion.mp3` is an original, copyright-free alien-invasion track made for it (theremin lead, pulsing synth bass, arpeggios, drums and laser zaps, 66 seconds, loops): upload it and put its id in Corny's `MusicId` to use it instead. Then **two UFOs** fly in, one on each side of the map, and hover over the grass just behind the bases; a glowing tractor beam shines down from each, and Corny appears inside both, about 120 studs tall, **floating in the beam** in a wise sage pose (legs folded back, hands together in front) with a glowing rainbow outline (no sparkles), gently bobbing. Every second or two he throws something in a big arc onto the map: cash bags, or brainrots with a 45% Candy and 8% Rainbow mutation chance (a beam shows where each one will land). When it ends he's beamed back up, the beams switch off, the UFOs fly away and the sky goes back to normal. (A different pose can be used by putting an animation id in `PoseAnimationId`.)
- **Ace's Event** (5 minutes): "ACE'S ADMIN EVENT!" intro in pinks, then the sky turns soft neon pink, **knee-deep water** flows out over the whole map and **lily pads** (some with pink water lilies), each with a glowing pink aura, drop flat into it and bob, and **pink sparkly dust** drifts everywhere. A giant Ace (about 120 studs, in his event look) appears on each side of the map standing in the water, slowly spinning on the spot like a pirouette, while **Cigna Glamourina flies around him spinning ballet pirouettes and leaps**. The whole server gets **x2 luck** while it runs, and a **Ballerina Capuchina with a rare mutation** (Smiley or rarer) is guaranteed to come down the conveyor. **Theme song:** `assets/music/ballet_action.mp3` is an original, copyright-free ballet-style waltz made for this game (music-box celesta, pizzicato strings, light percussion, 44 seconds, loops). For now Ace's event plays Roblox library track 1836281845 (the same as Corny's). To use the ballet track instead, upload it to Roblox (Creator Hub > Creations > Audio, or Studio's Asset Manager), then put its id in `MusicId` in `Config.FounderEvents.Ace` (e.g. `"rbxassetid://1234567890"`); it fades in and out with the event. (`compose_ballet_action.py` next to it is the script that made it.)
- **Event music:** in the **FOUNDER** tab, paste an uploaded sound's ID into **MY EVENT MUSIC** and press **SET**; it plays during your event in every server (empty + SET goes back to the default). Corny's event plays "Tractor Beam" (`assets/music/alien_abduction_1_tractor_beam.mp3`) by default, and the lobby plays "Chill Plaza" (`Config.GameMusic`).
- **Event look:** in the admin panel's **FOUNDER** tab, either put on your event outfit in game and press **USE WHAT I'M WEARING NOW**, or paste a costume's outfit ID (or its whole link) into the box and press **USE OUTFIT**. **RESET TO MY NORMAL AVATAR** forgets the saved look. With **USE WHAT I'M WEARING NOW**, the event giant becomes an exact copy of how your character looks right then, and it's saved for good (change it any time by saving again). Until a look is saved, the giant copies your character if you're in the server, then your outfit id (`OutfitId` in `Config.FounderEvents`), then your Roblox avatar, and for Corny last of all a look-alike built from parts.
- **Ace's event** comes next: it slots into `Config.FounderEvents` the same way.

## Quests, Shards and the Shard Shop

Fair progression for free-to-play players. None of this can be bought with Robux. (Diamonds were removed: old saves turned every Diamond into 50 Shards.)

- **Daily quests:** 3 a day, the same for everyone, and new ones at midnight Oklahoma time. Each pays **10 Shards**.
- **Weekly quests:** 3 a week, new every Monday, and much harder. Each pays **150 Shards**. With the weekly admin abuse gift (100) that's about 760 Shards a week at most.
- **Wall skins:** open the **QUESTS** button to see them. They're one ladder: you need the one before to buy the next (owning any higher skin counts, so new skins in between never lock anyone out). Picnic Checker 80 → Red Brick 250 → Mint Stripes 400 → Bubblegum Dots 550 → Candy Pink 700 → Smiley Sunshine 900 → Frozen Ice 1,200 → Royal Gold 1,500 → Jungle Stone 1,900 → Galaxy 2,400 → Cyber Neon 3,000 → Crystal Palace 3,700 → Royal Argyle 4,500 → Lava Core 5,500 → Celestial 7,000 → Rainbow Royale 9,000 → Void Emperor 12,000. Many have **patterns** on the floors and wall bands (checker, stripes, dots, argyle, smiley faces; Rainbow Royale's stripes are every color). **Beta Tester** (white, cyan glow, a floating 🧪 BETA TESTER sign) is free for testers (`Config.TesterUserIds`, and admins), and **Moderator** (black metal, red glow, a floating 🛡️ MODERATOR sign) is free for every admin; nobody else sees them. **Glamourina Moon** is Ace's own skin: pink walls with glowing magenta trim, pink dots, **four-leaf clovers on every pillar**, and a big glowing crescent moon over the base that gets a halo and sparkles once the base is fully upgraded. **Corny Gold** is Corny's own skin: navy walls, gold trim, corn cobs on every pillar, and the Corny Games logo on the windows. The server checks it's really them before they can claim or wear their skin. Skins only change the look; your base level still sets the wall height. Every floor (and the vault) matches your skin.
- **Shop tent:** a blue-and-cream striped circus-style tent past the bases near the cave the brainrots come out of, with a spinning shard crystal on top.
  - The left counter is the **Shard Shop**: 2x Cash for 30 min (150), Server Luck for everyone for 15 min (250), 2x Cash for 3 hours (600) and the **Infinite Laser Door** (12,500, one-time, the same as the gamepass).
  - The right counter opens the **Robux shop**: the limited event brainrot, gamepasses and boosts.

Quest pools, goals, rewards, skins and shop items are all in `Config.luau`.

## The vault

Every base has a gold **🔒 VAULT** hatch in the ground floor. The owner clicks it to go down to a vault room deep under the base, with walls and floor in the base's skin, a big round vault door, and gold-rimmed podiums. Hold **V** (Move to Vault) on a brainrot in your base to put it on a podium; in the vault, **Move to Base** brings it back up. Vault brainrots **keep earning, can't be stolen or sold, and stay through rebirths**. You start with 2 podiums; buy more at the upgrade post (VAULT card): 4 ($250K), 6 ($10M), 8 ($500M), 10 ($25B), 12 ($1T). Vault upgrades are kept through rebirths too. Climb the ladder (EXIT) to go back up. Only the owner can open a vault.

## Rebirth rewards

The more you rebirth, the cooler your base looks (in your stair carpet's colors): glowing pedestal rims (1 rebirth), torches by the door (3), banners showing your rebirth count (5), guardian pillars with glowing orbs (10), a royal runway with lamps (15), a sky beacon everyone can see (20), and at 25 the **King's balcony** over the door with a **throne**: a gem-crowned throne in your carpet colors, Corny's made of corn cobs and Ace's a giant pink bloom. Stand on the gold pad below to sit on it (owner only).

## Index

The orange **INDEX** button opens a collection book. One rarity page at a time shows every brainrot as a little 3D model: the ones you've ever had in full color with their income, the rest as dark "???" silhouettes, with a FOUND count (e.g. 23/68). You get a "📖 NEW in your Index" message the first time you get each one, and everything you already owned counts. The **SKINS** page shows every wall skin you can get, with OWNED / EQUIPPED or its price.

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
- A base at level 5 gets walls all the way up and a peaked roof with a gold ridge and a glowing star; VIPs can build two more floors on top and the roof moves up with them.
- **VIP** players wear a gold crown with red, purple and green gems over their VIP tag (they can hide both in Settings).
- **VIP Royale skin** (free with VIP, claimed in the skins list; non-VIPs see it with a GET VIP button): royal purple marble walls with gold trim and gold argyle floors, a 👑 VIP sign over the base, **velvet stairs** (purple with gold edges, glowing step lips and sparkles), a **VIP throne** (velvet and gold, crowned with jewels) on the rebirth balcony, and a **VIP vault**: velvet runner, gold-crowned pillars, a chandelier and its own VIP throne to sit on.

## Make money (Robux)

On the [Creator Dashboard](https://create.roblox.com/dashboard/creations), open your experience, then **Monetization**:

- **Passes**: create `2x Cash`, `VIP`, `Longer Lock` and `Infinite Laser Door`.
- **Developer Products**: create `Cash Bag`, `Cash Vault`, `Server Luck`, and `Instant Lock`.

Paste each ID into `Config.GamePasses` / `Config.Products` in `src/shared/Config.luau`. Items left at `Id = 0` show as **SOON** in the shop.

Suggested prices:

| Item | Type | Price |
|---|---|---|
| 2x Cash | Pass | 199 R$ (id `2023580373`) |
| VIP (+2 base slots, 2 extra floors to buy, crown + VIP tag, VIP Royale skin) | Pass | 249 R$ (id `2022590341`) |
| Longer Lock (2x lock time) | Pass | 149 R$ |
| Infinite Laser Door (lasers never turn off) | Pass | 450 R$ (or 12,500 Shards in the Shard Shop) |
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
src/client/Effects.client.luau    idle bobbing, rainbow cycling, spinning shop crystal (visual only)
src/client/Settings.client.luau   the settings panel (music volume, VIP tag)
src/client/Sprint.client.luau     sprinting (Shift, SPRINT button, left stick)
src/client/Music.client.luau      background music
src/client/Followers.client.luau  draws everyone's mini followers
src/server/LimitedStock.luau      global stock + serials for limited Robux brainrots
src/client/HUD.client.luau        cash HUD, shop, rebirth menu, announcements, prompts
```

The server decides every purchase, steal and cash change, so exploiters can't spawn cash or brainrots. Steals also have a server-side speed check, so teleporting home doesn't work.

## Next ideas

- **More brainrots**: 101 so far; keep adding (add one in `Config.Brainrots` and a design in `BrainrotModel.luau`).
- **Thumbnail + icon**: the biggest driver of clicks.
- **Sounds**: purchase, steal, slap, laser zap.
- **Limited-time event brainrots**, an **Index** of everything you've owned, **daily rewards**, **group rewards**.
- **Offline earnings** and **trading**.
