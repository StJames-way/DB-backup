const MAX_REQUEST_BYTES = 278_528;
const MAX_OIDC_TOKEN_CHARS = 16_384;
const SIGN_PATH = "/v1/sign";
const READY_PATH = "/readyz";
const GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com";
const GITHUB_OIDC_JWKS_URL =
  "https://token.actions.githubusercontent.com/.well-known/jwks";
const GITHUB_OIDC_ALGORITHM = "RS256";
const JWKS_CACHE_SECONDS = 300;
const GITHUB_JWKS_FETCH_ATTEMPTS = 6;
const GITHUB_JWKS_FETCH_TIMEOUT_MS = 15_000;
const GITHUB_JWKS_RETRY_BASE_MS = 500;
const textEncoder = new TextEncoder();

let githubJwksCache = null;

class OidcValidationError extends Error {
  constructor(code) {
    super(code);
    this.name = "OidcValidationError";
    this.code = code;
  }
}

class OidcUnavailableError extends Error {
  constructor(code, cause) {
    super(code, { cause });
    this.name = "OidcUnavailableError";
    this.code = code;
  }
}

function jsonResponse(status, payload, extraHeaders = {}) {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    ...extraHeaders,
  });
  return new Response(JSON.stringify(payload), { status, headers });
}

function hex(bytes) {
  return [...new Uint8Array(bytes)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

async function secureEqual(left, right) {
  const [leftDigest, rightDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", textEncoder.encode(left)),
    crypto.subtle.digest("SHA-256", textEncoder.encode(right)),
  ]);

  const leftBytes = new Uint8Array(leftDigest);
  const rightBytes = new Uint8Array(rightDigest);
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}

function base64UrlToBytes(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new OidcValidationError("jwt_base64url_invalid");
  }

  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    + "=".repeat((4 - (value.length % 4)) % 4);

  let decoded;
  try {
    decoded = atob(padded);
  } catch {
    throw new OidcValidationError("jwt_base64url_invalid");
  }

  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function decodeJwtJson(segment, label) {
  const bytes = base64UrlToBytes(segment);
  let parsed;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new OidcValidationError(`jwt_${label}_invalid`);
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new OidcValidationError(`jwt_${label}_invalid`);
  }
  return parsed;
}

function requireConfiguredValue(env, name) {
  const value = String(env[name] ?? "").trim();
  if (!value) {
    throw new OidcUnavailableError(`missing_worker_config_${name}`);
  }
  return value;
}

function requireStringClaim(claims, name) {
  const value = claims[name];
  if (typeof value !== "string" || !value) {
    throw new OidcValidationError(`missing_or_invalid_claim_${name}`);
  }
  return value;
}

function requireNumericDate(claims, name) {
  const value = claims[name];
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new OidcValidationError(`missing_or_invalid_claim_${name}`);
  }
  return value;
}

