import {
  loadProgram,
  searchExercises,
  searchPrograms,
  type ExerciseHit,
  type ProgramHit,
} from './pool';

/**
 * Die Schleife, in der der Plan entsteht.
 *
 * Früher reichte der Worker den Strom von Anthropic unverändert durch. Das geht
 * nicht mehr: das Modell darf jetzt im Pool suchen, und dafür muss jemand die
 * Werkzeugaufrufe ausführen und das Gespräch fortsetzen. Also übersetzt der
 * Worker den Strom in ein eigenes, viel kleineres Protokoll.
 *
 * Das ist kein Verlust, sondern ein Gewinn: die App muss Anthropics
 * Ereignisformat nicht mehr kennen, und ungültige Antworten fallen hier auf,
 * nicht erst auf dem Gerät.
 */

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-opus-5';

/** Notbremse. Mehr als eine Handvoll Suchrunden braucht kein Plan. */
const MAX_TURNS = 8;

export interface Usage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  stopReason: string | null;
}

export type AgentEvent =
  | { type: 'thinking'; text: string }
  | { type: 'search'; tool: string; terms: string[]; hits: number }
  | { type: 'writing'; chars: number }
  | { type: 'reuse'; ids: string[] }
  | { type: 'done'; text: string }
  | { type: 'error'; message: string; code: string };

// --- Werkzeuge -------------------------------------------------------------

/**
 * Was das Modell im Pool darf.
 *
 * Bewusst nur lesend. Geschrieben wird erst, wenn ein Mensch den Plan annimmt —
 * sonst füllt sich der Pool mit Entwürfen, die niemand wollte.
 */
export const TOOLS = [
  {
    name: 'uebungen_suchen',
    description:
      'Sucht im geteilten Pool nach vorhandenen Übungen. Nutze das, sobald du ' +
      'weißt, welche Art von Übung du brauchst — vorhandene Bausteine sind ' +
      'erprobt und dem Nutzer teils schon bekannt. Suche mehrfach mit ' +
      'unterschiedlichen Formulierungen, deutsche Wörter treffen nicht immer ' +
      'auf Anhieb.',
    input_schema: {
      type: 'object',
      properties: {
        stichworte: {
          type: 'array',
          items: { type: 'string' },
          description:
            'Einzelne Wörter oder kurze Wortstämme, keine ganzen Sätze. ' +
            'Beispiel: ["blattlesen", "notation", "rhythmus"].',
        },
      },
      required: ['stichworte'],
    },
  },
  {
    name: 'plaene_suchen',
    description:
      'Sucht nach vollständigen Plänen, die andere für ein ähnliches Anliegen ' +
      'angenommen haben. Wenn einer wirklich passt, lade ihn und pass ihn an, ' +
      'statt bei null anzufangen.',
    input_schema: {
      type: 'object',
      properties: {
        stichworte: {
          type: 'array',
          items: { type: 'string' },
          description: 'Einzelne Wörter, keine Sätze.',
        },
      },
      required: ['stichworte'],
    },
  },
  {
    name: 'plan_laden',
    description:
      'Lädt einen Plan aus der Trefferliste vollständig, mit allen Übungen ' +
      'und Listen. Danach kannst du ihn übernehmen und auf das Anliegen ' +
      'zuschneiden.',
    input_schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Die Kennung aus der Trefferliste.' },
      },
      required: ['id'],
    },
  },
] as const;

interface ToolOutcome {
  result: unknown;
  event: AgentEvent;
  reused: string[];
}

function termsOf(input: Record<string, unknown>): string[] {
  const raw = input.stichworte;
  return Array.isArray(raw) ? raw.filter((t): t is string => typeof t === 'string') : [];
}

async function runTool(
  env: Env,
  name: string,
  input: Record<string, unknown>,
): Promise<ToolOutcome> {
  switch (name) {
    case 'uebungen_suchen': {
      const hits: ExerciseHit[] = await searchExercises(env, input.stichworte);
      return {
        result: hits.length === 0 ? { treffer: [], hinweis: 'Nichts gefunden — erfinde die Übung selbst.' } : { treffer: hits },
        event: { type: 'search', tool: 'uebungen', terms: termsOf(input), hits: hits.length },
        reused: [],
      };
    }
    case 'plaene_suchen': {
      const hits: ProgramHit[] = await searchPrograms(env, input.stichworte);
      return {
        result: hits.length === 0 ? { treffer: [], hinweis: 'Nichts gefunden — bau den Plan selbst.' } : { treffer: hits },
        event: { type: 'search', tool: 'plaene', terms: termsOf(input), hits: hits.length },
        reused: [],
      };
    }
    case 'plan_laden': {
      const bundle = await loadProgram(env, input.id);
      const id = typeof input.id === 'string' ? input.id : '?';
      return {
        result: bundle ?? { fehler: 'Kein Plan mit dieser Kennung.' },
        event: { type: 'search', tool: 'plan_laden', terms: [id], hits: bundle === null ? 0 : 1 },
        reused: bundle === null ? [] : [id],
      };
    }
    default:
      return {
        result: { fehler: `Unbekanntes Werkzeug: ${name}` },
        event: { type: 'search', tool: name, terms: [], hits: 0 },
        reused: [],
      };
  }
}

