const GITHUB_API_VERSION = "2026-03-10";
const EVENT_TYPE = "supabase_backup_trigger";
const BACKUP_POLICY =
  "daily_full_age_encrypted_openbao_signed_retain_last_30_verified";
const BACKUP_FORMAT_VERSION = 5;

type TriggerBody = {
  force?: boolean;
};

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`Missing required secret: ${name}`);
  }
  return value;
}

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);

  if (a.length !== b.length) return false;

  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function parseBody(request: Request): Promise<TriggerBody> {
  if (!request.body) return {};

  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    throw new TypeError("Content-Type must be application/json");
  }

  const raw = await request.text();
  if (!raw.trim()) return {};
  if (raw.length > 1024) {
    throw new RangeError("Request body is too large");
  }

  const parsed: unknown = JSON.parse(raw);
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed)
  ) {
    throw new TypeError("Request body must be a JSON object");
  }

  const keys = Object.keys(parsed);
  if (keys.some((key) => key !== "force")) {
    throw new TypeError("Unknown request field");
  }

  const force = (parsed as Record<string, unknown>).force;
  if (force !== undefined && typeof force !== "boolean") {
    throw new TypeError("force must be boolean");
  }

  return { force: force ?? false };
}

Deno.serve(async (request: Request): Promise<Response> => {
  const requestId = crypto.randomUUID();

  try {
    if (request.method !== "POST") {
      return new Response(null, {
        status: 405,
        headers: {
          allow: "POST",
          "cache-control": "no-store",
        },
      });
    }

    /*
     * Esta función está pensada para una invocación programada de confianza,
     * por ejemplo pg_cron + pg_net. No debe ser un endpoint público anónimo.
     *
     * El invocador envía:
     *   Authorization: Bearer <SUPABASE_BACKUP_TRIGGER_SECRET>
     */
    const expectedTriggerSecret = requiredEnv(
      "SUPABASE_BACKUP_TRIGGER_SECRET",
    );
    const authorization = request.headers.get("authorization") ?? "";
    const expectedAuthorization = `Bearer ${expectedTriggerSecret}`;

    if (!constantTimeEqual(authorization, expectedAuthorization)) {
      console.warn("backup_dispatch_rejected", { requestId });
      return jsonResponse(401, {
        error: "unauthorized",
        request_id: requestId,
      });
    }

    const body = await parseBody(request);

    const githubToken = requiredEnv("GITHUB_BACKUP_DISPATCH_TOKEN");
    const githubOwner = requiredEnv("GITHUB_BACKUP_REPOSITORY_OWNER");
    const githubRepository = requiredEnv("GITHUB_BACKUP_REPOSITORY");
    const ageRecipient = requiredEnv("BACKUP_AGE_RECIPIENT").replace(
      /[\r\n]/g,
      "",
    );

    if (!/^age1[0-9a-z]+$/.test(ageRecipient)) {
      throw new Error("BACKUP_AGE_RECIPIENT has an invalid format");
    }

    const ageRecipientSha256 = await sha256Hex(ageRecipient);
    const endpoint =
      `https://api.github.com/repos/${encodeURIComponent(githubOwner)}/` +
      `${encodeURIComponent(githubRepository)}/dispatches`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);

    let response: Response;
    try {
      response = await fetch(endpoint, {
        method: "POST",
        signal: controller.signal,
        headers: {
          accept: "application/vnd.github+json",
          authorization: `Bearer ${githubToken}`,
          "content-type": "application/json",
          "user-agent": "camino-seguro-supabase-backup-dispatcher",
          "x-github-api-version": GITHUB_API_VERSION,
        },
        body: JSON.stringify({
          event_type: EVENT_TYPE,
          client_payload: {
            source: "supabase-edge-function",
            backup_policy: BACKUP_POLICY,
            backup_format_version: BACKUP_FORMAT_VERSION,
            age_recipient_sha256: ageRecipientSha256,
            force: body.force ?? false,
            requested_at_utc: new Date().toISOString(),
            request_id: requestId,
          },
        }),
      });
    } finally {
      clearTimeout(timeout);
    }

    if (response.status !== 204) {
      const githubRequestId = response.headers.get("x-github-request-id");
      const responseText = (await response.text()).slice(0, 1000);

      console.error("github_repository_dispatch_failed", {
        requestId,
        githubRequestId,
        status: response.status,
        response: responseText,
      });

      return jsonResponse(502, {
        error: "github_dispatch_failed",
        github_status: response.status,
        github_request_id: githubRequestId,
        request_id: requestId,
      });
    }

    console.info("github_repository_dispatch_created", {
      requestId,
      repository: `${githubOwner}/${githubRepository}`,
      force: body.force ?? false,
    });

    return jsonResponse(202, {
      accepted: true,
      event_type: EVENT_TYPE,
      request_id: requestId,
    });
  } catch (error) {
    const name = error instanceof Error ? error.name : "UnknownError";
    const message = error instanceof Error ? error.message : "Unknown error";

    console.error("backup_dispatch_internal_error", {
      requestId,
      name,
      message,
    });

    const clientError =
      error instanceof TypeError ||
      error instanceof RangeError ||
      error instanceof SyntaxError;

    return jsonResponse(clientError ? 400 : 500, {
      error: clientError ? "invalid_request" : "internal_error",
      request_id: requestId,
    });
  }
});
