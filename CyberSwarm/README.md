# Cyber Swarm

A reverse tower defense game for Roblox. **You** send swarms of robots down a lane. An **AI
military defense** (rifle turrets, gatling nests, howitzers, flak cannons, cryo mortars) tries to stop
them. After every wave the defense gains a random **stacking military mutation**, such as Rapid Reload,
Reactive Armor or EMP Strike, so each round gets harder. Spend coins between waves on robots and
upgrades, get survivors to the enemy **Command HQ**, and destroy it before the mutations overwhelm you.

The look is split on purpose. Your swarm and the UI use cyan and magenta accents. The defense is
olive, khaki and gunmetal with red warning lights, so you can always tell the two sides apart. Glow
is kept to small accents (robot eyes, turret lights, pad rings); the lobby is a bright, solid hall.
The game's name appears only as a small stencil on a lobby wall, never in the screen UI.

---

## Run it

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) 7.x: the CLI plus the Roblox
   Studio plugin. With [Aftman](https://github.com/LPGhatguy/aftman) or
   [Rokit](https://github.com/rojo-rbx/rokit), run `rokit add rojo-rbx/rojo`.
2. From this `CyberSwarm/` folder, run:
   ```sh
   rojo serve
   ```
3. Open Roblox Studio, create a new **Baseplate** place, open the **Rojo** plugin tab and click
   **Connect**.
4. Press **Play**. You spawn in the lobby facing the three round queue pads. Walk onto the **SOLO**
   pad; its floor ring lights up and the match starts after a 3 second countdown.

In Studio the game uses in-memory player data and prints a warning, because Studio has no DataStore
access by default. To test real saving, publish the place and enable
*Game Settings → Security → Enable Studio Access to API Services*.

The Output window should show the debug command banner, `[Tests] 42 passed, 0 failed.` and
`[Cyber Swarm] Server ready.`. You will also see one orange warning from DataService about in-memory
data; that is expected in an unpublished place.

### How to play a Solo match

| Phase | What happens |
|---|---|
| Countdown | The defense digs in. |
| Preparing (15 s) | Buy robots from the spawn bar (click, or press `1`-`5`). Upgrade robot types with the button under each card. The **Incoming Mutation** card shows what the defense gains next wave. |
| Wave | Your queued robots march down the lane. Survivors damage the HQ and earn coins. |
| Wave Result | You get the completion bonus, and the next mutation is rolled. |
| Match End | **Victory** if the HQ falls. **Defeat** if you run out of coins and robots, or hit the wave limit. Profile coins and stats are saved, then you return to the lobby. |

Unlock more robots (Medic, Glitch, Drone, Bomber) in the **Armory** (top bar) with profile coins,
then equip up to 5 in the **Loadout** panel (side rail). The **Deploy** panel lists the modes and
how many players stand on each pad; it is information only.

### Queueing (pads only)

Modes are joined **only by standing on that mode's pad** in the lobby. Mobile, console and desktop
all work the same way: walk on. There are no queue buttons, keybinds, prompts, or queue remotes.

- The server checks every player 10 times a second: the character must be alive and inside the pad
  zone (within its radius, and no more than 12 studs above it, so jumping in place is fine).
- One queue per player. Walking onto a different pad moves you there at once.
- Leaving the zone (walking, jumping, or being pushed off) removes you after a 0.3 s grace period,
  so physics jitter never drops you. Dying, resetting, or disconnecting removes you immediately.
- Feedback is in the world: the pad's floor ring fills as players join, and the queue board on the
  back wall shows each mode's count and countdown. A small status panel at the bottom of the screen
  reports the server's decision while you are queued.

The rules live in `Logic/QueueRules.luau` (pure) and are unit-tested for: stepping on and off
repeatedly, jitter shorter than the grace, being pushed off, dying on a pad, entering a match,
switching pads quickly, two players arriving together, and a full pad.

---

## Project structure

```
CyberSwarm/
├── default.project.json        Rojo mapping (see below)
├── selene.toml / stylua.toml   lint + format config
└── src/
    ├── shared/                 → ReplicatedStorage.Shared
    │   ├── Types.luau          shared type definitions (configs, data, snapshots)
    │   ├── Constants.luau      engineering constants, tags, layout names, error codes (no balance)
    │   ├── Theme.luau          colors (UI accents, lobby world, military palette), fonts, tweens
    │   ├── Remotes.luau        every remote, typed wrappers, per-player rate limiting
    │   ├── ConfigValidator.luau startup config checks
    │   ├── Config/             ALL balance numbers
    │   │   ├── RobotConfig     robots, upgrades, flight altitude
    │   │   ├── TowerConfig     tower base stats
    │   │   ├── MutationConfig  mutations, rarity weights, stat caps
    │   │   ├── MapConfig       maps
    │   │   ├── WaveConfig      phase timings, economy, swarm size, AI build order
    │   │   └── ModeConfig      Solo / 1v1 / Co-op, match payouts, new-profile defaults
    │   ├── Logic/              pure, unit-tested rules
    │   │   ├── StatResolver    tower stat resolution + robot upgrade scaling
    │   │   ├── MutationRoller  weighted rolls + stacking limits
    │   │   ├── WaveMath        coin formulas, swarm cap, payouts
    │   │   └── QueueRules      pad queue membership (grace, death, switching, capacity)
    │   └── Util/               Signal, Maid, Math, TableUtil, RateLimiter
    ├── server/                 → ServerScriptService.Server
    │   ├── Bootstrap.server.luau   the only Script
    │   ├── ServerTypes.luau    runtime records (Match, Arena, RobotUnit, TowerUnit, ...)
    │   ├── Notifier.luau       toasts / banners / error codes to players
    │   ├── Services/           Data, Map, Lobby, Queue, Match, Wave, Robot, Tower, Mutation, Economy
    │   ├── World/              Part-built lobby, Junkyard map, placeholder models, effects
    │   ├── Debug/DebugCommands.luau   Studio-only QA chat commands
    │   └── Tests/              TestRunner + *.spec modules (run automatically in Studio)
    └── client/                 → StarterPlayer.StarterPlayerScripts.Client
        ├── Bootstrap.client.luau   the only LocalScript
        ├── ClientState.luau    single mirror of server snapshots
        ├── UI/UIKit.luau       code-built UI helpers + auto scaling
        └── Controllers/        UI, Lobby, Shop, Hud, Camera, Input, Effects
```

### Architecture in one paragraph

Each Bootstrap requires its modules and calls `init()` (build state and world), then `start()`
(connect events). **MatchService** is the orchestrator. Every match is an isolated `Match` record
with its own `Maid`, `Random`, players, timers, one `Heartbeat` connection, and one or more
**arenas**, each a map copy with its own robots, towers, HQ and mutation stack. Lower services work
on those plain records and never require upward, so there are no circular requires:

```
QueueService ─▶ MatchService ─▶ WaveService ─▶ RobotService
                    │                └─▶ EconomyService ─▶ DataService
                    ├─▶ TowerService ─▶ RobotService, MutationService
                    ├─▶ MapService, LobbyService, MutationService
```

Robots never call TowerService. When a Glitch hacks a tower or a Bomber detonates, RobotService fires
`arena.towerHitRequested` (a `Signal`) and TowerService resolves it, including Reactive Armor
blocks. Gameplay callbacks only record outcomes. Phase changes happen at the end of the match tick
or from the phase timer, never mid-update. Match teardown is one `match.maid:destroy()`. That call
removes the Heartbeat connection, timers, signals, every map copy and every unit.

**Performance:** all robots in an arena move in one `workspace:BulkMoveTo` call per frame, along
waypoints with CFrame math (no Humanoids, no pathfinding). All towers in an arena run from that same
tick. Gunfire is drawn client-side by `EffectsController` from pooled parts, sent over an
`UnreliableRemoteEvent`. HUD and health bars are built once and only have text and sizes updated.

### Security

The server owns coins, robots, towers, health, waves and mutations. Clients only send intents
(`RequestSpawnRobot(robotId, laneIndex)`, `RequestUpgradeRobot`, `RequestSetLoadout`,
`RequestUnlockRobot`, `RequestSync`). There is deliberately no queue intent: queueing is decided
only by the server's pad detection. Every intent:

- passes a per-player, per-remote token-bucket rate limiter before any handler runs (limits are in
  `Remotes.luau`);
- has every argument type-checked (handlers receive `...unknown`);
- is checked against server state: in an active match, correct phase, robot exists and is not
  locked, robot is in the loadout snapshot taken at match start, lane exists, wave cap, affordable;
- is rejected with an error code that the client turns into a toast (`Constants.NoticeText`).

Cost, damage, position and time always come from config and server clocks, never from the client.

### Player data

`DataService` stores `{ schemaVersion, data, lock }` per player:

- **Session locking:** the lock holds the owning server's `JobId`. Other servers retry with
  exponential backoff until it is released, or until it goes stale (3 missed autosaves).
- **Retries** with exponential backoff on every load and save.
- **Autosave** every 60 s (this also refreshes the lock), plus a releasing save on `PlayerRemoving`
  and `BindToClose`.
- **Migrations:** `MIGRATIONS[n]` upgrades schema `n` to `n + 1`. Version 0 means a record saved
  before versioning existed. A record from a *newer* schema is never overwritten; the player is asked
  to rejoin.
- A load that still fails after retries **kicks** the player with a clear message instead of handing
  out defaults that could overwrite a real save.

---

## Extending the game

### Add a robot

1. Add an entry to `RobotConfig.Robots` (copy an existing one) and its id to `RobotConfig.Order`.
2. Pick abilities from the implemented kinds: `Heal`, `Disable`, `Explode`. The required fields for
   each are listed in `Constants.ABILITY_FIELDS`.
3. Optional: put a Model at `ServerStorage/Assets/Robots/<Name>` (the `modelPath`). It needs a
   `PrimaryPart`. Every other part is welded to it automatically. Without a model, a painted placeholder
   is generated from `visual`.

### Add a tower

1. Add an entry to `TowerConfig.Towers` and its id to `TowerConfig.Order`.
2. Reference it in `WaveConfig.DefensePlan[wave]` so the AI deploys it.
3. Optional asset at `ServerStorage/Assets/Towers/<Name>`: a `PrimaryPart` whose `PivotOffset` is the
   bottom centre, plus an anchored part named `Head` that turns to aim. Parts that turn with it must
   be unanchored and welded to `Head`. A part named `TargetLight` dims while the tower is hacked.

### Add a mutation

Add an entry to `MutationConfig.Mutations` and its id to `MutationConfig.Order`. A mutation is a list
of modifiers on tower stats from `Constants.TOWER_STATS`. For example:

```lua
{ stat = "fireRate", multiplier = 1.25 }  -- +25% per stack
{ stat = "armorHits", add = 1 }           -- +1 per stack
```

Stacking is always resolved from base stats:
`(base + Σadd) × (1 + Σ(multiplier − 1))`, then capped by `MutationConfig.StatCaps`. Two 1.25×
stacks give 1.5×, never 1.5625×. Stats with built-in behaviour: `armorHits` (Reactive Armor),
`empStun` (EMP Strike), `chainCount` (Shrapnel Rounds), `regenPerSecond` (Field Engineers) and
`magnet` (Flak Barrage). Plain numbers like `damage`, `range`, `fireRate`, `maxHealth`,
`splashRadius` and `slowDuration` work with no extra code.

### Add a map

`MapService` loads any Model from `ServerStorage/Maps/<templateName>`. Build the model in Studio, put
it in `ServerStorage/Maps`, then add the map id to a mode's `mapPool` in `ModeConfig`. FactoryFloor,
NeonCity, FrozenLab and VolcanoCore are already in `MapConfig` and only need their models. The
required structure:

```
<Map Model>                      any name; set templateName in MapConfig to match
├── Waypoints        (Folder)    single lane: Parts Waypoint_1, Waypoint_2, ... in order
│   └── Lane_1, Lane_2 (Folders) multi-lane: one folder per lane, each with Waypoint_N parts
├── TowerSlots       (Folder)    Parts TowerSlot_1..N; towers stand on each part's top face.
│                                The AI fills slots in number order, so number by priority.
├── BaseSpawn        (Part)      the enemy HQ stands on its top face, door facing the part's -Z
├── PlayerSpawns     (Folder)    Parts where players watch from (or a single Part)
└── Camera           (Part, optional) its CFrame is the match camera; otherwise one is computed
```

- Waypoint positions are the lane centre line at ground height. Robots walk the polyline from
  `Waypoint_1` to the last waypoint, where they hit the HQ.
- Make marker parts `Anchored`, `CanCollide = false` and `Transparency = 1`.
- The model is moved with `PivotTo`, so any pivot works. Each concurrent arena gets its own spot
  600 studs apart, starting at `Constants.World.MAP_ORIGIN`.
- If a template is missing or invalid, `MapService` warns and the match does not start. Players are
  told and returned to the lobby.

Junkyard is generated from Parts by `World/JunkyardBuilder.luau` and follows the same convention. If
you save your own `ServerStorage/Maps/Junkyard`, the hand-built version wins.

### Add a mode

Add an entry to `ModeConfig.Modes` and `ModeConfig.Order`. A lobby pad appears automatically.
`sideLayout = "Shared"` puts all players on one arena (Solo, Co-op).
`sideLayout = "PerPlayer"` gives each player an arena; the first HQ destroyed wins (1v1). Queue pads
are any Part tagged `CyberSwarm_QueuePad` with a `ModeId` attribute. Optional: a `QueueRadius`
number attribute (otherwise half the pad's footprint), a `Ring` folder of `Segment_1..N` parts that
fill as players join, and a `Mode_<ModeId>` TextLabel on a screen tagged `CyberSwarm_QueueBoard`.

---

## QA tools (Studio only)

`Debug/DebugCommands.luau` only runs when `RunService:IsStudio()` is true. Type these in chat:

| Command | Effect |
|---|---|
| `/cs skip` | jump to the next phase (skip prep, end the current wave, ...) |
| `/cs coins 500` | add match coins (in a match) or profile coins (in the lobby) |
| `/cs mutate RapidReload` | apply a mutation to your arena now |
| `/cs mutations` | list mutation ids |

### Tests

`server/Tests/*.spec.luau` cover stat resolution, mutation stacking and rolls, wave coin formulas,
and config validation (including deliberately broken configs). In Studio they run automatically at
startup and print `[Tests] N passed, M failed`. Failures are `warn`s, never errors. Turn this off with
`Constants.Debug.RUN_TESTS_IN_STUDIO`.

`ConfigValidator` also runs at every server start and warns about any config entry with a missing
field, a wrong type, or an unknown id.

### Lint and format

```sh
stylua src        # format
selene src        # lint (first run downloads the Roblox std definitions)
```

---

## Decisions and assumptions

- **Location:** the repository already contains another game (Crate Rush) at its root, so Cyber
  Swarm lives in its own `CyberSwarm/` folder with its own Rojo project.
- **Military theme:** the defense, its mutations, and the HQ are military-styled at your request.
  Mutation ids use military names; the mechanics match the original spec one to one:
  Rapid Reload = Overclock, Reactive Armor = Armor Plating, EMP Strike = EMP Pulse,
  Shrapnel Rounds = Chain Lightning, Field Engineers = Regen Core, Sniper Scopes = Long Range,
  Flak Barrage = Scrap Magnet, Fortifications = Reinforced Frame. Tower ids keep the spec names
  (`BasicTurret`, `Cannon`, ...) with military display names.
- **No Wally:** there are no external dependencies, so there is no `wally.toml`.
- **Mutation timing:** after wave N a mutation is rolled and shown as *incoming* during the next
  Preparing phase. It takes effect when wave N+1 starts, which is what lets players plan counters.
- **Reactive Armor** ("blocks first hit per robot"): each tower ignores the first hostile effect it
  receives from each individual robot (Bomber blast or Glitch hack), plus one more per extra stack.
- **Flak Barrage** ("pulls flyers lower"): flyers drop to a lower altitude and ground-only towers can
  hit them.
- **EMP Strike:** a tower's pulse only goes on cooldown when it actually stuns something.
- **Upgrades** are per match and per robot type. Each level adds +20% health and +15% damage
  (`RobotConfig.Upgrade`) to robots released afterwards.
- **Purchases** only happen during Preparing; queued robots are released when the wave starts.
  Coins are spent on purchase and are not refunded.
- **Lose conditions** are checked after each wave: every player in the arena can no longer afford
  their cheapest robot, or the mode's wave limit was reached. A wave also ends after
  `WaveConfig.maxWaveDuration` seconds as a safety net.
- **Rewards:** arrival coins are paid the moment a robot reaches the HQ. The completion bonus is paid
  at wave end, and only to players who sent at least one robot that wave.
- **Destroyed towers** are rebuilt at full health at the start of the next Preparing phase. The AI
  adds towers from `WaveConfig.DefensePlan` into free slots in slot order.
- **Co-op and 1v1** need two players (`minPlayers = 2`). They use the same match pipeline as Solo.
  Solo is the path tested end to end.
- **Mega Mech** is configured but `locked = true`. It is not purchasable or equippable and shows as
  "Coming soon".
- **Player characters** are frozen on their arena's observation deck during a match and the camera
  switches to a fixed tactical view. On touch devices the default thumbstick is hidden in-match so
  it never covers the spawn bar.
- **Lobby spawning:** each player's `RespawnLocation` is set to the lobby spawn, so a template's own
  SpawnLocation never pulls players away from the lobby.
- **Gems** and **settings** are stored in player data but nothing uses them yet, matching the spec's
  data shape.
