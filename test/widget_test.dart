import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/seed.dart';
import 'package:programs/data/storage.dart';
import 'package:programs/main.dart';
import 'package:programs/state/app_state.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  final state = AppState(Store(MemoryStorageBackend()), seed: seedBundle());
  await tester.pumpWidget(ProgramsApp(state: state));
  await tester.pumpAndSettle();
}

/// Box-Titel werden als RichText mit `┤ … ├` gesetzt — `find.text` greift dort
/// nicht, weil der Text aus mehreren Abschnitten besteht.
Finder findRich(String needle) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text.toPlainText().toUpperCase().contains(needle.toUpperCase()),
);

void main() {
  testWidgets('Startbildschirm zeigt Wortmarke und Seed-Programme', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('LEVELUP'), findsOneWidget);
    expect(find.text('ÜBUNGSPROGRAMME'), findsOneWidget);
    expect(find.text('Bach lesen lernen'), findsOneWidget);
    expect(find.text('Kraft Grundprogramm'), findsOneWidget);
  });

  testWidgets('Statuszeile zählt Programme und Übungen', (tester) async {
    await _pumpApp(tester);
    expect(find.textContaining('// 4 PROGRAMME'), findsOneWidget);
  });

  testWidgets('Programm öffnen zeigt Begründung und Phasen', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Bach lesen lernen'));
    await tester.pumpAndSettle();

    // Titel sitzt eingekerbt in der Kante, deshalb der RichText-Finder.
    expect(findRich('WARUM DIESER PLAN'), findsOneWidget);
    expect(findRich('NOTATION AUTOMATISIEREN'), findsOneWidget);
    expect(find.text('PROGRAMM STARTEN'), findsOneWidget);
  });

  testWidgets('Tag öffnen und Session starten führt in den Player', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Gehörtraining Grundstock'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PROGRAMM STARTEN'));
    await tester.pumpAndSettle();

    expect(find.text('SESSION STARTEN'), findsOneWidget);
    expect(find.text('Intervalle hören'), findsOneWidget);

    await tester.tap(find.text('SESSION STARTEN'));
    await tester.pumpAndSettle();

    // Player: Übungstitel groß, Position, sonst nichts. Kein Trefferzähler,
    // keine Merksätze, keine Zusammenfassung — das steht hinter dem
    // Fragezeichen.
    expect(find.text('ÜBUNG 1 VON 2'), findsOneWidget);
    expect(find.text('Intervalle hören'), findsOneWidget);
    expect(find.text('RICHTIG'), findsNothing);
    expect(find.text('DANEBEN'), findsNothing);
  });

  testWidgets('das Fragezeichen erklärt die Übung', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Gehörtraining Grundstock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROGRAMM STARTEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SESSION STARTEN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('?'));
    await tester.pumpAndSettle();

    expect(find.text('SCHLIESSEN'), findsOneWidget);

    await tester.tap(find.text('SCHLIESSEN'));
    await tester.pumpAndSettle();
    expect(find.text('SCHLIESSEN'), findsNothing);
  });

  testWidgets('eine Quoten-Übung lässt sich abhaken', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Gehörtraining Grundstock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROGRAMM STARTEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SESSION STARTEN'));
    await tester.pumpAndSettle();

    // Ohne Trefferzähler muss "Erledigt" offen sein — sonst käme man aus
    // einer Quoten-Übung nicht mehr heraus.
    final erledigt = find.widgetWithText(FilledButton, 'ERLEDIGT');
    expect(tester.widget<FilledButton>(erledigt).onPressed, isNotNull);

    await tester.tap(erledigt);
    await tester.pumpAndSettle();

    expect(find.text('ÜBUNG 2 VON 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'FERTIG'));
    await tester.pumpAndSettle();

    expect(find.text('TAG ABSCHLIESSEN'), findsOneWidget);
  });

  testWidgets('Übungsbibliothek listet die Domänen', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    expect(find.textContaining('Übungen ('), findsOneWidget);
    expect(find.text('GEIGE'), findsWidgets);
  });

  testWidgets('Importbildschirm bietet alle drei Wege an', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Kastentitel stecken in RichText-Spans, deshalb über das Prädikat.
    Finder kasten(String titel) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(titel),
    );

    expect(kasten('PLAN ERSTELLEN (PRO)'), findsOneWidget);
    // Der kostenlose Weg über den eigenen Chat ist seit dem Umbau der
    // eigentliche Hauptweg.
    expect(kasten('PLAN AUS DEM CHAT (FREE)'), findsOneWidget);
    expect(kasten('FERTIGES BUNDLE EINFÜGEN'), findsOneWidget);
  });

  testWidgets('die Schritte des freien Weges liegen eingeklappt', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Eingeklappt, damit der Bildschirm zwei Angebote zeigt und nicht eine
    // Liste loser Aufgaben.
    expect(find.text('PROMPT IN ZWISCHENABLAGE'), findsNothing);

    await tester.tap(find.text('SCHRITTE ANZEIGEN'));
    await tester.pumpAndSettle();

    expect(find.text('PROMPT IN ZWISCHENABLAGE'), findsOneWidget);
    expect(find.text('IMPORTIEREN'), findsOneWidget);
  });
}
