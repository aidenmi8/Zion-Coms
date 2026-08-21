import { LocalCommunityCreateFlow } from "@/features/communities/ui/LocalCommunityCreateFlow";
import { SettingsSectionHeader } from "./SettingsSectionHeader";

export function LocalCommunitiesSettingsCard() {
  return (
    <section className="space-y-6" data-testid="local-communities-settings">
      <SettingsSectionHeader
        description="Create communities on the local Zion relay. No external account or hosted service is required."
        title="Local communities"
      />
      <div className="rounded-2xl border border-border/60 bg-card/50 p-5">
        <LocalCommunityCreateFlow />
      </div>
    </section>
  );
}
