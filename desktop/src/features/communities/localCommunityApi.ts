import { invoke } from "@tauri-apps/api/core";

export const LOCAL_COMMUNITY_LIMIT = 3;
export const VALID_LOCAL_COMMUNITY_NAME = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export type LocalCommunityAvailabilityResponse = {
  available?: boolean;
  normalized_host?: string;
  error?: string;
};

export type LocalCommunityMutationResponse = {
  community_id?: string;
  host?: string;
  relay_url?: string;
  status?: "created";
  owner_pubkey?: string;
  error?: string;
};

export function localCommunityRelayUrl(
  response: LocalCommunityMutationResponse,
) {
  const relayUrl = response.relay_url?.trim();
  return relayUrl || null;
}

export function checkLocalCommunityName(name: string, relayUrl?: string) {
  return invoke<LocalCommunityAvailabilityResponse>(
    "check_local_community_name",
    { name, relayUrl: relayUrl ?? null },
  );
}

export function createLocalCommunity(name: string, relayUrl?: string) {
  return invoke<LocalCommunityMutationResponse>("create_local_community", {
    name,
    relayUrl: relayUrl ?? null,
  });
}