// --- Strom lesen -----------------------------------------------------------

interface Block {
  type: string;
  text: string;
  /** Nur bei `thinking`: muss unverändert zurückgereicht werden. */
  signature: string;
  /** Nur bei `tool_use`. */
  id: string;
  name: string;
  json: string;
  /** Nur bei `redacted_thinking`. */
  raw: unknown;
}

function emptyBlock(): Block {
  return { type: '', text: '', signature: '', id: '', name: '', json: '', raw: null };
}

/**
 * Ein durchgelaufener Zug: was das Modell gesagt hat und ob es weitermachen
 * will.
 */
interface Turn {
  content: unknown[];
  toolCalls: { id: string; name: string; input: Record<string, unknown> }[];
  text: string;
  stopReason: string | null;
}

/**
 * Liest den SSE-Strom eines Zuges und meldet den Fortschritt unterwegs.
 *
 * Der Text wird gesammelt statt durchgereicht — er ist am Ende ein
 * JSON-Dokument, das der Worker prüfen muss, bevor die App es sieht. Was die
 * App währenddessen bekommt, ist die Länge: genug für einen Fortschrittsbalken,
 * ohne halbfertiges JSON zu verschicken.
 */
async function readTurn(
  body: ReadableStream<Uint8Array>,
  usage: Usage,
  emit: (event: AgentEvent) => void,
  charsBefore: number,
): Promise<Turn> {
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  const blocks: Block[] = [];
  let buffer = '';
  let stopReason: string | null = null;
  let thinking = '';
  let lastReported = 0;

  const handle = (line: string): void => {
    if (!line.startsWith('data: ')) return;
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(line.slice(6)) as Record<string, unknown>;
    } catch {
      return;
    }

    const index = typeof event.index === 'number' ? event.index : 0;

    switch (event.type) {
      case 'message_start': {
        const message = event.message as Record<string, unknown> | undefined;
        mergeUsage(usage, message?.usage);
        break;
      }
      case 'content_block_start': {
        const start = event.content_block as Record<string, unknown> | undefined;
        const block = emptyBlock();
        block.type = typeof start?.type === 'string' ? start.type : '';
        if (block.type === 'tool_use') {
          block.id = String(start?.id ?? '');
          block.name = String(start?.name ?? '');
        }
        if (block.type === 'redacted_thinking') block.raw = start;
        blocks[index] = block;
        break;
      }
      case 'content_block_delta': {
        const delta = event.delta as Record<string, unknown> | undefined;
        const block = blocks[index] ?? (blocks[index] = emptyBlock());
        switch (delta?.type) {
          case 'text_delta':
            block.text += String(delta.text ?? '');
            // Nicht bei jedem Häppchen melden — das wären hunderte Ereignisse.
            if (block.text.length - lastReported >= 400) {
              lastReported = block.text.length;
              emit({ type: 'writing', chars: charsBefore + block.text.length });
            }
            break;
          case 'thinking_delta':
            block.text += String(delta.thinking ?? '');
            thinking += String(delta.thinking ?? '');
            emit({ type: 'thinking', text: lastSentence(thinking) });
            break;
          case 'signature_delta':
            block.signature += String(delta.signature ?? '');
            break;
          case 'input_json_delta':
            block.json += String(delta.partial_json ?? '');
            break;
        }
        break;
      }
      case 'message_delta': {
        const delta = event.delta as Record<string, unknown> | undefined;
        if (typeof delta?.stop_reason === 'string') stopReason = delta.stop_reason;
        mergeUsage(usage, event.usage);
        break;
      }
    }
  };

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += value;
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';
    for (const line of lines) handle(line);
  }
  handle(buffer);

  // Zurück in das Format, das Anthropic im nächsten Zug erwartet. Die
  // Denkblöcke müssen mitsamt Signatur unverändert zurück, sonst lehnt die API
  // die Fortsetzung ab.
  const content: unknown[] = [];
  const toolCalls: Turn['toolCalls'] = [];
  let text = '';

  for (const block of blocks) {
    if (block === undefined) continue;
    switch (block.type) {
      case 'thinking':
        content.push({ type: 'thinking', thinking: block.text, signature: block.signature });
        break;
      case 'redacted_thinking':
        content.push(block.raw);
        break;
      case 'text':
        content.push({ type: 'text', text: block.text });
        text += block.text;
        break;
      case 'tool_use': {
        let input: Record<string, unknown> = {};
        try {
          input = block.json.length > 0 ? (JSON.parse(block.json) as Record<string, unknown>) : {};
        } catch {
          // Unvollständiges Werkzeug-Argument: leer weitergeben, das Werkzeug
          // meldet dann selbst, dass nichts gefunden wurde.
        }
        content.push({ type: 'tool_use', id: block.id, name: block.name, input });
        toolCalls.push({ id: block.id, name: block.name, input });
        break;
      }
    }
  }

  return { content, toolCalls, text, stopReason };
}

