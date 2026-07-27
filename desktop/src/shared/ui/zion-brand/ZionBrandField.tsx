import * as React from "react";

import { motionForVariant } from "./brandAssetManifest";
import { ZionMotion } from "./ZionMotion";

type Mark = {
  driftX: number;
  driftY: number;
  left: string;
  rotate: number;
  scale: number;
  size: number;
  top: string;
};

const MARKS: readonly Mark[] = [
  { top: "11%", left: "17%", size: 26, rotate: -8, scale: 0.9, driftX: -8, driftY: 7 },
  { top: "19%", left: "74%", size: 22, rotate: 10, scale: 0.88, driftX: 7, driftY: -6 },
  { top: "37%", left: "11%", size: 20, rotate: 16, scale: 0.84, driftX: -6, driftY: 5 },
  { top: "51%", left: "66%", size: 28, rotate: -10, scale: 0.92, driftX: 9, driftY: 8 },
  { top: "73%", left: "28%", size: 24, rotate: 6, scale: 0.9, driftX: 5, driftY: -5 },
  { top: "84%", left: "81%", size: 18, rotate: -14, scale: 0.82, driftX: -4, driftY: 4 },
] as const;

const ONBOARDING_MOTION = motionForVariant("onboarding");
const FIELD_SETTLE_MS =
  ONBOARDING_MOTION.durationMs + ("settleMs" in ONBOARDING_MOTION ? ONBOARDING_MOTION.settleMs : 0);

function applyFieldFrame(progress: number, elements: readonly (HTMLSpanElement | null)[]) {
  const clampedProgress = Math.min(Math.max(progress, 0), 1);
  const settleProgress = 1 - Math.pow(1 - clampedProgress, 3);

  elements.forEach((element, index) => {
    const mark = MARKS[index];
    if (!element || !mark) return;

    const translateX = (1 - settleProgress) * mark.driftX;
    const translateY = (1 - settleProgress) * mark.driftY;
    const opacity = 0.24 + settleProgress * 0.52;
    const scale = mark.scale + settleProgress * (1 - mark.scale);

    element.style.opacity = `${opacity}`;
    element.style.transform =
      `translate(${translateX}px, ${translateY}px) rotate(${mark.rotate}deg) scale(${scale})`;
  });
}

function supportsMediaListener(queryList: MediaQueryList) {
  return typeof queryList.addEventListener === "function";
}

export function ZionBrandField() {
  const markRefs = React.useRef<(HTMLSpanElement | null)[]>([]);
  const [reducedMotion, setReducedMotion] = React.useState(false);

  React.useEffect(() => {
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

  React.useEffect(() => {
    const elements = markRefs.current;

    if (reducedMotion) {
      applyFieldFrame(1, elements);
      return;
    }

    applyFieldFrame(0, elements);

    let animationFrameId = 0;
    const startTime = performance.now();

    const tick = (now: number) => {
      const elapsedMs = Math.min(now - startTime, FIELD_SETTLE_MS);
      applyFieldFrame(elapsedMs / FIELD_SETTLE_MS, elements);

      if (elapsedMs < FIELD_SETTLE_MS) {
        animationFrameId = window.requestAnimationFrame(tick);
      }
    };

    animationFrameId = window.requestAnimationFrame(tick);

    return () => window.cancelAnimationFrame(animationFrameId);
  }, [reducedMotion]);

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 overflow-hidden"
      data-brand-surface="zion-brand-field"
    >
      {MARKS.map((mark, index) => (
        <span
          key={`${mark.top}-${mark.left}`}
          ref={(element) => {
            markRefs.current[index] = element;
          }}
          className="absolute block will-change-transform"
          style={{
            left: mark.left,
            opacity: 0.24,
            top: mark.top,
            width: mark.size,
          }}
        >
          <ZionMotion
            className="w-full opacity-70"
            decorative
            loop={false}
            playing={!reducedMotion}
            variant="onboarding"
          />
        </span>
      ))}
    </div>
  );
}