function audienceContains(audience, expected) {
  if (typeof audience === "string") return audience === expected;
  if (Array.isArray(audience)) {
    return audience.length > 0
      && audience.every((value) => typeof value === "string")
      && audience.includes(expected);
  }
  return false;
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function errorCauseDetails(error) {
  const cause = error instanceof Error ? error.cause : undefined;
  return {
    name: error instanceof Error ? error.name : typeof error,
    message: error instanceof Error ? error.message : String(error),
    causeName: cause instanceof Error ? cause.name : undefined,
    causeMessage: cause instanceof Error ? cause.message : undefined,
  };
}

async function fetchGithubJwksResponse() {
  let lastError;

  for (
    let attempt = 1;
    attempt <= GITHUB_JWKS_FETCH_ATTEMPTS;
    attempt += 1
  ) {
    try {
      const response = await fetch(GITHUB_OIDC_JWKS_URL, {
        method: "GET",
        headers: {
          accept: "application/json",
          "user-agent": "camino-backup-gateway/1.0",
        },
        redirect: "manual",
        signal: AbortSignal.timeout(GITHUB_JWKS_FETCH_TIMEOUT_MS),
        cf: {
          cacheEverything: true,
          cacheTtlByStatus: {
            "200-299": JWKS_CACHE_SECONDS,
            "400-499": 0,
            "500-599": 0,
          },
        },
      });

      if (
        response.ok
        || ![429, 500, 502, 503, 504].includes(response.status)
      ) {
        return response;
      }

      lastError = new Error(`github_jwks_http_${response.status}`);
    } catch (error) {
      lastError = error;
    }

    if (attempt < GITHUB_JWKS_FETCH_ATTEMPTS) {
      const delay = Math.min(
        8_000,
        GITHUB_JWKS_RETRY_BASE_MS * (2 ** (attempt - 1)),
      );
      await wait(delay);
    }
  }

  throw new OidcUnavailableError(
    "github_jwks_fetch_failed",
    lastError,
  );
}

async function fetchGithubJwks(forceRefresh = false) {
  const now = Date.now();
  if (
    !forceRefresh
    && githubJwksCache
    && githubJwksCache.expiresAt > now
  ) {
    return githubJwksCache.keys;
  }

  const response = await fetchGithubJwksResponse();

  if (!response.ok) {
    throw new OidcUnavailableError(
      `github_jwks_http_${response.status}`,
    );
  }

  let document;
  try {
    document = await response.json();
  } catch (error) {
    throw new OidcUnavailableError("github_jwks_json_invalid", error);
  }

  if (!document || !Array.isArray(document.keys) || document.keys.length === 0) {
    throw new OidcUnavailableError("github_jwks_keys_missing");
  }

  const keys = document.keys.filter((key) => (
    key
    && typeof key === "object"
    && key.kty === "RSA"
    && typeof key.kid === "string"
    && key.kid.length > 0
    && typeof key.n === "string"
    && typeof key.e === "string"
    && (key.use === undefined || key.use === "sig")
    && (key.alg === undefined || key.alg === GITHUB_OIDC_ALGORITHM)
  ));

  if (keys.length === 0) {
    throw new OidcUnavailableError("github_jwks_no_usable_keys");
  }

  githubJwksCache = {
    keys,
    expiresAt: now + JWKS_CACHE_SECONDS * 1_000,
  };
  return keys;
}

async function getGithubSigningKey(kid) {
  let keys = await fetchGithubJwks(false);
  let jwk = keys.find((candidate) => candidate.kid === kid);

  if (!jwk) {
    keys = await fetchGithubJwks(true);
    jwk = keys.find((candidate) => candidate.kid === kid);
  }

  if (!jwk) {
    throw new OidcValidationError("jwt_kid_not_recognized");
  }

  try {
    return await crypto.subtle.importKey(
      "jwk",
      jwk,
      {
        name: "RSASSA-PKCS1-v1_5",
        hash: "SHA-256",
      },
      false,
      ["verify"],
    );
  } catch (error) {
    throw new OidcUnavailableError("github_jwk_import_failed", error);
  }
}

async function verifyGithubOidc(token, env) {
  if (!token || token.length > MAX_OIDC_TOKEN_CHARS) {
    throw new OidcValidationError("jwt_size_invalid");
  }

  const segments = token.split(".");
  if (segments.length !== 3 || segments.some((segment) => !segment)) {
    throw new OidcValidationError("jwt_compact_format_invalid");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  const header = decodeJwtJson(encodedHeader, "header");
  const claims = decodeJwtJson(encodedPayload, "payload");

  if (header.alg !== GITHUB_OIDC_ALGORITHM) {
    throw new OidcValidationError("jwt_algorithm_not_allowed");
  }
  if (header.typ !== "JWT") {
    throw new OidcValidationError("jwt_type_not_allowed");
  }
  if (typeof header.kid !== "string" || !header.kid) {
    throw new OidcValidationError("jwt_kid_missing");
  }

  const signingKey = await getGithubSigningKey(header.kid);
  const signature = base64UrlToBytes(encodedSignature);
  const signingInput = textEncoder.encode(`${encodedHeader}.${encodedPayload}`);

  const signatureValid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    signingKey,
    signature,
    signingInput,
  );
  if (!signatureValid) {
    throw new OidcValidationError("jwt_signature_invalid");
  }

  const expectedAudience = requireConfiguredValue(
    env,
    "GITHUB_OIDC_AUDIENCE",
  );
  const leeway = Number(env.JWT_LEEWAY_SECONDS ?? "30");
  if (!Number.isSafeInteger(leeway) || leeway < 0 || leeway > 120) {
    throw new OidcUnavailableError("invalid_worker_config_JWT_LEEWAY_SECONDS");
  }

  if (claims.iss !== GITHUB_OIDC_ISSUER) {
    throw new OidcValidationError("claim_iss_not_allowed");
  }
  if (!audienceContains(claims.aud, expectedAudience)) {
    throw new OidcValidationError("claim_aud_not_allowed");
  }

  const now = Math.floor(Date.now() / 1_000);
  const exp = requireNumericDate(claims, "exp");
  const iat = requireNumericDate(claims, "iat");
  const nbf = requireNumericDate(claims, "nbf");
  if (exp < now - leeway) {
    throw new OidcValidationError("jwt_expired");
  }
  if (nbf > now + leeway) {
    throw new OidcValidationError("jwt_not_yet_valid");
  }
  if (iat > now + leeway || exp <= iat) {
    throw new OidcValidationError("jwt_time_window_invalid");
  }

  requireStringClaim(claims, "jti");
  const repository = requireStringClaim(claims, "repository");
  const repositoryId = requireStringClaim(claims, "repository_id");
  const repositoryOwnerId = requireStringClaim(
    claims,
    "repository_owner_id",
  );
  const ref = requireStringClaim(claims, "ref");
  const sha = requireStringClaim(claims, "sha");
  const runId = requireStringClaim(claims, "run_id");
  const runAttempt = requireStringClaim(claims, "run_attempt");
  const eventName = requireStringClaim(claims, "event_name");
  const workflowRef = requireStringClaim(claims, "workflow_ref");
  const workflowSha = requireStringClaim(claims, "workflow_sha");
  const jobWorkflowRef = requireStringClaim(claims, "job_workflow_ref");
  const jobWorkflowSha = requireStringClaim(claims, "job_workflow_sha");
  const runnerEnvironment = requireStringClaim(
    claims,
    "runner_environment",
  );

  if (!/^[0-9a-f]{40}$/.test(sha) || !/^[0-9a-f]{40}$/.test(workflowSha)) {
    throw new OidcValidationError("claim_sha_invalid");
  }
  if (!/^\d+$/.test(runId) || !/^\d+$/.test(runAttempt)) {
    throw new OidcValidationError("claim_run_identity_invalid");
  }

  const expectedClaims = {
    repository: requireConfiguredValue(env, "ALLOWED_REPOSITORY"),
    repository_id: requireConfiguredValue(env, "ALLOWED_REPOSITORY_ID"),
    repository_owner_id: requireConfiguredValue(
      env,
      "ALLOWED_REPOSITORY_OWNER_ID",
    ),
    ref: requireConfiguredValue(env, "ALLOWED_REF"),
    workflow_ref: requireConfiguredValue(
      env,
      "ALLOWED_CALLER_WORKFLOW_REF",
    ),
    job_workflow_ref: requireConfiguredValue(
      env,
      "ALLOWED_JOB_WORKFLOW_REF",
    ),
    job_workflow_sha: requireConfiguredValue(
      env,
      "ALLOWED_JOB_WORKFLOW_SHA",
    ),
    runner_environment: "github-hosted",
  };

  const actualClaims = {
    repository,
    repository_id: repositoryId,
    repository_owner_id: repositoryOwnerId,
    ref,
    workflow_ref: workflowRef,
    job_workflow_ref: jobWorkflowRef,
    job_workflow_sha: jobWorkflowSha,
    runner_environment: runnerEnvironment,
  };

  for (const [name, expected] of Object.entries(expectedClaims)) {
    if (actualClaims[name] !== expected) {
      throw new OidcValidationError(`claim_${name}_not_allowed`);
    }
  }

  const allowedEvents = new Set(
    requireConfiguredValue(env, "ALLOWED_EVENTS")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
  if (!allowedEvents.has(eventName)) {
    throw new OidcValidationError("claim_event_name_not_allowed");
  }

  return {
    repository,
    repositoryId,
    repositoryOwnerId,
    ref,
    sha,
    runId,
    runAttempt,
    eventName,
    workflowRef,
    workflowSha,
    jobWorkflowRef,
    jobWorkflowSha,
    runnerEnvironment,
  };
}

async function readLimitedBody(stream, limit) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks = [];
  let size = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel("request body too large");
        throw new RangeError("request body too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

async function handleReadiness(request, env) {
  if (request.method !== "GET") {
    return jsonResponse(405, { detail: "Method not allowed" }, { allow: "GET" });
  }

  if (!env.BACKUP_HEALTH_TOKEN || !env.BACKUP_GATEWAY_TOKEN) {
    return jsonResponse(503, { detail: "Gateway not configured" });
  }

  const suppliedAuthorization = request.headers.get("authorization") || "";
  const expectedAuthorization = `Bearer ${env.BACKUP_HEALTH_TOKEN}`;
  if (!(await secureEqual(suppliedAuthorization, expectedAuthorization))) {
    return jsonResponse(401, { detail: "Unauthorized" });
  }

  const requestId = crypto.randomUUID();

  try {
    if (env.READY_RATE_LIMITER) {
      const { success } = await env.READY_RATE_LIMITER.limit({
        key: "backup-readyz",
      });
      if (!success) {
        return jsonResponse(
          429,
          { detail: "Too many requests" },
          { "retry-after": "60", "x-request-id": requestId },
        );
      }
    }

    const upstream = await env.BACKUP_SIGNER.fetch(
      "http://camino-backup-signer.flycast/readyz",
      {
        method: "GET",
        headers: {
          "x-backup-gateway-token": env.BACKUP_GATEWAY_TOKEN,
          "x-request-id": requestId,
        },
        redirect: "manual",
      },
    );

    if (!upstream.ok) {
      console.warn("readyz_upstream_not_ready", {
        requestId,
        status: upstream.status,
      });
      return jsonResponse(
        503,
        { detail: "Service unavailable" },
        { "x-request-id": requestId },
      );
    }

    return jsonResponse(
      200,
      { status: "ready", service: "backup-gateway" },
      { "x-request-id": requestId },
    );
  } catch (error) {
    console.error("readyz_exception", {
      requestId,
      message: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });
    return jsonResponse(
      503,
      { detail: "Service unavailable" },
      { "x-request-id": requestId },
    );
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/healthz" && request.method === "GET") {
      return jsonResponse(200, { status: "ok", service: "backup-gateway" });
    }

    if (url.pathname === READY_PATH) {
      return handleReadiness(request, env);
    }

    if (url.pathname !== SIGN_PATH) {
      return jsonResponse(404, { detail: "Not found" });
    }
    if (request.method !== "POST") {
      return jsonResponse(405, { detail: "Method not allowed" }, { allow: "POST" });
    }

    const clientKey = request.headers.get("cf-connecting-ip") || "unknown";
    const edgeLimit = await env.EDGE_RATE_LIMITER.limit({ key: clientKey });
    if (!edgeLimit.success) {
      return jsonResponse(429, { detail: "Too many requests" }, { "retry-after": "60" });
    }

    const authorization = request.headers.get("authorization") || "";
    const bearerMatch = /^Bearer\s+(\S+)$/i.exec(authorization);
    if (!bearerMatch) {
      return jsonResponse(401, { detail: "Bearer token requerido" });
    }

    const oidcToken = bearerMatch[1];
    const tokenHash = hex(
      await crypto.subtle.digest("SHA-256", textEncoder.encode(oidcToken)),
    );
    const tokenLimit = await env.TOKEN_RATE_LIMITER.limit({ key: tokenHash });
    if (!tokenLimit.success) {
      return jsonResponse(429, { detail: "Too many requests" }, { "retry-after": "60" });
    }

    const requestId = crypto.randomUUID();
    try {
      await verifyGithubOidc(oidcToken, env);
    } catch (error) {
      if (error instanceof OidcUnavailableError) {
        console.error("github_oidc_verifier_unavailable", {
          requestId,
          code: error.code,
          ...errorCauseDetails(error),
        });
        return jsonResponse(
          503,
          { detail: "OIDC verifier unavailable" },
          {
            "x-request-id": requestId,
            "x-auth-layer": "cloudflare-worker",
          },
        );
      }

      console.warn("github_oidc_rejected", {
        requestId,
        code: error instanceof OidcValidationError
          ? error.code
          : "unexpected_validation_error",
      });
      return jsonResponse(
        403,
        { detail: "Identidad OIDC no autorizada" },
        {
          "x-request-id": requestId,
          "x-auth-layer": "cloudflare-worker",
        },
      );
    }

    const contentType = request.headers.get("content-type") || "";
    if (!contentType.toLowerCase().startsWith("application/json")) {
      return jsonResponse(415, { detail: "Content-Type debe ser application/json" });
    }

    const rawLength = request.headers.get("content-length");
    if (rawLength !== null) {
      const length = Number(rawLength);
      if (!Number.isSafeInteger(length) || length < 0) {
        return jsonResponse(400, { detail: "Content-Length no válido" });
      }
      if (length > MAX_REQUEST_BYTES) {
        return jsonResponse(413, { detail: "Solicitud demasiado grande" });
      }
    }

    let body;
    try {
      body = await readLimitedBody(request.body, MAX_REQUEST_BYTES);
    } catch (error) {
      if (error instanceof RangeError) {
        return jsonResponse(413, { detail: "Solicitud demasiado grande" });
      }
      return jsonResponse(400, { detail: "No se pudo leer la solicitud" });
    }

    const originLimit = await env.ORIGIN_RATE_LIMITER.limit({ key: "v1-sign" });
    if (!originLimit.success) {
      return jsonResponse(429, { detail: "Signer temporarily rate limited" }, { "retry-after": "60" });
    }

    if (!env.BACKUP_GATEWAY_TOKEN) {
      return jsonResponse(503, { detail: "Gateway not configured" });
    }

    const upstreamHeaders = new Headers({
      authorization: `Bearer ${oidcToken}`,
      "content-type": "application/json",
      "x-backup-gateway-token": env.BACKUP_GATEWAY_TOKEN,
      "x-request-id": requestId,
    });

    let upstream;
    try {
      upstream = await env.BACKUP_SIGNER.fetch(
        "http://camino-backup-signer.flycast/v1/sign",
        {
          method: "POST",
          headers: upstreamHeaders,
          body,
          redirect: "manual",
        },
      );
    } catch (error) {
      console.error("signer_upstream_exception", {
        requestId,
        message: error instanceof Error ? error.message : String(error),
      });
      return jsonResponse(503, { detail: "Signer unavailable" }, { "x-request-id": requestId });
    }

    const responseHeaders = new Headers({
      "cache-control": "no-store",
      "content-type": upstream.headers.get("content-type") || "application/json",
      "x-request-id": requestId,
    });
    return new Response(upstream.body, {
      status: upstream.status,
      headers: responseHeaders,
    });
  },
};
