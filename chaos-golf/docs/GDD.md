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

## 3. The lobby (fully enclosed)

A perfect circular room (radius 80, 45 tall) under an architecturally framed **geodesic glass dome** (160 diameter, Glass, transparency 0.6, reflectance 0.2). No baseplate, terrain or outdoor scenery is visible from anywhere; every room and hallway has a ceiling.

- **Fountain** at (0,0,0): tiered medium-poly fountain; neon-blue ParticleEmitter streams (rate 45, lifetime 1.2–1.8 s, speed 4–8, cyan→deep blue) arc from the spout and cascade over the upper basin into a large circular collecting bowl.
- **Spawn** at (0,3,−25), facing south toward the fountain.
- **Neon floor paths** (2 studs wide) run from the fountain to each room in its quadrant colour.
- **Wall labels**: big neon typography over every archway, plus "◀ SHOP" and "LEADERBOARDS ▶" on the SE/SW walls so all directions are readable from spawn.
- **Direction sign** (solid, not neon) in front of spawn: ▲ Practice ahead, ◀ Shop left, Leaderboards right ▶, Matchmaking behind you.
- **Daily Rewards board** near spawn (14-day calendar).

### North — Matchmaking & map voting (0,0,−120)

- Three portals: **Ranked 1v1**, **Classic (turn-based, 4)**, **Race Chaos (8)**. Standing inside a portal's bubble queues you; leaving it leaves the queue.
- **Patience pay**: +1 coin / 30 s (0–60 s), +2 / 20 s (61–120 s), +5 / 15 s (121 s+).
- **Server-wide vote**: three holographic signs show three distinct maps drawn with equal weight. Step on a sign's pad to vote (move your vote anytime). The next match to launch from any portal plays the winner, then three new maps are drawn. Your vote shows a private "✓ YOUR VOTE" marker.
- **Invite kiosk**: opens the Roblox invite prompt (friends in the server give +15% match coins).

### East — Mega Shop (120,0,0)

- **Coin Shop**: 12 pedestals with spinning balls, the daily rotation (same in every server, refreshes 00:00 UTC). Prompt to buy or equip.
- **Four category crates**: Ball Skins, Trails, Knockout Effects, Arrow Skins. Each opens with coins or a crate key, with an odds board behind it and a pity guarantee.
- **Catalog terminal**: a large interactive in-world screen with a data-driven grid (`ShopCatalog`). Tabs: Today / Crates / Locker (filter chips by category) / Passes. Clicking a ball thumbnail shows it on the Locker pedestal. `Config.UI.ShopMode = "Screen"` turns the same grid into a centred overlay.
- **Locker pedestal**: Q / E browse your skins on a spinning pedestal, F to equip.
- **Stat upgrade terminal**: Power (+5%/level), Control (+8%/level), Bounce (+6%/level), up to level 5. Active in Classic, Race and Practice; off in Ranked.
- **Creator code kiosk**: type a code on the in-world screen. It unlocks the Creator Fan ball and credits that creator for your purchases.
- **Mythic Featured shrine** (isolated alcove): the Featured crate plus a live counter of the global stock remaining across all servers.
- **Pass pedestals and coin-pack kiosks** (Robux).

### South — Practice Zone (0,0,120)

- Five lanes. The active minigame rotates every 20 minutes on a clock shared by every server:
  - **Target Putting**: 5 putts; stop on the rings (10 / 5 / 2 points).
  - **Velocity Long-Drive**: 3 drives up a 28° ramp; your best distance counts.
  - **Hazard Avoidance**: thread three spinning sweepers and sink it in 4 strokes or fewer.
- Each run pays that minigame's **tokens** (Target / Drive / Hazard), which can't be bought with coins or Robux.
- The **token kiosk** sells only the active minigame's crate and its four themed skins.
- **Replay Tutorial** pad.

### West — Hall of Leaderboards (−120,0,0)

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

Roblox physics handles collisions. The server adds rolling resistance (10 studs/s² + 0.55·v), surfaces (sand ×4.5 drag, ice ×0.2, boost pads), rest detection (speed < 1.1 for 0.35 s), cup capture (inside 1.3 studs and slower than 24 studs/s, otherwise it lips out), and out-of-bounds resets (+1 stroke, back to the last rest spot). Shots are validated (rate-limited, ball at rest, your turn, power clamped).

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

