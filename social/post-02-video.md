STATUS: DRAFT, not posted

The final demo post for the hackathon (built at NEAR HACKATHON, @NEARProtocol, #NEARHackathon, video, repo and demo links).
Pick ONE option. The fenced text is the exact post text. The same text is saved alone in its own file for post.py.

[ATTACH VIDEO]

Option A, Soko Run first (file: social/post-02-video-a.txt, 278/280 by post.py, dry-run hash 648d142e with no media)
```
Built at NEAR HACKATHON: Soko Kuu, a Kenyan market game. Listen to Radio Soko, buy before the rise, sell before the fall. Then try the live market on NEAR testnet.

Play: https://kenkomu.github.io/soko-kuu/
Code: https://github.com/kenkomu/soko-kuu

@NEARProtocol #NEARHackathon
```

Option B, the stall and the chama (file: social/post-02-video-b.txt, 279/280 by post.py, dry-run hash 84b0953d with no media)
```
Soko Kuu, built at NEAR HACKATHON. Run a stall in a Kenyan market: buy nyanya before the price rises, join a chama, build credit. Testnet, no wallet, no real money.

Play: https://kenkomu.github.io/soko-kuu/
Code: https://github.com/kenkomu/soko-kuu

@NEARProtocol #NEARHackathon
```

How the video gets on the post (post.py cannot upload video)
- Way 1: Ken posts it by hand in X: paste the chosen text exactly, attach the video, post. Then tell the xposter the post id.
- Way 2: Ken uploads the video and gives a media id. The xposter runs a new dry run with `--media-id <id>`.
  The media id is part of the hash, so the hash changes and Ken approves the new one before any send.

Where each claim comes from
- Soko Run, five market days, Radio Soko about tomorrow, buy before the rise, sell before the fall: app/lib/run/soko_run_engine.dart, app/lib/l10n.dart, app/DEMO.md.
- Live market on NEAR testnet, chama, credit, stall (Duka), no wallet, no real money: README.md.
- Demo link: https://kenkomu.github.io/soko-kuu/ answered 200 on 14 Nov 2026. Its build has "Play Soko Run" with five days and has API_BASE=https://app.chukua.xyz built in, so "Live market on NEAR" talks to the testnet runner.
- Repo link: git remote origin; answered 200 on 14 Nov 2026 (public).
- post.py counts raw characters. X counts each link as 23, so on X both options come out shorter than shown.

Honesty notes for the video (keep these true on screen)
- Soko Run is offline. Nothing in it goes to the runner or the chain, and its points are separate from the live game.
- If the video shows the live market, say it is NEAR testnet. Do not show or say goods are tokens (not deployed yet).

[VERIFY] items
- [VERIFY] The demo video is recorded and shows what the text says (Soko Run and the live market on testnet).
- [VERIFY] The hackathon's rules for the video (length, where it must be hosted) are not in the repo. Check the hackathon page.
