# VPS firewall and post-deploy checklist

## Before install: DNS (Namecheap)
1. chukua.xyz uses Namecheap's nameservers (dns1/dns2.registrar-servers.com). In Namecheap: Domain List > Manage >
   Advanced DNS > Add New Record: Type `A Record`, Host `app`, Value = the VPS public IPv4, TTL Automatic. Namecheap DNS has
   no proxy, so there is nothing else to switch off. If the VPS has IPv6 add an `AAAA` too, or none.
2. Check, before running `install.sh` (and certainly before running certbot):
   ```
   dig +short app.chukua.xyz @dns1.registrar-servers.com   # must print exactly the VPS public IP before you run certbot
   ssh USER@VPS 'curl -4 -s https://ifconfig.me'; echo   # the IP to compare with
   ```
   certbot gets its certificate only when the record is in place and ports 80/443 are open (see below). A wrong record shows
   up as certificate errors in `/var/log/letsencrypt/letsencrypt.log`.
3. `CORS_ORIGINS` in `/etc/sokokuu/runner.env` must hold the GitHub Pages origin (placeholder `https://YOURUSER.github.io`
   until the user supplies it). Localhost is always allowed without an entry.

## nginx (already running on this VPS) and the runner's port
This VPS already runs nginx on ports 80 and 443 for other sites. The runner adds ONE new file and never changes any
other site's config. Nothing here may modify another `server` block, `nginx.conf` or `conf.d`.
```
ss -ltn | grep 8787          # must print nothing; docker may use 8787. If it does, set PORT=<free port> in
                             # /etc/sokokuu/runner.env and change both proxy_pass lines in the nginx file to match
sudo grep -rh server_name /etc/nginx/sites-enabled /etc/nginx/conf.d | sort -u > ~/nginx-names-before.txt; cat ~/nginx-names-before.txt
sudo cp runner/deploy/nginx-app.chukua.xyz.conf /etc/nginx/sites-available/app.chukua.xyz
sudo ln -s /etc/nginx/sites-available/app.chukua.xyz /etc/nginx/sites-enabled/app.chukua.xyz
sudo nginx -t && sudo systemctl reload nginx     # reload only after "syntax is ok"
which certbot || sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d app.chukua.xyz           # adds 443 + certificate lines to our file only; accept the redirect
sudo nginx -t && sudo systemctl reload nginx
sudo grep -rh server_name /etc/nginx/sites-enabled /etc/nginx/conf.d | sort -u | diff ~/nginx-names-before.txt -   # only app.chukua.xyz is new
for h in $(cat ~/nginx-names-before.txt | tr -d ';' | sed 's/server_name//'); do curl -sI -m 10 https://$h | head -1; done   # same answers as before
```
To undo: `sudo rm /etc/nginx/sites-enabled/app.chukua.xyz && sudo nginx -t && sudo systemctl reload nginx`.

## Firewall
The runner binds 127.0.0.1:8787 (BIND_ADDR, the testnet default), so it is unreachable from outside even without a firewall rule; keep 8787 closed there too as a second layer.
ufw may already be set up for the other sites: run `sudo ufw status` first and add rules only if needed (80/tcp, 443/tcp and
SSH must already be allowed; add nothing for 8787). Do not run `ufw enable` or change defaults if it is already active. Note that
Docker-published ports bypass ufw, but the runner is not a container. Check from your laptop that
`curl -m 5 http://VPS_IP:8787/v1/health` does NOT answer, and on the VPS `ss -ltn | grep 8787` shows `127.0.0.1:8787`. Prefer SSH keys only (no password logins).

## After deploy (set API=https://app.chukua.xyz and PAGES=https://YOURUSER.github.io)
1. Service: `systemctl status sokokuu-runner` is active; `journalctl -u sokokuu-runner -n 30` shows
   `clock synced from contract`.
2. Health: `curl -s $API/v1/health` has `"mode":"testnet"`, `"degraded":null`, the contract id
   `sokokuu.sokokuu-ken.testnet`, and `chain_drift:null`. A `relayer_balance_alarm` means top up the relayer.
3. HTTPS: `curl -sI $API/v1/health` is HTTP/2 200 with a valid certificate.
4. CORS preflight from the Pages origin:
   `curl -si -X OPTIONS $API/v1/act -H "Origin: $PAGES" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type"`
   must include `access-control-allow-origin: https://YOURUSER.github.io`. Repeat with `Origin: https://evil.example`:
   no allow-origin header. (From a checkout, `runner/scripts/cors_check.sh $PAGES` tests a local build the same way.)
