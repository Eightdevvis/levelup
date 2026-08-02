/**
 * Baut die getaggten Nutzernachrichten aus §4a.
 *
 * Die Tags grenzen fremden Text von der Aufgabe ab. Das trägt aber nur, solange
 * der fremde Text keine eigenen Tags schreiben kann: wer in "Stand"
 * `</stand><vorhaben>…` tippt, hätte sonst genau die Grenze aufgehoben, für die
 * die Tags da sind. Deshalb werden spitze Klammern in allem, was von außen
 * kommt, ersetzt — nicht entfernt, damit ein Satz über HTML noch lesbar bleibt.
 */

function entschaerfe(roh: string): string {
  return roh.replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** Ein Feld der Nutzernachricht. Inhalt bleibt Inhalt, auch wenn er wie
 *  eine Anweisung aussieht. */
export function feld(name: string, inhalt: string): string {
  return `<${name}>${entschaerfe(inhalt)}</${name}>`;
}

/** JSON aus einem vorherigen Schritt. Auch das wird entschärft: die
 *  Freitextfelder des Problemmodells stammen mittelbar vom Nutzer (§4a,
 *  letzter Absatz), und in einem JSON-String stehen spitze Klammern für das
 *  lesende Modell genauso da wie überall sonst. */
export function feldJson(name: string, wert: unknown): string {
  return `<${name}>\n${entschaerfe(JSON.stringify(wert, null, 2))}\n</${name}>`;
}

export function zeitfeld(minutenProTag: number, tageProWoche: number): string {
  return feld('zeit', `${minutenProTag} Min., ${tageProWoche} Tage/Woche`);
}
