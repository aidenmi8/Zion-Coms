use std::process::{Command, Output};

use buzz_agent::config::{Config, ThinkingEffort};
use buzz_agent::Provider;

const PROBE_MODE: &str = "ZION_CONFIG_PROBE";

fn base_probe_command() -> Command {
    let mut command = Command::new(std::env::current_exe().expect("current test executable"));
    command
        .args([
            "--exact",
            "config_probe_from_isolated_environment",
            "--nocapture",
        ])
        .env_clear()
        .env(PROBE_MODE, "1")
        .env("OPENAI_COMPAT_API_KEY", "test-key")
        .env("OPENAI_COMPAT_BASE_URL", "http://127.0.0.1:9")
        .env("EXPECT_PROVIDER", "openai");
    command
}

fn assert_probe_passed(output: Output) {
    assert!(
        output.status.success(),
        "config probe failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn config_probe_from_isolated_environment() {
    if std::env::var_os(PROBE_MODE).is_none() {
        return;
    }

    let config = Config::from_env().expect("agent config must accept the isolated environment");
    assert_eq!(config.provider, Provider::OpenAi);
    assert_eq!(
        config.model,
        std::env::var("EXPECT_MODEL").expect("EXPECT_MODEL")
    );
    assert_eq!(
        config.thinking_effort,
        Some(
            match std::env::var("EXPECT_THINKING")
                .expect("EXPECT_THINKING")
                .as_str()
            {
                "low" => ThinkingEffort::Low,
                "medium" => ThinkingEffort::Medium,
                other => panic!("unexpected EXPECT_THINKING={other}"),
            }
        )
    );
    assert_eq!(
        config.max_output_tokens,
        std::env::var("EXPECT_MAX_OUTPUT")
            .expect("EXPECT_MAX_OUTPUT")
            .parse::<u32>()
            .expect("numeric EXPECT_MAX_OUTPUT")
    );
    assert_eq!(
        config.max_context_tokens,
        std::env::var("EXPECT_MAX_CONTEXT")
            .expect("EXPECT_MAX_CONTEXT")
            .parse::<u64>()
            .expect("numeric EXPECT_MAX_CONTEXT")
    );
}

#[test]
fn zion_agent_keys_precede_every_legacy_desktop_key() {
    let output = base_probe_command()
        .env("ZION_AGENT_PROVIDER", "openai")
        .env("BUZZ_AGENT_PROVIDER", "databricks")
        .env("ZION_AGENT_MODEL", "gpt-5.4")
        .env("BUZZ_AGENT_MODEL", "legacy-model")
        .env("ZION_AGENT_THINKING_EFFORT", "low")
        .env("BUZZ_AGENT_THINKING_EFFORT", "medium")
        .env("ZION_AGENT_MAX_OUTPUT_TOKENS", "4096")
        .env("BUZZ_AGENT_MAX_OUTPUT_TOKENS", "8192")
        .env("ZION_AGENT_MAX_CONTEXT_TOKENS", "20000")
        .env("BUZZ_AGENT_MAX_CONTEXT_TOKENS", "30000")
        .env("EXPECT_MODEL", "gpt-5.4")
        .env("EXPECT_THINKING", "low")
        .env("EXPECT_MAX_OUTPUT", "4096")
        .env("EXPECT_MAX_CONTEXT", "20000")
        .output()
        .expect("run isolated config probe");

    assert_probe_passed(output);
}

#[test]
fn desktop_zion_only_agent_environment_reaches_agent_config() {
    let output = base_probe_command()
        .env("ZION_AGENT_PROVIDER", "openai")
        .env("ZION_AGENT_MODEL", "gpt-5.4")
        .env("ZION_AGENT_THINKING_EFFORT", "medium")
        .env("ZION_AGENT_MAX_OUTPUT_TOKENS", "6000")
        .env("ZION_AGENT_MAX_CONTEXT_TOKENS", "24000")
        .env("EXPECT_MODEL", "gpt-5.4")
        .env("EXPECT_THINKING", "medium")
        .env("EXPECT_MAX_OUTPUT", "6000")
        .env("EXPECT_MAX_CONTEXT", "24000")
        .output()
        .expect("run isolated config probe");

    assert_probe_passed(output);
}

#[test]
fn legacy_agent_environment_remains_a_complete_fallback() {
    let output = base_probe_command()
        .env("BUZZ_AGENT_PROVIDER", "openai")
        .env("BUZZ_AGENT_MODEL", "gpt-5.3")
        .env("BUZZ_AGENT_THINKING_EFFORT", "low")
        .env("BUZZ_AGENT_MAX_OUTPUT_TOKENS", "5000")
        .env("BUZZ_AGENT_MAX_CONTEXT_TOKENS", "22000")
        .env("EXPECT_MODEL", "gpt-5.3")
        .env("EXPECT_THINKING", "low")
        .env("EXPECT_MAX_OUTPUT", "5000")
        .env("EXPECT_MAX_CONTEXT", "22000")
        .output()
        .expect("run isolated config probe");

    assert_probe_passed(output);
}
