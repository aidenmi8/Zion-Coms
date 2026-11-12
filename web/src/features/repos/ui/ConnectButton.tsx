import { ExternalLink } from "lucide-react";

import { relayWsUrl } from "@/shared/lib/relay-url";
import { Button } from "@/shared/ui/button";

export function ConnectButton({ className }: { className?: string }) {
  const deepLink = `buzz://connect?relay=${encodeURIComponent(relayWsUrl())}`;

  return (
    <Button
      asChild
      className={`bg-[#4E7CFF] text-[#0A0A0A] hover:bg-[#416BE0] focus-visible:ring-[#4E7CFF] ${className ?? ""}`}
    >
      <a href={deepLink}>
        <ExternalLink className="h-4 w-4" />
        Open in Zion
      </a>
    </Button>
  );
}
