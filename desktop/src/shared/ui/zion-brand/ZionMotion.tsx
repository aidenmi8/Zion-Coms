import type * as React from "react";
import { useEffect, useState } from "react";

import { cn } from "@/shared/lib/cn";
import {
  frameAtTime,
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
  motionContractOverride?: ZionMotionContract;
  playing?: boolean;
  variant?: ZionMotionVariant;
};

type ZionMotionContract = ReturnType<typeof motionForVariant>;
type ZionMotionRenderAsset = {
  mode: ZionMotionContract["mode"];
  src: string | null;
};

function readReducedMotionPreference() {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }

  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function supportsMediaListener(queryList: MediaQueryList) {
  return typeof queryList.addEventListener === "function";
}

function usePrefersReducedMotion() {
  const [reducedMotion, setReducedMotion] = useState(readReducedMotionPreference);

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }

    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const handleChange = () => setReducedMotion(mediaQuery.matches);

    handleChange();

    if (supportsMediaListener(mediaQuery)) {
      mediaQuery.addEventListener("change", handleChange);
      return () => mediaQuery.removeEventListener("change", handleChange);
    }

    mediaQuery.addListener(handleChange);
    return () => mediaQuery.removeListener(handleChange);
  }, []);

  return reducedMotion;
}

export function resolveMotionRenderAsset(
  contract: ZionMotionContract,
  {
    elapsedMs = 0,
    loop = contract.loop,
    playing = true,
    reducedMotion = false,
  }: {
    elapsedMs?: number;
    loop?: boolean;
    playing?: boolean;
    reducedMotion?: boolean;
  } = {},
): ZionMotionRenderAsset {
  if (contract.mode === "code-native") {
    return { mode: "code-native", src: null };
  }

  const firstFrame = contract.frames[0] ?? null;
  if (firstFrame === null || reducedMotion || !playing) {
    return { mode: "dedicated-frame", src: firstFrame };
  }

  const frameDurationMs =
    contract.frames.length > 0
      ? contract.durationMs / contract.frames.length
      : contract.durationMs;

  return {
    mode: "dedicated-frame",
    src:
      frameAtTime(contract.frames, elapsedMs, frameDurationMs, loop) ??
      firstFrame,
  };
}

function useMotionElapsedMs({
  durationMs,
  loop,
  mode,
  playing,
  reducedMotion,
}: {
  durationMs: number;
  loop: boolean;
  mode: ZionMotionContract["mode"];
  playing: boolean;
  reducedMotion: boolean;
}) {
  const [elapsedMs, setElapsedMs] = useState(0);

  useEffect(() => {
    if (mode !== "dedicated-frame" || !playing || reducedMotion) {
      setElapsedMs(0);
      return;
    }

    let animationFrameId = 0;
    const startMs = performance.now();

    const tick = (nowMs: number) => {
      const nextElapsedMs = loop
        ? Math.max(0, nowMs - startMs)
        : Math.min(Math.max(0, nowMs - startMs), durationMs);

      setElapsedMs(nextElapsedMs);

      if (loop || nextElapsedMs < durationMs) {
        animationFrameId = requestAnimationFrame(tick);
      }
    };

    animationFrameId = requestAnimationFrame(tick);

    return () => cancelAnimationFrame(animationFrameId);
  }, [durationMs, loop, mode, playing, reducedMotion]);

  return elapsedMs;
}

/** Shared motion layer for loaders, onboarding, pairing, and agent activity. */
export function ZionMotion({
  ariaLabel,
  className,
  decorative = true,
  loop,
  motionContractOverride,
  playing = true,
  variant = "loader",
}: ZionMotionProps) {
  const contract = motionContractOverride ?? motionForVariant(variant);
  const effectiveLoop = loop ?? contract.loop;
  const reducedMotion = usePrefersReducedMotion();
  const elapsedMs = useMotionElapsedMs({
    durationMs: contract.durationMs,
    loop: effectiveLoop,
    mode: contract.mode,
    playing,
    reducedMotion,
  });
  const renderAsset = resolveMotionRenderAsset(contract, {
    elapsedMs,
    loop: effectiveLoop,
    playing,
    reducedMotion,
  });
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
      {renderAsset.mode === "code-native" || renderAsset.src === null ? (
        <ZionMark
          ariaLabel={trimmedLabel}
          className="zion-motion__mark"
          decorative={decorative}
        />
      ) : (
        <img
          alt={decorative ? "" : trimmedLabel ?? ""}
          aria-hidden={decorative ? true : undefined}
          className="zion-motion__frame"
          data-brand-surface="zion-motion-frame"
          src={renderAsset.src}
        />
      )}
    </span>
  );
}
