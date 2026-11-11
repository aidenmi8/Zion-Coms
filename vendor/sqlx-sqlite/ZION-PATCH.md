Source: launchbadge/sqlx commit f1e94ec34dd5f11ad6488a3a8ac7988439a3f757, sqlx-sqlite, version 0.9.0.

Purpose: retain Zion's pinned SQLx transaction fix while allowing the patched libsqlite3-sys 0.39 family required by rusqlite 0.41. The Rust source and tests are copied unchanged. Cargo.toml has been adapted for a standalone path crate and the SQLite dependency bound raised. Its upstream Clippy rules and configuration, plus the MIT and Apache licenses, are retained.

Retire this copy when a maintained SQLx version includes the transaction fix and supports the patched SQLite family, after its regression tests pass.
