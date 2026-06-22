# Rohomieo dev shortcuts

.PHONY: check test fmt clippy build web icons dev clean

check: fmt clippy web-build

test:
	cargo test -p rohomieo-proto -p rohomieo-signaling

fmt:
	cargo fmt --all

clippy:
	cargo clippy -p rohomieo-proto -p rohomieo-signaling -- -D warnings

build:
	cargo build --release -p rohomieo-signaling -p rohomieo-host

web-icons:
	cd web && python3 scripts/gen-icons.py

web-build: web-icons
	cd web && npm run build

web-install:
	cd web && npm ci

dev:
	./scripts/dev.sh

clean:
	cargo clean
	rm -rf web/dist
