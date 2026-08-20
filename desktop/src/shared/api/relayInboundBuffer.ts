export const MAX_PENDING_RELAY_FRAMES = 256;
export const MAX_PENDING_RELAY_BYTES = 1024 * 1024;

function utf8ByteLength(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) bytes += 1;
    else if (code <= 0x7ff) bytes += 2;
    else if (
      code >= 0xd800 &&
      code <= 0xdbff &&
      value.charCodeAt(index + 1) >= 0xdc00 &&
      value.charCodeAt(index + 1) <= 0xdfff
    ) {
      bytes += 4;
      index += 1;
    } else bytes += 3;
  }
  return bytes;
}

function nativeByteArrayLength(value: unknown): number | null {
  if (!Array.isArray(value)) return null;
  return value.every(
    (byte) => Number.isInteger(byte) && byte >= 0 && byte <= 0xff,
  )
    ? value.length
    : null;
}

function estimateRelayMessageBytes(message: unknown): number | null {
  if (typeof message === "string") return utf8ByteLength(message);
  if (typeof message !== "object" || message === null) return null;

  const { type, data } = message as Record<string, unknown>;
  if (type === "Text" && typeof data === "string") {
    return utf8ByteLength(data);
  }
  if (type === "Binary" || type === "Ping" || type === "Pong") {
    return nativeByteArrayLength(data);
  }
  if (type !== "Close") return null;
  if (data === null) return 0;
  if (typeof data !== "object" || data === null) return null;

  const { code, reason } = data as Record<string, unknown>;
  return Number.isInteger(code) &&
    typeof code === "number" &&
    code >= 0 &&
    code <= 0xffff &&
    typeof reason === "string"
    ? 2 + utf8ByteLength(reason)
    : null;
}

export function createRelayInboundBuffer(
  handle: (message: unknown) => Promise<void>,
  onError: (error: unknown) => void,
) {
  let pending: Array<{ bytes: number; message: unknown }> | null | undefined =
    [];
  let pendingBytes = 0;
  let rejectOverflow = (_error: Error) => {};
  const overflow = new Promise<never>((_resolve, reject) => {
    rejectOverflow = reject;
  });
  void overflow.catch(() => {});

  return {
    overflow,
    receive(message: unknown) {
      if (pending === null) {
        void handle(message).catch(onError);
        return;
      }
      if (pending === undefined) return;
      if (pending.length >= MAX_PENDING_RELAY_FRAMES) {
        pending = undefined;
        const error = new Error("Relay sent too many frames while connecting.");
        rejectOverflow(error);
        onError(error);
        return;
      }
      const bytes = estimateRelayMessageBytes(message);
      if (bytes === null) {
        pending = undefined;
        const error = new Error(
          "Relay frame could not be safely sized while connecting.",
        );
        rejectOverflow(error);
        onError(error);
        return;
      }
      if (bytes > MAX_PENDING_RELAY_BYTES - pendingBytes) {
        pending = undefined;
        const error = new Error("Relay sent too much data while connecting.");
        rejectOverflow(error);
        onError(error);
        return;
      }
      pendingBytes += bytes;
      pending.push({ bytes, message });
    },
    async drain() {
      while (pending?.length) {
        const next = pending.shift();
        if (!next) break;
        await handle(next.message);
        pendingBytes -= next.bytes;
      }
      if (pending) pending = null;
    },
  };
}
