#!/usr/bin/env python3
"""Writes ~/.config/soko-kuu/x.env from hidden prompts. Nothing is echoed or logged."""
import getpass, os
path = os.path.expanduser("~/.config/soko-kuu/x.env")
os.makedirs(os.path.dirname(path), exist_ok=True)
labels = [("X_API_KEY", "Consumer Key (API Key)"), ("X_API_SECRET", "Consumer Secret (API Key Secret)"),
          ("X_ACCESS_TOKEN", "Access Token"), ("X_ACCESS_SECRET", "Access Token Secret")]
vals = {}
for k, label in labels:
    v = getpass.getpass(f"{label} (hidden, paste then Enter): ").strip().strip('"\'')
    vals[k] = v
    print(f"  got {len(v)} characters")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    f.writelines(f"{k}={v}\n" for k, v in vals.items())
print(f"Saved {path} (mode 600). Next: python3 social/check_keys.py")
