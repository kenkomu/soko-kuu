# Soko Kuu: working rules

Closed-loop Kenyan market game on NEAR testnet. Deadline: Sat 14 Nov 2026 23:59 UTC; submit by Fri 13 Nov.
Design notes: /home/ken/reports/Soko Kuu game research.md and /home/ken/reports/Soko Kuu mobile UI inspiration.md
API contract: docs/API.md (single source of truth between app and runner). Security, efficiency and UX rules: docs/SECURITY_UX.md (every owner reads it).

## Folder ownership (agent teams: nobody edits another owner's folder)
| Owner | Folder | Deliverable |
|---|---|---|
| econ | `econ/` | Rust crate: pricing curve, events, chama and credit rules, 100-seed stability sim (money drift within +-15%). No NEAR deps. |
| contract | `contract/` | NEAR contract (near-sdk-contract-tools MultiToken), signed `act`, non-transferable pts, uses `econ`. Unit tests. |
| runner | `runner/` | Relayer, email login, merchant decision loop, `/v1/sim`, demo mode. Implements docs/API.md. |
| app | `app/` | Flutter (Android + web). Talks only to the API. Offline demo mode. |

## Rules
- Prices are rule-based code. The LLM may only write voice lines; default `LLM_PROVIDER=none`.
- No cash-out, token, prize or paid randomness. Points are non-transferable.
- Changes to docs/API.md need a message to both `runner` and `app` first.
- Day-1 tests: compare Dart-signed bytes with near-api-js; CORS call from Pages to runner; contract-tools builds against near-sdk.
- Commit small. No secrets in the repo.