Hidden Elo MMR (start 1000, K 32, 48 for the first 5 placement matches) shown as tiers with three divisions: Bronze → Silver → Gold → Platinum → Diamond → Onyx → Chaos Legend. Reaching Gold, Diamond, Onyx and Chaos Legend unlocks a rank skin. Leaving mid-match counts as a loss. The rank shows on your nametag and the player list.

## 5. Courses

12 maps (6 themes × Sprint / Gauntlet): Neon Arcade, Candy Clash, Frost Factory, Lava Lab, Jungle Temple, Orbit Station. Each map's holes are generated deterministically from its seed (`World/CourseBuilder`), so a map always plays the same and can be learned:

- 12-stud tiles on an 8×8 grid; a self-avoiding path of 4–7 (Sprint) or 7–10 (Gauntlet) tiles.
- ±4-stud ramps, bumpers, spinners (hinge motors), pushers (prismatic servos), sand, ice, boost pads, narrow bridges over the void, and Chaos Boxes.
- Rails close every non-connected edge (no shortcuts); par comes from length, turns and hazards.
- Each course sits in its own enclosed themed hall, far from the lobby, with characters parked in a sealed booth.

Adding a map is one line in `src/shared/Maps.luau`.

## 6. Progression & cosmetics

| Category | Count | Built-in effects | Sources |
|---|---|---|---|
| Ball Skins | 56 | Epic+ auto aura; Legendary+ glow; pulse/rainbow animation | Coin Shop, Skin Crate, Mythic Featured, tokens, Ranked tiers, passes, creator code, achievements, Day 14 |
| Trails | 14 | Glow + sparks on Epic+ | Trail Crate, login |
| Knockout Effects | 11 | 9 styles (Burst, Stars, Ring, Confetti, Shatter, Lightning, Flames, Vortex, Nova) | Knockout Crate, login |
| Arrow Skins | 12 | 6 styles, pulse on Epic+ | Arrow Crate, login |
| Celebrations | 4 | Cup-sink effect | Celebration Pack pass |

**14-day login calendar** (claim at the board near spawn; missing a day restarts the streak): coins, keys for all four crates, the Daily Spark trail, Sunrise Chevron arrow, Daily Fireworks knockout, and on **Day 14 the exclusive Legendary "Eternal Dawn" ball** (unique golden ray aura) plus 1,500 coins.

## 7. Onboarding

1. First join: a private 3-hole **tutorial** (aim & power → bank shots → Chaos Box + Cup Magnet) with in-world instruction signs. It can be skipped anytime and pays 200 coins + the Rookie skin on first completion.
2. Back in the lobby, a **walking arrow** with glowing footprints leads to the direction sign in front of spawn, then disappears for good.
3. The Daily Rewards board reminds you when a claim is ready.

## 8. Social & CCU

- **+15% match coins** whenever a Roblox friend is in the same server (shown as a tag under the coin counter).
- Invite kiosk in the North room.
- Server-wide callouts in chat for hole-in-ones, knockouts, Legendary+ unboxes and Day-14 claims.

## 9. Data

`UltimateGolf_v1` DataStore, one key per user (`u_<userId>`), saved with UpdateAsync, retries and a soft session lock (prevents two servers overwriting each other):

```
Coins, Tokens{Target,Drive,Hazard},
Owned{Skins{},Trails{},Knockouts{},Arrows{}}, Equipped{Skins,Trails,Knockouts,Arrows},
Keys{Skins,Trails,Knockouts,Arrows}, Login{Day,LastClaim},
Celebration, Upgrades{Power,Control,Bounce},
Stats{Wins,Matches,Sabotages,Knockouts,CoinsEarned,HoleInOnes,Holes},
Ranked{MMR,Wins,Losses,Draws,Played,Peak},
Creator, TutorialDone, DirectoryDone, Pity{crateId=n}, Receipts[], Lock
```

Other stores: `_Public` (equipped skin, trail and MMR, for podiums), `_Global` (Mythic stock), `_CreatorSales`, and `_LB_<Stat>_<D|W|A>` ordered stores.

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
