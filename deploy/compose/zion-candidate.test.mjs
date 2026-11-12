import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const root = fileURLToPath(new URL("../../", import.meta.url));
const overlay = "deploy/compose/compose.zion-candidate.yml";
const gateway = "deploy/compose/compose.zion-gateway.yml";
// Deliberately synthetic: never inherit credentials, Compose switches or .env.
const env = {
  PATH: process.env.PATH,
  HOME: process.env.HOME,
  DOCKER_CONFIG: "/nonexistent-zion-synthetic-docker-config",
  ZION_RELAY_IMAGE: `example.invalid/zion@sha256:${"1".repeat(64)}`,
  ZION_POSTGRES_IMAGE: `postgres:17-alpine@sha256:${"2".repeat(64)}`,
  ZION_REDIS_IMAGE: `redis:7-alpine@sha256:${"3".repeat(64)}`,
  POSTGRES_PASSWORD: "synthetic-pg-only",
  REDIS_PASSWORD: "synthetic-redis-only",
  BUZZ_S3_ACCESS_KEY: "synthetic-media",
  BUZZ_S3_SECRET_KEY: "synthetic-media-only",
  BUZZ_RELAY_PRIVATE_KEY: "1".repeat(64),
  RELAY_OWNER_PUBKEY: "2".repeat(64),
  BUZZ_GIT_HOOK_HMAC_SECRET: "3".repeat(64),
};

function render(extra = {}, files = []) {
  assert.ok(existsSync(`${root}${overlay}`), "candidate overlay must exist");
  return spawnSync(
    process.env.ZION_COMPOSE_BIN || "docker-compose",
    [
      "--env-file",
      "/dev/null",
      "-f",
      "deploy/compose/compose.yml",
      "-f",
      overlay,
      ...files.flatMap((file) => ["-f", file]),
      "config",
      "--format",
      "json",
    ],
    { cwd: root, env: { ...env, ...extra }, encoding: "utf8", timeout: 15000 },
  );
}

