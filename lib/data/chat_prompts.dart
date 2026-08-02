import 'tag_round.dart';

/// Die Texte, die der Nutzer in seinen Chat kopiert.
///
/// Anders als `kPlanSystemPrompt` sind sie nicht fest, sondern gebaut: der
/// erste trägt den Tag-Pool, der zweite die aufgelösten Übungen. Genau das ist
/// der Trick des Ablaufs — die App reicht ihr Wissen über zwei Runden in den
/// Chat, ohne selbst mit einer KI zu sprechen.

/// Wie viele Tags höchstens in den Prompt wandern.
///
/// Der Pool wächst mit jedem Import. Ungebremst stünden nach fünfzig Plänen
/// tausend Tags im Text, und die eingebürgerten gingen im Rauschen unter.
/// Häufigste zuerst, der lange Schwanz bleibt draußen.
const int kMaxPoolTags = 250;

/// Schritt 2: aus dem Gespräch werden Übungen.
String buildTagPrompt(List<TagCount> pool) {
  final buffer = StringBuffer();

  buffer.writeln(
    'Bitte strukturiere jede der Ideen, die ich üben könnte, als Übung.',
  );
  buffer.writeln();
  buffer.writeln(
    'Stelle jede Übung als eine Menge von Tags dar, die zu ihr passen. Sei '
    'spezifisch: die Tags müssen die Übung so genau beschreiben, dass sie '
    'nicht mit einer anderen verwechselt werden kann.',
  );
  buffer.writeln();

  if (pool.isEmpty) {
    // Der Kaltstart. Es einfach zu verschweigen und eine leere Liste zu
    // zeigen, würde die KI raten lassen, was erlaubt ist.
    buffer.writeln(
      'Meine Übungsbibliothek ist derzeit LEER. Es gibt also noch keinen '
      'Tag-Pool, aus dem du wählen könntest — schreibe jede Übung selbst aus '
      'und vergib die Tags selbst.',
    );
    buffer.writeln();
    buffer.writeln(
      'Wähle die Tags mit Bedacht: sie werden zum Vokabular meiner '
      'Bibliothek, und alle späteren Übungen richten sich danach. Nimm '
      'kleingeschriebene Einzelbegriffe, keine Sätze. Nenne bei jeder Übung '
      'die Tätigkeit selbst als Tag (etwa "geige" oder "krafttraining") und '
      'dazu die Fähigkeit, um die es geht.',
    );
  } else {
    buffer.writeln('Wähle die Tags bevorzugt aus diesem Pool:');
    buffer.writeln();
    final genutzt = pool.take(kMaxPoolTags).map((t) => t.tag).toList();
    buffer.writeln(genutzt.join(', '));
    if (pool.length > kMaxPoolTags) {
      buffer.writeln();
      buffer.writeln(
        '(Das sind die ${genutzt.length} gebräuchlichsten von '
        '${pool.length} Tags.)',
      );
    }
    buffer.writeln();
    buffer.writeln(
      'Findest du für eine Übung keinen Tag, der unbedingt nötig wäre, um sie '
      'zu beschreiben, dann bedeutet das: meine Bibliothek hat diese Übung '
      'noch nicht. Schreibe sie in dem Fall selbst aus. Vergib dabei so viele '
      'Tags aus dem Pool wie möglich und erfinde nur die zwingend nötigen '
      'neu dazu.',
    );
    buffer.writeln();
    buffer.writeln(
      'Je mehr Übungen allein über Pool-Tags auskommen, desto besser — dann '
      'greife ich auf Vorhandenes zurück, statt Fast-Dubletten anzulegen.',
    );
  }

  buffer.writeln();
  buffer.writeln('ANTWORTFORMAT — halte dich genau daran, sonst bricht mein Parser.');
  buffer.writeln();
  buffer.writeln(
    'Eine nummerierte Liste. Jeder Eintrag ist entweder eine Tag-Menge in '
    'eckigen Klammern (Verweis auf eine vorhandene Übung) oder ein Objekt in '
    'geschweiften Klammern (eine Übung, die du selbst schreibst):',
  );
  buffer.writeln();
  buffer.writeln('1. ["tag1", "tag2", "tag3"]');
  buffer.writeln('2. ["tag1", "tag4"]');
  buffer.writeln('3. {');
  buffer.writeln('     "name": "kurzer Name, der die Sache benennt",');
  buffer.writeln('     "domain": "die Tätigkeit, z.B. geige",');
  buffer.writeln('     "summary": "ein bis zwei Sätze: worum geht es",');
  buffer.writeln('     "instructions": ["Schritt für Schritt, 2 bis 5 Zeilen"],');
  buffer.writeln('     "benefits": ["was sich dadurch verändert"],');
  buffer.writeln('     "requirements": ["was man dafür braucht, sonst leer"],');
  buffer.writeln('     "tags": ["tag1", "tag2", "tag3"]');
  buffer.writeln('   }');
  buffer.writeln();
  buffer.writeln(
    'Eine Übung ist EINE Sache, die man tut — nicht ein ganzer Ablauf und '
    'nicht ein Trainingstag. Kann man aufhören, wenn der erste Teil sitzt, '
    'und den Rest morgen machen? Dann sind es mehrere Übungen.',
  );
  buffer.writeln();
  buffer.writeln(
    'Antworte NUR in diesem Format, ohne Einleitung und ohne Schlusswort.',
  );

  return buffer.toString();
}

