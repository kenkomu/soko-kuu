#!/usr/bin/env bash
# Run ON THE VPS, as root (sudo), from a checkout of the whole repo (the runner depends on ../econ):
#   sudo bash runner/deploy/install.sh
# Fresh Ubuntu 24.04 x86-64 prerequisites (run once, before this script):
#   sudo apt update && sudo apt install -y build-essential pkg-config libssl-dev cmake git curl
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y     # as your normal user, not root
#   source "$HOME/.cargo/env"
# The build needs about 1 GB RAM per compiler job. Machines with 4 GB or more (e.g. 7.8 GB) need nothing special; below
# 3 GB without swap this script adds a 2 GB swap file and uses one job; 3 to 4 GB uses 2 jobs. Disk: about 4 GB for the release build (target/ plus ~/.cargo).
# It builds the release binary (about 5 minutes on 8 cores; expect 15 to 25 minutes on 1 to 2 vCPUs),
# creates the unprivileged user, installs the binary, the systemd unit and an env template.
# It contacts no server except what cargo fetches while building. It never touches your key.
#
# Build on the VPS or cross-compile? Build on the VPS (this script): the binary links the VPS's own glibc, so there is
# no mismatch. Copying a binary built on a newer desktop distro (scp) can fail with "GLIBC_x.y not found"; only do it
# when the VPS and your machine run the same distro release and CPU architecture:
#   cargo build --release --manifest-path runner/rs/Cargo.toml && scp runner/rs/target/release/sokokuu-runner VPS:/tmp/
# then on the VPS: install -m 755 /tmp/sokokuu-runner /opt/sokokuu/bin/ && systemctl restart sokokuu-runner
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root: sudo bash $0"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
RS="$HERE/../rs"
[ -f "$RS/Cargo.toml" ] && [ -d "$RS/../../econ" ] || { echo "run from a full repo checkout (runner/ and econ/ side by side)"; exit 1; }

# cargo usually lives in the invoking user's home, not root's
if ! command -v cargo >/dev/null; then
  U="${SUDO_USER:-}"; H="$(getent passwd "$U" | cut -d: -f6 || true)"
  [ -x "$H/.cargo/bin/cargo" ] && export PATH="$H/.cargo/bin:$PATH"
fi
command -v cargo >/dev/null || { echo "cargo not found. As your normal user: sudo apt install -y build-essential pkg-config libssl-dev cmake git curl; curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then rerun with sudo bash"; exit 1; }
command -v cc >/dev/null && command -v pkg-config >/dev/null || { echo "missing build tools: sudo apt install -y build-essential pkg-config libssl-dev cmake"; exit 1; }

# Low-memory VPS: the dependency tree (near-* crates) can be killed by the OOM killer without swap.
MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo); SWAP_KB=$(awk '/SwapTotal/{print $2}' /proc/meminfo)
if [ "$MEM_KB" -lt 3000000 ] && [ "$SWAP_KB" -eq 0 ]; then
  echo "== low memory: creating a 2 GB swap file /swapfile"
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
AVAIL_KB=$(df --output=avail -k "$RS" | tail -1)
[ "$AVAIL_KB" -gt 5000000 ] || echo "WARNING: less than 5 GB free disk; the build may fail"
# Fewer parallel jobs on small machines keeps peak memory down (use CARGO_BUILD_JOBS=2 yourself if you like).
if [ "$MEM_KB" -lt 3000000 ]; then export CARGO_BUILD_JOBS=1
elif [ "$MEM_KB" -lt 6000000 ]; then export CARGO_BUILD_JOBS=2   # 6 GB or more: cargo's default (all cores)
fi

if ss -ltn 2>/dev/null | grep -qE '[:.]8787\b' && ! systemctl is-active --quiet sokokuu-runner; then
  echo "WARNING: something already listens on port 8787. Pick another PORT in /etc/sokokuu/runner.env and in the nginx proxy_pass."
fi

