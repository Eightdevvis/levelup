/**
 * Spielt den Grundstock in eine laufende API ein (Spec §10).
 *
 * Läuft mit Node, nicht im Worker — die Dateien liegen im Repository, nicht in
 * der Cloud. Die Arbeit macht der Server: er hat die Bindings zu D1, Vectorize
 * und Workers AI.
 *
 *   BETREIBER_TOKEN=… npx tsx grundstock/einspielen.ts https://levelup-api…workers.dev
 *
 * Ohne URL geht es gegen `http://127.0.0.1:8787`, also gegen `wrangler dev`.
 * Mehrfaches Ausführen legt nichts doppelt an: die Kennungen stehen in den
 * Dateien.
 */

import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DATEIEN = ['geige.json', 'krafttraining.json'];

interface Bericht {
  taetigkeit: string;
  angelegt: string[];
  uebersprungen: string[];
  fehler: string[];
}

async function main(): Promise<void> {
  const basis = process.argv[2] ?? 'http://127.0.0.1:8787';
  const token = process.env.BETREIBER_TOKEN;

  if (token === undefined || token.length === 0) {
    console.error('BETREIBER_TOKEN fehlt. Setzen mit: wrangler secret put BETREIBER_TOKEN');
    process.exit(1);
  }

  const hier = dirname(fileURLToPath(import.meta.url));
  let fehlerhaft = false;

  for (const name of DATEIEN) {
    const inhalt = JSON.parse(await readFile(join(hier, name), 'utf8')) as unknown;

    const antwort = await fetch(`${basis}/v1/grundstock`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify(inhalt),
    });

    if (!antwort.ok) {
      console.error(`${name}: ${antwort.status} ${await antwort.text()}`);
      fehlerhaft = true;
      continue;
    }

    const bericht = (await antwort.json()) as Bericht;
    console.log(
      `${name}: ${bericht.angelegt.length} angelegt, ` +
        `${bericht.uebersprungen.length} schon vorhanden`,
    );
    if (bericht.fehler.length > 0) {
      console.error(bericht.fehler.join('\n'));
      fehlerhaft = true;
    }
  }

  process.exit(fehlerhaft ? 1 : 0);
}

void main();
