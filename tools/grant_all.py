"""Grant EVERY asset the game uses to Dev's alt (User 347852675) and check each grant.
Run it after any upload, from any thread (Dev 2026-11-20: new uploads kept missing grants,
"User is not authorized to access Asset" in Studio).

Why grants were missed: the permissions API answers 200 even when an asset is refused
(still processing right after upload, ...); the refusal is only in the body
("errors"). This script reads successAssetIds/errors for every id and retries refused
ones a few times.

Ids come from the lock files (art/*.lock.json) and every Config/*.luau in src (Models Id =
..., rbxassetid://...). Roblox-library sounds (Config/Sounds.luau) are not ours and are
skipped. Needs env ROBLOXAPIKEY (never printed).

  python3 tools/grant_all.py            # grant + verify all
  python3 tools/grant_all.py --user ID  # another user
"""
import glob
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from upload_images import ROOT, request  # noqa: E402

USER = sys.argv[sys.argv.index("--user") + 1] if "--user" in sys.argv else "347852675"
URL = "https://apis.roblox.com/asset-permissions-api/v1/assets/permissions"


def collect():
    ids = {}
    for path in glob.glob(os.path.join(ROOT, "art", "*.lock.json")):
        for name, e in json.load(open(path)).items():
            if isinstance(e, dict) and e.get("id"):
                ids[int(e["id"])] = name
    for path in glob.glob(os.path.join(ROOT, "src", "**", "*.luau"), recursive=True):
        if path.endswith("Sounds.luau") or path.endswith("Products.luau"):
            continue
        text = open(path).read()
        for m in re.finditer(r"(\w+) = \{ Id = (\d{6,})", text):
            ids.setdefault(int(m.group(2)), m.group(1))
        for m in re.finditer(r"rbxassetid://(\d{6,})", text):
            ids.setdefault(int(m.group(1)), os.path.basename(path))
    return ids


def grant(batch):
    body = {"subjectType": "User", "subjectId": USER, "action": "Use",
            "requests": [{"assetId": str(a), "grantToDependencies": False} for a in batch]}
    for attempt in range(5):
        code, res = request("PATCH", URL, json.dumps(body).encode(), {"Content-Type": "application/json-patch+json"})
        if code == 429 or code >= 500:
            time.sleep(2 ** attempt * 2)
            continue
        break
    ok = set(int(a) for a in (res or {}).get("successAssetIds", [])) if isinstance(res, dict) else set()
    errs = (res or {}).get("errors", []) if isinstance(res, dict) else [str(res)]
    return code, ok, errs


def main():
    ids = collect()
    todo = sorted(ids)
    print(f"{len(todo)} assets to grant to User {USER}")
    for round_ in range(4):
        failed = []
        for i in range(0, len(todo), 20):
            batch = todo[i:i + 20]
            code, ok, errs = grant(batch)
            for a in batch:
                if a not in ok:
                    failed.append(a)
            if errs and round_ == 3:
                print(f"  errors: {json.dumps(errs)[:600]}")
        if not failed:
            print(f"all {len(ids)} granted and confirmed")
            return 0
        print(f"round {round_ + 1}: {len(failed)} refused, retrying in 20 s")
        todo = failed
        time.sleep(20)
    for a in todo:
        print(f"NOT GRANTED: {ids[a]} {a}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
