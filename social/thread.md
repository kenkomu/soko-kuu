STATUS: DRAFT, not posted

Thread, replies under the video post (post-02-video.md) once it is live. Each fenced block is the exact text of one post,
280 raw characters max by post.py. Post one at a time: save the block alone in a file, dry run with
`--reply-to <previous post id>`, show Ken the text and hash, send only after his yes for that exact text.
The thread is optional. The hackathon needs the video post; these replies add detail.

Post 2 (two ways to play) 226/280
```
Two ways to play, chosen on the first screen. Play Soko Run: five quick market days on your phone, offline, no sign-in. Live market on NEAR: the shared testnet market with chama, credit and other players. You can switch later.
```

Post 3 (Soko Run) 263/280
```
Soko Run: every day Radio Soko tells you about tomorrow. Drought in Kiambu? Tomatoes will be scarce. It is right about 3 times in 4. Buy before the rise, sell before the fall. Titles go from Mgeni to Tajiri wa Soko. The Daily Soko is the same 5 days for everyone.
```

Post 4 (what NEAR does) 262/280
```
What NEAR does here: a testnet contract (sokokuu.sokokuu-ken.testnet) holds the whole live market. A relayer pays gas, so players never see a wallet. Each action is signed with the player's own ed25519 key; the contract checks signature, nonce and expiry itself.
```

Post 5 (points and the economy) 254/280
```
Points (pts) are a NEP-245 token that cannot be sent to anyone: mt_transfer always panics NON_TRANSFERABLE. Live prices come from a plain Rust crate, no AI. A 100-seed, 60-day simulation keeps total money within 15%; the worst drift measured is about 1%.
```

Post 6 (try it) 224/280
```
Try it, no account or email: open the link, tap "I am 18 or older. Start", then Play Soko Run (about a minute). For the live market: Play as a guest, tap a crop for "Why this price", buy, sell, then look at Chama and Ripoti.
```

Post 7 (goods, current wording: NOT deployed yet). Keep this wording until Ken says the contract upgrade is done. 123/280
```
Today only pts is a token on testnet. Goods as NEP-245 token ids are written and tested in the source but not deployed yet.
```
Held-back alternate, do NOT use until the upgrade is confirmed live [VERIFY: deployed?]:
```
Goods are NEP-245 token ids too (tomato, maize, sukuma, onion, fish, charcoal): buying mints, selling burns. Still non-transferable.
```

Post 8 (honest notes) 246/280
```
Honest notes: Soko Run is offline and never touches the chain; its points are separate. In the live market, chama votes and loans are real. Email sign-in is not set up, so guest play is the way in. Soko Run's radio lines are English only for now.
```

Post 9 (close and thanks) 259/280
```
No cash-out, no token sale, no prize, no paid chance. 18+ gate first. Testnet only. Built at NEAR HACKATHON, Games track. Most code was written with Claude Code, directed and reviewed by me. Asante for reading.

Repo (MIT): https://github.com/kenkomu/soko-kuu
```

Where each claim comes from
- Post 2: entry screen strings in app/lib/run/entry.dart and app/lib/l10n.dart ("Five quick market days on this phone. No sign-in, nothing is sent anywhere.", "The shared market with chama, credit and other players.", "You can switch later.").
- Post 3: app/lib/run/soko_run_engine.dart (5 days; a rumour is true with chance 0.75; news line "Drought in Kiambu. Few tomato lorries will reach the soko tomorrow."; titles Mgeni, Mchuuzi, Mfanyabiashara, Tajiri wa Soko; Daily Soko seed is the same for everyone on the same UTC date) and the UI line "Radio Soko is right about 3 times in 4."
- Post 4: README.md "What NEAR does here".
- Post 5: README.md (NEP-245 pts, non-transferable, mt_transfer panics NON_TRANSFERABLE, rule-based econ crate, 100-seed 60-day sim within +-15%, worst drift about 1%).
- Post 6: README.md "Try it in 90 seconds", app/DEMO.md (Soko Run "about a minute").
- Post 7: README.md "Known gaps" (goods not NEP-245 token ids yet).
- Post 8: app/DEMO.md (Soko Run sends nothing; its points are separate), README.md (chama votes and loans real against the live runner; email sign-in not set up), app/lib/run/soko_run_engine.dart TODO (news lines stay English for now). The hosted web build has API_BASE=https://app.chukua.xyz built in (checked 14 Nov 2026).
- Post 9: README.md (what the game never does, AI assistance, MIT license, Games track).

[VERIFY] items
- [VERIFY: deployed?] Post 7 alternate: only after the goods upgrade is live on testnet and contract/JUDGES.md shows the new code hash.
- [VERIFY] README.md line 37 still says Soko Run is "a quick 10-day offline run". The code, app/JUDGES.md and app/DEMO.md say 5 days (commit 035d5bb). The drafts use 5. README is not in social/; its owner should fix it before judges read it.
