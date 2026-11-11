import { useEffect, useId, useRef, useState } from "react";
import { type Bee, spawnBees, stepBees } from "./bees";

// Two-tone Zion palette; the existing swarm motion stays unchanged.
const DEFAULT_PALETTE = ["#A6A6A8", "#4E7CFF"];

// Keep the original sprite footprint and scale so swarm density stays unchanged.
const BEE_W = 46;
const BEE_H = 31;

// Preserve the existing heading offset when replacing only the decorative art.
const ROT_OFFSET = 90;
// Below this speed (px/s) we hold the last facing rather than snapping to a
// meaningless angle when a bee is nearly stationary.
const ROT_MIN_SPEED = 6;
const INTRO_MS = 1050;
const TAU = Math.PI * 2;

// Approved Zion slash geometry, shared with Zion-App's public/buzz-mark.svg.
const ZION_SPRITE_PATH = "M16 30 32 12h20L36 30H16Z M12 52 28 34h20L32 52H12Z";

// Deterministic per-index tint so SSR and client agree (no Math.random). The
// sine-hash seed is independent of the bee's position seed (R2 in bees.ts) so
// same-color bees don't line up into diagonal streaks. Rotation and size are no
// longer per-bee (velocity-driven rotation + uniform size), so this is tint-only.
const hash = (i: number, seed: number) => {
  const v = Math.sin((i + 1) * seed) * 43758.5453;
  return v - Math.floor(v); // fractional part → [0, 1)
};
function tintOf(i: number, paletteLen: number) {
  return Math.floor(hash(i, 12.9898) * paletteLen);
}

