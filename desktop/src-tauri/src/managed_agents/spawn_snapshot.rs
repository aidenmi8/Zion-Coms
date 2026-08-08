//! Runtime-only snapshot of the effective managed-agent spawn configuration.
//!
//! This is the prerequisite contract used by the restart-diff and parallelism
//! intake lines. It deliberately never crosses a persistence boundary.

use std::collections::BTreeMap;

use serde::Serialize;

use super::{
    effective_config::{resolve_effective_config, EffectiveConfigResult},
    known_acp_runtime, normalize_agent_args,
    persona_events::preview_prospective_persona_snapshot,
    readiness::EffectiveHarnessDescriptor,
    runtime::{resolve_session_title, SESSION_TITLE_ENV_VAR},
    types::{AgentDefinition, ManagedAgentRecord, TeamRecord},
    GlobalAgentConfig,
};

/// Inputs already resolved by the spawn path.
pub(crate) struct SpawnConfigInputs<'a> {
    pub record: &'a ManagedAgentRecord,
    pub descriptor: &'a EffectiveHarnessDescriptor,
    pub relay_url: &'a str,
    pub team_instructions: Option<&'a str>,
    pub system_prompt: Option<&'a str>,
    pub model: Option<&'a str>,
    pub provider: Option<&'a str>,
}

/// Effective values that determine what the child process receives.
#[derive(Clone, Serialize, PartialEq)]
pub(crate) struct SpawnConfigSnapshot {
    pub acp_command: String,
    pub command: String,
    pub args: Vec<String>,
    pub mcp_command: String,
    pub env: BTreeMap<String, String>,
    pub relay_url: String,
    pub team_instructions: Option<String>,
    pub system_prompt: Option<String>,
    pub model: Option<String>,
    pub provider: Option<String>,
    pub session_title: Option<String>,
    pub auth_tag: Option<String>,
    pub respond_to: String,
    pub respond_to_allowlist: Option<Vec<String>>,
    pub idle_timeout_seconds: Option<u64>,
    pub max_turn_duration_seconds: Option<u64>,
    pub parallelism: u32,
}

impl SpawnConfigSnapshot {
    pub(crate) fn from_inputs(inputs: SpawnConfigInputs<'_>) -> Self {
        let SpawnConfigInputs {
            record,
            descriptor,
            relay_url,
            team_instructions,
            system_prompt,
            model,
            provider,
        } = inputs;
        Self {
            acp_command: record.acp_command.clone(),
            command: descriptor.command.clone(),
            args: descriptor.args.clone(),
            mcp_command: known_acp_runtime(&descriptor.command)
                .and_then(|runtime| runtime.mcp_command)
                .unwrap_or("")
                .to_string(),
            env: descriptor.env.clone(),
            relay_url: relay_url.to_string(),
            team_instructions: team_instructions.map(str::to_string),
            system_prompt: system_prompt.map(str::to_string),
            model: model.map(str::to_string),
            provider: provider.map(str::to_string),
            session_title: (!descriptor.env.contains_key(SESSION_TITLE_ENV_VAR))
                .then(|| resolve_session_title(record.display_name.as_deref(), &record.name))
                .flatten(),
            auth_tag: record.auth_tag.clone(),
            respond_to: record.respond_to.as_str().to_string(),
            respond_to_allowlist: (record.respond_to == super::types::RespondTo::Allowlist).then(
                || {
                    super::types::validate_respond_to_allowlist(&record.respond_to_allowlist)
                        .unwrap_or_else(|_| record.respond_to_allowlist.clone())
                },
            ),
            idle_timeout_seconds: record.idle_timeout_seconds,
            max_turn_duration_seconds: record.max_turn_duration_seconds,
            parallelism: super::effective_parallelism(&descriptor.command, record.parallelism),
        }
    }

    /// Canonical projection used for runtime equality checks.
    pub(crate) fn canonical(&self) -> serde_json::Value {
        serde_json::to_value(self).unwrap_or(serde_json::Value::Null)
    }
}

impl std::fmt::Debug for SpawnConfigSnapshot {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SpawnConfigSnapshot")
            .field("acp_command", &self.acp_command)
            .field("command", &self.command)
            .field("args", &"<redacted>")
            .field(
                "safe_env_key_count",
                &self
                    .env
                    .keys()
                    .filter(|key| super::env_vars::is_safe_to_reveal(key))
                    .count(),
            )
            .field("relay_url", &"<redacted>")
            .field("parallelism", &self.parallelism)
            .finish()
    }
}

/// Resolve the current team instructions for a deployment.
pub(crate) fn effective_team_instructions(
    record: &ManagedAgentRecord,
    teams: &[TeamRecord],
) -> Option<String> {
    teams
        .iter()
        .find(|team| Some(team.id.as_str()) == record.team_id.as_deref())
        .and_then(|team| team.instructions.as_deref())
        .map(str::trim)
        .filter(|instructions| !instructions.is_empty())
        .map(str::to_string)
}

/// Snapshot the effective spawn configuration as if the record started now.
pub(crate) fn prospective_spawn_config_snapshot(
    record: &ManagedAgentRecord,
    personas: &[AgentDefinition],
    teams: &[TeamRecord],
    workspace_relay: &str,
    global: &GlobalAgentConfig,
) -> SpawnConfigSnapshot {
    let prospective_record = preview_prospective_persona_snapshot(record, personas);
    let descriptor = crate::managed_agents::resolve_effective_harness_descriptor(
        &prospective_record,
        personas,
        global,
    )
    .unwrap_or_else(|_| {
        let command = crate::managed_agents::record_agent_command(&prospective_record, personas);
        let args = normalize_agent_args(&command, prospective_record.agent_args.clone());
        EffectiveHarnessDescriptor {
            command,
            args,
            env: Default::default(),
        }
    });

    let (prompt, model, provider) =
        match resolve_effective_config(&prospective_record, personas, global) {
            EffectiveConfigResult::Resolved(config) => (
                config.system_prompt.value,
                config.model.value,
                config.provider.value,
            ),
            EffectiveConfigResult::OrphanedInstance { .. } => (None, None, None),
        };
    let team_instructions = effective_team_instructions(&prospective_record, teams);
    let relay_url =
        crate::relay::effective_agent_relay_url(&prospective_record.relay_url, workspace_relay);
    SpawnConfigSnapshot::from_inputs(SpawnConfigInputs {
        record: &prospective_record,
        descriptor: &descriptor,
        relay_url: &relay_url,
        team_instructions: team_instructions.as_deref(),
        system_prompt: prompt.as_deref(),
        model: model.as_deref(),
        provider: provider.as_deref(),
    })
}
