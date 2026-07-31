import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:programs/ui/widgets.dart';

/// Der Kastentitel saß früher in einer freistehenden Position ohne bekannte
/// Breite. Ein langer Titel wurde deshalb am Rand abgeschnitten, statt
/// umzubrechen — sichtbar geworden an einer Phasenüberschrift.
void main() {
  const langerTitel = 'Woche 3: Genauigkeit und echter Text im Fließtext';

  Future<Size> titelGroesse(WidgetTester tester, double breite) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: breite,
              child: const ZBox(
                title: langerTitel,
                trailing: '4W',
                child: Text('Inhalt'),
              ),
            ),
          ),
        ),
      ),
    );
    // Gezielt der Titel, nicht der Kasteninhalt: RichText trägt den Text in
    // Spans, deshalb über das Prädikat statt über find.text.
    return tester.getSize(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('WOCHE 3'),
      ),
    );
  }

  testWidgets('ein langer Titel bleibt innerhalb des Kastens', (tester) async {
    final groesse = await titelGroesse(tester, 300);
    expect(groesse.width, lessThanOrEqualTo(300));
  });

  testWidgets('er bricht um, statt abgeschnitten zu werden', (tester) async {
    final schmal = await titelGroesse(tester, 240);
    final breit = await titelGroesse(tester, 600);

    // Umbruch heißt: schmaler wird höher. Würde er abgeschnitten, bliebe die
    // Höhe gleich und nur der Text verschwände.
    expect(schmal.height, greaterThan(breit.height));
  });
}
