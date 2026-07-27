import type * as React from "react";

import { cn } from "@/shared/lib/cn";
import {
  motionForVariant,
  type ZionMotionVariant,
} from "./brandAssetManifest";
import { ZionMark } from "./ZionMark";
import "./zion-motion.css";

type ZionMotionStyle = React.CSSProperties & {
  "--zion-motion-duration"?: string;
  "--zion-motion-iteration-count"?: string;
  "--zion-motion-settle-duration"?: string;
  "--zion-motion-stagger-duration"?: string;
};

export type ZionMotionProps = {
  ariaLabel?: string;
  className?: string;
  decorative?: boolean;
  loop?: boolean;
  playing?: boolean;
  variant?: ZionMotionVariant;
};

/** Shared motion layer for loaders, onboarding, pairing, and agent activity. */
export function ZionMotion({
  ariaLabel,
  className,
  decorative = true,
  loop,
  playing = true,
  variant = "loader",
}: ZionMotionProps) {
  const contract = motionForVariant(variant);
  const effectiveLoop = loop ?? contract.loop;
  const rootStyle: ZionMotionStyle = {
    "--zion-motion-duration": `${contract.durationMs}ms`,
    "--zion-motion-iteration-count": effectiveLoop ? "infinite" : "1",
    "--zion-motion-settle-duration":
      "settleMs" in contract ? `${contract.settleMs}ms` : "0ms",
    "--zion-motion-stagger-duration":
      "staggerMs" in contract ? `${contract.staggerMs}ms` : "0ms",
  };
  const trimmedLabel = ariaLabel?.trim() || undefined;

  return (
    <span
      aria-label={!decorative ? trimmedLabel : undefined}
      className={cn("zion-motion", `zion-motion--${variant}`, className)}
      data-brand-surface="zion-motion"
      data-loop={effectiveLoop ? "true" : "false"}
      data-playing={playing ? "true" : "false"}
      data-zion-variant={variant}
      role={!decorative && trimmedLabel ? "img" : undefined}
      style={rootStyle}
    >
      {decorative && trimmedLabel ? (
        <span className="sr-only">{trimmedLabel}</span>
      ) : null}
      <ZionMark
        ariaLabel={trimmedLabel}
        className="zion-motion__mark"
        decorative={decorative}
      />
    </span>
  );
}
