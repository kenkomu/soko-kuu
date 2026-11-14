STATUS: DRAFT, not posted

Checklist for today, Sat 14 Nov 2026. The hackathon deadline is 23:59 UTC tonight (CLAUDE.md).
Steps Ken does by hand are marked (Ken). Nothing here is posted by an agent without Ken's yes for the exact text.

Already live on X (posted.log)
- Text post: https://x.com/i/status/2120539714369225111 (11 Nov 2026)
- Poster post with the required tags: https://x.com/i/status/2120544157483598158 (11 Nov 2026)

1. Check the links open (Ken, 2 minutes)
- [ ] https://kenkomu.github.io/soko-kuu/ opens in a private window. Tap "I am 18 or older. Start". You see "Play Soko Run" and "Live market on NEAR".
- [ ] "Live market on NEAR", then "Play as a guest (no email)" loads the Soko tab with prices (this checks the runner and CORS from the browser).
- [ ] https://app.chukua.xyz/v1/health shows "mode":"testnet" and "degraded":null (it did at 09:45 on 14 Nov 2026).
- [ ] https://github.com/kenkomu/soko-kuu opens while logged out (repo is public, LICENSE is MIT).

2. Record the demo video (Ken)
- [ ] Start at the age gate, then the choice screen.
- [ ] Soko Run: "Play your first market". Buy tomatoes on day 1 (Radio Soko says they will rise), tap "Next day", see "Radio was right", sell, play to day 5, "Close the market", show the score and title.
- [ ] Live market on NEAR: guest play, open a crop for "Why this price", buy and sell, then Duka, Chama and Ripoti ("What if? Fast-forward", 30 days, Drought).
- [ ] Say or caption that it is NEAR testnet and that Soko Run is offline. Do not show or say goods are tokens (not deployed yet).
- [ ] [VERIFY] Hackathon video rules (length, format, where it must be hosted). Not in the repo; check the hackathon page.

3. Post the video post (Ken picks option A or B in social/post-02-video.md)
- [ ] Way 1 (simplest): paste the chosen text exactly into X, attach the video, post.
- [ ] Way 2: upload the video, give the xposter the media id. The xposter runs a new dry run with `--media-id`, the hash changes, Ken says yes to that exact text and hash, then it is sent.
- [ ] Open the new post logged out: the video plays, @NEARProtocol is a link, #NEARHackathon is a link, both URLs open.
- [ ] Copy the post link (https://x.com/i/status/...). Give the id to the xposter.

4. Thread (optional, after step 3)
- [ ] social/thread.md, posts 2 to 9, each a reply to the one before, each with its own dry run and yes. Skip it if time is short.

5. Submit the hackathon form before 23:59 UTC tonight (Ken)
- [ ] [VERIFY] Form link and fields are not in the repo. Check the hackathon page.
- [ ] Paste: the video post link from step 3, repo https://github.com/kenkomu/soko-kuu, demo https://kenkomu.github.io/soko-kuu/, and the video link if asked.
- [ ] Submit, then keep the confirmation (screenshot or email).

Claims to keep out
- Do not say goods are tokens until the upgrade is deployed (thread post 7 stays on "not deployed yet").
- Do not say prices are AI. They are rule-based code; LLM_PROVIDER=none.
- No prize, reward, airdrop, earn or money language. Points are for play only.
- Do not say mainnet. Do not say "locked" or "trustless" (the contract account keeps one full-access key, contract/JUDGES.md).

Mechanics
- post.py takes a file holding only the exact post text (max 280 raw characters). Dry run first; it prints the length and a hash.
- Send only with `--send --confirm <hash>`, after Ken says yes to that exact text in this session.
- A media id or a reply-to id changes the hash, so dry run again after adding one.

[VERIFY] items
- [VERIFY] Hackathon video rules and the submission form link and fields.
- [VERIFY] README.md says Soko Run is 10 days; the code and app docs say 5. README is outside social/, so its owner should fix it.
