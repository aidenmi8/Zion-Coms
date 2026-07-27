import type * as React from "react";

import { cn } from "@/shared/lib/cn";
import { ZionMotion } from "@/shared/ui/zion-brand/ZionMotion";
import "./starter-team-presence.css";

export const STARTER_TEAM_NAMES = ["Fizz", "Honey", "Bumble"] as const;

export type StarterTeamName = (typeof STARTER_TEAM_NAMES)[number];

export type StarterTeamPresenceProps = {
  name: StarterTeamName;
  phase: "entering" | "settled" | "reduced-motion";
};

const STARTER_TEAM_VARIANTS: Record<
  StarterTeamName,
  {
    accent: string;
    glow: string;
    orbitA: { left: string; top: string };
    orbitB: { left: string; top: string };
    shell: string;
    tilt: string;
  }
> = {
  Fizz: {
    accent: "rgba(215, 229, 255, 0.72)",
    glow: "rgba(165, 185, 255, 0.36)",
    orbitA: { left: "24%", top: "34%" },
    orbitB: { left: "73%", top: "69%" },
    shell:
      "linear-gradient(180deg, rgb(29 35 58 / 0.96), rgb(14 18 32 / 0.98))",
    tilt: "-7deg",
  },
  Honey: {
    accent: "rgba(241, 229, 255, 0.72)",
    glow: "rgba(207, 171, 255, 0.34)",
    orbitA: { left: "70%", top: "28%" },
    orbitB: { left: "26%", top: "74%" },
    shell:
      "linear-gradient(180deg, rgb(33 26 47 / 0.96), rgb(17 13 28 / 0.98))",
    tilt: "9deg",
  },
  Bumble: {
    accent: "rgba(223, 234, 255, 0.72)",
    glow: "rgba(161, 202, 255, 0.32)",
    orbitA: { left: "28%", top: "72%" },
    orbitB: { left: "74%", top: "34%" },
    shell:
      "linear-gradient(180deg, rgb(24 34 45 / 0.96), rgb(12 18 28 / 0.98))",
    tilt: "4deg",
  },
};

type StarterPresenceStyle = React.CSSProperties & {
  "--starter-presence-accent"?: string;
  "--starter-presence-glow"?: string;
  "--starter-presence-orbit-a-left"?: string;
  "--starter-presence-orbit-a-top"?: string;
  "--starter-presence-orbit-b-left"?: string;
  "--starter-presence-orbit-b-top"?: string;
  "--starter-presence-shell"?: string;
  "--starter-presence-tilt"?: string;
};

export function StarterTeamPresence({ name, phase }: StarterTeamPresenceProps) {
  const variant = STARTER_TEAM_VARIANTS[name];
  const style: StarterPresenceStyle = {
    "--starter-presence-accent": variant.accent,
    "--starter-presence-glow": variant.glow,
    "--starter-presence-orbit-a-left": variant.orbitA.left,
    "--starter-presence-orbit-a-top": variant.orbitA.top,
    "--starter-presence-orbit-b-left": variant.orbitB.left,
    "--starter-presence-orbit-b-top": variant.orbitB.top,
    "--starter-presence-shell": variant.shell,
    "--starter-presence-tilt": variant.tilt,
  };

  return (
    <span
      aria-hidden="true"
      className={cn(
        "starter-team-presence",
        `starter-team-presence--${name.toLowerCase()}`,
      )}
      data-brand-surface="starter-team-presence"
      data-persona={name}
      data-phase={phase}
      data-zion-variant="agent-entrance"
      style={style}
    >
      <span className="starter-team-presence__backdrop" />
      <span className="starter-team-presence__orbit starter-team-presence__orbit--a" />
      <span className="starter-team-presence__orbit starter-team-presence__orbit--b" />
      <span className="starter-team-presence__ring starter-team-presence__ring--inner" />
      <span className="starter-team-presence__ring starter-team-presence__ring--outer" />
      <ZionMotion
        className="starter-team-presence__core"
        loop={false}
        playing={phase === "entering"}
        variant="agent-entrance"
      />
    </span>
  );
}
