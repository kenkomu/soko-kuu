STATUS: DRAFT, not posted.

Thread, replies to the main post (post-01-demo.md). Each fenced block is the exact text of one post, 280 raw characters max.
Post with post.py one at a time, using --reply-to with the previous id. Dry run first. Do not use --send until Ken approves.

Post 2 (what NEAR does)
```
What NEAR does here: a testnet contract (sokokuu.sokokuu-ken.testnet) holds the whole game world. A relayer pays gas, so players never see a wallet. Each action is signed with the player's own ed25519 key; the contract checks signature, nonce and expiry itself.
```

Post 3 (non-transferable points)
```
Points (pts) are a NEP-245 token on purpose non-transferable. mt_transfer always panics NON_TRANSFERABLE. You can check read-only, no account or gas. Steps are in contract/JUDGES.md in the repo.
```

Post 4 (economy)
```
The economy is a Rust crate with no AI in it. A 100-seed x 60-day simulation keeps total money near target: worst single-day drift about 1.05% against a 15% limit. The tests fail the build if it breaks.
```

Post 5 (game loop and polish)
```
Every 30 seconds: read a price, see "Why this price", buy or sell. A sale ends with Faida (profit) or Hasara (loss). A beat-yesterday card, a kind first-loss message, and sound/haptics toggles. English and Kiswahili.
```

Post 6 (honest about the demo)
```
Honest note: the offline demo uses a simplified chama (computer-controlled members, fixed pot). Against the live runner (app.chukua.xyz) chama votes and loans are real. Email sign-in is not set up; guest play is the supported path.
```

Post 7 (goods, current wording: NOT deployed yet). Keep this wording until Ken says the contract upgrade is done.
```
Today only pts is a token on testnet. Goods as NEP-245 token ids are written and tested in the source but not deployed yet.
```
Held-back alternate, do NOT use until the upgrade is confirmed live [VERIFY: deployed?]:
```
Goods are NEP-245 token ids too (tomato, maize, sukuma, onion, fish, charcoal): buying mints, selling burns. Still non-transferable.
```

Post 8 (close)
```
No cash-out, no token sale, no prize, no paid chance. 18+ gate first. Testnet only. Built for the NEAR Hackathon (Games). Most code was written with Claude Code, directed and reviewed by me.

Repo (MIT): https://github.com/kenkomu/soko-kuu
```
