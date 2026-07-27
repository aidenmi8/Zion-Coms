import { motion, useReducedMotion } from "motion/react";

import { cn } from "@/shared/lib/cn";
import { ZionMotion } from "@/shared/ui/zion-brand/ZionMotion";
import { useTranscriptAnimationEnabled } from "./transcriptAnimationPreference";

const MARKS = ["first", "second", "third"] as const;
const STAGGER_SECONDS = 0.25;
const CYCLE_SECONDS = 1.8;

export function TurnLivenessIndicator({ className }: { className?: string }) {
  const animationsEnabled = useTranscriptAnimationEnabled();
  const shouldReduceMotion = useReducedMotion();
  const showStaggeredRow = animationsEnabled && !shouldReduceMotion;

  if (!showStaggeredRow) {
    return (
      <div
        aria-label="Agent turn in progress"
        className={cn("opacity-25", className)}
        data-testid="turn-liveness-indicator"
        role="status"
      >
        <ZionMotion
          className="text-foreground"
          variant="liveness"
          playing={!shouldReduceMotion}
        />
      </div>
    );
  }

  return (
    <div
      aria-label="Agent turn in progress"
      className={cn("flex items-center gap-1.5 opacity-25", className)}
      data-testid="turn-liveness-indicator"
      role="status"
    >
      {MARKS.map((mark, index) => (
        <motion.div
          animate={{
            opacity: [0, 1, 1, 0],
            y: [4, 0, -1, -4],
          }}
          key={mark}
          transition={{
            delay: index * STAGGER_SECONDS,
            duration: CYCLE_SECONDS,
            ease: "easeInOut",
            repeat: Number.POSITIVE_INFINITY,
            times: [0, 0.3, 0.7, 1],
          }}
        >
          <ZionMotion
            className="w-5! text-foreground"
            variant="liveness"
            playing={!shouldReduceMotion}
          />
        </motion.div>
      ))}
    </div>
  );
}
