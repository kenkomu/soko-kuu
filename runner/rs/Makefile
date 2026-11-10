.PHONY: demo start test build testnet
# Demo mode: in-memory seeded ledger, same API, no chain or relayer needed.
demo:
	MODE=demo DEV_RETURN_TOKEN=1 PORT=$${PORT:-8787} cargo run --release
build:
	cargo build --release
start:
	cargo run --release
test:
	cargo test
# Real testnet. Needs RELAYER_ACCOUNT_ID, RELAYER_KEY_FILE (a path), CONTRACT_ID in the environment; see ../DEPLOY.md.
testnet:
	@for v in RELAYER_ACCOUNT_ID RELAYER_KEY_FILE CONTRACT_ID; do \
	  eval "val=\$$$$v"; [ -n "$$val" ] || { echo "missing $$v (see runner/DEPLOY.md)"; exit 1; }; done
	@[ -r "$$RELAYER_KEY_FILE" ] || { echo "RELAYER_KEY_FILE not readable: $$RELAYER_KEY_FILE"; exit 1; }
	MODE=testnet PORT=$${PORT:-8787} cargo run --release --features testnet
