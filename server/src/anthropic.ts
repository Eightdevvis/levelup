import type { Melder } from './ereignisse';
import type { Ergebnis } from './pruefen';

/**
 * Ein KI-Aufruf: System-Prompt und Nutzernachricht rein, geprüftes Objekt raus.
 *
 * Der Vorgänger (`agent.ts`) führte ein Gespräch mit Werkzeugen und ließ das
 * Modell selbst entscheiden, wann es sucht und wann es schreibt. Das ist die
 * Stelle, an der die Wiederverwendung unzuverlässig wurde. Jetzt hat jeder
 * Aufruf genau eine Aufgabe und ein festes Ausgabeformat; gesucht wird im Code.
 *
 * Nachgebessert wird höchstens zweimal, mit der Fehlerliste als Folgenachricht.
 * Danach bricht der Lauf ab — ungeprüftes JSON wandert nirgendwohin.
 */

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';

/** Zwei Nachbesserungen. Wer dreimal dieselbe Regel bricht, bricht sie auch
 *  beim vierten Mal, und jede Runde kostet den Betreiber Token. */
const MAX_NACHBESSERUNGEN = 2;

export interface Verbrauch {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}

export function leererVerbrauch(): Verbrauch {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
}

export function addiere(ziel: Verbrauch, dazu: Verbrauch): void {
  ziel.input += dazu.input;
  ziel.output += dazu.output;
  ziel.cacheRead += dazu.cacheRead;
  ziel.cacheWrite += dazu.cacheWrite;
}

/** Fehler stromaufwärts — Netz, Kontingent bei Anthropic, kaputte Antwort. */
export class UpstreamError extends Error {}

/** Die KI hat auch nach den Nachbesserungen nichts Gültiges geliefert. */
export class SchemaError extends Error {
  constructor(readonly probleme: string[]) {
    super(`Ausgabe hielt der Prüfung nicht stand: ${probleme.join('; ')}`);
  }
}

export interface Auftrag<T> {
  /** Aufgabe, Regeln, Ausgabeformat. Fest pro Schritt, deshalb cachebar. */
  system: string;
  /** Nutzereingabe bzw. JSON aus dem vorherigen Schritt — getaggt (§4a). */
  nachricht: string;
  modell: string;
  maxTokens: number;
  /** Prüft und baut das Ergebnis neu auf. Nur was hier herauskommt, reist weiter. */
  pruefe: (roh: unknown) => Ergebnis<T>;
  melde?: Melder;
  /** Ob Denkereignisse nach außen gehen. Beim Kurator nicht: fünfzehn
   *  Gedankengänge hintereinander sind kein Fortschritt, sondern Flackern. */
  zeigeGedanken?: boolean;
}

export interface Antwort<T> {
  wert: T;
  verbrauch: Verbrauch;
}

export async function frage<T>(env: Env, auftrag: Auftrag<T>): Promise<Antwort<T>> {
  const verbrauch = leererVerbrauch();
  const messages: unknown[] = [{ role: 'user', content: auftrag.nachricht }];
  let letzteProbleme: string[] = ['keine Antwort'];

  for (let versuch = 0; versuch <= MAX_NACHBESSERUNGEN; versuch++) {
    const durchlauf = await einDurchlauf(env, auftrag, messages, verbrauch);

    const roh = schneideJson(durchlauf.text);
    const geprueft: Ergebnis<T> =
      roh === null
        ? { ok: false, fehler: ['Die Antwort enthielt kein lesbares JSON-Objekt.'] }
        : auftrag.pruefe(roh);

    if (geprueft.ok) return { wert: geprueft.wert, verbrauch };

    letzteProbleme = geprueft.fehler;
    if (versuch === MAX_NACHBESSERUNGEN) break;

    auftrag.melde?.({ type: 'repair', problems: geprueft.fehler.length });
    // Der eigene Text kommt zurück, damit das Modell nicht von vorn anfängt —
    // ohne die Denkblöcke, die ohne Werkzeuggebrauch nicht zurückmüssen und
    // beim Nachbessern nur die Eingabe aufblähen.
    messages.push({ role: 'assistant', content: [{ type: 'text', text: durchlauf.text }] });
    messages.push({
      role: 'user',
      content:
        'Deine Ausgabe hielt der Prüfung nicht stand:\n\n' +
        geprueft.fehler.map((f) => `- ${f}`).join('\n') +
        '\n\nGib das vollständige JSON noch einmal aus, mit genau diesen ' +
        'Punkten behoben. Ändere sonst nichts. Antworte nur mit dem JSON.',
    });
  }

  throw new SchemaError(letzteProbleme);
}

// --- Ein einzelner Durchlauf ----------------------------------------------

interface Durchlauf {
  text: string;
  stopReason: string | null;
}

