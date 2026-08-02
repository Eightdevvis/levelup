import 'package:flutter_test/flutter_test.dart';
import 'package:programs/data/ai_prompt.dart';

/// Der Prompt zum Kopieren.
///
/// Er ist der kostenlose Weg: Prompt in einen Chat, JSON zurück in die App.
/// Der Server hat seit Rev. 2 keinen einzelnen Prompt mehr, gegen den sich
/// hier vergleichen ließe — er führt drei getrennte Aufrufe. Dass dessen
/// Prompts wortgleich in der Spec stehen, prüft `server/test/spec-treue.test.ts`.
///
/// Bleibt die Frage, die hier einmal schiefging: ob die inhaltlichen Regeln
/// im App-Prompt überhaupt stehen. Die Materialregel fehlte dort, und der
/// kostenlose Weg lieferte weiter Übungen, die stillschweigend einen Stapel
/// Notenkarten voraussetzen.
void main() {
  /// Regeln, die im Prompt der App stehen müssen. Kurze, wörtliche Stücke:
  /// eine Umformulierung soll auffallen, eine andere Zeilenumbruchstelle nicht.
  const gemeinsam = <String, String>{
    'Materialregel': 'was jemand hat, der diese Fähigkeit übt',
    'Eine Übung ist eine Sache': 'Eine Übung ist EINE Sache, die man tut',
    'Einheit aus mehreren Übungen': 'meist drei bis sechs',
    'Name benennt, beschreibt nicht': 'Der Name benennt die Sache',
    'Zweifelsregel': 'Im Zweifel die Übung, die nichts braucht',
    'Diagnose zuerst': 'rationale',
    'Quote statt Dauer': 'nicht "duration"',
  };

  gemeinsam.forEach((name, stueck) {
    test('$name steht im Prompt der App', () {
      expect(kPlanSystemPrompt, contains(stueck));
    });
  });

  test('der App-Prompt kennt alle Zieltypen', () {
    for (final kind in ['duration', 'reps', 'quota', 'open']) {
      expect(kPlanSystemPrompt, contains('"kind": "$kind"'), reason: kind);
    }
  });
}
