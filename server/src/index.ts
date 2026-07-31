import { PLAN_SYSTEM_PROMPT } from './plan_prompt';

/**
 * LevelUp-API.
 *
 * Steht zwischen App und Anthropic, damit der Schlüssel des Betreibers nie auf
 * ein fremdes Gerät gelangt. Sie hält drei Dinge fest, die die App nicht
 * bestimmen darf: den System-Prompt, die Antwortlänge und das Kontingent.
 *
 * Phase 1 kennt keine Anmeldung — ein Gerät registriert sich einmal und
 * bekommt ein Token. Der Platz für ein späteres Konto ist im Schema bereits
 * vorgesehen (`devices.user_id`).
 */

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-opus-5';

// --- kleine Helfer ---------------------------------------------------------

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization,content-type',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...CORS },
  });
}

function fail(message: string, status: number, code?: string): Response {
  return json({ error: { message, code } }, status);
}

/** Zufall aus der Web-Crypto — nie `Math.random()` für etwas, das schützt. */
function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Gespeichert wird nur der Hash. Wer die Datenbank liest, kann sich damit
 * nicht als fremdes Gerät ausgeben — und die Suche läuft über einen
 * Index-Treffer statt über einen Zeichenvergleich, was zeitbasierte
 * Rückschlüsse ausschließt.
 */
async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(token),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function logError(where: string, error: unknown): void {
  console.error(
    JSON.stringify({
      message: 'request failed',
      where,
      error: error instanceof Error ? error.message : String(error),
    }),
  );
}

interface DeviceRow {
  id: string;
  user_id: string | null;
}

async function authenticate(
  request: Request,
  env: Env,
): Promise<DeviceRow | null> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const tokenHash = await hashToken(header.slice(7).trim());

  const device = await env.DB.prepare(
    'SELECT id, user_id FROM devices WHERE token_hash = ?',
  )
    .bind(tokenHash)
    .first<DeviceRow>();
  if (device === null) return null;

  return device;
}

interface Quota {
  used: number;
  free: number;
  today: number;
  dailyLimit: number;
}

async function quotaFor(deviceId: string, env: Env): Promise<Quota> {
  const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
  // Fehlgeschlagene Läufe zählen nicht gegen das Kontingent — wer nichts
  // bekommen hat, soll nichts verbrauchen.
  const row = await env.DB.prepare(
    `SELECT
       COUNT(*) AS used,
       COALESCE(SUM(CASE WHEN created_at > ? THEN 1 ELSE 0 END), 0) AS today
     FROM generations
     WHERE device_id = ? AND status != 'failed'`,
  )
    .bind(dayAgo, deviceId)
    .first<{ used: number; today: number }>();

  return {
    used: row?.used ?? 0,
    free: Number(env.FREE_GENERATIONS),
    today: row?.today ?? 0,
    dailyLimit: Number(env.DAILY_LIMIT),
  };
}

// --- Endpunkte -------------------------------------------------------------

