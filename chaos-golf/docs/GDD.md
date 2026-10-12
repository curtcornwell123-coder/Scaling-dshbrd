# Ultimate Golf — Game Design Document

Multiplayer chaos mini-golf for Roblox. **You are the ball.** Short, readable holes, physical sabotage, and a lobby you navigate entirely on foot: no menus, only in-world kiosks, pads and portals.

---

## 1. Pillars

1. **Immersion first.** The only persistent screen element is the coin counter. Everything else is a physical object you walk up to.
2. **Chaos, but fair.** Abilities and ball-on-ball knockouts make every match loud; Ranked strips paid power (upgrades off) and uses identical loadouts.
3. **Earn everything.** Every cosmetic can be earned by playing. Robux buys time, support and a few exclusive looks, never wins.
4. **Rivals-grade polish.** Clean medium-poly shapes, SmoothPlastic + Neon only, rounded/bevelled edges, high-contrast neon trims, vibrant solid and gradient colours, no noisy textures.

## 2. Visual direction

| Element | Rule |
|---|---|
| Materials | SmoothPlastic and Neon. Glass only for the sky-roof dome and some skins. ForceField for portal films and queue bubbles. |
| Shapes | `Parts.roundedBox` (rounded vertical edges), bevelled slabs with neon top trims, cylinders for pillars, rims and pads. |
| Colour | Light cool walls (#E6EAF2), navy plinths and trims (#1B2033), one accent per quadrant: North #FF6B00, East #00FF66, South #FF00A0, West #00E5FF. |
| Gradients | `SurfaceGui` + `UIGradient` panels on hero walls (Roblox has no native surface gradients). |
| Lighting | `Future` technology, bright ambient, PointLights/SurfaceLights in ceilings; neon parts never cast shadows. |
| Golf ball | One shared mesh for every skin: a 1.5-stud sphere with 108 micro-indented dimples (`assets/mesh/golfball.obj`). Physics stays a perfect `Ball` part; the dimple mesh is a `SpecialMesh` on top. Skins change only colour, material, glow, pulse and aura. |

### UI design system (`src/shared/UIKit.luau`)

One kit for the HUD and every in-world screen:

- Base slate `RGB(24,28,36)`, surfaces `RGB(32,37,48)` / `RGB(42,48,62)`, off-white text, muted grey secondary text.
- Subtle 8px corners (6px for chips), 1px hairline strokes, 8/12px spacing.
- Two accents only: **Primary green** for Buy / Equip / Claim CTAs, **Info blue** for selection and secondary emphasis. Rarity and quadrant colours appear only as small dots and tags.
- `UIGridLayout` grids, `TweenService` hover lift (scale 1.03 + stroke highlight) and press feedback on every button.

## 3. The lobby: a modern country club

A circular marble-and-walnut atrium (radius 56) under an oak ceiling on black-steel I-beams, a glass lantern and a brass halo chandelier. Four glass corridors lead to the wings. The style is marble, walnut, brass and black steel: symmetric, high detail, no kid neon (`LobbyBuilder`, `LobbyKit`).

- **Premium Marble Fountain** in the centre: three tiers, running water curtains and jets (protected asset, see BACKLOG).
- **Spawn** south of the fountain, facing it. The view from spawn is symmetric with nothing in the middle.
- **Stations** on the atrium wall: **Locker** (browse and equip skins), **Rewards** (14-day calendar + Corny Games group reward with the Kernel ball), **Ball Upgrades**, **Creator Code**. Lounges sit in the window bays.
- **Practice doorway signs**: two digital signs show the practice that is live now and the one up next, with the countdown.

### North: Matchmaking & map voting

- Three portals: **Ranked 1v1**, **Classic (turn-based, 4)**, **Race Chaos (8)**. Standing inside a portal's bubble queues you; leaving it leaves the queue.
- **Patience pay**: +1 coin / 30 s (0–60 s), +2 / 20 s (61–120 s), +5 / 15 s (121 s+).
- **Server-wide vote**: three signs show three distinct maps. Step on a sign's pad to vote; the next match plays the winner.
- **Invite kiosk** (friends in the server give +10% match coins each, up to +40%).

### East: Pro Shop

- **Ball collection**: 12 balls in jewellery-style glass cases (walnut plinths, brass edges, velvet decks, engraved plaques). A balanced set (5 Common, 4 Rare, 2 Epic, 1 Legendary) every 10 minutes, the same in every server; the hanging board by the entrance counts down.
- **Limited vault** in the middle of the runner: the **Corny Games Studio** ball, 500 ever made (global stock), each printed with its serial, behind velvet ropes.
- **Four category crates** (Ball Skins, Trails, Knockout Effects, Arrow Skins) with odds boards and pity; the **Mythic Featured shrine** with its global stock counter; pass pedestals and coin-pack kiosks.
- **Catalog terminal**: data-driven grid (`ShopCatalog`): Rotation / Crates / Locker / Passes.

### South: Practice Range

- **One game is live on all six lanes** and rotates every 20 minutes on a clock shared by every server (`Minigames.active`). The whole range dresses itself as the live game's biome (`PracticeBiomes`): ground, backdrop sky, lane floors and rails, and themed props.
  - **Target Putting** (Garden Green): 5 putts; stop on the rings (10 / 5 / 2 points).
  - **Velocity Long-Drive** (Night Driving Range): 3 drives up a 28° ramp; best distance counts.
  - **Hazard Avoidance** (Construction Yard): thread three spinning sweepers, sink it in 4 strokes or fewer.
  - **Bank Shot** (Frozen Rink, slippery ice lanes): the cup hides behind an ice wall; bank off the boards and sink it in 3 strokes or fewer.
  - **Gate Run** (Desert Canyon): 3 shots through 5 narrowing gates (gate n = n points); a shot only scores if the ball stops before the red line.
- A **broadcast TV** over the lanes and the gantry header show what's live, what's next and the countdown. A lane that is mid-run when the game changes finishes the run first.
- Each run pays that game's **tokens**, which can't be bought. The **Token Exchange** hut shows the live game's crate and balls and sells every game's (one tab per game).
- The **best-scores board** shows the live game's all-time top scores. There is a **Replay Tutorial** pad.

### West: Hall of Leaderboards

- Three boards: **Wins**, **Coins earned**, **Sabotages**, each Daily / Weekly / All-Time (OrderedDataStores).
- Each player pages their own view with physical ◀ / ▶ / period buttons (local only).
- **Trophy podiums**: a spinning copy of the current Daily leader's real ball (skin, aura and an orbiting trail) with name, value and rank, refreshed every 20 s.

## 4. Core gameplay

### Controls (you are the ball)

| Input | Action |
|---|---|
| Camera (mouse / drag / right stick) | Aim: the arrow follows the camera |
| Hold Left Click / Space / R2 / PUTT button | Charge the power meter (sweeps 0→1→0); release to putt |
| 1 / 2 (X / Y on gamepad, touch buttons) | Use ability slot 1 / 2 |
| X / B / SKIP button | Skip the tutorial or leave a practice lane |

The aim guide is your equipped **Arrow Skin** (styles: Classic, Chevron, Dotted, Laser, Comet, Rainbow). The power meter and ability strip float next to the ball.

### Ball physics (server-authoritative)

Roblox physics handles collisions. The server adds rolling resistance (10 studs/s² + 0.55·v), a skid-then-roll start (for 0.18 s after the stroke the ball has a little more grip and its spin builds up; after that the spin matches the ground exactly, so the print turns as it rolls), level turf that keeps a rolling ball down over floor seams, turf that takes 15% of the pace off a hard landing, surfaces (sand ×4.5 drag, ice ×0.2, boost pads), rest detection (speed < 1.1 for 0.35 s), the cup (a real hole, CupHole: cut through the green and the layers under it, 1.3-stud radius, 1.9 deep, white liner, dark bottom; real physics decides, like a real green: a dying putt drops on any part of the hole, a firm centred putt hits the back of the cup and drops, up to ~21 studs/s dead centre - (2R - r)·√(g/2r), the same rule that gives real golf its 1.63 m/s - an off-centre one has to be slower, too fast and it hops the hole or lips out off the rim ("Lip out"), a chip or jump that lands in the hole stays in once the ball is below the rim; a slow ball hanging up to 0.3 studs over the rim is drawn in and one that stops on the lip teeters 0.35 s first; Tiny-Cup balls ride an invisible lid over the cup and are judged on the flat by CupPhysics with the same drop-speed rule), and out-of-bounds resets (+1 stroke, back to the last rest spot). Shots are validated (rate-limited, ball at rest, your turn, power clamped).

### Modes

| Mode | Players | Flow | Scoring | Ball collisions | Abilities | Upgrades |
|---|---|---|---|---|---|---|
| Ranked 1v1 | 2 | Simultaneous | Fewest total strokes | Ghost (no contact) | Fixed: Mulligan + Cup Magnet | Off |
| Classic | 2–4 | Turn-based (25 s turns) | Fewest total strokes | Solid | 1 random + Chaos Boxes | On |
| Race Chaos | 2–8 | Simultaneous; 30 s finish window after the first sink | Points by finish order (10/8/6/5/4/3/2/1) | Solid | 1 random + Chaos Boxes | On |

Every match is 6 holes. Each hole has a 120 s limit and a stroke cap of par + 4. A scorecard shows between holes and a results card at the end.

### Chaos abilities (hold up to 2)

| Ability | Type | Effect |
|---|---|---|
| Shockwave | Sabotage | Blasts opponent balls within 22 studs away from yours |
| Frost Curse | Sabotage | The leader's next shot skids like ice |
| Gust | Sabotage | Every opponent's next shot is pushed sideways |
| Tiny Cup | Sabotage | Opponents' cups shrink to 45% for 15 s |
| Cup Magnet | Buff | Your next shot is pulled into the cup from 7 studs |
| Mulligan | Buff | Undo your last shot and get the stroke back |

**Knockouts**: hitting another ball at speed plays your equipped **Knockout Effect**. If that ball goes out of bounds within 5 s, it's a **KNOCKOUT**: a bigger effect, a sabotage on the leaderboard, and a server-wide callout.

### Ranked

Everyone starts **Unranked**: win 3 Ranked games to place (the results screen counts down "UNRANKED · 2 wins to rank"; placing shows a toast). Hidden Elo MMR starts at 600, the foot of Bronze (K 32, 48 for the first 5 matches), so the first rank is Bronze and players climb from there through tiers with three divisions: Bronze (III from 600) → Silver (900) → Gold (1100) → Platinum (1300) → Diamond (1500) → Onyx (1700) → Chaos Legend (1900). Rank-ups toast too. Reaching Gold, Diamond, Onyx and Chaos Legend unlocks a rank skin. Leaving mid-match counts as a loss. The rank shows on your nametag and the player list ("UNRANKED" until placed). Profiles from before this (start 1000, shown Silver II without a game) restart Unranked at 600 unless they already had 3 Ranked wins.

## 5. Courses

22 maps (Sprint / Gauntlet) across 9 worlds: Meadow Greens, Sunset Canyon, Frost, Lava, Jungle, Tropical Cove, Autumn Woods, Blossom Gardens and **Ocean Piers**. Each map's holes are generated deterministically from its seed (`World/CourseBuilder`), so a map always plays the same and can be learned:

- 12-stud tiles on an 8×8 grid; a self-avoiding path of 4–7 (Sprint) or 7–10 (Gauntlet) tiles (Ocean maps favour long straight piers).
- Holes lie on the ground like a real course (no plateaus or ramps): the turf floor sits on the earth, jump gaps and bridges cross creeks dug into it (water, lava on the volcano), and a ball that ends up on the land, in a creek or in the sea is out of bounds (stroke, back to where it was played).
- Bumpers, spinners (hinge motors), pushers (prismatic servos), windmills, humps, tunnels, sand, ice, boost pads, narrow bridges and Chaos Boxes. Every hole has at least one obstacle.
- **Boost jumps** (`Jump` = per-hole chance): a launch tile (a boost lane that pulls any ball to 70 studs/s, then an 18° kicker), an open gap with no floor, and a sandy landing tile. About 19 studs of flight over the 12-stud gap; falling short is out of bounds (+1 stroke). Both Ocean maps (Coral Cove, Leviathan Leap) are full of them, and seven other maps have a few.
- **Ocean Piers**: the holes lie on sand banks at sea level with the water lapping just below the turf, with sand islets and palms, lighthouses, sea stacks, buoys and sailboats.
- Rails close every non-connected edge (no shortcuts); par comes from length, turns and hazards.
- Boost feel: pads have a glass top, LED strips and chasing chevrons. Boosting plays an FOV kick, radial speed lines, a light blur, edge glow, a "BOOST!" pop and a whoosh for you, and a streak burst others can see.

Adding a map is one line in `src/shared/Maps.luau`.

## 6. Progression & cosmetics

| Category | Count | Built-in effects | Sources |
|---|---|---|---|
| Ball Skins | 76 | Epic+ auto aura; Legendary+ glow; pulse/rainbow animation | Coin Shop, Skin Crate, Mythic Featured, tokens, Ranked tiers, passes, creator code, achievements, Day 14 |
| Trails | 14 | Glow + sparks on Epic+ | Trail Crate, login |
| Knockout Effects | 11 | 9 styles (Burst, Stars, Ring, Confetti, Shatter, Lightning, Flames, Vortex, Nova) | Knockout Crate, login |
| Arrow Skins | 12 | 6 styles, pulse on Epic+ | Arrow Crate, login |
| Celebrations | 4 | Cup-sink effect | Celebration Pack pass |

**Game passes** (Store tab; set up with `tools/setup_monetization.py`, icons in `assets/icons`): the cosmetic passes lead, classy and never an edge: **Tour Collection** (299: Tour Black, Tour Pearl, Tour Graphite balls), **Heritage Collection** (249: pinstriped Cream, Forest and Oxblood club balls), **Members Club** (199: Members Contrail trail, Members Line aim, MEMBER nametag); then VIP (+10% coins, VIP Aurum, gold name), Celebration Pack, 2x Coins and Founder. Ball upgrades stay off in Ranked and power-ups are never sold.

**14-day login calendar** (claim at the Rewards station; missing a day restarts the streak): coins, keys for all four crates, the Daily Spark trail, Sunrise Chevron arrow, Daily Fireworks knockout, and on **Day 14 the exclusive Legendary "Eternal Dawn" ball** (unique golden ray aura) plus 1,500 coins.

## 7. Onboarding

1. First join: **"What are you playing on?"** with three big cards (Console, Phone/Tablet, Keyboard & Mouse). The choice is saved in the profile, and every control hint (tutorial checklist, guide) uses it; a connected controller always wins.
2. Then a one-time invite: play the private 3-hole **tutorial** (aim & power → bank shots → Chaos Box + Cup Magnet), skip it, or read the guide first. The tutorial can be skipped anytime and pays 200 coins + the Rookie skin on first completion. Replay it from the pad in the Practice Range.
3. The **Player Guide** (HUD button, G, or Select/View on a controller) explains everything in 7 tabs: Controls (one tutorial each for Console, Phone & Tablet, Keyboard & Mouse, switchable), Modes, Power-ups (how many you start with in each mode and how you earn more), Balls & Skins, Practice, Rewards and Shop. Its text is generated from the game config, so numbers stay correct.
4. Menus work on every device: buttons are controller-selectable, open panels focus their first button on a controller, B closes the top panel, and the guide scales and scrolls on phones.

## 8. Social & CCU

- **+15% match coins** whenever a Roblox friend is in the same server (shown as a tag under the coin counter).
- Invite kiosk in the North room.
- Server-wide callouts in chat for hole-in-ones, knockouts, Legendary+ unboxes and Day-14 claims.

## 9. Data

`UltimateGolf_v1` DataStore, one key per user (`u_<userId>`), saved with UpdateAsync, retries and a soft session lock (prevents two servers overwriting each other):

```
Coins, Tokens{Target,Drive,Hazard,Bank,Gates},
Owned{Skins{},Trails{},Knockouts{},Arrows{}}, Equipped{Skins,Trails,Knockouts,Arrows},
Keys{Skins,Trails,Knockouts,Arrows}, Login{Day,LastClaim},
Celebration, Upgrades{Power,Control,Bounce},
Stats{Wins,Matches,Sabotages,Knockouts,CoinsEarned,HoleInOnes,Holes},
Ranked{MMR,Wins,Losses,Draws,Played,Peak,V},
Creator, TutorialDone, Device, GroupClaimed, PracticeBest{}, Serials{skinId=n}, Pity{crateId=n}, Receipts[], Lock
```

Other stores: `_Public` (equipped skin, trail, MMR and Ranked wins, for podiums), `_Global` (Mythic stock), `_CreatorSales`, and `_LB_<Stat>_<D|W|A>` ordered stores.

## 10. Code map

```
src/shared/   Config · Skins · Cosmetics · Crates · DailyRewards · Maps · Abilities · Ranks · Minigames · ShopCatalog · UIKit · Net
src/server/   Main (boot order)
  World/      Parts (geometry kit) · LobbyTypes (contract) · LobbyBuilder · CourseBuilder
  Services/   Data · Activity · Zones · Social · Economy · Tags · MythicStock · CreatorCodes · Monetization
  Golf/       BallService · AbilityService · MatchService
  Lobby/      Voting · Matchmaking · Shop · Displays · Daily · Leaderboards · Practice · Tutorial
src/client/   Main → modules/ State · Hud · WorldFx · GolfController · MatchUi · Previews · Catalog · Terminals · Boards · Prompts · Guide
```

All remotes are declared in `Net.luau` and every client request is validated on the server (types, ownership, prices, rate limits).
