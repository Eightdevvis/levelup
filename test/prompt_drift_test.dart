import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/ai_prompt.dart';

/// Es gibt zwei Prompts: den verbindlichen auf dem Server
/// (`server/src/plan_prompt.ts`) und den zum Kopieren in der App. Sie sind
/// bewusst nicht identisch — der Server kennt Werkzeuge und den Pool, der
/// andere nicht.
///
/// Die inhaltlichen Regeln müssen aber in beiden stehen. Genau das ist einmal
/// schiefgegangen: die Materialregel kam nur auf den Server, und der
/// kostenlose Weg konnte weiter Übungen liefern, die stillschweigend einen
/// Stapel Notenkarten voraussetzen.
void main() {
  late String serverPrompt;

  setUpAll(() {
    final datei = File('server/src/plan_prompt.ts');
    // Ohne den Server (etwa in einem abgespeckten Checkout) ist hier nichts
    // zu prüfen — dann soll der Test nicht fälschlich rot werden.
    serverPrompt = datei.existsSync() ? datei.readAsStringSync() : '';
  });

  /// Regeln, die in beiden Fassungen stehen müssen. Kurze, wörtliche Stücke:
  /// eine Umformulierung soll auffallen, eine andere Zeilenumbruchstelle nicht.
  const gemeinsam = <String, String>{
    'Materialregel': 'was jemand hat, der diese Fähigkeit übt',
    'Eine Übung ist eine Sache': 'Eine Übung ist EINE Sache, die man tut',
    'Einheit aus mehreren Übungen': 'meist drei bis sechs',
    'Zweifelsregel': 'Im Zweifel die Übung, die nichts braucht',
    'Diagnose zuerst': 'rationale',
    'Quote statt Dauer': 'nicht "duration"',
  };

  gemeinsam.forEach((name, stueck) {
    test('$name steht im Prompt der App', () {
      expect(kPlanSystemPrompt, contains(stueck));
    });

    test('$name steht auch im Prompt des Servers', () {
      if (serverPrompt.isEmpty) return;
      expect(serverPrompt, contains(stueck));
    });
  });

  test('beide kennen dieselben Zieltypen', () {
    if (serverPrompt.isEmpty) return;
    for (final kind in ['duration', 'reps', 'quota', 'open']) {
      expect(kPlanSystemPrompt, contains('"kind": "$kind"'), reason: kind);
      expect(serverPrompt, contains('"kind": "$kind"'), reason: kind);
    }
  });
}
