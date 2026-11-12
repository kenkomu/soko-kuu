# Soko Kuu: notes for judges

A market-trading game set in a Kenyan soko. Play with points (pts), buy and sell produce, join a chama, take small credit.

## Try it in 90 seconds
No account and no runner needed: the app opens in an offline demo by default. The step-by-step path with what to tap and what you should see is in [DEMO.md](DEMO.md). After the 18+ gate you choose **Play Soko Run** (a 10-day offline run: listen to Radio Soko, buy low, sell high; nothing is sent anywhere) or **Live market on NEAR**. For the live market, in short: confirm 18+, play as a guest, open a price to read "Why this price", go to midday, buy and sell, then look at Duka, Chama, Deni and Ripoti (the "What if? Fast-forward" preview is at the top of the Soko Report tab).
Screenshots of each screen are in `screenshots/` (listed in README.md).

## What the app never does
- No wallet. The player never sees a wallet, keys or seed phrases. (A throwaway play key is kept on the device to sign game actions.)
- No cash-out. Points cannot be bought, sold or exchanged for money, and there are no prizes.
- No transfer of points between players.
- No paid chances: prices follow fixed market rules.
- 18+ gate before anything else; "I am under 18" does not let you in.
- Guest play: no email needed. Clearing app data starts a new player (the app says so).
- The "What if?" fast-forward is a preview only and never changes your game.

## Where the Swahili text lives
Switch language in Settings (gear icon, top right): English / Kiswahili.
- `lib/l10n.dart`: the runtime translations. The `sw` map holds screen text keyed by the English sentence; `errorText` holds API error sentences, `tutorial` the first-day guidance, `capLines` the "Why this price" lines, `_goods` the crop names.
- `lib/l10n/app_en.arb` and `lib/l10n/app_sw.arb`: the error sentences as reviewable files; `test/arb_parity_test.dart` checks they match `errorText`.
- Text written by the market itself (for example the Radio Soko headline) comes from the game data and may appear in English.
