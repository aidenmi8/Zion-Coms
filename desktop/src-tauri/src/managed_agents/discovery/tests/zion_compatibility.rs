use super::super::{
    default_agent_command, known_acp_runtime_exact, normalize_agent_args, record_agent_command,
};
use super::record_with;

#[test]
fn default_agent_command_resolves_bundled_zion_agent() {
    assert_eq!(default_agent_command(), "zion-agent");
    assert_eq!(
        normalize_agent_args(&default_agent_command(), vec!["acp".into()]),
        Vec::<String>::new()
    );
}

#[test]
fn bundled_zion_agent_is_the_canonical_runtime_command() {
    let runtime = known_acp_runtime_exact("buzz-agent").expect("bundled runtime");
    assert_eq!(runtime.commands.first().copied(), Some("zion-agent"));
    assert!(runtime.commands.contains(&"buzz-agent"));
    assert_eq!(runtime.mcp_command, Some("zion-dev-mcp"));
    assert_eq!(default_agent_command(), "zion-agent");
}

#[test]
fn legacy_bundled_override_migrates_but_custom_override_is_preserved() {
    let legacy = record_with(None, None, Some("buzz-agent"));
    assert_eq!(
        record_agent_command(&legacy, &[]),
        "zion-agent",
        "recognized bundled input must migrate to the canonical launcher"
    );

    let custom = record_with(None, None, Some("/opt/custom/buzz-agent-wrapper"));
    assert_eq!(
        record_agent_command(&custom, &[]),
        "/opt/custom/buzz-agent-wrapper",
        "custom commands must remain byte-for-byte unchanged"
    );
}
