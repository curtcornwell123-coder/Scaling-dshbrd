# Ultimate Golf — Economy & Price Sheet

Design rule: **nothing you can buy wins a match.** Stat upgrades (the only power) are coin-only and switched off in Ranked 1v1. Robux buys cosmetics, convenience and support. Every crate shows its odds in-world, has a pity guarantee, and refunds part of the price on duplicates.

## How fast players earn (no boosts)

| Source | Amount | Notes |
|---|---|---|
| Match (≈9 min incl. intro/scorecards) | ≈145 coins avg | 25 participation + 3/hole + 10/birdie + 50/hole-in-one + placement + 4/sabotage (cap 40) |
| Placement — Ranked 1v1 | 120 win / 70 draw / 40 loss | |
| Placement — Classic (4) | 150 / 90 / 60 / 40 | |
| Placement — Race (8) | 180 / 140 / 110 / 90 / 75 / 60 / 50 / 40 | |
| Queue drip (standing in a bubble) | +1/30s → +2/20s → +5/15s | Never boosted |
| 14-day login calendar | 3,700 coins + 7 crate keys + 3 exclusive cosmetics + Eternal Dawn | Resets if a day is missed |
| Practice minigames | 1–6 tokens per run | Tokens can't be bought |

**≈950 coins / hour** of matches for a typical player. Friend in server +15%, VIP +10%, 2x Coins doubles the total (match rewards only).

## Coin prices (time to earn at ≈950/h)

| Item | Price | Time |
|---|---|---|
| Common skin (daily rotation) | 300 | ~19 min |
| Rare skin | 900 | ~57 min |
| Epic skin | 2,500 | ~2.6 h |
| Legendary skin | 7,000 | ~7.4 h |
| Ball Skin Crate | 600 | ~38 min |
| Trail Crate / Knockout Crate | 500 | ~32 min |
| Arrow Crate | 400 | ~25 min |
| Mythic Featured Crate | 6,000 | ~6.3 h (or 99 Robux) |
| Upgrade levels 1→5 (per stat) | 400 / 900 / 1,800 / 3,500 / 6,500 | 13,100 per stat, 39,300 for all three (~41 h) |

## Crate odds (also shown on every crate)

| Crate | Common | Rare | Epic | Legendary | Mythic | Pity |
|---|---|---|---|---|---|---|
| Ball Skin (600) | 55% | 28% | 12% | 4.4% | 0.6% | Legendary+ within 35 |
| Trail / Knockout (500) | 52% | 30% | 13% | 4.2% | 0.8% | Legendary+ within 30 |
| Arrow (400) | 52% | 30% | 13% | 4.2% | 0.8% | Legendary+ within 30 |
| Mythic Featured (6,000 / 99 R$) | — | — | 55% | 35% | 10% | Mythic within 12 |
| Token crates (12 tokens) | 50% | 32% | 14% | 4% | — | Legendary within 25 |

Duplicates refund a multiple of the crate price: Common 0.15×, Rare 0.35×, Epic 0.75×, Legendary 1.5×, Mythic 3×.
The Mythic Featured Crate has one **global** stock of 10,000 per season, shared by every server; every skin in it can also be earned with coins.

## Robux: what to create (Creator Dashboard → Monetization)

Upload the matching icon from `assets/icons/`, then paste each id into `src/shared/Config.luau` (`Config.GamePasses` / `Config.DevProducts`). Anything left at `Id = 0` shows "Coming soon" in-game and can't be bought.

### Game passes

| Pass | Price | What it does | Icon |
|---|---|---|---|
| VIP | **249 R$** | +10% match coins, VIP Aurum Legendary skin, gold name | `pass_vip.png` |
| 2x Coins | **399 R$** | Doubles match coins (not queue drip, refunds or tokens) | `pass_double_coins.png` |
| Celebration Pack | **149 R$** | 3 exclusive cup-sink celebrations (Fireworks, Galaxy, Confetti) | `pass_celebrations.png` |
| Founder | **99 R$** | Founder Epic skin + FOUNDER title. Sell at launch only, then take it off sale | `pass_founder.png` |

### Developer products

| Product | Price | Grants | Coins per Robux | Icon |
|---|---|---|---|---|
| Coin Pouch | **49 R$** | 1,000 coins (~1 h of play) | 20.4 | `product_coins_1.png` |
| Coin Sack | **149 R$** | 3,500 coins | 23.5 | `product_coins_2.png` |
| Coin Chest | **399 R$** | 10,000 coins | 25.1 | `product_coins_3.png` |
| Coin Vault | **999 R$** | 28,000 coins | 28.0 | `product_coins_4.png` |
| Mythic Featured Crate | **99 R$** | 1 Mythic Featured Crate open (uses global stock; sold out = 6,000 coins instead) | — | `product_mythic_crate.png` |

Why these prices: passes sit at the common Roblox price points (99–399) for their value tier; coin packs give a mild bulk bonus so bigger packs feel fair without making the small one a rip-off; one pouch ≈ one hour of play, so a 49 R$ purchase is a time-saver, never a power purchase.

## Creator codes

Codes live in `Config.CreatorCodes` (`CODE = { Name, UserId }`). While a player has a code cached, every coin spend and Robux purchase is added to the `UltimateGolf_v1_CreatorSales` DataStore under that code (`Coins`, `Robux`, `Purchases`, `Supporters`). Roblox can't split Robux automatically, so pay creators from those totals (for example, 10–20% of attributed Robux, paid with group payouts).

## Fairness checklist

- Odds are visible in-world before every crate open; pity counters are saved per crate.
- Upgrades never apply in Ranked; Ranked rewards (tier skins) are earned only by playing.
- Token currencies can't be bought with coins or Robux.
- Paid random items (Mythic crate for Robux) show their odds, per Roblox's paid random item policy.
