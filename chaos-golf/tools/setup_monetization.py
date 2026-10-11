"""Create Ultimate Golf's game passes and developer products through Open Cloud, then write their
ids into src/shared/Config.luau.

Usage: python3 tools/setup_monetization.py UNIVERSE_ID [--dry-run]

Auth: the x-api-key header is added by the environment's network proxy (never stored here).
Idempotent: anything that already exists with the same name is reused, not recreated.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "shared", "Config.luau")
ICONS = os.path.join(ROOT, "assets", "icons")
API = "https://apis.roblox.com"

PASSES = [  # (Config key, name, price, description, icon, for sale)
    ("VIP", "VIP", 249, "+10% coins from every match, the VIP Aurum Legendary skin and a gold nametag.", "pass_vip.png", True),
    ("DoubleCoins", "2x Coins", 399, "Double coins from every match.", "pass_double_coins.png", True),
    ("Celebrations", "Celebration Pack", 149, "3 exclusive cup-sink celebrations: Fireworks, Galaxy and Confetti.",
     "pass_celebrations.png", True),
    ("Founder", "Founder", 99, "Founder Epic skin and the FOUNDER title. Launch only!", "pass_founder.png", True),
]
PRODUCTS = [  # (Config key, name, price, description, icon)
    ("Coins1", "Coin Pouch", 49, "1,000 coins.", "product_coins_1.png"),
    ("Coins2", "Coin Sack", 149, "3,500 coins.", "product_coins_2.png"),
    ("Coins3", "Coin Chest", 399, "10,000 coins.", "product_coins_3.png"),
    ("Coins4", "Coin Vault", 999, "28,000 coins.", "product_coins_4.png"),
    ("MythicCrate", "Mythic Featured Crate", 99,
     "Open 1 Mythic Featured Crate (odds shown in game). If the global stock is sold out you get 6,000 coins instead.",
     "product_mythic_crate.png"),
]


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "60", "-w", "\n%{http_code}", *args], capture_output=True, text=True)
    body, _, code = r.stdout.rpartition("\n")
    try:
        data = json.loads(body) if body.strip() else {}
    except json.JSONDecodeError:
        data = {"raw": body[:400]}
    return int(code or 0), data


def existing(universe):
    _, p = curl(f"{API}/game-passes/v1/universes/{universe}/game-passes/creator?pageSize=100")
    _, d = curl(f"{API}/developer-products/v2/universes/{universe}/developer-products/creator?pageSize=100")
    passes = {x["name"]: x["gamePassId"] for x in p.get("gamePasses", [])}
    products = {x["name"]: x["productId"] for x in d.get("developerProducts", [])}
    return passes, products


def create(kind, universe, name, price, desc, icon, for_sale):
    url = (f"{API}/game-passes/v1/universes/{universe}/game-passes" if kind == "pass"
           else f"{API}/developer-products/v2/universes/{universe}/developer-products")
    code, data = curl("-X", "POST", url, "-F", f"name={name}", "-F", f"description={desc}",
                      "-F", f"isForSale={'true' if for_sale else 'false'}", "-F", f"price={price}",
                      "-F", f"imageFile=@{os.path.join(ICONS, icon)};type=image/png")
    if code not in (200, 201):
        raise SystemExit(f"create {kind} {name!r} failed [{code}]: {json.dumps(data)[:400]}")
    ident = data.get("gamePassId") or data.get("productId") or data.get("id")
    if not ident:
        raise SystemExit(f"create {kind} {name!r}: no id in response {json.dumps(data)[:400]}")
    return int(ident)


def write_ids(ids):
    src = open(CONFIG, encoding="utf-8").read()
    for key, ident in ids.items():
        pat = re.compile(r"(\n\t" + re.escape(key) + r" = \{ Id = )\d+")
        src, n = pat.subn(lambda m: m.group(1) + str(ident), src, count=1)
        if n != 1:
            raise SystemExit(f"Config.luau: no entry for {key}")
    open(CONFIG, "w", encoding="utf-8").write(src)


def main(argv):
    if not argv or not argv[0].isdigit():
        raise SystemExit(__doc__)
    universe, dry = argv[0], "--dry-run" in argv
    have_passes, have_products = existing(universe)
    ids = {}
    for key, name, price, desc, icon, for_sale in PASSES:
        if name in have_passes:
            ids[key] = have_passes[name]
            print(f"pass    {name:<22} exists  {ids[key]}")
        elif dry:
            print(f"pass    {name:<22} would create ({price} R$)")
        else:
            ids[key] = create("pass", universe, name, price, desc, icon, for_sale)
            print(f"pass    {name:<22} created {ids[key]}")
    for key, name, price, desc, icon in PRODUCTS:
        if name in have_products:
            ids[key] = have_products[name]
            print(f"product {name:<22} exists  {ids[key]}")
        elif dry:
            print(f"product {name:<22} would create ({price} R$)")
        else:
            ids[key] = create("product", universe, name, price, desc, icon, True)
            print(f"product {name:<22} created {ids[key]}")
    if ids and not dry:
        write_ids(ids)
        print(f"wrote {len(ids)} ids into {os.path.relpath(CONFIG, ROOT)}")


if __name__ == "__main__":
    main(sys.argv[1:])
