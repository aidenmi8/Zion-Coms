//! One-time migration of the pre-scoping global retention database.

use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};

use super::{open_retention_db, RetainedEvent};

const MIGRATION_NAME: &str = "legacy_global_retention_db";

pub fn legacy_retention_db_path(base_dir: &Path) -> PathBuf {
    base_dir.join("retention.db")
}

/// Copy the active owner's legacy pending rows into one scoped database.
pub fn migrate_legacy_retention_db(
    base_dir: &Path,
    scope_db_path: &Path,
    owner_pubkey: &str,
) -> Result<usize, String> {
    let legacy_path = legacy_retention_db_path(base_dir);
    if !legacy_path.exists() || legacy_path == scope_db_path {
        return Ok(0);
    }

    let scope_id = scope_identifier(scope_db_path);
    let mut scope_conn = open_retention_db(scope_db_path)?;
    if migration_marker_present(&scope_conn)? {
        return Ok(0);
    }

    let legacy_conn = open_retention_db(&legacy_path)?;
    if !claim_legacy_rows(&legacy_conn, &scope_id)? {
        return Ok(0);
    }

    let rows = legacy_rows_for_owner(&legacy_conn, owner_pubkey)?;
    let copied = rows.len();
    let transaction = scope_conn
        .transaction()
        .map_err(|e| format!("failed to open retention migration transaction: {e}"))?;
    for row in &rows {
        transaction
            .execute(
                "INSERT INTO persona_events
                 (kind, pubkey, d_tag, content, created_at, raw_event, pending_sync)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT (kind, pubkey, d_tag) DO NOTHING",
                params![
                    row.kind,
                    row.pubkey,
                    row.d_tag,
                    row.content,
                    row.created_at,
                    row.raw_event,
                    row.pending_sync as i32,
                ],
            )
            .map_err(|e| format!("failed to copy legacy retained event: {e}"))?;
    }
    write_migration_marker(&transaction, &scope_id)?;
    transaction
        .commit()
        .map_err(|e| format!("failed to commit retention migration: {e}"))?;
    Ok(copied)
}

fn legacy_rows_for_owner(
    conn: &Connection,
    owner_pubkey: &str,
) -> Result<Vec<RetainedEvent>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT kind, pubkey, d_tag, content, created_at, raw_event, pending_sync
             FROM persona_events
             WHERE pubkey = ?1
             ORDER BY (kind != 5), created_at ASC",
        )
        .map_err(|e| format!("failed to prepare legacy retention query: {e}"))?;
    let rows = stmt
        .query_map(params![owner_pubkey], |row| {
            Ok(RetainedEvent {
                kind: row.get(0)?,
                pubkey: row.get(1)?,
                d_tag: row.get(2)?,
                content: row.get(3)?,
                created_at: row.get(4)?,
                raw_event: row.get(5)?,
                pending_sync: row.get::<_, i32>(6)? != 0,
            })
        })
        .map_err(|e| format!("failed to query legacy retained events: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("failed to read legacy retained row: {e}"))
}

fn scope_identifier(scope_db_path: &Path) -> String {
    scope_db_path
        .file_stem()
        .map(|stem| stem.to_string_lossy().to_string())
        .unwrap_or_default()
}

fn ensure_migration_table(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS retention_migrations (
            name TEXT PRIMARY KEY,
            scope_id TEXT NOT NULL
        );",
    )
    .map_err(|e| format!("failed to create retention migration table: {e}"))
}

fn migration_marker_present(conn: &Connection) -> Result<bool, String> {
    ensure_migration_table(conn)?;
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM retention_migrations WHERE name = ?1)",
        params![MIGRATION_NAME],
        |row| row.get(0),
    )
    .map_err(|e| format!("failed to read retention migration marker: {e}"))
}

fn write_migration_marker(conn: &Connection, scope_id: &str) -> Result<(), String> {
    ensure_migration_table(conn)?;
    conn.execute(
        "INSERT OR REPLACE INTO retention_migrations (name, scope_id) VALUES (?1, ?2)",
        params![MIGRATION_NAME, scope_id],
    )
    .map_err(|e| format!("failed to write retention migration marker: {e}"))?;
    Ok(())
}

fn claim_legacy_rows(legacy_conn: &Connection, scope_id: &str) -> Result<bool, String> {
    ensure_migration_table(legacy_conn)?;
    legacy_conn
        .execute(
            "INSERT OR IGNORE INTO retention_migrations (name, scope_id) VALUES (?1, ?2)",
            params![MIGRATION_NAME, scope_id],
        )
        .map_err(|e| format!("failed to claim legacy retention rows: {e}"))?;
    let claimed_by: Option<String> = legacy_conn
        .query_row(
            "SELECT scope_id FROM retention_migrations WHERE name = ?1",
            params![MIGRATION_NAME],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("failed to read legacy retention claim: {e}"))?;
    Ok(claimed_by.as_deref() == Some(scope_id))
}