echo "== building"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  # build as the normal user so target/ and ~/.cargo stay owned by them
  sudo -u "$SUDO_USER" env "PATH=$PATH" ${CARGO_BUILD_JOBS:+CARGO_BUILD_JOBS=$CARGO_BUILD_JOBS} bash -c "cd '$RS' && cargo build --release --features testnet"
else
  ( cd "$RS" && cargo build --release --features testnet )
fi

echo "== user and directories"
id sokokuu >/dev/null 2>&1 || useradd --system --home-dir /var/lib/sokokuu --create-home --shell /usr/sbin/nologin sokokuu
install -d -m 755 /opt/sokokuu/bin
install -d -m 750 -o root -g sokokuu /etc/sokokuu
install -m 755 "$RS/target/release/sokokuu-runner" /opt/sokokuu/bin/sokokuu-runner
install -m 644 "$HERE/sokokuu-runner.service" /etc/systemd/system/sokokuu-runner.service
if [ ! -f /etc/sokokuu/runner.env ]; then
  install -m 600 -o root -g root "$HERE/runner.env.example" /etc/sokokuu/runner.env
  echo "created /etc/sokokuu/runner.env from the template: EDIT IT (CORS_ORIGINS, ADMIN_TOKEN, PHASE_SECS)"
fi
systemctl daemon-reload

cat <<'MSG'

== next steps (nothing is started yet)
0. DNS first (certbot needs it to get the certificate): in Namecheap (Advanced DNS) add an A record: Host app, Value = this
   VPS's public IPv4, TTL Automatic. Check:  dig +short app.chukua.xyz @dns1.registrar-servers.com   (must print this VPS's IP)
   On the VPS:  curl -4 -s https://ifconfig.me ; echo      and compare. Do not continue to step 4 until they match.
   Port check: `ss -ltn | grep 8787` must print nothing (docker or another service may use it). If it prints a line, pick a
   free port: set PORT=<free port> in /etc/sokokuu/runner.env and use the same port in the nginx proxy_pass lines.
1. Copy the relayer key file from YOUR machine (run this there, not here). The key file path on your machine is
   ~/.near-credentials/testnet/relayer.sokokuu-ken.testnet.key ; replace USER and VPS_HOST:

     scp ~/.near-credentials/testnet/relayer.sokokuu-ken.testnet.key USER@VPS_HOST:/tmp/relayer.key

   Then on the VPS:

     sudo install -m 600 -o sokokuu -g sokokuu /tmp/relayer.key /etc/sokokuu/relayer.key
     sudo shred -u /tmp/relayer.key
     ls -l /etc/sokokuu/relayer.key        # must show -rw------- sokokuu sokokuu

   (The env file reads it via RELAYER_KEY_FILE=/etc/sokokuu/relayer.key. The service user needs to read the env file:
   it is read by systemd as root, so root ownership with mode 600 is correct.)
2. Edit the settings:  sudo nano /etc/sokokuu/runner.env      (ADMIN_TOKEN: openssl rand -hex 24)
3. Start:  sudo systemctl enable --now sokokuu-runner && sudo journalctl -u sokokuu-runner -n 30 --no-pager
   Expect: "clock synced from contract" and no "testnet unavailable".
4. HTTPS with the EXISTING nginx (it already serves other sites on 80/443; never edit their config, add only our own file):
     sudo grep -rh server_name /etc/nginx/sites-enabled /etc/nginx/conf.d | sort -u    # note the other sites
     sudo cp runner/deploy/nginx-app.chukua.xyz.conf /etc/nginx/sites-available/app.chukua.xyz
     sudo ln -s /etc/nginx/sites-available/app.chukua.xyz /etc/nginx/sites-enabled/app.chukua.xyz
     sudo nginx -t && sudo systemctl reload nginx          # reload only if the test says ok
     which certbot || sudo apt install -y certbot python3-certbot-nginx
     sudo certbot --nginx -d app.chukua.xyz                # edits only our file; answer yes to the redirect
     sudo nginx -t && sudo systemctl reload nginx
   Then run  curl -sI https://<each other site's name>  and check they answer as before.
5. Firewall and checklist: runner/deploy/CHECKLIST.md (check `sudo ufw status` first; add rules only if needed)
MSG
