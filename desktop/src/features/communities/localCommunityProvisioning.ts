import type { Community } from "./types";

const ZION_PRIVATE_RELAY_NAME = "zion private relay";

export type LocalCommunityProvisioningRelay = Pick<
  Community,
  "name" | "relayUrl"
>;

export function resolveLocalCommunityProvisioningRelay(
  communities: readonly Community[],
  activeCommunity: Community | null,
): LocalCommunityProvisioningRelay | null {
  const zionRelay = communities.find(
    (community) =>
      community.name.trim().toLowerCase() === ZION_PRIVATE_RELAY_NAME,
  );
  if (zionRelay) {
    return { name: zionRelay.name, relayUrl: zionRelay.relayUrl };
  }

  if (!activeCommunity) return null;
  return {
    name: activeCommunity.name,
    relayUrl: activeCommunity.relayUrl,
  };
}