5. Long-poll is not buffered: `curl -s -m 30 -w "\n%{time_total}s\n" "$API/v1/events?since=0"` returns the events at once if
   there are any, otherwise after about 25 s with no stall beyond that.
6. One guest login in the app (or `POST $API/v1/auth/guest` with `{pubkey, age_confirmed:true}`) returns a `player_id`.
7. One buy: the clock must be at midday (`/v1/state` phase). If not, advance once:
   `curl -X POST $API/v1/admin/advance -H "x-admin-token: $ADMIN_TOKEN"`. A signed buy through the app returns a
   `tx_hash` that is a real hash (not `demo:`); look it up on https://testnet.nearblocks.io.
8. Restarting the runner against a contract that already has play shows `chain_drift` after the next act (the runner
   keeps a mirror of the world). For a clean demo use a fresh contract and do not restart mid-game; see `../DEPLOY.md`.
9. Kill switch works: `curl -X POST $API/v1/admin/pause -H "x-admin-token: $ADMIN_TOKEN" -d '{"paused":true}'`, then `false`.

## Updating
`git pull && sudo bash runner/deploy/install.sh && sudo systemctl restart sokokuu-runner`. The env file is never overwritten.

## Troubleshooting: default nginx 404, certificate mismatch, or `{"detail":"Not Found"}`
Symptoms: `/v1/health` returns nginx's default 404, HTTPS shows a certificate that does not cover app.chukua.xyz, or a
FastAPI-style `{"detail":"Not Found"}` appears. Run on the VPS, in this order, and stop at the first failure:
```
# 1. Does another site already claim the name? (also look for a catch-all that proxies everything to another app)
sudo nginx -T 2>/dev/null | grep -nE "server_name|listen|proxy_pass|^# configuration file"
sudo grep -rn "chukua" /etc/nginx/
ls -l /etc/nginx/sites-enabled/
# 2. Is our file enabled and loaded?
sudo nginx -T 2>/dev/null | grep -n "app.chukua.xyz"       # must show our server block
# 3. What is really on 8787? Our runner must answer; a FastAPI/uvicorn or docker process there explains {"detail":"Not Found"}
sudo ss -ltnp | grep -E ':(80|443|8787)\b'
curl -s http://127.0.0.1:8787/v1/health                      # must be the runner's JSON
# 4. Does nginx route the name correctly, bypassing DNS and TLS?
curl -s -H 'Host: app.chukua.xyz' http://127.0.0.1/v1/health
# 5. DNS points here?
dig +short app.chukua.xyz @dns1.registrar-servers.com ; curl -4 -s https://ifconfig.me ; echo
# 6. Certificate, only after step 4 works over HTTP
sudo certbot --nginx -d app.chukua.xyz
sudo certbot certificates                                    # must list app.chukua.xyz
echo | openssl s_client -connect app.chukua.xyz:443 -servername app.chukua.xyz 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```
Reading the results:
- Step 3 shows something other than `sokokuu-runner` on 8787: pick a free port, set `PORT=` in `/etc/sokokuu/runner.env`,
  change both `proxy_pass` lines, `sudo systemctl restart sokokuu-runner`, reload nginx.
- Step 1 shows another block with `server_name app.chukua.xyz` (or `server_name _` with a regex or wildcard that also
  matches): nginx warns `conflicting server name "app.chukua.xyz"` in `nginx -t` and ignores the second one. Remove the
  duplicate name from that other block (that is the owner's decision; this kit does not edit other sites).
- Step 4 works but HTTPS shows the wrong certificate: the 443 block for the name does not exist yet. Run certbot (step 6).
  Without it, a request to https://app.chukua.xyz is served by the first 443 server block, which has another site's certificate.
- Step 4 gives the default 404: our file is not in `sites-enabled` or nginx was not reloaded (`sudo nginx -t && sudo systemctl reload nginx`).
Systemd: `systemctl is-active sokokuu-runner`, `journalctl -u sokokuu-runner -n 50 --no-pager`; if it fails to start the log names the
missing variable (key file, contract, account). `sudo systemd-analyze verify /etc/systemd/system/sokokuu-runner.service`.
Final check: `curl -s https://app.chukua.xyz/v1/health | python3 -c 'import sys,json; d=json.load(sys.stdin)["data"]; print(d["mode"], d["degraded"])'` must print `testnet None`.
