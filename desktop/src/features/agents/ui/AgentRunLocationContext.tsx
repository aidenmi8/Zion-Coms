import * as React from "react";

import type { AgentRunLocation } from "../lib/agentAccessWarning";

const AgentRunLocationContext = React.createContext<AgentRunLocation | null>(
  null,
);

export function AgentRunLocationProvider({
  children,
  runLocation,
}: {
  children: React.ReactNode;
  runLocation: AgentRunLocation | null;
}) {
  return (
    <AgentRunLocationContext.Provider value={runLocation}>
      {children}
    </AgentRunLocationContext.Provider>
  );
}

export function useAgentRunLocation(): AgentRunLocation | null {
  return React.useContext(AgentRunLocationContext);
}
