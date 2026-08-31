import { LocalCommunityCreateFlow } from "@/features/communities/ui/LocalCommunityCreateFlow";
import { Button } from "@/shared/ui/button";

type LocalCommunityOnboardingProps = {
  onBack: () => void;
  onReady?: () => void;
};

export function LocalCommunityOnboarding({
  onBack,
  onReady,
}: LocalCommunityOnboardingProps) {
  return (
    <div className="flex w-full max-w-[620px] flex-col items-center text-center">
      <h1 className="text-title font-normal">Create a Zion community</h1>
      <p className="mt-3 text-sm leading-6 text-foreground/80">
        Choose a name. Your community, identity, and data stay on this Zion
        relay.
      </p>
      <div className="mt-10 w-full text-left">
        <LocalCommunityCreateFlow onComplete={onReady} />
      </div>
      <Button
        className="mt-8 rounded-full"
        onClick={onBack}
        type="button"
        variant="ghost"
      >
        Back
      </Button>
    </div>
  );
}