async function einDurchlauf<T>(
  env: Env,
  auftrag: Auftrag<T>,
  messages: unknown[],
  verbrauch: Verbrauch,
): Promise<Durchlauf> {
  const response = await fetch(ANTHROPIC_URL, {
    method: 'POST',
    headers: {
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: auftrag.modell,
      max_tokens: auftrag.maxTokens,
      // Ohne Strom läuft ein langer Aufruf in den Zeitablauf der Verbindung.
      stream: true,
      thinking: { type: 'adaptive', display: 'summarized' },
      // Gleicher System-Prompt bei jedem Aufruf desselben Schritts — im
      // Zwischenspeicher kostet er ab dem zweiten Lauf einen Bruchteil.
      system: [{ type: 'text', text: auftrag.system, cache_control: { type: 'ephemeral' } }],
      messages,
    }),
  });

  if (!response.ok || response.body === null) {
    const detail = await response.text().catch(() => '');
    throw new UpstreamError(`status ${response.status}: ${detail.slice(0, 300)}`);
  }

  return lies(response.body, verbrauch, auftrag);
}

/**
 * Liest den SSE-Strom.
 *
 * Der Text wird gesammelt, nicht durchgereicht: er ist am Ende ein
 * JSON-Dokument, das hier geprüft wird, bevor die App es sieht. Nach außen
 * geht nur die Länge — genug für einen Fortschrittsbalken.
 */
async function lies<T>(
  body: ReadableStream<Uint8Array>,
  verbrauch: Verbrauch,
  auftrag: Auftrag<T>,
): Promise<Durchlauf> {
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = '';
  let text = '';
  let gedanken = '';
  let zuletztGemeldet = 0;
  let stopReason: string | null = null;

  const zeile = (roh: string): void => {
    if (!roh.startsWith('data: ')) return;
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(roh.slice(6)) as Record<string, unknown>;
    } catch {
      return; // Herzschlag oder Bruchstück
    }

    switch (event.type) {
      case 'message_start': {
        const message = event.message as Record<string, unknown> | undefined;
        mergeVerbrauch(verbrauch, message?.usage);
        break;
      }
      case 'content_block_delta': {
        const delta = event.delta as Record<string, unknown> | undefined;
        if (delta?.type === 'text_delta') {
          text += String(delta.text ?? '');
          // Nicht bei jedem Häppchen melden — das wären hunderte Ereignisse.
          if (text.length - zuletztGemeldet >= 400) {
            zuletztGemeldet = text.length;
            auftrag.melde?.({ type: 'writing', chars: text.length });
          }
        } else if (delta?.type === 'thinking_delta') {
          gedanken += String(delta.thinking ?? '');
          if (auftrag.zeigeGedanken !== false) {
            auftrag.melde?.({ type: 'thinking', text: letzterSatz(gedanken) });
          }
        }
        break;
      }
      case 'message_delta': {
        const delta = event.delta as Record<string, unknown> | undefined;
        if (typeof delta?.stop_reason === 'string') stopReason = delta.stop_reason;
        mergeVerbrauch(verbrauch, event.usage);
        break;
      }
      case 'error': {
        const fehler = event.error as Record<string, unknown> | undefined;
        throw new UpstreamError(String(fehler?.message ?? 'Fehler im Strom'));
      }
    }
  };

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += value;
    const zeilen = buffer.split('\n');
    buffer = zeilen.pop() ?? '';
    for (const z of zeilen) zeile(z);
  }
  zeile(buffer);

  if (stopReason === 'max_tokens') {
    throw new UpstreamError('Die Antwort wurde von der Längengrenze abgeschnitten.');
  }
  return { text, stopReason };
}

function mergeVerbrauch(verbrauch: Verbrauch, roh: unknown): void {
  if (typeof roh !== 'object' || roh === null) return;
  const u = roh as Record<string, number>;
  verbrauch.input += typeof u.input_tokens === 'number' ? u.input_tokens : 0;
  verbrauch.output += typeof u.output_tokens === 'number' ? u.output_tokens : 0;
  verbrauch.cacheRead += typeof u.cache_read_input_tokens === 'number' ? u.cache_read_input_tokens : 0;
  verbrauch.cacheWrite +=
    typeof u.cache_creation_input_tokens === 'number' ? u.cache_creation_input_tokens : 0;
}

function letzterSatz(gedanken: string): string {
  const getrimmt = gedanken.trimEnd();
  if (getrimmt.length === 0) return '';
  const schnitt = getrimmt.search(/[.!?]\s[^.!?]*$/);
  return (schnitt === -1 ? getrimmt : getrimmt.slice(schnitt + 1)).trim();
}

/**
 * Schneidet das JSON-Objekt aus dem Antworttext.
 *
 * Modelle rahmen es gern mit einem Satz oder einem Codeblock ein, und ein
 * Neuversuch deswegen wäre die teuerste Art, eine Klammer zu suchen.
 */
export function schneideJson(text: string): unknown {
  const start = text.indexOf('{');
  const ende = text.lastIndexOf('}');
  if (start === -1 || ende <= start) return null;
  try {
    return JSON.parse(text.slice(start, ende + 1)) as unknown;
  } catch {
    return null;
  }
}
