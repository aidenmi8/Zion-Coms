import * as React from "react";
import { useReducedMotion } from "motion/react";

import {
  isWelcomeKickoffStageExiting,
  type WelcomeKickoffStagePhase,
} from "@/features/onboarding/useWelcomeKickoffStage";
import { cn } from "@/shared/lib/cn";
import { STARTER_TEAM_NAMES, StarterTeamPresence } from "./StarterTeamPresence";

const STAGE_EXIT_ANIMATION = "motion-kickoff-stage-exit";

/**
 * The welcome team characters standing on top of the Welcome composer banner
 * while the team is being set up. Positioned relative to the banner wrapper
 * (`bottom-full` = feet on the banner's top edge) and purely decorative —
 * the banner's own copy carries the setup status for screen readers.
 *
 * Placeholder choreography: staggered rise-from-below entrance per character
 * (CSS `motion-kickoff-character-enter`, delay via `--stagger-index`), whole
 * row crossfades out on either resolution — the first agent message landing,
 * or the wait timing out. The characters must not linger after a timeout: a
 * stage that stays up implies a team is still coming when none is.
 */
export function WelcomeKickoffStage({
  onExitComplete,
  phase,
}: {
  onExitComplete: () => void;
  phase: WelcomeKickoffStagePhase;
}) {
  const shouldReduceMotion = useReducedMotion();
  const handleAnimationEnd = React.useCallback(
    (event: React.AnimationEvent<HTMLDivElement>) => {
      if (event.animationName === STAGE_EXIT_ANIMATION) {
        onExitComplete();
      }
    },
    [onExitComplete],
  );

  if (phase === "hidden" || phase === "done") return null;

  return (
    <div
      aria-hidden
      className={cn(
        "pointer-events-none absolute bottom-full left-10 z-10 flex items-end gap-4",
        isWelcomeKickoffStageExiting(phase) && "motion-kickoff-stage-exit",
      )}
      data-phase={phase}
      data-testid="welcome-kickoff-stage"
      onAnimationEnd={handleAnimationEnd}
    >
      {STARTER_TEAM_NAMES.map((name, index) => (
        <span
          className="block h-16 w-16"
          data-testid={`welcome-kickoff-stage-${name.toLowerCase()}`}
          key={name}
          style={{ "--stagger-index": index } as React.CSSProperties}
        >
          <StarterTeamPresence
            name={name}
            phase={shouldReduceMotion ? "reduced-motion" : "entering"}
          />
        </span>
      ))}
    </div>
  );
}
