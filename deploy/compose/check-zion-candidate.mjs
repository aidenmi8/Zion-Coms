// Read-only gate for `docker compose ... config --format json` on stdin.
// No Docker daemon calls, credential generation, environment loading or starts.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const project = "zion-clean-rc-20261106";
const immutable = /^[^\s@]+@sha256:[a-f0-9]{64}$/;
const pg17 =
  /^(?:docker\.io\/library\/)?postgres:17(?:[.-][a-z0-9.-]+)?@sha256:[a-f0-9]{64}$/;

/** Refuse mutable images, reused storage and non-loopback candidate exposure. */
export function validateCandidate(config) {
  assert.equal(config.name, project, "candidate project must be isolated");
  const services = config.services;
  const names = Object.keys(services).sort();
  const base = ["minio", "minio-init", "pairing", "postgres", "redis", "relay"];
  const withGateway = [...base, "push-gateway", "push-postgres"].sort();
  assert.ok(
    JSON.stringify(names) === JSON.stringify(base) ||
      JSON.stringify(names) === JSON.stringify(withGateway),
    "unexpected or missing candidate services",
  );
  const storage = {
    relay: [["buzz-git-data", "/data/git"]],
    postgres: [["buzz-postgres-data", "/var/lib/postgresql/data"]],
    redis: [["buzz-redis-data", "/data"]],
    minio: [["buzz-minio-data", "/data"]],
    "push-postgres": [["zion-push-postgres-data", "/var/lib/postgresql/data"]],
  };
  for (const [name, service] of Object.entries(services)) {
    assert.match(
      service.image,
      immutable,
      `${name}: immutable image digest required`,
    );
    assert.ok(
      !service.build &&
        !service.container_name &&
        !service.network_mode &&
        !service.privileged &&
        !service.volumes_from?.length,
      `${name}: isolation bypass`,
    );
    assert.ok(
      !service.env_file?.length,
      `${name}: env_file must not load .env`,
    );
    assert.deepEqual(
      Object.keys(service.networks),
      ["buzz-net"],
      `${name}: candidate network only`,
    );
    for (const port of service.ports ?? []) {
      assert.equal(
        port.host_ip,
        "127.0.0.1",
        `${name}: loopback only; Tailscale human check pending`,
      );
    }
    for (const volume of service.volumes ?? []) {
      assert.equal(volume.type, "volume", `${name}: no host data mounts`);
      assert.ok(config.volumes[volume.source], `${name}: undeclared volume`);
    }
    assert.deepEqual(
      (service.volumes ?? []).map(({ source, target }) => [source, target]),
      storage[name] ?? [],
      `${name}: exact fresh storage mapping required`,
    );
  }
  for (const [key, volume] of Object.entries(config.volumes)) {
    assert.equal(
      volume.name,
      `${project}_${key}`,
      "old or custom volume name refused",
    );
    assert.ok(
      !volume.external && !volume.driver_opts && !volume.driver,
      "external/custom volume refused",
    );
  }
  assert.deepEqual(Object.keys(config.networks), ["buzz-net"]);
  const network = config.networks["buzz-net"];
  assert.equal(network.name, `${project}_buzz-net`, "old network name refused");
  assert.ok(
    !network.external && !network.driver_opts && network.driver === "bridge",
    "external/custom network refused",
  );
  for (const name of [
    "postgres",
    ...(services["push-postgres"] ? ["push-postgres"] : []),
  ]) {
    assert.match(services[name].image, pg17, "PostgreSQL 17 digest required");
  }
  const relay = services.relay.environment;
  assert.equal(
    relay.BUZZ_PUSH_ENABLED,
    "false",
    "relay push needs separate approval",
  );
  for (const key of [
    "BUZZ_REQUIRE_AUTH_TOKEN",
    "BUZZ_REQUIRE_RELAY_MEMBERSHIP",
    "BUZZ_ALLOW_NIP_OA_AUTH",
  ]) {
    assert.equal(
      relay[key],
      "true",
      "preserve upstream production auth configuration",
    );
  }
  const relayDb = new URL(relay.DATABASE_URL);
  assert.equal(relayDb.hostname, "postgres", "fresh local database only");
  assert.equal(
    new URL(relay.REDIS_URL).hostname,
    "redis",
    "fresh local Redis only",
  );
  assert.equal(relay.BUZZ_S3_ENDPOINT, "http://minio:9000");
  assert.equal(services.pairing.image, services.relay.image);
  if (services["push-gateway"]) {
    const pushDb = new URL(services["push-gateway"].environment.DATABASE_URL);
    assert.equal(
      pushDb.hostname,
      "push-postgres",
      "separate fresh gateway database only",
    );
    assert.equal(pushDb.pathname, "/buzz_push");
    assert.notEqual(
      pushDb.username,
      "buzz_push_admin",
      "gateway requires DML-only runtime role",
    );
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    validateCandidate(JSON.parse(readFileSync(0, "utf8")));
    console.log(
      "PASS candidate config: isolated, digest-pinned, loopback only (not started)",
    );
  } catch {
    // Never dump the rendered document: it contains operator credentials.
    console.error("REFUSED candidate config: invalid or unsafe configuration");
    process.exitCode = 1;
  }
}
