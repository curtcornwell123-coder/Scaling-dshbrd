"""Create game passes / developer products for Merge A Egg and Cyber Swarm through Open Cloud.

Everything is created OFF SALE: the games' scripts must check these ids first. Put them on sale in
Creator Hub (or re-run with --on-sale for a game) once the code honours them.
Idempotent: items that already exist with the same name are reused. Ids -> marketing/<game>/passes/ids.json

Usage: python3 marketing/create_passes.py merge|cyber [--dry-run] [--on-sale]
Auth: the x-api-key header is added by the environment's network proxy.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://apis.roblox.com"

GAMES = {
    "merge": {
        "universe": "10770247652",
        "passes": [
            ("VIP", 249, "Exclusive VIP tag and perks.", "merge_vip"),
            ("2x Speed", 199, "Double the speed you gain on treadmills.", "merge_2x_speed"),
            ("2x Egg Luck", 249, "Double luck for rare eggs.", "merge_2x_luck"),
            ("Auto Merge", 299, "Automatically merges matching eggs in your base.", "merge_auto_merge"),
            ("Extra Merger", 149, "Adds one extra merger to your base.", "merge_extra_merger"),
        ],
        "products": [
            ("2x Server Luck (15 min)", 49, "Double egg luck for the whole server for 15 minutes.", "merge_server_luck"),
            ("Speed Boost (15 min)", 29, "Double treadmill speed gains for 15 minutes.", "merge_speed_boost"),
        ],
    },
    "cyber": {
        "universe": "10769914606",
        "passes": [
            ("VIP", 249, "Exclusive VIP tag and perks.", "cyber_vip"),
            ("2x Coins", 299, "Double coins.", "cyber_2x_coins"),
            ("Extra Robot Slot", 149, "Bring one more robot into every push.", "cyber_extra_slot"),
            ("2x Game Speed", 199, "Play at double speed.", "cyber_2x_speed"),
        ],
        "products": [
            ("Coin Pack (Small)", 49, "A small pack of coins.", "cyber_coins_1"),
            ("Coin Pack (Medium)", 149, "A medium pack of coins.", "cyber_coins_2"),
            ("Coin Pack (Large)", 399, "A large pack of coins.", "cyber_coins_3"),
        ],
    },
}


def curl(*args):
    r = subprocess.run(["curl", "-sS", "-m", "90", "-w", "\n%{http_code}", *args], capture_output=True, text=True)
    body, _, code = r.stdout.rpartition("\n")
    try:
        data = json.loads(body) if body.strip() else {}
    except json.JSONDecodeError:
        data = {"raw": body[:400]}
    return int(code or 0), data


def main(argv):
    game = argv[0] if argv else ""
    if game not in GAMES:
        raise SystemExit(__doc__)
    dry, on_sale = "--dry-run" in argv, "--on-sale" in argv
    spec, uni = GAMES[game], GAMES[game]["universe"]
    icons = os.path.join(HERE, game, "passes")
    _, p = curl(f"{API}/game-passes/v1/universes/{uni}/game-passes/creator?pageSize=100")
    _, d = curl(f"{API}/developer-products/v2/universes/{uni}/developer-products/creator?pageSize=100")
    have = {("pass", x["name"]): x["gamePassId"] for x in p.get("gamePasses", [])}
    have.update({("product", x["name"]): x["productId"] for x in d.get("developerProducts", [])})
    ids_path = os.path.join(icons, "ids.json")
    ids = json.load(open(ids_path)) if os.path.exists(ids_path) else {"passes": {}, "products": {}}
    for kind, url, items in (("pass", f"{API}/game-passes/v1/universes/{uni}/game-passes", spec["passes"]),
                             ("product", f"{API}/developer-products/v2/universes/{uni}/developer-products",
                              spec["products"])):
        bucket = ids["passes" if kind == "pass" else "products"]
        for name, price, desc, icon in items:
            if (kind, name) in have:
                bucket[name] = have[(kind, name)]
                print(f"{kind:<8}{name:<26} exists  {bucket[name]}")
                continue
            if dry:
                print(f"{kind:<8}{name:<26} would create ({price} R$, {'on' if on_sale else 'off'} sale)")
                continue
            code, data = curl("-X", "POST", url, "-F", f"name={name}", "-F", f"description={desc}",
                              "-F", f"isForSale={'true' if on_sale else 'false'}", "-F", f"price={price}",
                              "-F", f"imageFile=@{os.path.join(icons, icon + '.png')};type=image/png")
            ident = data.get("gamePassId") or data.get("productId") or data.get("id")
            if code not in (200, 201) or not ident:
                raise SystemExit(f"create {kind} {name!r} failed [{code}]: {json.dumps(data)[:400]}")
            bucket[name] = int(ident)
            print(f"{kind:<8}{name:<26} created {ident}")
            json.dump(ids, open(ids_path, "w"), indent=2)
    if not dry:
        json.dump(ids, open(ids_path, "w"), indent=2)
        print("ids ->", os.path.relpath(ids_path, os.path.dirname(HERE)))


if __name__ == "__main__":
    main(sys.argv[1:])
