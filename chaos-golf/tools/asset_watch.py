"""Watch the Roblox Creator Store for re-uploads of our models.

Searches the Toolbox (Models) for each watched asset's keywords and reports models
uploaded in the last N days by anyone other than the owning group. Roblox has no
usage alerts for assets, so this catches the common case: a stolen copy being
re-published to the Creator Store. Private copies inside other games can't be seen.

Usage: python3 tools/asset_watch.py [--days 8]
Prints "NO NEW MATCHES" or one line per suspect with a store link.
"""
import argparse
import datetime as dt
import json
import sys
import urllib.parse
import urllib.request

OWNER_GROUP = 187537803  # Corny Games

WATCHED = [
    {
        "name": "Premium Marble Fountain",
        "asset": 114362425242752,
        "uploaded": "2026-10-11T08:01:17Z",  # a copy can't be older than the original
        "must_mention": "fountain",
        "keywords": ["premium marble fountain", "marble fountain", "three tier fountain", "luxury fountain", "lobby fountain", "golf fountain"],
    },
]

API = "https://apis.roblox.com/toolbox-service/v1"


def get(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "corny-asset-watch"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def search(keyword, pages=2):
    ids, cursor = [], ""
    for _ in range(pages):
        q = {"keyword": keyword, "limit": 30}
        if cursor:
            q["cursor"] = cursor
        data = get(f"{API}/marketplace/10?{urllib.parse.urlencode(q)}")
        ids += [x["id"] for x in data.get("data", [])]
        cursor = data.get("nextPageCursor") or ""
        if not cursor:
            break
    return ids


def details(ids):
    out = []
    for i in range(0, len(ids), 30):
        chunk = ",".join(str(x) for x in ids[i:i + 30])
        out += get(f"{API}/items/details?assetIds={chunk}").get("data", [])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=8)
    args = ap.parse_args()
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)
    suspects = []
    for w in WATCHED:
        ids = []
        for kw in w["keywords"]:
            try:
                ids += search(kw)
            except Exception as e:  # keep going: one failed search shouldn't hide the rest
                print(f"search failed for {kw!r}: {e}", file=sys.stderr)
        seen = set()
        for item in details(list(dict.fromkeys(ids))):
            a, c = item.get("asset", {}), item.get("creator", {})
            if a.get("id") in seen or a.get("id") == w["asset"]:
                continue
            seen.add(a.get("id"))
            if c.get("type") == 2 and c.get("id") == OWNER_GROUP:
                continue
            created = dt.datetime.fromisoformat(a.get("createdUtc", "1970-01-01T00:00:00Z").replace("Z", "+00:00"))
            original = dt.datetime.fromisoformat(w["uploaded"].replace("Z", "+00:00"))
            text = (a.get("name", "") + " " + a.get("description", "")).lower()
            if created >= max(since, original) and w["must_mention"] in text:
                suspects.append((w["name"], a, c, created))
    if not suspects:
        print("NO NEW MATCHES")
        return
    for name, a, c, created in suspects:
        print(f"[{name}] {a.get('name')!r} by {c.get('name')} ({'group' if c.get('type') == 2 else 'user'} {c.get('id')}), "
              f"uploaded {created:%Y-%m-%d}, scripts {a.get('scriptCount', 0)}: https://create.roblox.com/store/asset/{a.get('id')}")


if __name__ == "__main__":
    main()
