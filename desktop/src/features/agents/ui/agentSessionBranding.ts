const ZION_CLI_GROUP =
  "(?:agents|messages|channels|dms|reactions|canvas|feed|users|workflows|social|repos|upload|mem|notes|patches|pr|issues|emoji|pack)";

const BUZZ_CLI_COMMAND = new RegExp(
  `(^|[;&|]\\s*)(?:\\./target/release/)?buzz(?=\\s+(?:(?:--[^\\s]+)(?:\\s+[^\\s]+)?\\s+)*${ZION_CLI_GROUP}\\b)`,
  "g",
);

const CODEX_SKILLS_CONTEXT_WARNING_PREFIXES = [
  "Warning: Skill descriptions were shortened to fit the ",
  "Warning: Exceeded skills context budget",
];

/**
 * Present the compatibility `buzz` executable as Zion in compact activity
 * labels. The stored/raw command remains unchanged so diagnostics and replay
 * retain the real executable name.
 */
export function formatZionActivityCommand(command: string): string {
  return command.replace(BUZZ_CLI_COMMAND, "$1Zion");
}

/** Replace legacy product names in agent-authored prose shown by Zion. */
export function formatZionAgentText(text: string): string {
  return text
    .replace(/\bBuzz relay\b/gi, "Zion relay")
    .replace(/\bBuzz platform\b/gi, "Zion platform")
    .replace(/\bBuzz CLI\b/gi, "Zion CLI");
}

/**
 * codex-acp currently converts Codex runtime warnings into ordinary assistant
 * message chunks. This warning is operational setup noise, not agent output.
 */
export function isCodexSkillsContextWarning(text: string): boolean {
  const trimmed = text.trimStart();
  return CODEX_SKILLS_CONTEXT_WARNING_PREFIXES.some((prefix) =>
    trimmed.startsWith(prefix),
  );
}
