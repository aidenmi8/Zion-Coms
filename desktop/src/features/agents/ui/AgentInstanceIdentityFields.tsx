import type { RespondToMode } from "@/shared/api/types";
import { cn } from "@/shared/lib/cn";
import { Input } from "@/shared/ui/input";

import { OwnerOnlyAccessField } from "./OwnerOnlyAccessField";
import {
  PERSONA_FIELD_CONTROL_CLASS,
  PERSONA_FIELD_SHELL_CLASS,
} from "./agentConfigOptions";

export function AgentInstanceIdentityFields({
  accessLocked,
  allowlist,
  disabled,
  name,
  onAllowlistChange,
  onModeChange,
  onNameChange,
  respondTo,
}: {
  accessLocked: boolean;
  allowlist: string[];
  disabled: boolean;
  name: string;
  onAllowlistChange: (allowlist: string[]) => void;
  onModeChange: (mode: RespondToMode) => void;
  onNameChange: (name: string) => void;
  respondTo: RespondToMode;
}) {
  return (
    <>
      <div className="space-y-1.5">
        <label
          className="text-sm font-medium text-foreground"
          htmlFor="edit-agent-name"
        >
          Agent name
        </label>
        <div
          className={cn(
            "flex min-h-11 items-center px-3",
            PERSONA_FIELD_SHELL_CLASS,
          )}
        >
          <Input
            autoCorrect="off"
            className={cn(
              "h-8 px-0 py-0 leading-6",
              PERSONA_FIELD_CONTROL_CLASS,
            )}
            disabled={disabled}
            id="edit-agent-name"
            onChange={(event) => onNameChange(event.target.value)}
            placeholder="Agent name"
            value={name}
          />
        </div>
      </div>
      <OwnerOnlyAccessField
        accessLocked={accessLocked}
        allowlist={allowlist}
        disabled={disabled}
        mode={respondTo}
        onAllowlistChange={onAllowlistChange}
        onModeChange={onModeChange}
      />
    </>
  );
}