function mergeUsage(usage: Usage, raw: unknown): void {
  if (typeof raw !== 'object' || raw === null) return;
  const u = raw as Record<string, number>;
  // Eingabe und Zwischenspeicher werden je Zug neu gemeldet und summiert;
  // die Ausgabe ebenso.
  usage.input += typeof u.input_tokens === 'number' ? u.input_tokens : 0;
  usage.output += typeof u.output_tokens === 'number' ? u.output_tokens : 0;
  usage.cacheRead += typeof u.cache_read_input_tokens === 'number' ? u.cache_read_input_tokens : 0;
  usage.cacheWrite +=
    typeof u.cache_creation_input_tokens === 'number' ? u.cache_creation_input_tokens : 0;
}

function lastSentence(thinking: string): string {
  const trimmed = thinking.trimEnd();
  if (trimmed.length === 0) return '';
  const cut = trimmed.search(/[.!?]\s[^.!?]*$/);
  return (cut === -1 ? trimmed : trimmed.slice(cut + 1)).trim();
}

// --- Die Schleife ----------------------------------------------------------

export interface AgentRun {
  /** Der zusammengesetzte Text des letzten Zuges — das JSON-Dokument. */
  text: string;
  stopReason: string | null;
  usage: Usage;
  /** Kennungen, die aus dem Pool übernommen wurden. */
  reused: string[];
}

/**
 * Führt das Gespräch, bis das Modell fertig ist.
 *
 * @param withTools Ob der Pool zur Verfügung steht. Beim Überarbeiten nicht:
 *   dort geht es um den vorliegenden Plan, nicht um neue Bausteine.
 */
export async function run(
  env: Env,
  system: string,
  firstMessage: unknown,
  emit: (event: AgentEvent) => void,
  withTools: boolean,
): Promise<AgentRun> {
  const messages: unknown[] = [{ role: 'user', content: firstMessage }];
  const usage: Usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, stopReason: null };
  const reused: string[] = [];
  let chars = 0;

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const response = await fetch(ANTHROPIC_URL, {
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
        // Der Prompt ist bei jedem Aufruf gleich — zwischengespeichert kostet
        // die Eingabe ab dem zweiten Lauf einen Bruchteil.
        system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
        ...(withTools ? { tools: TOOLS } : {}),
        messages,
      }),
    });

    if (!response.ok || response.body === null) {
      const detail = await response.text().catch(() => '');
      throw new UpstreamError(`status ${response.status}: ${detail.slice(0, 300)}`);
    }

    const result = await readTurn(response.body, usage, emit, chars);
    usage.stopReason = result.stopReason;
    chars += result.text.length;

    if (result.stopReason !== 'tool_use' || result.toolCalls.length === 0) {
      return { text: result.text, stopReason: result.stopReason, usage, reused };
    }

    messages.push({ role: 'assistant', content: result.content });

    const results: unknown[] = [];
    for (const call of result.toolCalls) {
      const outcome = await runTool(env, call.name, call.input);
      emit(outcome.event);
      reused.push(...outcome.reused);
      results.push({
        type: 'tool_result',
        tool_use_id: call.id,
        content: JSON.stringify(outcome.result),
      });
    }
    messages.push({ role: 'user', content: results });
  }

  throw new UpstreamError(`über ${MAX_TURNS} Züge ohne Ergebnis`);
}

export class UpstreamError extends Error {}
