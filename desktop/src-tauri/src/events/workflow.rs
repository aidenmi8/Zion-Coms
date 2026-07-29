use nostr::{EventBuilder, Kind};

use super::{check_content, tag};

/// Kind 30620 — replaceable workflow definition.
///
/// The `d` tag carries the workflow id; `h` tag carries the channel id; the
/// content is the YAML definition. Same (pubkey, d) replaces the prior version.
pub fn build_workflow_definition(
    workflow_id: &str,
    channel_id: &str,
    yaml_definition: &str,
) -> Result<EventBuilder, String> {
    check_content(yaml_definition)?;
    let tags = vec![tag(vec!["d", workflow_id])?, tag(vec!["h", channel_id])?];
    Ok(EventBuilder::new(Kind::Custom(30620), yaml_definition.to_string()).tags(tags))
}

/// Kind 5 — NIP-09 deletion targeting a kind:30620 workflow definition.
pub fn build_workflow_delete(
    workflow_id: &str,
    owner_pubkey_hex: &str,
) -> Result<EventBuilder, String> {
    let coord = format!("30620:{owner_pubkey_hex}:{workflow_id}");
    let tags = vec![tag(vec!["a", &coord])?];
    Ok(EventBuilder::new(Kind::Custom(5), "").tags(tags))
}

/// Kind 46020 — trigger a workflow run by id.
pub fn build_workflow_trigger(workflow_id: &str) -> Result<EventBuilder, String> {
    let tags = vec![tag(vec!["d", workflow_id])?];
    Ok(EventBuilder::new(Kind::Custom(46020), "").tags(tags))
}

fn validate_approval_digest(digest: &str) -> Result<(), String> {
    if digest.len() != 64
        || !digest
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        return Err("approval digest must be 64 hexadecimal characters".into());
    }
    Ok(())
}

/// Kind 46030 — grant an approval digest (with optional note).
pub fn build_approval_grant(digest: &str, note: Option<&str>) -> Result<EventBuilder, String> {
    validate_approval_digest(digest)?;
    let tags = vec![tag(vec!["d", digest])?];
    Ok(EventBuilder::new(Kind::Custom(46030), note.unwrap_or("")).tags(tags))
}

/// Kind 46031 — deny an approval digest (with optional note).
pub fn build_approval_deny(digest: &str, note: Option<&str>) -> Result<EventBuilder, String> {
    validate_approval_digest(digest)?;
    let tags = vec![tag(vec!["d", digest])?];
    Ok(EventBuilder::new(Kind::Custom(46031), note.unwrap_or("")).tags(tags))
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr::Keys;

    #[test]
    fn approval_commands_bind_the_stored_digest_with_a_d_tag() {
        let digest = "ab".repeat(32);
        for builder in [
            build_approval_grant(&digest, Some("yes")).expect("grant"),
            build_approval_deny(&digest, Some("no")).expect("deny"),
        ] {
            let event = builder.sign_with_keys(&Keys::generate()).expect("sign");
            assert!(event.tags.iter().any(|tag| {
                let values = tag.as_slice();
                values.first().map(String::as_str) == Some("d") && values.get(1) == Some(&digest)
            }));
            assert!(!event
                .tags
                .iter()
                .any(|tag| { tag.as_slice().first().map(String::as_str) == Some("t") }));
        }
        assert!(build_approval_grant("short", None).is_err());
        assert!(build_approval_deny("not-hex", None).is_err());
    }
}
