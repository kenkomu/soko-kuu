STATUS: DRAFT, not posted.

Pre-post checklist (nothing has been posted; no X credentials were touched)

Must do before any post
- [ ] [ATTACH VIDEO]: record the demo video (not recorded yet). Upload it and pass the media id with --media-id.
- [ ] Say in the video or caption which build it shows: offline demo (simplified chama) or live runner (real chama votes and loans).
- [ ] [VERIFY] Which build does https://kenkomu.github.io/soko-kuu/ run (offline demo or API_BASE=https://app.chukua.xyz)? Open it in a private window, play as guest.
- [ ] [VERIFY] https://app.chukua.xyz/v1/health returns "mode":"testnet" and "degraded":null. Also check CORS from the Pages origin.
- [ ] [VERIFY: deployed?] NEP-245 goods (commit 02b32aa) are in source only. Include the goods line (post-01 alternate, thread post 7) only after the upgrade is live and the code hash in contract/JUDGES.md is updated. Check: mt_supply for token_id "tomato" answers on testnet.
- [ ] [VERIFY] Numbers still current: 100 seeds x 60 days, worst daily drift 105 bp (1.05%) vs 1,500 bp limit (econ/JUDGES.md, run of 10 Nov 2026). Re-run `cd econ && cargo run --release --bin econ_sim -- stability 100 60` if econ changed.
- [ ] [VERIFY] Test counts if you quote them: README says contract 42 unit tests, contract/JUDGES.md says 46. They disagree; not used in the drafts.
- [ ] [VERIFY] Sale result (Faida/Hasara), beat-yesterday card, kind first-loss message, sound/haptics toggles are in the version the Pages link serves (told by team lead; not checked in README or app/DEMO.md).
- [ ] [VERIFY] English and Kiswahili switch exists (app/DEMO.md step 0:20).
- [ ] Confirm the repo is public and the LICENSE is MIT.
- [ ] Hashtag/handle choices ("#NEAR") are Ken's call.

Claims to keep out
- Do not say goods are tokens unless deployed.
- Do not say prices are "AI"; they are rule-based, LLM_PROVIDER=none.
- No prize, reward, airdrop, earn or money language. Points are play only.
- The contract account keeps one full-access key (contract/JUDGES.md caveat); do not say it is "locked" or "trustless".

Mechanics
- post.py takes a file holding only the exact post text (max 280 raw chars). Copy each fenced block into its own temp file.
- Dry run first (prints length and a hash). Send only with `--send --confirm <hash>`, after Ken approves.
- Thread: post 1 first, then --reply-to <previous id> for each next post.