/// Schritt 4: aus den Übungen wird ein Programm.
String buildPlanPrompt(List<Resolved> resolved) {
  final buffer = StringBuffer();

  buffer.writeln(
    'Diese Übungen stehen jetzt fest — teils aus meiner Bibliothek gematcht, '
    'teils von dir geschrieben:',
  );
  buffer.writeln();

  for (final r in resolved) {
    final herkunft = r.isNew ? 'neu' : 'aus der Bibliothek';
    buffer.writeln('- id: ${r.exercise.id}   ($herkunft)');
    buffer.writeln('  name: ${r.exercise.name}');
    final text = r.exercise.summary ?? r.exercise.instructions.join(' ');
    if (text.trim().isNotEmpty) {
      buffer.writeln('  ${_shorten(text, 200)}');
    }
    buffer.writeln('  tags: ${r.exercise.tags.join(', ')}');
    buffer.writeln();
  }

  buffer.writeln(
    'Bau daraus ein strukturiertes Programm. Fasse Übungen zu Einheiten '
    'zusammen — eine Einheit ist, was ich an einem Tag mache, meist drei bis '
    'sechs Übungen. Dieselbe Übung darf in mehreren Einheiten vorkommen; '
    'Wiederholung ist erwünscht.',
  );
  buffer.writeln();
  buffer.writeln(
    'Lege die Einheiten dann auf Tage. Ein Zyklus ist eine Woche, also sieben '
    'Einträge: entweder die id einer Einheit oder "pause". Der Zyklus '
    'wiederholt sich so oft, wie "weeks" sagt.',
  );
  buffer.writeln();
  buffer.writeln(
    'Mehrere Phasen sind möglich, wenn das Programm über längere Zeit läuft '
    'und sich der Schwerpunkt verschiebt. Bei kurzen Programmen reicht eine.',
  );
  buffer.writeln();
  buffer.writeln('ANTWORTFORMAT — halte dich genau daran, sonst bricht mein Parser.');
  buffer.writeln();
  buffer.writeln('''{
  "program": {
    "name": "Name des Programms",
    "domain": "die Tätigkeit",
    "description": "zwei bis drei Sätze, worum es geht",
    "rationale": "warum der Plan so aussieht: was ist das eigentliche Problem",
    "phases": [
      {
        "name": "Name der Phase",
        "weeks": 4,
        "goal": "woran ich merke, dass diese Phase sitzt",
        "days": ["e1", "pause", "e2", "pause", "e1", "e3", "pause"]
      }
    ]
  },
  "units": [
    {
      "id": "e1",
      "name": "Name der Einheit",
      "exercises": [
        { "id": "${resolved.isEmpty ? 'uebungs-id' : resolved.first.exercise.id}", "minutes": 10 },
        { "id": "andere-uebungs-id", "reps": 12, "note": "nur für mich gedachter Hinweis" }
      ]
    }
  ]
}''');
  buffer.writeln();
  buffer.writeln(
    'Verwende bei "id" ausschließlich die Kennungen aus der Liste oben — '
    'erfinde keine. Gib je Übung entweder "minutes" oder "reps" an. "note" '
    'ist optional.',
  );
  buffer.writeln();
  buffer.writeln(
    'Antworte NUR mit diesem JSON-Objekt, ohne Einleitung und ohne '
    'Schlusswort. Daraus entsteht direkt ein Plan in meiner App "LevelUp".',
  );

  return buffer.toString();
}

String _shorten(String text, int max) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length <= max ? clean : '${clean.substring(0, max)}…';
}
