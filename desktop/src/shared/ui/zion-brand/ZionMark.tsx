import { cn } from "@/shared/lib/cn";

export type ZionMarkProps = {
  ariaLabel?: string;
  className?: string;
  decorative?: boolean;
};

/** The static, first-paint-safe Zion product mark. */
export function ZionMark({
  ariaLabel = "Zion",
  className,
  decorative = true,
}: ZionMarkProps) {
  return (
    <svg
      aria-label={decorative ? undefined : ariaLabel}
      aria-hidden={decorative ? true : undefined}
      className={cn("zion-mark", className)}
      data-brand-surface="zion-mark"
      focusable="false"
      role={decorative ? undefined : "img"}
      viewBox="0 0 64 64"
    >
      <g fill="currentColor">
        <path d="M16 30 32 12h20L36 30H16Z" />
        <path d="M12 52 28 34h20L32 52H12Z" />
      </g>
    </svg>
  );
}
