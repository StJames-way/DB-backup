const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
}

function jsonResponse(body: unknown, status = 200, extraHeaders: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...extraHeaders },
  })
}

function requireEnv(name: string): string {
  const value = (Deno.env.get(name) ?? "").trim()
  if (!value) throw new Error(`${name} is not configured`)
  return value
}

function getDateParts(timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date())
  const out: Record<string, string> = {}
  for (const part of parts) if (part.type !== "literal") out[part.type] = part.value
  return { date: `${out.year}-${out.month}-${out.day}`, hour: out.hour }
}

function timingSafeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder()
  const a = encoder.encode(left)
  const b = encoder.encode(right)
  if (a.length !== b.length) return false
  let mismatch = 0
  for (let i = 0; i < a.length; i += 1) mismatch |= a[i] ^ b[i]
  return mismatch === 0
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("")
}

function isNativeAgeRecipient(value: string): boolean {
  return /^age1[0-9a-z]{20,}$/i.test(value)
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405, { Allow: "POST" })
  }

  try {
    const expectedSecret = requireEnv("BACKUP_TRIGGER_SECRET")
    const receivedSecret = req.headers.get("x-backup-trigger-secret") ?? ""
    if (!timingSafeEqual(expectedSecret, receivedSecret)) {
      return jsonResponse({ error: "Unauthorized" }, 401)
    }

    const githubToken = requireEnv("GITHUB_TOKEN")
    const githubRepo = requireEnv("GITHUB_BACKUP_REPO")
    const eventType = requireEnv("GITHUB_BACKUP_EVENT_TYPE")
    const ageRecipient = requireEnv("BACKUP_AGE_RECIPIENT")
    const dispatchSource = requireEnv("BACKUP_DISPATCH_SOURCE")
    const backupPolicy = requireEnv("BACKUP_POLICY")
    const backupFormatVersion = Number.parseInt(requireEnv("BACKUP_FORMAT_VERSION"), 10)
    const timeZone = requireEnv("BACKUP_TIMEZONE")
    const scheduleHour = requireEnv("BACKUP_SCHEDULE_HOUR").padStart(2, "0")

    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(githubRepo)) {
      throw new Error("GITHUB_BACKUP_REPO is invalid")
    }
    if (!/^[A-Za-z0-9_.-]+$/.test(eventType)) throw new Error("GITHUB_BACKUP_EVENT_TYPE is invalid")
    if (!Number.isSafeInteger(backupFormatVersion) || backupFormatVersion < 1) {
      throw new Error("BACKUP_FORMAT_VERSION is invalid")
    }
    if (!/^([01][0-9]|2[0-3])$/.test(scheduleHour)) {
      throw new Error("BACKUP_SCHEDULE_HOUR is invalid")
    }
    if (!isNativeAgeRecipient(ageRecipient)) throw new Error("BACKUP_AGE_RECIPIENT is invalid")

    const url = new URL(req.url)
    const force = url.searchParams.get("force") === "1"
    const local = getDateParts(timeZone)
    if (!force && local.hour !== scheduleHour) {
      return jsonResponse({
        status: "skipped",
        reason: `Not ${scheduleHour}:00 in ${timeZone}`,
        local_date: local.date,
        local_hour: local.hour,
      })
    }

    const ageRecipientSha256 = await sha256Hex(ageRecipient)
    const response = await fetch(`https://api.github.com/repos/${githubRepo}/dispatches`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${githubToken}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
        "User-Agent": "supabase-backup-trigger",
      },
      body: JSON.stringify({
        event_type: eventType,
        client_payload: {
          source: dispatchSource,
          local_date: local.date,
          local_hour: local.hour,
          triggered_at: new Date().toISOString(),
          force,
          idempotency_key: `supabase-full-${local.date}`,
          backup_policy: backupPolicy,
          backup_format_version: backupFormatVersion,
          encryption: "age-recipient",
          age_recipient_sha256: ageRecipientSha256,
        },
      }),
    })

    if (!response.ok) {
      const errorText = await response.text()
      return jsonResponse({
        status: "GitHub dispatch failed",
        github_status: response.status,
        github_response: errorText.slice(0, 2000),
      }, 502)
    }

    return jsonResponse({
      status: "Pipeline disparado con éxito",
      local_date: local.date,
      age_recipient_sha256: ageRecipientSha256,
    })
  } catch (error) {
    console.error(error)
    return jsonResponse({ error: "Server misconfigured" }, 500)
  }
})
