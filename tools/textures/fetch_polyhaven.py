"""fetch_polyhaven.py OUT_DIR asset_id... (RES=1k|2k): diffuse, GL normal, roughness and AO maps."""
import json, sys, os, urllib.request
out = sys.argv[1]
ids = sys.argv[2:]
UA = {"User-Agent": "BurnGameDev/1.0 (texture fetch)"}


def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()


for i in ids:
    files = json.loads(fetch("https://api.polyhaven.com/files/" + i))
    want = {"Diffuse": "diff", "nor_gl": "nor", "Rough": "rough", "AO": "ao"}
    for key, short in want.items():
        if key not in files:
            print(i, "missing", key, list(files.keys()))
            continue
        res = files[key].get(os.environ.get("RES","1k"))
        fmt = res.get("jpg") or res.get("png")
        ext = "jpg" if "jpg" in res else "png"
        dest = os.path.join(out, f"{i}_{short}.{ext}")
        with open(dest, "wb") as f:
            f.write(fetch(fmt["url"]))
    print("ok", i)
