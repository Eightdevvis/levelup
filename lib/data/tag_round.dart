import '../model/exercise.dart';

/// Runde 1 des kostenlosen Weges: aus einer KI-Antwort werden Übungen.
///
/// Der Gedanke dahinter: eine Übung wird nicht über ihren Namen erkannt,
/// sondern über die Menge ihrer Tags. Namen erfindet jede KI anders, Tags
/// nicht — „Aufnahme gegen Original stellen" und „Mitschnitt mit dem Original
/// vergleichen" sind zwei Namen für dieselbe Sache, tragen aber dieselben
/// Tags. Deshalb bittet der Prompt um Tag-Mengen und nicht um Titel.
///
/// Findet die KI keinen passenden Tag, heißt das: die Bibliothek kennt diese
/// Übung noch nicht. Dann schreibt sie die Übung selbst, und die Bibliothek
/// wächst um genau das, was ihr gefehlt hat.

/// Ein Tag mit seiner Häufigkeit in der Bibliothek.
class TagCount {
  const TagCount(this.tag, this.count);

  final String tag;
  final int count;
}

/// Alle Tags der Bibliothek, häufigste zuerst.
///
/// Die Reihenfolge ist kein Schmuck: der Pool wandert in den Prompt, und was
/// oben steht, wird eher gewählt. Häufige Tags sind die eingebürgerten — genau
/// die sollen bevorzugt werden, damit die Bibliothek nicht in Synonyme
/// zerfällt.
List<TagCount> tagPool(Iterable<Exercise> exercises) {
  final counts = <String, int>{};
  for (final exercise in exercises) {
    for (final tag in exercise.tags) {
      final clean = normalizeTag(tag);
      if (clean.isEmpty) continue;
      counts[clean] = (counts[clean] ?? 0) + 1;
    }
    // Der Bereich zählt nur mit, wenn er nicht ohnehin schon als Tag
    // dasteht — sonst stünde die Tätigkeit doppelt so hoch im Pool, wie sie
    // wirklich vorkommt.
    final domain = normalizeTag(exercise.domain);
    final schonGezaehlt = exercise.tags.any((t) => normalizeTag(t) == domain);
    if (domain.isNotEmpty && domain != 'allgemein' && !schonGezaehlt) {
      counts[domain] = (counts[domain] ?? 0) + 1;
    }
  }

  final pool = [
    for (final entry in counts.entries) TagCount(entry.key, entry.value),
  ]..sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.tag.compareTo(b.tag);
  });
  return pool;
}

/// Kleingeschrieben, ohne Rand, Leerzeichen zu Unterstrichen, Umlaute
/// ausgeschrieben.
///
/// Ohne die Kleinschreibung werden „Geige", „geige" und „geige " zu drei Tags.
/// Und die Umlaute müssen weg, weil Tags durch einen fremden Chat reisen und
/// wieder zurück: schreibt die KI „gehoer" statt „gehör", zeigt der Verweis
/// ins Leere und die Übung wird ein zweites Mal erfunden. Der Grundstock hält
/// sich schon an diese Schreibweise.
String normalizeTag(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
}

// --- Was die KI in Runde 1 zurückgibt ---------------------------------------

/// Ein Eintrag aus der Antwort: entweder ein Verweis über Tags oder eine
/// selbst geschriebene Übung.
sealed class ExerciseRequest {
  const ExerciseRequest();
}

/// „Nimm die Übung, auf die diese Tags passen."
class TagRequest extends ExerciseRequest {
  const TagRequest(this.tags);
  final List<String> tags;
}

/// „Die gibt es bei euch noch nicht, hier ist sie."
class DraftRequest extends ExerciseRequest {
  const DraftRequest(this.exercise);
  final Exercise exercise;
}

class RoundOneResult {
  const RoundOneResult({required this.requests, required this.problems});

  final List<ExerciseRequest> requests;

  /// Zeilen, die weder als Tag-Liste noch als Übung lesbar waren. Sie werden
  /// benannt statt verschluckt: wer nicht sieht, dass etwas fehlt, sucht den
  /// Fehler später im Plan.
  final List<String> problems;

  bool get isEmpty => requests.isEmpty;
}

/// Liest die Antwort der KI.
///
/// Bewusst nachsichtig: Nummerierung, Aufzählungsstriche, Code-Zäune und ein
/// „Hier bitte:" davor dürfen drinstehen. Wer eine KI-Antwort von Hand
/// zurechtschneiden muss, macht dabei Fehler — und der Ärger darüber trifft
/// die App, nicht die KI.
RoundOneResult parseRoundOne(String raw) {
  final requests = <ExerciseRequest>[];
  final problems = <String>[];

  for (final block in _splitEntries(stripFences(raw))) {
    final trimmed = block.trim();
    if (trimmed.isEmpty) continue;

    if (trimmed.startsWith('[')) {
      final tags = _parseTagList(trimmed);
      if (tags.isEmpty) {
        problems.push(trimmed, 'keine brauchbaren Tags');
      } else {
        requests.add(TagRequest(tags));
      }
      continue;
    }

    if (trimmed.startsWith('{')) {
      final exercise = _parseDraft(trimmed);
      if (exercise == null) {
        problems.push(trimmed, 'als Übung nicht lesbar (name und tags nötig)');
      } else {
        requests.add(DraftRequest(exercise));
      }
      continue;
    }

    problems.push(trimmed, 'weder Tag-Liste noch Übung');
  }

  return RoundOneResult(requests: requests, problems: problems);
}

