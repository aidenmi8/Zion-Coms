import type { ManagedAgentBackend, RespondToMode } from "@/shared/api/types";

export type AgentRunLocation = "local" | "remote";

export function runLocationForBackend(
  backend: ManagedAgentBackend | null | undefined,
): AgentRunLocation | null {
  if (!backend) return null;
  return backend.type === "local" ? "local" : "remote";
}

export function runLocationForRunOn(
  runOn: string | null | undefined,
): AgentRunLocation | null {
  if (!runOn) return null;
  return runOn === "local" ? "local" : "remote";
}

export function agentAccessWarningText(
  mode: RespondToMode,
  runLocation?: AgentRunLocation | null,
): string | null {
  if (mode !== "anyone" && mode !== "allowlist") return null;
  const audience = mode === "anyone" ? "Anyone" : "Selected people";
  const target =
    runLocation === "remote"
      ? "the server it runs on, including any accounts and tools available there"
      : "your computer, including files, accounts, and connected tools";
  return `${audience} can use this agent to access ${target}.`;
}
