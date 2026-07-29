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
  {
    top: "11%",
    left: "17%",
    size: 26,
    rotate: -8,
    scale: 0.9,
    driftX: -8,
    driftY: 7,
  },
  {
    top: "19%",
    left: "74%",
    size: 22,
    rotate: 10,
    scale: 0.88,
    driftX: 7,
    driftY: -6,
  },
  {
    top: "37%",
    left: "11%",
    size: 20,
    rotate: 16,
    scale: 0.84,
    driftX: -6,
    driftY: 5,
  },
  {
    top: "51%",
    left: "66%",
    size: 28,
    rotate: -10,
    scale: 0.92,
    driftX: 9,
    driftY: 8,
  },
  {
    top: "73%",
    left: "28%",
    size: 24,
    rotate: 6,
    scale: 0.9,
    driftX: 5,
    driftY: -5,
  },
  {
    top: "84%",
    left: "81%",
    size: 18,
    rotate: -14,
    scale: 0.82,
    driftX: -4,
    driftY: 4,
  },
] as const;

const ONBOARDING_MOTION = motionForVariant("onboarding");
const FIELD_SETTLE_MS =
  ONBOARDING_MOTION.durationMs +
  ("settleMs" in ONBOARDING_MOTION ? ONBOARDING_MOTION.settleMs : 0);

function readReducedMotionPreference() {
  if (
    typeof window === "undefined" ||
    typeof window.matchMedia !== "function"
  ) {
    return false;
  }

  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export function getZionBrandFieldProgress({
  elapsedMs = 0,
  reducedMotion = false,
}: {
  elapsedMs?: number;
  reducedMotion?: boolean;
}) {
  if (reducedMotion) return 1;
  return Math.min(Math.max(elapsedMs / FIELD_SETTLE_MS, 0), 1);
}

function getSettledProgress(progress: number) {
  return 1 - (1 - progress) ** 3;
}

export function getZionBrandFieldMarkStyle(
  mark: Mark,
  {
    elapsedMs = 0,
    reducedMotion = false,
  }: {
    elapsedMs?: number;
    reducedMotion?: boolean;
  } = {},
) {
  const settleProgress = getSettledProgress(
    getZionBrandFieldProgress({ elapsedMs, reducedMotion }),
  );

  const translateX = (1 - settleProgress) * mark.driftX;
  const translateY = (1 - settleProgress) * mark.driftY;
  const opacity = 0.24 + settleProgress * 0.52;
  const scale = mark.scale + settleProgress * (1 - mark.scale);

  return {
    opacity,
    transform: `translate(${translateX}px, ${translateY}px) rotate(${mark.rotate}deg) scale(${scale})`,
  };
}

function applyFieldFrame(
  elapsedMs: number,
  reducedMotion: boolean,
  elements: readonly (HTMLSpanElement | null)[],
) {
  const styleInput = { elapsedMs, reducedMotion };

  elements.forEach((element, index) => {
    const mark = MARKS[index];
    if (!element || !mark) return;
    const style = getZionBrandFieldMarkStyle(mark, styleInput);
    element.style.opacity = `${style.opacity}`;
    element.style.transform = style.transform;
  });
}

function supportsMediaListener(queryList: MediaQueryList) {
  return typeof queryList.addEventListener === "function";
}

export function ZionBrandField() {
  const markRefs = React.useRef<(HTMLSpanElement | null)[]>([]);
  const [reducedMotion, setReducedMotion] = React.useState(
    readReducedMotionPreference,
  );

  React.useEffect(() => {
    if (
      typeof window === "undefined" ||
      typeof window.matchMedia !== "function"
    ) {
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

  React.useEffect(() => {
    const elements = markRefs.current;

    if (reducedMotion) {
      applyFieldFrame(FIELD_SETTLE_MS, true, elements);
      return;
    }

    applyFieldFrame(0, false, elements);

    let animationFrameId = 0;
    const startTime = performance.now();

    const tick = (now: number) => {
      const elapsedMs = Math.min(now - startTime, FIELD_SETTLE_MS);
      applyFieldFrame(elapsedMs, false, elements);

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
      {MARKS.map((mark, index) => {
        const presentation = getZionBrandFieldMarkStyle(mark, {
          reducedMotion,
        });

        return (
          <span
            key={`${mark.top}-${mark.left}`}
            ref={(element) => {
              markRefs.current[index] = element;
            }}
            className="absolute block will-change-transform"
            style={{
              left: mark.left,
              opacity: presentation.opacity,
              top: mark.top,
              transform: presentation.transform,
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
        );
      })}
    </div>
  );
}