extension _Problems on List<String> {
  void push(String text, String why) {
    final short = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    add('$why: $short');
  }
}

/// Entfernt Code-Zäune und einleitende Prosa.
String stripFences(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```[a-zA-Z]*\s*');
  text = text.replaceAll(fence, '').replaceAll('```', '');
  return text.trim();
}

/// Zerlegt die Antwort in Einträge.
///
/// Die KI nummeriert („1. [...]"), und die Übungsobjekte gehen über mehrere
/// Zeilen. Deshalb wird an den Nummern geschnitten und nicht an Zeilenenden.
List<String> _splitEntries(String text) {
  final entries = <String>[];
  final buffer = StringBuffer();
  // Zeilenanfang, dann eine Zahl mit Punkt oder Klammer, oder ein Strich.
  final marker = RegExp(r'^\s*(\d+\s*[.)]|[-*•])\s*');

  for (final line in text.split('\n')) {
    if (marker.hasMatch(line) && buffer.isNotEmpty) {
      entries.add(buffer.toString());
      buffer.clear();
    }
    buffer.writeln(line.replaceFirst(marker, ''));
  }
  if (buffer.isNotEmpty) entries.add(buffer.toString());
  return entries;
}

List<String> _parseTagList(String text) {
  final close = text.indexOf(']');
  if (close == -1) return const [];
  final inner = text.substring(1, close);

  final tags = <String>[];
  for (final part in inner.split(',')) {
    final tag = normalizeTag(part.replaceAll(RegExp('["\']'), ''));
    if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
  }
  return tags;
}

/// Liest ein Übungsobjekt.
///
/// Kein `jsonDecode`: die KI schreibt in diesem Format gern JavaScript statt
/// JSON — Schlüssel ohne Anführungszeichen, einfache statt doppelte. Daran zu
/// scheitern wäre die teuerste Art, ein Komma zu suchen.
Exercise? _parseDraft(String text) {
  final name = _field(text, 'name') ?? _field(text, 'titel');
  if (name == null || name.isEmpty) return null;

  final tags = _list(text, 'tags').map(normalizeTag).where((t) => t.isNotEmpty).toList();
  if (tags.isEmpty) return null;

  // Verlangt wird "description". Die alten Namen werden trotzdem gelesen: eine
  // KI, die schon einmal ein Übungsobjekt gesehen hat, schreibt gern das alte
  // Format, und daran zu scheitern hilft niemandem.
  final beschreibung =
      _field(text, 'description') ??
      _field(text, 'anleitung') ??
      _field(text, 'beschreibung') ??
      _field(text, 'summary');
  final zeilen = _list(text, 'instructions');
  final description = [
    if (beschreibung != null && beschreibung.isNotEmpty) beschreibung,
    ...zeilen.where((z) => z.trim().isNotEmpty),
  ].join('\n');

  return Exercise(
    id: slugFor(tags.first, name),
    name: name,
    description: description.isEmpty ? null : description,
    benefits: _list(text, 'benefits'),
    // "requirements" hieß das Feld früher.
    equipment: _list(text, 'equipment').isNotEmpty
        ? _list(text, 'equipment')
        : _list(text, 'requirements'),
    tags: tags,
    source: 'chat',
  );
}

