import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/storage.dart';
import 'package:programs/main.dart';
import 'package:programs/state/app_state.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  final state = AppState(Store(MemoryStorageBackend()));
  await tester.pumpWidget(ProgramsApp(state: state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Startbildschirm zeigt die Seed-Programme', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Programme'), findsOneWidget);
    expect(find.text('Bach lesen lernen'), findsOneWidget);
    expect(find.text('Kraft Grundprogramm'), findsOneWidget);
  });

  testWidgets('Programm öffnen zeigt Begründung und Phasen', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Bach lesen lernen'));
    await tester.pumpAndSettle();

    expect(find.text('WARUM DIESER PLAN'), findsOneWidget);
    expect(find.text('Notation automatisieren'), findsOneWidget);
    expect(find.text('Programm starten'), findsOneWidget);
  });

  testWidgets('Tag öffnen und Session starten führt in den Player',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Gehörtraining Grundstock'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Programm starten'));
    await tester.pumpAndSettle();

    expect(find.text('Session starten'), findsOneWidget);
    expect(find.text('Intervalle hören'), findsOneWidget);

    await tester.tap(find.text('Session starten'));
    await tester.pumpAndSettle();

    // Player: erster Schritt von zweien, Quoten-Bedienung sichtbar.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('richtig'), findsOneWidget);
    expect(find.text('daneben'), findsOneWidget);
  });

  testWidgets('Quoten-Übung zählt Treffer und führt zum Abschluss',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Gehörtraining Grundstock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Programm starten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session starten'));
    await tester.pumpAndSettle();

    // "Erledigt" bleibt gesperrt, solange kein Versuch gezählt wurde.
    final erledigt = find.widgetWithText(FilledButton, 'Erledigt');
    expect(tester.widget<FilledButton>(erledigt).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Erledigt'));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Fertig'));
    await tester.pumpAndSettle();

    expect(find.text('Tag abschließen'), findsOneWidget);
  });

  testWidgets('Übungsbibliothek listet die Domänen', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('Übungen ('), findsOneWidget);
    expect(find.text('geige'), findsWidgets);
  });

  testWidgets('Importbildschirm ist erreichbar', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('Prompt in Zwischenablage'), findsOneWidget);
  });
}
