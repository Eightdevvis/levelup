import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/storage.dart';
import 'package:programs/main.dart';
import 'package:programs/state/app_state.dart';
import 'package:programs/ui/chat_import_screen.dart';

import 'support/seed.dart';

/// Der kostenlose Weg von Hand durchgespielt.
///
/// Die Runden hängen aneinander: erst wenn Runde 1 aufgelöst ist, gibt es
/// Kennungen für Runde 2. Genau das prüft dieser Test — die reinen Parser
/// stehen in `tag_round_test.dart`.

Future<AppState> pumpImport(WidgetTester tester, {bool withSeed = true}) async {
  // Der Ablauf ist lang. Auf dem Vorgabeschirm von 800x600 liegen die Knöpfe
  // unter dem Rand und lassen sich nicht antippen.
  await tester.binding.setSurfaceSize(const Size(900, 3200));
  // Zurücksetzen muss innerhalb des Tests angemeldet werden — ein globales
  // tearDown läuft außerhalb und bricht mit „inTest is not true".
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(
    Store(MemoryStorageBackend()),
    seed: withSeed ? seedBundle() : null,
  );
  await tester.pumpWidget(
    ProgramsApp(state: state, home: const ChatImportScreen()),
  );
  await tester.pumpAndSettle();
  return state;
}

/// Box-Titel sind RichText mit `┤ … ├` — `find.text` greift dort nicht.
Finder findRich(String needle) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text.toPlainText().toUpperCase().contains(needle.toUpperCase()),
);

void main() {
  // Die Zwischenablage ist im Test kein echter Dienst.
  final copied = <String>[];
  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  testWidgets('zeigt die drei Schritte, aber Schritt 3 erst nach Runde 1', (
    tester,
  ) async {
    await pumpImport(tester);

    expect(find.text('MIT DEINER KI REDEN'), findsOneWidget);
    expect(find.text('ÜBUNGEN HERAUSSCHÄLEN'), findsOneWidget);
    // Ohne aufgelöste Übungen gibt es nichts zu ordnen.
    expect(find.text('PROGRAMM BAUEN LASSEN'), findsNothing);
  });

  testWidgets('der kopierte Text trägt den Tag-Pool der Bibliothek', (
    tester,
  ) async {
    await pumpImport(tester);

    await tester.tap(find.text('TEXT FÜR DIE KI KOPIEREN').first);
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('Wähle die Tags bevorzugt aus diesem Pool'));
    expect(copied.single, isNot(contains('LEER')));
  });

  testWidgets('bei leerer Bibliothek sagt der Text, dass der Pool leer ist', (
    tester,
  ) async {
    await pumpImport(tester, withSeed: false);

    await tester.tap(find.text('TEXT FÜR DIE KI KOPIEREN').first);
    await tester.pumpAndSettle();

    expect(copied.single, contains('LEER'));
  });

  testWidgets('eine unlesbare Antwort wird benannt, nicht verschluckt', (
    tester,
  ) async {
    await pumpImport(tester);

    await tester.enterText(find.byType(TextField).first, 'Klar, gerne doch!');
    await tester.tap(find.text('ÜBUNGEN AUFLÖSEN'));
    await tester.pumpAndSettle();

    expect(findRich('DAS GING NICHT'), findsOneWidget);
    expect(find.text('PROGRAMM BAUEN LASSEN'), findsNothing);
  });

  testWidgets('ganzer Durchlauf: zwei Runden, ein Plan in der Bibliothek', (
    tester,
  ) async {
    final state = await pumpImport(tester, withSeed: false);

    // --- Runde 1: die KI schreibt zwei Übungen aus.
    await tester.enterText(find.byType(TextField).first, '''
1. {"name": "Frei sprechen ohne Skript", "domain": "sprechen",
    "summary": "Zwei Minuten reden, ohne abzulesen.",
    "tags": ["sprechen", "freies_reden"]}
2. {"name": "Aufnahme anhören", "domain": "sprechen",
    "summary": "Die eigene Aufnahme einmal ganz durchhören.",
    "tags": ["sprechen", "rueckkopplung", "aufnahme"]}
''');
    await tester.tap(find.text('ÜBUNGEN AUFLÖSEN'));
    await tester.pumpAndSettle();

    expect(findRich('GEFUNDEN'), findsOneWidget);
    expect(find.textContaining('0 aus der Bibliothek · 2 neu'), findsOneWidget);
    expect(find.text('PROGRAMM BAUEN LASSEN'), findsOneWidget);

    // --- Der zweite Text muss die Kennungen aus Runde 1 tragen.
    copied.clear();
    await tester.tap(find.text('TEXT FÜR DIE KI KOPIEREN').last);
    await tester.pumpAndSettle();
    expect(copied.single, contains('sprechen-frei-sprechen-ohne-skript'));

    // --- Runde 2: die KI ordnet sie zu einem Programm.
    await tester.enterText(find.byType(TextField).last, '''
{
  "program": {
    "name": "Frei reden",
    "domain": "sprechen",
    "description": "Vom Ablesen zum freien Vortrag.",
    "phases": [
      {"name": "Anfang", "weeks": 2, "goal": "Zwei Minuten ohne Skript",
       "days": ["e1", "pause", "e1", "pause", "e1", "pause", "pause"]}
    ]
  },
  "units": [
    {"id": "e1", "name": "Tagesrunde", "exercises": [
      {"id": "sprechen-frei-sprechen-ohne-skript", "minutes": 5},
      {"id": "sprechen-aufnahme-anhoeren", "minutes": 5}
    ]}
  ]
}
''');
    await tester.tap(find.text('PLAN LESEN'));
    await tester.pumpAndSettle();

    expect(find.text('Frei reden'), findsOneWidget);
    expect(find.textContaining('2 ÜBUNGEN'), findsWidgets);

    // --- Übernehmen landet in der Bibliothek.
    await tester.tap(find.text('IN MEINE BIBLIOTHEK'));
    await tester.pumpAndSettle();

    expect(state.library.programs, hasLength(1));
    expect(state.library.exercises, hasLength(2));
    expect(state.library.programs.values.single.totalDays, 14);
  });

  testWidgets('Tag-Mengen ohne Entsprechung werden angezeigt', (tester) async {
    await pumpImport(tester, withSeed: false);

    await tester.enterText(find.byType(TextField).first, '''
1. ["klavier", "fingersatz", "tonleiter"]
2. {"name": "Echte Übung", "tags": ["klavier", "haltung"]}
''');
    await tester.tap(find.text('ÜBUNGEN AUFLÖSEN'));
    await tester.pumpAndSettle();

    expect(find.textContaining('OHNE ENTSPRECHUNG'), findsOneWidget);
    expect(find.textContaining('klavier, fingersatz, tonleiter'), findsOneWidget);
  });
}