function config(extra = {}, files = []) {
  const result = render(extra, files);
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

async function validate(document) {
  const module = new URL("./check-zion-candidate.mjs", import.meta.url);
  assert.ok(existsSync(module), "candidate preflight must exist");
  const { validateCandidate } = await import(module);
  return validateCandidate(document);
}

test("NIP-11 distribution fields and OCI annotations identify Zion, not wire names", () => {
  // Source-level smoke guard; the Rust test above exercises serialized RelayInfo.
  const source = readFileSync(`${root}crates/buzz-relay/src/nip11.rs`, "utf8");
  assert.match(source, /name: "Zion Relay"\.to_string\(\)/);
  assert.match(
    source,
    /description: "Zion — private team communication relay"\.to_string\(\)/,
  );
  assert.match(
    source,
    /software: "https:\/\/github.com\/aidenmi8\/Zion-Coms"\.to_string\(\)/,
  );
  assert.match(source, /version: env!\("CARGO_PKG_VERSION"\)/);
  for (const [file, title] of [
    ["Dockerfile", "Zion"],
    ["Dockerfile.push-gateway", "Zion Push Gateway"],
  ]) {
    const dockerfile = readFileSync(`${root}${file}`, "utf8");
    assert.ok(dockerfile.includes(`org.opencontainers.image.title="${title}"`));
    assert.ok(
      dockerfile.includes(
        'org.opencontainers.image.source="https://github.com/aidenmi8/Zion-Coms"',
      ),
    );
    assert.ok(
      dockerfile.includes('org.opencontainers.image.licenses="Apache-2.0"'),
    );
    assert.ok(dockerfile.includes("USER buzz:buzz"));
    assert.ok(dockerfile.includes("/usr/local/bin/buzz-"));
  }
});

test("rendered upstream + candidate stack is isolated, pinned and complete", async () => {
  const document = config();
  assert.equal(document.name, "zion-clean-rc-20261106");
  assert.deepEqual(Object.keys(document.services).sort(), [
    "minio",
    "minio-init",
    "pairing",
    "postgres",
    "redis",
    "relay",
  ]);
  assert.equal(
    document.services.relay.environment.DATABASE_URL,
    "postgres://buzz:synthetic-pg-only@postgres:5432/buzz",
  );
  assert.equal(
    document.services.relay.environment.BUZZ_S3_ENDPOINT,
    "http://minio:9000",
  );
  assert.equal(
    document.services.relay.environment.BUZZ_S3_ADDRESSING_STYLE,
    "path",
  );
  assert.equal(
    document.services.relay.environment.BUZZ_GIT_REPO_PATH,
    "/data/git",
  );
  assert.equal(document.services.relay.environment.BUZZ_PUSH_ENABLED, "false");
  assert.equal(
    document.services.relay.environment.BUZZ_PAIRING_RELAY_URL,
    "ws://127.0.0.1:23350",
  );
  assert.equal(
    document.services.pairing.entrypoint[0],
    "/usr/local/bin/buzz-pair-relay",
  );
  assert.equal(document.services.postgres.image, env.ZION_POSTGRES_IMAGE);
  assert.equal(
    document.services.relay.depends_on["minio-init"].condition,
    "service_completed_successfully",
  );
  assert.deepEqual(
    document.services.relay.ports.map((port) => port.published),
    ["23300", "23380", "23392"],
  );
  assert.equal(document.services.pairing.ports[0].published, "23350");
  assert.equal(Object.keys(document.volumes).length, 4);
  assert.equal(document.services.postgres.ports, undefined);
  assert.equal(document.services.redis.ports, undefined);
  assert.equal(document.services.minio.ports, undefined);
  assert.doesNotThrow(() => validateCandidateShape(document));
  await validate(document);
});

function validateCandidateShape(document) {
  for (const service of Object.values(document.services)) {
    assert.match(service.image, /@sha256:[a-f0-9]{64}$/);
    assert.equal(service.env_file, undefined);
    assert.equal(service.container_name, undefined);
    for (const port of service.ports ?? [])
      assert.equal(port.host_ip, "127.0.0.1");
  }
  for (const volume of Object.values(document.volumes)) {
    assert.ok(volume.name.startsWith("zion-clean-rc-20261106_"));
    assert.ok(!volume.external);
  }
  for (const network of Object.values(document.networks)) {
    assert.ok(network.name.startsWith("zion-clean-rc-20261106_"));
    assert.ok(!network.external);
  }
}

test("required values cannot silently fall back to mutable upstream images", async () => {
  for (const key of [
    "ZION_RELAY_IMAGE",
    "ZION_POSTGRES_IMAGE",
    "ZION_REDIS_IMAGE",
    "BUZZ_RELAY_PRIVATE_KEY",
    "RELAY_OWNER_PUBKEY",
  ]) {
    const result = render({ [key]: "" });
    assert.notEqual(result.status, 0, key);
    assert.ok(result.stderr.includes(key), result.stderr);
  }
  for (const [key, value] of [
    ["ZION_RELAY_IMAGE", "example.invalid/zion:latest"],
    ["ZION_POSTGRES_IMAGE", "postgres:16-alpine"],
    ["ZION_REDIS_IMAGE", "redis:7-alpine"],
  ]) {
    await assert.rejects(
      validate(config({ [key]: value })),
      /immutable|PostgreSQL 17/,
    );
  }
});

test("preflight rejects old storage, public exposure and bypassed isolation in rendered config", async () => {
  const mutations = [
    (c) => {
      c.name = "buzz";
    },
    (c) => {
      c.volumes["buzz-postgres-data"].name = "buzz-postgres-data";
    },
    (c) => {
      c.volumes["buzz-git-data"].external = true;
    },
    (c) => {
      c.networks["buzz-net"].external = true;
    },
    (c) => {
      c.services.relay.ports[0].host_ip = "0.0.0.0";
    },
    (c) => {
      c.services.relay.network_mode = "host";
    },
    (c) => {
      c.services.relay.container_name = "buzz-relay";
    },
    (c) => {
      c.services.relay.volumes_from = ["container:old-zion-relay:ro"];
    },
    (c) => {
      c.services.relay.volumes = [];
    },
    (c) => {
      c.services.relay.volumes[0].source = "buzz-postgres-data";
    },
    (c) => {
      c.services.relay.volumes[0] = {
        type: "bind",
        source: "/old/data",
        target: "/data/git",
      };
    },
    (c) => {
      c.services.postgres.image = `postgres:16-alpine@sha256:${"4".repeat(64)}`;
    },
    (c) => {
      c.services.relay.environment.BUZZ_PUSH_ENABLED = "true";
    },
  ];
  for (const mutate of mutations) {
    const document = config();
    mutate(document);
    await assert.rejects(validate(document));
  }
});

test("optional gateway keeps separate storage and requires explicit relay push opt-in", async () => {
  assert.ok(
    existsSync(`${root}${gateway}`),
    "separate gateway template must exist",
  );
  const gatewayEnv = {
    ZION_GATEWAY_IMAGE: `example.invalid/zion-push@sha256:${"4".repeat(64)}`,
    ZION_PUSH_POSTGRES_PASSWORD: "synthetic-push-pg-only",
    ZION_PUSH_RUNTIME_DATABASE_URL:
      "postgres://gateway_runtime:synthetic@push-postgres:5432/buzz_push",
    ZION_PUSH_GRANT_KEYS: "synthetic-grant-placeholder",
    ZION_PUSH_TOKEN_KEYS: "synthetic-token-placeholder",
    ZION_PUSH_APP_ID: "EXAMPLE.com.example.zion",
    ZION_PUSH_APNS_TOPIC: "com.example.zion",
    ZION_PUSH_APNS_ENVIRONMENT: "sandbox",
    ZION_PUSH_APNS_CERT_FILE: "/nonexistent/synthetic-apns.pem",
    ZION_PUSH_ATTEST_ROOT_FILE: "/nonexistent/synthetic-attest.pem",
  };
  const document = config(gatewayEnv, [gateway]);
  assert.equal(
    document.services["push-postgres"].image,
    env.ZION_POSTGRES_IMAGE,
  );
  assert.equal(
    document.services["push-gateway"].environment.DATABASE_URL,
    "postgres://gateway_runtime:synthetic@push-postgres:5432/buzz_push",
  );
  assert.equal(document.services["push-gateway"].ports[0].published, "23360");
  assert.equal(
    document.services["push-gateway"].environment
      .BUZZ_PUSH_APP_ATTEST_ENVIRONMENT,
    "production",
  );
  assert.equal(
    document.services["push-gateway"].environment.BUZZ_PUSH_APNS_ENVIRONMENT,
    "sandbox",
  );
  assert.equal(document.services.relay.environment.BUZZ_PUSH_ENABLED, "false");
  assert.equal(document.services["push-postgres"].ports, undefined);
  assert.equal(Object.keys(document.volumes).length, 5);
  validateCandidateShape(document);
  await validate(document);
  document.services["push-gateway"].environment.BUZZ_PUSH_APNS_ENVIRONMENT =
    "invalid";
  await assert.rejects(validate(document));
  const enabled = config(
    { ...gatewayEnv, ZION_CANDIDATE_PUSH_ENABLED: "true" },
    [gateway],
  );
  assert.equal(enabled.services.relay.environment.BUZZ_PUSH_ENABLED, "true");
  await validate(enabled);
  enabled.services.relay.environment.BUZZ_PUSH_GATEWAY_DELIVERY_URL =
    "http://other-gateway:8080/v1/deliveries/apns";
  await assert.rejects(validate(enabled));
});

test("read-only preflight CLI refuses unsafe config without printing credentials", () => {
  const checker = fileURLToPath(
    new URL("./check-zion-candidate.mjs", import.meta.url),
  );
  for (const [input, status] of [
    [JSON.stringify(config()), 0],
    [
      JSON.stringify(
        config({ ZION_RELAY_IMAGE: "example.invalid/zion:latest" }),
      ),
      1,
    ],
    ["not-json-synthetic-secret-do-not-print", 1],
  ]) {
    const result = spawnSync(process.execPath, [checker], {
      input,
      encoding: "utf8",
      timeout: 10000,
      env,
    });
    assert.equal(result.status, status, result.stderr);
    assert.ok(
      !`${result.stdout}${result.stderr}`.includes(
        "synthetic-secret-do-not-print",
      ),
    );
    assert.ok(!`${result.stdout}${result.stderr}`.includes("not-json-s"));
    assert.ok(
      !`${result.stdout}${result.stderr}`.includes("synthetic-pg-only"),
    );
    assert.ok(
      !`${result.stdout}${result.stderr}`.includes("synthetic-media-only"),
    );
  }
});
