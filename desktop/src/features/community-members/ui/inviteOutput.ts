/** Canonical filename for an exported Zion community invite QR code. */
export const INVITE_PNG_FILENAME = "zion-community-invite.png";

/**
 * Preserve neutral HTTPS invite URLs while upgrading legacy custom-scheme
 * values returned by older relays before they reach a newly emitted surface.
 */
export function canonicalizeInviteOutputUrl(url: string): string {
  return url.replace(/^buzz:\/\//i, "zion://");
}
