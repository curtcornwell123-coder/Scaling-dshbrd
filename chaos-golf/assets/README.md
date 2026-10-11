# Ultimate Golf: art assets

Everything here is generated procedurally by the scripts in `tools/` and is original art. There are no external images, no Robux logo and no Roblox trademarks. Icons are 512x512 PNGs, drawn at 2048 px and downsampled with LANCZOS. They share one house style: gradient + ray backgrounds, bold outlined shapes, soft drop shadows, glossy highlights and Inter Black type. Key content stays inside the central circle with an 8% margin, because Roblox crops game-pass icons to a circle.

`icons/contact_sheet.png` shows every icon at a glance, with game passes shown circle-cropped.

## Regenerate

```sh
pip install numpy scipy pillow          # Inter font: apt install fonts-inter
python3 tools/gen_ball.py               # mesh/golfball.obj + preview, prints mesh stats
python3 tools/gen_icons.py              # all icons + contact sheet (~2-3 min)
python3 tools/gen_icons.py pass_vip game_icon   # only the named icons (sheet is rebuilt from the PNGs)
python3 tools/gen_icons.py --no-sheet           # skip the contact sheet
```

Both scripts are deterministic, so re-running them produces identical files.

## Mesh

| File | Use |
|---|---|
| `mesh/golfball.obj` | The dimpled ball for every skin. It has 108 dimples, 482 verts / 960 tris, an exact 1.5-stud diameter, normals and UVs. Import it and set `Config.Ball.MeshId`; see `mesh/README.md`. |
| `mesh/golfball_preview.png` | Software-rendered preview of the mesh, for review only. |

## Game passes

Upload each one in Creator Dashboard → your experience → **Monetization → Passes → Create a Pass**. Use the icon, name and description below, set the price, then paste the pass id into `Config.GamePasses.<Key>.Id`.

| File | Config key | Upload name | Recommended description | Price (Config) |
|---|---|---|---|---|
| `icons/pass_vip.png` | `VIP` | VIP | Earn +10% Coins from every match, unlock the gold VIP Aurum ball skin and show off a gold VIP nametag. | 249 |
| `icons/pass_double_coins.png` | `DoubleCoins` | 2x Coins | Double the Coins you earn from every match, forever. | 399 |
| `icons/pass_celebrations.png` | `Celebrations` | Celebration Pack | Unlock 3 exclusive cup-sink celebrations: Fireworks, Galaxy and Confetti. | 149 |
| `icons/pass_founder.png` | `Founder` | Founder | Launch-only! Get the Founder ball skin and the Founder title. | 99 |

## Developer products

Upload each one in **Monetization → Developer Products → Create**, then paste the product id into `Config.DevProducts.<Key>.Id`.

| File | Config key | Upload name | Recommended description | Price (Config) |
|---|---|---|---|---|
| `icons/product_coins_1.png` | `Coins1` | Coin Pouch | 1,000 Coins for skins, crates and upgrades. | 49 |
| `icons/product_coins_2.png` | `Coins2` | Coin Sack | 3,500 Coins for skins, crates and upgrades. | 149 |
| `icons/product_coins_3.png` | `Coins3` | Coin Chest | 10,000 Coins for skins, crates and upgrades. | 399 |
| `icons/product_coins_4.png` | `Coins4` | Coin Vault | 28,000 Coins, the best value. | 999 |
| `icons/product_mythic_crate.png` | `MythicCrate` | Mythic Featured Crate | Open 1 Mythic Featured Crate: 10% Mythic, 35% Legendary, 55% Epic. Limited global stock each season. | 99 |

The coin tiers grow in grandeur from pouch to sack to chest to vault, with matching background colours from green to blue to purple to red-gold.

## In-game references (UI images, shop signs, reward popups)

Upload these in Studio **Asset Manager → Images** (or Creator Dashboard → Development Items → Decals). Then use the resulting `rbxassetid://` id in the relevant ImageLabel / SurfaceGui. No code references them yet.

| File | Use | Suggested asset name |
|---|---|---|
| `icons/crate_skins.png` | Shop crate: **Ball Skin Crate** (`Crates.Skins`, #3D8BFF). Emblem: two-tone ball. | Crate - Ball Skins |
| `icons/crate_trails.png` | Shop crate: **Trail Crate** (`Crates.Trails`, #00E5FF). Emblem: ball + ribbon trail. | Crate - Trails |
| `icons/crate_knockouts.png` | Shop crate: **Knockout Crate** (`Crates.Knockouts`, #FF5A36). Emblem: impact burst. | Crate - Knockouts |
| `icons/crate_arrows.png` | Shop crate: **Arrow Crate** (`Crates.Arrows`, #FFC83D). Emblem: aim arrow. | Crate - Arrows |
| `icons/crate_mythic_featured.png` | **Mythic Featured Crate** shrine and hero art (`Crates.Featured`). Red + gold, aura, "MYTHIC" ribbon. | Crate - Mythic Featured |
| `icons/crate_target.png` | **Bullseye Crate** (Target practice tokens). Emblem: bullseye. | Crate - Bullseye |
| `icons/crate_drive.png` | **Long-Drive Crate** (Drive practice tokens). Emblem: rocket + speed lines. | Crate - Long Drive |
| `icons/crate_hazard.png` | **Hazard Crate** (Hazard practice tokens). Emblem: hazard stripes. | Crate - Hazard |
| `icons/icon_daily_grand.png` | 14-day login calendar grand prize: the exclusive **Eternal Dawn** ball (#FFB547 → #FF5E7E, golden rays). | Daily - Eternal Dawn |

## Experience icon

| File | Use |
|---|---|
| `icons/game_icon.png` | Creator Dashboard → your experience → **Configure → Basic Info → Icon** (512x512). The title "ULTIMATE GOLF" is drawn in the image. |

## Review

| File | Use |
|---|---|
| `icons/contact_sheet.png` | Every icon with its filename. Review only, do not upload. |