function useReducedMotion() {
  const [reduced, setReduced] = useState(
    () => window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  return reduced;
}

export function BeeField({
  count = 24,
  repel = true,
  palette = DEFAULT_PALETTE,
  sizeScale = 1,
  bleed = 0,
  zIndex,
  clip = true,
}: {
  count?: number;
  repel?: boolean;
  palette?: string[];
  // Global multiplier on every bee's rendered size. The footer packs many more
  // bees, so it renders them smaller (sizeScale < 1) to match the dense field.
  sizeScale?: number;
  // Extra simulation space beyond the visible field. Bees are still clipped by
  // the section, but they can partially leave the viewport instead of banking
  // exactly at the edge.
  bleed?: number;
  // Stacking order of the field. Sections pass a value to place the swarm above
  // or below the wordmark — the hero runs two fields (behind + in front of the
  // brand text) for depth.
  zIndex?: number;
  // When false, the field doesn't clip its bees at its own bounds — paired with a
  // non-clipping parent section, bees drift past the edge (up to `bleed`px) so the
  // swarm bridges into the neighbouring section instead of hard-cropping.
  clip?: boolean;
}) {
  const maskPrefix = useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const wrap = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  // SSR + initial client render = count, matching the statically-exported HTML
  // (no hydration mismatch). The effect then halves it on narrow screens. This
  // is the single source of truth for both rendered bees and spawned bees.
  const [n, setN] = useState(count);
  useEffect(() => {
    const updateCount = () => {
      setN(window.innerWidth < 640 ? Math.ceil(count / 2) : count);
    };
    const raf = requestAnimationFrame(updateCount);
    window.addEventListener("resize", updateCount);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", updateCount);
    };
  }, [count]);

  // Per-bee render data, recomputed when count or palette changes.
  const renderedBees = Array.from({ length: n }, (_, i) => ({
    key: `${maskPrefix}-bee-${i}`,
    tint: tintOf(i, palette.length),
  }));

  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    // Source the bee nodes directly from the committed DOM (the rendered spans
    // are el's children) rather than from ref callbacks — ref timing relative to
    // this effect is fragile, and getting it wrong leaves every bee stacked at
    // the origin instead of spread across the field.
    const beeNodes = Array.from(el.children) as HTMLElement[];
    const bleedPx = Math.max(0, bleed);
    let w = el.clientWidth + bleedPx * 2,
      h = el.clientHeight + bleedPx * 2;
    let bees: Bee[] = spawnBees(n, w, h, bleedPx);
    const introFrom = bees.map((b, i) => {
      const angle = b.seed * TAU + i * 0.37;
      return {
        x: w / 2 + Math.cos(angle) * (w * 0.7 + bleedPx + BEE_W),
        y: h / 2 + Math.sin(angle) * (h * 0.7 + bleedPx + BEE_H),
      };
    });
    // Smoothed facing angle (deg) per bee, so bees bank toward their heading
    // instead of snapping. Seeded from the initial wander heading.
    const rot = bees.map((b) => (b.heading * 180) / Math.PI + ROT_OFFSET);
    let pointer: { x: number; y: number } | null = null;
    // Listen on WINDOW, not `el`: the wrapper is pointer-events:none (so it never
    // blocks clicks on the content beneath it), which means pointer events never
    // reach it — listening on `el` left repel permanently dead. We translate the
    // global cursor into field-local coordinates via the live bounding rect.
    const onMove = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      pointer = {
        x: e.clientX - r.left + bleedPx,
        y: e.clientY - r.top + bleedPx,
      };
    };
    const onLeave = () => {
      pointer = null;
    };
    if (repel && !reduce) {
      window.addEventListener("pointermove", onMove, { passive: true });
      // Clear when the cursor leaves the document entirely.
      document.addEventListener("pointerleave", onLeave);
    }
    const paint = (introProgress = 1) =>
      beeNodes.forEach((node, i) => {
        const b = bees[i];
        if (node && b) {
          const easedIntro = 1 - (1 - introProgress) ** 3;
          const from = introFrom[i];
          const displayX = from ? from.x + (b.x - from.x) * easedIntro : b.x;
          const displayY = from ? from.y + (b.y - from.y) * easedIntro : b.y;
          node.style.transform = `translate(${displayX - bleedPx}px, ${displayY - bleedPx}px) rotate(${rot[i]}deg) scale(${sizeScale})`;
        }
      });
    let introProgress = reduce ? 1 : 0;
    const observer = new ResizeObserver(() => {
      const nextW = el.clientWidth + bleedPx * 2;
      const nextH = el.clientHeight + bleedPx * 2;
      if (nextW <= 0 || nextH <= 0 || (nextW === w && nextH === h)) return;
      const scaleX = nextW / Math.max(1, w);
      const scaleY = nextH / Math.max(1, h);
      bees = bees.map((bee) => ({
        ...bee,
        x: bee.x * scaleX,
        y: bee.y * scaleY,
        homeX: (bee.homeX ?? w / 2) * scaleX,
        homeY: (bee.homeY ?? h / 2) * scaleY,
      }));
      for (const from of introFrom) {
        from.x *= scaleX;
        from.y *= scaleY;
      }
      w = nextW;
      h = nextH;
      pointer = null;
      paint(introProgress);
    });
    observer.observe(el);
    if (reduce) {
      paint();
      return () => observer.disconnect();
    } // freeze
    paint(0);
    let last = performance.now();
    const t0 = last;
    let raf = 0;
    const loop = (t: number) => {
      const dt = Math.min(0.05, (t - last) / 1000);
      last = t;
      // Elapsed seconds drive each bee's independent wander heading.
      bees = stepBees(bees, pointer, dt, w, h, repel, (t - t0) / 1000, bleedPx);
      // Rotate each bee toward its travel direction (shortest-arc lerp).
      bees.forEach((b, i) => {
        const speed = Math.hypot(b.vx, b.vy);
        if (speed > ROT_MIN_SPEED) {
          const target = (Math.atan2(b.vy, b.vx) * 180) / Math.PI + ROT_OFFSET;
          const diff = ((target - rot[i] + 540) % 360) - 180;
          rot[i] += diff * 0.18;
        }
      });
      introProgress = Math.min(1, (t - t0) / INTRO_MS);
      paint(introProgress);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      observer.disconnect();
      window.removeEventListener("pointermove", onMove);
      document.removeEventListener("pointerleave", onLeave);
    };
  }, [n, repel, reduce, sizeScale, bleed]);

  return (
    <div
      ref={wrap}
      aria-hidden
      style={{
        position: "absolute",
        inset: 0,
        overflow: clip ? "hidden" : "visible",
        pointerEvents: "none",
        zIndex,
      }}
    >
      {renderedBees.map(({ key, tint }) => (
        <span
          key={key}
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            width: BEE_W,
            height: BEE_H,
            color: palette[tint],
            transformOrigin: "center",
            willChange: "transform",
          }}
        >
          <svg
            className="zion-sprite"
            viewBox="0 0 64 64"
            aria-hidden
            width={BEE_W}
            height={BEE_H}
            style={{ display: "block", overflow: "visible" }}
            focusable="false"
          >
            <title>Animated Zion mark</title>
            <path
              d={ZION_SPRITE_PATH}
              fill="currentColor"
              fillRule="evenodd"
              clipRule="evenodd"
            />
          </svg>
        </span>
      ))}
    </div>
  );
}