/** Einmalige Registrierung. Gibt das einzige Mal ein Token im Klartext aus. */
async function registerDevice(request: Request, env: Env): Promise<Response> {
  let platform = 'unknown';
  try {
    const body = (await request.json()) as { platform?: unknown };
    if (typeof body.platform === 'string') platform = body.platform.slice(0, 32);
  } catch {
    // Rumpf ist optional — Plattform bleibt unbekannt.
  }

  const token = randomToken();
  const id = `dev_${randomToken().slice(0, 24)}`;
  const now = Date.now();

  await env.DB.prepare(
    `INSERT INTO devices (id, token_hash, platform, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(id, await hashToken(token), platform, now, now)
    .run();

  return json({
    deviceId: id,
    token,
    freeGenerations: Number(env.FREE_GENERATIONS),
  });
}

async function me(device: DeviceRow, env: Env): Promise<Response> {
  const quota = await quotaFor(device.id, env);
  return json({
    deviceId: device.id,
    linkedAccount: device.user_id !== null,
    used: quota.used,
    remaining: Math.max(0, quota.free - quota.used),
    dailyRemaining: Math.max(0, quota.dailyLimit - quota.today),
  });
}

/**
 * Erzeugt einen Plan und reicht den Ereignisstrom von Anthropic unverändert
 * an die App durch — dadurch bleibt die Fortschrittsanzeige erhalten und der
 * Worker muss die Antwort nie im Speicher halten.
 *
 * Der Verbrauch wird nebenher aus dem durchlaufenden Strom gelesen und nach
 * dessen Ende gebucht.
 */
async function generate(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  device: DeviceRow,
): Promise<Response> {
  let prompt = '';
  try {
    const body = (await request.json()) as { request?: unknown };
    if (typeof body.request === 'string') prompt = body.request.trim();
  } catch {
    return fail('Ungültiger Rumpf.', 400, 'bad_request');
  }

  if (prompt.length === 0) {
    return fail('Beschreib, worum es gehen soll.', 400, 'empty_request');
  }
  if (prompt.length > Number(env.MAX_REQUEST_CHARS)) {
    return fail(
      `Die Beschreibung ist zu lang (max. ${env.MAX_REQUEST_CHARS} Zeichen).`,
      400,
      'request_too_long',
    );
  }

  const quota = await quotaFor(device.id, env);
  if (quota.today >= quota.dailyLimit) {
    return fail(
      'Tageslimit erreicht. Morgen geht es weiter.',
      429,
      'daily_limit',
    );
  }
  if (quota.used >= quota.free) {
    return fail(
      'Freikontingent aufgebraucht.',
      402,
      'quota_exhausted',
    );
  }

  const generationId = `gen_${randomToken().slice(0, 24)}`;
  await env.DB.prepare(
    `INSERT INTO generations (id, device_id, created_at) VALUES (?, ?, ?)`,
  )
    .bind(generationId, device.id, Date.now())
    .run();

  const upstream = await fetch(ANTHROPIC_URL, {
    method: 'POST',
    headers: {
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: Number(env.MAX_OUTPUT_TOKENS),
      stream: true,
      thinking: { type: 'adaptive', display: 'summarized' },
      // Der Prompt ist bei jedem Aufruf identisch — zwischengespeichert
      // kostet die Eingabe ab dem zweiten Lauf ein Zehntel.
      system: [
        {
          type: 'text',
          text: PLAN_SYSTEM_PROMPT,
          cache_control: { type: 'ephemeral' },
        },
      ],
      messages: [{ role: 'user', content: prompt }],
    }),
  });

  if (!upstream.ok || upstream.body === null) {
    ctx.waitUntil(
      env.DB.prepare(`UPDATE generations SET status = 'failed' WHERE id = ?`)
        .bind(generationId)
        .run()
        .then(() => undefined),
    );
    logError('anthropic', `status ${upstream.status}`);
    return fail(
      'Der Planer ist gerade nicht erreichbar. Bitte später nochmal.',
      502,
      'upstream',
    );
  }

  // Verbrauch mitlesen, ohne den Strom aufzuhalten oder zu puffern.
  const meter = new UsageMeter();
  const metered = upstream.body.pipeThrough(meter.transform());

  ctx.waitUntil(meter.finished.then((usage) => record(env, generationId, usage)));

  return new Response(metered, {
    headers: {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      ...CORS,
    },
  });
}

interface Usage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  stopReason: string | null;
}

async function record(
  env: Env,
  generationId: string,
  usage: Usage,
): Promise<void> {
  // Ein abgelehnter oder abgebrochener Lauf zählt nicht gegen das Kontingent,
  // die Token sind aber trotzdem angefallen und werden festgehalten.
  const status =
    usage.stopReason === 'end_turn' || usage.stopReason === 'max_tokens'
      ? 'done'
      : 'failed';

  try {
    await env.DB.prepare(
      `UPDATE generations
         SET input_tokens = ?, output_tokens = ?, cache_read = ?,
             cache_write = ?, status = ?, stop_reason = ?
       WHERE id = ?`,
    )
      .bind(
        usage.input,
        usage.output,
        usage.cacheRead,
        usage.cacheWrite,
        status,
        usage.stopReason,
        generationId,
      )
      .run();
  } catch (error) {
    logError('record-usage', error);
  }
}

/**
 * Liest Verbrauchszahlen aus dem vorbeifließenden SSE-Strom.
 *
 * Bewusst als Durchleitung statt als Sammlung: der Plan kann 15 kB groß sein
 * und muss die App sofort erreichen, nicht erst am Ende.
 */
class UsageMeter {
  private buffer = '';
  private usage: Usage = {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    stopReason: null,
  };

  private resolve!: (usage: Usage) => void;
  readonly finished = new Promise<Usage>((r) => {
    this.resolve = r;
  });

  transform(): TransformStream<Uint8Array, Uint8Array> {
    const decoder = new TextDecoder();
    return new TransformStream({
      transform: (chunk, controller) => {
        controller.enqueue(chunk); // zuerst weiterreichen, dann auswerten
        this.buffer += decoder.decode(chunk, { stream: true });
        const lines = this.buffer.split('\n');
        this.buffer = lines.pop() ?? '';
        for (const line of lines) this.read(line);
      },
      flush: () => {
        this.read(this.buffer);
        this.resolve(this.usage);
      },
    });
  }

  private read(line: string): void {
    if (!line.startsWith('data: ')) return;
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(line.slice(6)) as Record<string, unknown>;
    } catch {
      return; // Bruchstück oder Herzschlag
    }

    const message = event.message as Record<string, unknown> | undefined;
    this.merge(event.usage ?? message?.usage);

    const delta = event.delta as Record<string, unknown> | undefined;
    if (typeof delta?.stop_reason === 'string') {
      this.usage.stopReason = delta.stop_reason;
    }
  }

  private merge(raw: unknown): void {
    if (typeof raw !== 'object' || raw === null) return;
    const u = raw as Record<string, unknown>;
    const pick = (key: string, current: number): number =>
      typeof u[key] === 'number' ? (u[key] as number) : current;

    this.usage.input = pick('input_tokens', this.usage.input);
    this.usage.output = pick('output_tokens', this.usage.output);
    this.usage.cacheRead = pick('cache_read_input_tokens', this.usage.cacheRead);
    this.usage.cacheWrite = pick(
      'cache_creation_input_tokens',
      this.usage.cacheWrite,
    );
  }
}

// --- Einstieg --------------------------------------------------------------

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    try {
      if (url.pathname === '/v1/devices' && request.method === 'POST') {
        return await registerDevice(request, env);
      }

      const needsAuth =
        url.pathname === '/v1/me' || url.pathname === '/v1/generate';
      if (needsAuth) {
        const device = await authenticate(request, env);
        if (device === null) {
          return fail('Nicht angemeldet.', 401, 'unauthenticated');
        }

        if (url.pathname === '/v1/me') return await me(device, env);
        if (request.method !== 'POST') {
          return fail('Nur POST.', 405, 'method_not_allowed');
        }
        return await generate(request, env, ctx, device);
      }

      return fail('Unbekannter Endpunkt.', 404, 'not_found');
    } catch (error) {
      logError(url.pathname, error);
      return fail('Unerwarteter Fehler.', 500, 'internal');
    }
  },
} satisfies ExportedHandler<Env>;
