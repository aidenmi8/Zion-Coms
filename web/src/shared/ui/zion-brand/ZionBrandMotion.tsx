import * as React from "react";

import { cn } from "@/shared/lib/cn";
import sentraLockupDark from "@/assets/sentra-lockup-dark.svg";

import "./zion-brand-motion.css";

export type ZionBrandMotionVariant =
  | "loader"
  | "onboarding"
  | "liveness"
  | "pairing"
  | "agent-entrance";

const MOTION_DURATION_MS: Record<ZionBrandMotionVariant, number> = {
  loader: 1800,
  onboarding: 3300,
  liveness: 1400,
  pairing: 1800,
  "agent-entrance": 1800,
};

function usePrefersReducedMotion() {
  const [reducedMotion, setReducedMotion] = React.useState(false);

  React.useEffect(() => {
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReducedMotion(mediaQuery.matches);
    update();
    mediaQuery.addEventListener?.("change", update);
    return () => mediaQuery.removeEventListener?.("change", update);
  }, []);

  return reducedMotion;
}

export type ZionBrandMotionProps = {
  ariaLabel?: string;
  className?: string;
  decorative?: boolean;
  loop?: boolean;
  playing?: boolean;
  variant?: ZionBrandMotionVariant;
};

export function ZionBrandMotion({
  ariaLabel,
  className,
  decorative = true,
  loop,
  playing = true,
  variant = "loader",
}: ZionBrandMotionProps) {
  const reducedMotion = usePrefersReducedMotion();
  const effectivePlaying = playing && !reducedMotion;
  const effectiveLoop =
    loop ?? (variant === "loader" || variant === "liveness");
  const label = ariaLabel?.trim() || undefined;

  return (
    <span
      className={cn(
        "zion-brand-motion",
        `zion-brand-motion--${variant}`,
        className,
      )}
      data-brand-surface="zion-motion"
      data-loop={effectiveLoop ? "true" : "false"}
      data-playing={effectivePlaying ? "true" : "false"}
      data-reduced-motion={reducedMotion ? "true" : "false"}
      data-zion-variant={variant}
      style={
        {
          "--zion-brand-motion-duration": `${MOTION_DURATION_MS[variant]}ms`,
        } as React.CSSProperties
      }
    >
      <img
        alt={decorative ? "" : (label ?? "Zion")}
        aria-hidden={decorative ? true : undefined}
        className="zion-brand-motion__mark"
        src={sentraLockupDark}
      />
    </span>
  );
}
