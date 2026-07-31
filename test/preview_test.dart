import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/storage.dart';
import 'package:programs/main.dart';
import 'package:programs/model/library.dart';
import 'package:programs/state/app_state.dart';
import 'package:programs/ui/program_screen.dart';

/// Reinschauen und Übernehmen sind zwei verschiedene Dinge.
///
/// Vorher installierte ein Antippen in der offenen Bibliothek sofort — wer nur
/// schauen wollte, hatte das Programm danach auf seinem Startbildschirm. Und
/// weil es der normale Programmbildschirm war, stand dort auch "Programm
/// löschen", was in einer geteilten Bibliothek nichts zu suchen hat.
void main() {
  late AppState state;
  late Bundle fremd;

  setUp(() async {
    state = AppState(Store(MemoryStorageBackend()));
    await state.init();
    fremd = Bundle.fromJson(
      jsonDecode(File('test/fixtures/live_plan.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  Future<void> pumpVorschau(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: ProgramScreen(
            programId: fremd.programs.single.id,
            preview: fremd,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Ansehen legt nichts in die eigene Bibliothek', (tester) async {
    expect(state.programs, isEmpty);
    await pumpVorschau(tester);

    // Der Plan ist zu sehen …
    expect(find.textContaining('Zehnfinger'), findsWidgets);
    // … gehört aber weiterhin nicht mir.
    expect(state.programs, isEmpty);
  });

  testWidgets('in der Vorschau gibt es kein Löschen', (tester) async {
    await pumpVorschau(tester);

    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.text('Programm löschen'), findsNothing);
  });

  testWidgets('übernommen wird per Knopf, nicht per Blick', (tester) async {
    await pumpVorschau(tester);

    // Der Knopf liegt unterhalb des sichtbaren Bereichs; die ListView baut
    // ihn erst, wenn er in die Nähe kommt.
    final knopf = find.text('IN MEINE BIBLIOTHEK');
    await tester.scrollUntilVisible(knopf, 200);
    expect(knopf, findsOneWidget);
    expect(find.text('PROGRAMM STARTEN'), findsNothing);

    await tester.tap(knopf);
    await tester.pumpAndSettle();

    expect(state.programs, hasLength(1));
    expect(state.programs.single.id, fremd.programs.single.id);
  });

  testWidgets('ein eigenes Programm hat Menü und Startknopf', (tester) async {
    await state.installBundle(fremd);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: ProgramScreen(programId: fremd.programs.single.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    final knopf = find.text('PROGRAMM STARTEN');
    await tester.scrollUntilVisible(knopf, 200);
    expect(knopf, findsOneWidget);
  });
}
