import { cn } from "@/shared/lib/cn";
import { ZION_BRAND_ASSETS } from "./brandAssetManifest";

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
    <img
      aria-hidden={decorative ? true : undefined}
      alt={decorative ? "" : ariaLabel}
      className={cn("zion-mark", className)}
      data-brand-surface="zion-mark"
      src={ZION_BRAND_ASSETS.mark.canonicalPath}
    />
  );
}
