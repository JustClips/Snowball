"""Grant every uploaded Snowball asset (models, images, animations) to a game's universe,
with grantToDependencies so a model's meshes and textures come along (Dev 2026-11-20:
place 130604909447489 = universe 10778042297). Needs env ROBLOXAPIKEY (never printed).

  python3 tools/grant_universe.py [universeId]
"""
import json, os, sys, time

sys.path.insert(0, os.path.dirname(__file__))
from upload_images import ROOT, request  # noqa: E402

UNIVERSE = sys.argv[1] if len(sys.argv) > 1 else "10778042297"
LOCKS = ["models.lock.json", "images.lock.json", "anims.lock.json"]


def grant(ids, deps):
    body = {"subjectType": "Universe", "subjectId": UNIVERSE, "action": "Use",
            "requests": [{"assetId": str(a), "grantToDependencies": deps} for a in ids]}
    for attempt in range(5):
        code, res = request("PATCH", "https://apis.roblox.com/asset-permissions-api/v1/assets/permissions",
                            json.dumps(body).encode(), {"Content-Type": "application/json-patch+json"})
        if code == 429 or code >= 500:
            time.sleep(2 ** attempt * 2)
            continue
        return code, res
    return code, res


def main():
    total, failed = 0, []
    for f in LOCKS:
        p = os.path.join(ROOT, "art", f)
        if not os.path.exists(p):
            continue
        lock = json.load(open(p))
        items = sorted(lock.items())
        deps = f == "models.lock.json"
        for i in range(0, len(items), 20):
            chunk = items[i:i + 20]
            code, res = grant([e["id"] for _, e in chunk], deps)
            total += len(chunk)
            if code >= 300:
                failed += [n for n, _ in chunk]
                print(f"{f} chunk {i}: {code} {str(res)[:300]}", flush=True)
            else:
                errs = (res or {}).get("errors") if isinstance(res, dict) else None
                if errs:
                    print(f"{f} chunk {i}: partial {str(errs)[:300]}", flush=True)
    print(f"granted {total - len(failed)}/{total} assets to universe {UNIVERSE}")


if __name__ == "__main__":
    main()
