#!/usr/bin/env python3
"""Post to X (API v2, OAuth 1.0a user context). Stdlib only.

Default is a DRY RUN: prints exactly what would be posted, sends nothing.
Sending requires --send AND the text hash from the dry run (--confirm HASH),
so only text that was shown and approved can go out.

Credentials: ~/.config/soko-kuu/x.env (outside the repo, chmod 600):
  X_API_KEY= X_API_SECRET= X_ACCESS_TOKEN= X_ACCESS_SECRET=
"""
import argparse, base64, hashlib, hmac, json, os, secrets, sys, time, urllib.parse, urllib.request

ENV = os.path.expanduser("~/.config/soko-kuu/x.env")
URL = "https://api.x.com/2/tweets"
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "posted.log")

def load():
    d = {}
    try:
        for l in open(ENV):
            l = l.strip()
            if l and not l.startswith("#") and "=" in l:
                k, v = l.split("=", 1); d[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return d

def pct(s): return urllib.parse.quote(str(s), safe="~")

def auth_header(c, method, url):
    p = {"oauth_consumer_key": c["X_API_KEY"], "oauth_nonce": secrets.token_hex(16),
         "oauth_signature_method": "HMAC-SHA1", "oauth_timestamp": str(int(time.time())),
         "oauth_token": c["X_ACCESS_TOKEN"], "oauth_version": "1.0"}
    base = "&".join([method, pct(url), pct("&".join(f"{pct(k)}={pct(v)}" for k, v in sorted(p.items())))])
    key = f"{pct(c['X_API_SECRET'])}&{pct(c['X_ACCESS_SECRET'])}"
    p["oauth_signature"] = base64.b64encode(hmac.new(key.encode(), base.encode(), hashlib.sha1).digest()).decode()
    return "OAuth " + ", ".join(f'{pct(k)}="{pct(v)}"' for k, v in sorted(p.items()))

MEDIA_URL = "https://api.x.com/2/media/upload"

def upload_image(c, data, path):
    """Simple (one-shot) image upload, X API v2. Multipart body is not part of the OAuth 1.0a signature."""
    mtype = "image/png" if path.lower().endswith(".png") else "image/jpeg"
    b = "----sokokuu" + secrets.token_hex(12)
    parts = []
    for name, val in (("media_category", "tweet_image"), ("media_type", mtype)):
        parts.append(f'--{b}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{val}\r\n'.encode())
    parts.append(f'--{b}\r\nContent-Disposition: form-data; name="media"; filename="{os.path.basename(path)}"\r\n'
                 f'Content-Type: {mtype}\r\n\r\n'.encode() + data + b"\r\n")
    parts.append(f"--{b}--\r\n".encode())
    req = urllib.request.Request(MEDIA_URL, b"".join(parts), method="POST",
        headers={"Authorization": auth_header(c, "POST", MEDIA_URL),
                 "Content-Type": f"multipart/form-data; boundary={b}"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=120))
    except urllib.error.HTTPError as e:
        sys.exit(f"X media upload error {e.code}: {e.read().decode()[:300]} (nothing was posted)")
    mid = (r.get("data") or {}).get("id") or r.get("media_id_string")
    if not mid: sys.exit(f"X media upload: no media id in reply: {json.dumps(r)[:300]} (nothing was posted)")
    return str(mid)

def main():
    a = argparse.ArgumentParser()
    a.add_argument("text_file", help="file holding the exact post text")
    a.add_argument("--reply-to", help="tweet id to reply to (for threads)")
    a.add_argument("--media-id", help="already-uploaded media id")
    a.add_argument("--image", help="PNG/JPEG to upload and attach (max 5 MB); its bytes are part of the hash")
    a.add_argument("--send", action="store_true")
    a.add_argument("--confirm", help="hash printed by the dry run")
    a = a.parse_args()
    text = open(a.text_file).read().strip()
    img = open(a.image, "rb").read() if a.image else b""
    if a.image and a.media_id: sys.exit("Use --image or --media-id, not both.")
    if len(img) > 5 * 1024 * 1024: sys.exit(f"Image too big: {len(img)} bytes (max 5 MB)")
    img_sha = hashlib.sha256(img).hexdigest()[:12] if img else ""
    seed = text + "|" + (a.reply_to or "") + "|" + (a.media_id or "")
    if img: seed += "|img:" + hashlib.sha256(img).hexdigest()
    h = hashlib.sha256(seed.encode()).hexdigest()[:8]
    if len(text) > 280: sys.exit(f"Too long: {len(text)}/280")
    if "[" in text and "]" in text and any(t in text for t in ("[VERIFY", "[ATTACH", "[REPO", "[DEMO")):
        sys.exit("Placeholder still in text; fill it in first.")
    imginfo = f" image={a.image} ({len(img)} bytes, sha256 {img_sha})" if img else ""
    print(f"--- would post ({len(text)}/280) ---\n{text}\n--- reply_to={a.reply_to} media={a.media_id}{imginfo} hash={h} ---")
    if not a.send:
        print("DRY RUN. Nothing sent. To send: add --send --confirm", h); return
    if a.confirm != h: sys.exit("Hash mismatch or missing --confirm; not sent.")
    c = load()
    miss = [k for k in ("X_API_KEY","X_API_SECRET","X_ACCESS_TOKEN","X_ACCESS_SECRET") if not c.get(k)]
    if miss: sys.exit(f"Missing in {ENV}: {', '.join(miss)}")
    media_id = a.media_id
    if img:
        media_id = upload_image(c, img, a.image)
        print(f"uploaded image, media id {media_id}")
    body = {"text": text}
    if a.reply_to: body["reply"] = {"in_reply_to_tweet_id": a.reply_to}
    if media_id: body["media"] = {"media_ids": [media_id]}
    req = urllib.request.Request(URL, json.dumps(body).encode(), method="POST",
        headers={"Authorization": auth_header(c, "POST", URL), "Content-Type": "application/json"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as e:
        sys.exit(f"X error {e.code}: {e.read().decode()[:300]}")
    tid = r["data"]["id"]
    open(LOG, "a").write(f"{time.strftime('%F %T')} {tid} {h}\n")
    print(f"POSTED https://x.com/i/status/{tid}")

main()
