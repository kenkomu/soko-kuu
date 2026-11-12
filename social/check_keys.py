#!/usr/bin/env python3
"""Checks the X keys without posting: format check, then GET /2/users/me. Prints only the username."""
import json, os, sys, urllib.request, urllib.error
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "post.py")).read().replace("\nmain()\n", "\n")
ns = {"__name__": "post", "__file__": os.path.join(os.path.dirname(os.path.abspath(__file__)), "post.py")}; exec(compile(src, "post.py", "exec"), ns)
c = ns["load"]()
need = {"X_API_KEY": (20, 30), "X_API_SECRET": (40, 60), "X_ACCESS_TOKEN": (40, 60), "X_ACCESS_SECRET": (40, 60)}
ok = True
for k, (lo, hi) in need.items():
    n = len(c.get(k, ""))
    flag = "ok" if lo <= n <= hi else ("MISSING" if n == 0 else "odd length")
    if flag != "ok": ok = False
    print(f"{k}: {n} chars -> {flag}")
if os.path.exists(ns["ENV"]) and oct(os.stat(ns["ENV"]).st_mode)[-3:] != "600": print("WARNING: run chmod 600 on the file")
if not ok: sys.exit("Fix the lines above first (typical lengths: key 25, secret 50, token ~50, token secret 45).")
url = "https://api.x.com/2/users/me"
req = urllib.request.Request(url, headers={"Authorization": ns["auth_header"](c, "GET", url)})
try:
    r = json.load(urllib.request.urlopen(req, timeout=30))
    print("KEYS WORK. Posting account: @" + r["data"]["username"])
except urllib.error.HTTPError as e:
    sys.exit(f"X rejected it ({e.code}): {e.read().decode()[:250]}")
