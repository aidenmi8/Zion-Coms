Source: Mesh-LLM/mesh-llm tag v0.76.2, commit a0c1e66b0ac037dd56544b9e2d94969ea43d694f, crates/mesh-llm-log-store.

Purpose: keep the pinned examples-only Mesh smoke harness while moving bundled SQLite from rusqlite 0.40/libsqlite3-sys 0.38 to the patched rusqlite 0.41/libsqlite3-sys 0.39 pair. The Rust source and tests are copied unchanged. Only Cargo.toml has been adapted to be a standalone path crate and use the patched SQLite dependency. The upstream LICENSE is retained.

Retire this copy when Mesh-LLM publishes an equivalent update compatible with the pinned smoke harness and its regression tests pass.
