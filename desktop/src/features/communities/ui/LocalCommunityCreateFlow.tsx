import * as React from "react";
import { AlertCircle, LoaderCircle } from "lucide-react";

import {
  checkLocalCommunityName,
  createLocalCommunity,
  localCommunityRelayUrl,
  VALID_LOCAL_COMMUNITY_NAME,
} from "@/features/communities/localCommunityApi";
import { useCommunityOnboarding } from "@/features/onboarding/communityOnboarding";
import {
  CHANNEL_FORM_FIELD_CONTROL_CLASS,
  CHANNEL_FORM_FIELD_SHELL_CLASS,
} from "@/features/channels/ui/channelFormStyles";
import { cn } from "@/shared/lib/cn";
import { Button } from "@/shared/ui/button";
import { Input } from "@/shared/ui/input";

type LocalCommunityCreateFlowProps = {
  onComplete?: () => void;
};

export function LocalCommunityCreateFlow({
  onComplete,
}: LocalCommunityCreateFlowProps) {
  const onboarding = useCommunityOnboarding();
  const [name, setName] = React.useState("");
  const [availability, setAvailability] = React.useState<boolean | null>(null);
  const [checkingName, setCheckingName] = React.useState(false);
  const [action, setAction] = React.useState<string | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  const normalizedName = name.trim().toLowerCase();
  const validName =
    normalizedName.length <= 63 &&
    VALID_LOCAL_COMMUNITY_NAME.test(normalizedName);

  React.useEffect(() => {
    if (!normalizedName || !validName) {
      setCheckingName(false);
      return;
    }
    let cancelled = false;
    setCheckingName(true);
    const handle = window.setTimeout(() => {
      void checkLocalCommunityName(normalizedName)
        .then((response) => {
          if (!cancelled)
            setAvailability(
              response.error ? null : (response.available ?? false),
            );
        })
        .catch(() => {
          if (!cancelled) setAvailability(null);
        })
        .finally(() => {
          if (!cancelled) setCheckingName(false);
        });
    }, 350);
    return () => {
      cancelled = true;
      window.clearTimeout(handle);
    };
  }, [normalizedName, validName]);

  const create = (event: React.FormEvent) => {
    event.preventDefault();
    if (!validName || availability === false || action) return;
    setAction("Creating community…");
    setError(null);
    void (async () => {
      try {
        const available = await checkLocalCommunityName(normalizedName);
        if (available.error || !available.available) {
          setAvailability(false);
          throw new Error(
            available.error ?? "That Zion address is already taken.",
          );
        }
        const response = await createLocalCommunity(normalizedName);
        if (response.error || !response.host) {
          throw new Error(
            response.error ?? "Could not create the local community.",
          );
        }
        const relayUrl = localCommunityRelayUrl(response);
        if (!relayUrl)
          throw new Error("The Zion relay did not return a community address.");
        if (
          !onboarding.start({
            source: "add-community",
            relayUrl,
            communityName: normalizedName,
          })
        ) {
          throw new Error(
            "Another community is already being connected. Finish it before connecting this one.",
          );
        }
        onComplete?.();
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : String(cause));
      } finally {
        setAction(null);
      }
    })();
  };

  const feedback =
    name && !validName
      ? "Use lowercase letters, numbers, and single hyphens."
      : checkingName
        ? "Checking this Zion address…"
        : availability === false
          ? "That Zion address is already taken."
          : availability === true
            ? "That Zion address is available."
            : "This community will stay on the active Zion relay.";

  return (
    <form className="space-y-5" onSubmit={create}>
      <div className="space-y-1.5">
        <label
          className="text-sm font-medium text-foreground"
          htmlFor="local-community-name"
        >
          Community address
        </label>
        <div
          className={cn(
            "flex min-h-11 items-center px-3",
            CHANNEL_FORM_FIELD_SHELL_CLASS,
          )}
        >
          <Input
            autoCapitalize="none"
            autoComplete="off"
            autoCorrect="off"
            autoFocus
            className={cn(
              "h-8 min-w-0 px-0 py-0 leading-6",
              CHANNEL_FORM_FIELD_CONTROL_CLASS,
            )}
            data-testid="local-community-create-name"
            disabled={Boolean(action)}
            id="local-community-name"
            maxLength={63}
            onChange={(event) => {
              setName(event.target.value.toLowerCase());
              setAvailability(null);
              setError(null);
            }}
            placeholder="north-star"
            spellCheck={false}
            value={name}
          />
          <span className="shrink-0 text-sm text-muted-foreground/70">
            on the active relay
          </span>
        </div>
        <p
          className={cn(
            "text-xs leading-5",
            availability === false || (name && !validName)
              ? "text-destructive"
              : "text-muted-foreground",
          )}
        >
          {feedback}
        </p>
      </div>
      {error ? (
        <div
          className="flex items-start gap-3 rounded-xl border border-destructive/30 bg-destructive/10 p-4"
          role="alert"
        >
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
          <p className="text-sm leading-5 text-destructive">{error}</p>
        </div>
      ) : null}
      <div className="flex justify-end pt-1">
        <Button
          data-testid="local-community-create-submit"
          disabled={
            !validName ||
            availability === false ||
            checkingName ||
            Boolean(action)
          }
          type="submit"
        >
          {action ? <LoaderCircle className="h-4 w-4 animate-spin" /> : null}
          {action ?? "Create community"}
        </Button>
      </div>
    </form>
  );
}