/// Kennung aus Bereich und Name: `geige-rhythmus-klopfen`.
///
/// Ableitbar statt zufällig, damit derselbe Name zweimal importiert nicht
/// zwei Übungen ergibt.
String slugFor(String domain, String name) {
  final teile = normalizeTag('$domain $name').replaceAll('_', '-');
  final gekuerzt = teile.length > 60 ? teile.substring(0, 60) : teile;
  return gekuerzt.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

String? _field(String text, String key) {
  final pattern = RegExp(
    '["\']?$key["\']?\\s*:\\s*(".*?"|\'.*?\')',
    dotAll: true,
  );
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  final roh = match.group(1)!;
  return roh.substring(1, roh.length - 1).replaceAll(r'\"', '"').trim();
}

List<String> _list(String text, String key) {
  final pattern = RegExp('["\']?$key["\']?\\s*:\\s*\\[(.*?)\\]', dotAll: true);
  final match = pattern.firstMatch(text);
  if (match == null) return const [];

  final werte = <String>[];
  for (final teil in RegExp('".*?"|\'.*?\'').allMatches(match.group(1)!)) {
    final wert = teil.group(0)!;
    final sauber = wert.substring(1, wert.length - 1).trim();
    if (sauber.isNotEmpty) werte.add(sauber);
  }
  return werte;
}

// --- Auflösen gegen die Bibliothek ------------------------------------------

/// Ab hier gilt eine Tag-Menge als dieselbe Übung.
///
/// Geraten, aber nicht beliebig: bei drei verlangten Tags und einer Übung mit
/// vier heißt 0,6 „mindestens drei davon gemeinsam". Zu niedrig, und jede
/// Geigenübung passt auf jede andere; zu hoch, und der Nutzer bekommt zehn
/// Fast-Dubletten, weil nie etwas trifft.
const double kTagMatchThreshold = 0.6;

/// Eine aufgelöste Position: welche Übung hier steht und woher sie kommt.
class Resolved {
  const Resolved({
    required this.exercise,
    required this.isNew,
    required this.score,
    required this.wantedTags,
  });

  final Exercise exercise;

  /// Ob die Übung neu entstanden ist — dann muss sie mit ins Bundle.
  final bool isNew;

  /// Wie gut die Tags übereinstimmten. 1,0 bei neu geschriebenen.
  final double score;

  /// Was die KI angefordert hatte. Steht im Bericht, damit sichtbar ist,
  /// warum diese Übung genommen wurde.
  final List<String> wantedTags;
}

class ResolveResult {
  const ResolveResult({
    required this.resolved,
    required this.unmatched,
    required this.problems,
  });

  final List<Resolved> resolved;

  /// Tag-Mengen ohne Treffer. Die KI hat angenommen, die Bibliothek habe so
  /// eine Übung — hat sie nicht. Das gehört dem Nutzer gesagt, damit er
  /// nachfordern kann, statt ein Loch im Plan zu bekommen.
  final List<List<String>> unmatched;

  final List<String> problems;

  int get reused => resolved.where((r) => !r.isNew).length;
  int get created => resolved.where((r) => r.isNew).length;
}

/// Wie ähnlich sich zwei Tag-Mengen sind (Jaccard).
double tagSimilarity(Iterable<String> a, Iterable<String> b) {
  final setA = a.map(normalizeTag).where((t) => t.isNotEmpty).toSet();
  final setB = b.map(normalizeTag).where((t) => t.isNotEmpty).toSet();
  if (setA.isEmpty || setB.isEmpty) return 0;
  final shared = setA.intersection(setB).length;
  return shared / (setA.length + setB.length - shared);
}

/// Setzt die Antwort der KI gegen die Bibliothek.
///
/// Neu geschriebene Übungen werden dabei mitgeführt: verlangt ein späterer
/// Eintrag dieselben Tags, greift er auf die eben entstandene zu, statt eine
/// zweite fast gleiche zu erzeugen.
ResolveResult resolveRequests(
  RoundOneResult round,
  Iterable<Exercise> library,
) {
  final bestand = <Exercise>[...library];
  final resolved = <Resolved>[];
  final unmatched = <List<String>>[];

  for (final request in round.requests) {
    switch (request) {
      case DraftRequest(:final exercise):
        // Auch eine selbst geschriebene Übung kann schon dastehen — etwa
        // wenn derselbe Chat zweimal importiert wird.
        final treffer = _bestMatch(exercise.tags, bestand);
        if (treffer != null && treffer.score >= kTagMatchThreshold) {
          resolved.add(
            Resolved(
              exercise: treffer.exercise,
              isNew: false,
              score: treffer.score,
              wantedTags: exercise.tags,
            ),
          );
        } else {
          bestand.add(exercise);
          resolved.add(
            Resolved(
              exercise: exercise,
              isNew: true,
              score: 1,
              wantedTags: exercise.tags,
            ),
          );
        }

      case TagRequest(:final tags):
        final treffer = _bestMatch(tags, bestand);
        if (treffer == null || treffer.score < kTagMatchThreshold) {
          unmatched.add(tags);
        } else {
          resolved.add(
            Resolved(
              exercise: treffer.exercise,
              isNew: false,
              score: treffer.score,
              wantedTags: tags,
            ),
          );
        }
    }
  }

  return ResolveResult(
    resolved: resolved,
    unmatched: unmatched,
    problems: round.problems,
  );
}

class _Match {
  const _Match(this.exercise, this.score);
  final Exercise exercise;
  final double score;
}

_Match? _bestMatch(Iterable<String> tags, List<Exercise> library) {
  _Match? best;
  for (final exercise in library) {
    final score = tagSimilarity(tags, exercise.tags);
    if (best == null || score > best.score) best = _Match(exercise, score);
  }
  return best;
}
