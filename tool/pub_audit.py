"""Print pub.dev metadata for packages: version, date, publisher, licence, platforms, points, likes.

Usage: python -I tool/pub_audit.py record drift camera ...
Used in P0-01 to fill docs/ARCHITECTURE.md section 6.
"""
import json, urllib.request, sys
from concurrent.futures import ThreadPoolExecutor

def get(u):
    with urllib.request.urlopen(u, timeout=30) as r:
        return json.load(r)

def one(p):
    try:
        a = get(f"https://pub.dev/api/packages/{p}")
        s = get(f"https://pub.dev/api/packages/{p}/score")
        pub = get(f"https://pub.dev/api/packages/{p}/publisher").get("publisherId")
        tags = s.get("tags", [])
        lic = ",".join(t[8:] for t in tags if t.startswith("license:") and t not in ("license:osi-approved", "license:fsf-libre"))
        plat = ",".join(t[9:] for t in tags if t.startswith("platform:"))
        disc = "DISCONTINUED" if a.get("isDiscontinued") else ""
        if a.get("replacedBy"):
            disc += " replacedBy=" + a["replacedBy"]
        lat = a["latest"]
        sdk = lat["pubspec"].get("environment", {})
        return f"{p}|{lat['version']}|{lat.get('published','')[:10]}|{pub}|{lic}|{plat}|{s.get('grantedPoints')}/{s.get('maxPoints')}|{s.get('likeCount')}|{disc}|{sdk}"
    except Exception as e:
        return f"{p}|ERROR {e}"

with ThreadPoolExecutor(8) as ex:
    for line in ex.map(one, sys.argv[1:]):
        print(line)
