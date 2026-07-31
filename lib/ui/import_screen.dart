import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_prompt.dart';
import '../main.dart';
import '../state/app_state.dart';
import 'generate_screen.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Die beiden Wege zu einem Plan.
///
/// Oben der bequeme: beschreiben, fertig. Darunter der kostenlose: Prompt
/// kopieren, in ein LLM werfen, Antwort einfügen. Beide führen zum selben
/// Ergebnis, der zweite kostet nur Handgriffe statt Geld.
///
/// Die Schritte des zweiten Weges liegen eingeklappt. Ausgebreitet standen sie
/// gleichrangig neben dem ersten Weg und ließen den Bildschirm wie eine Liste
/// loser Aufgaben aussehen, statt wie zwei Angebote.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  ImportResult? _result;
  bool _busy = false;
  bool _stepsOpen = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final result = await AppScope.of(context).importJson(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result.ok) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final scheme = Theme.of(context).colorScheme;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('PLAN HOLEN')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 8, 15, 40),
        children: [
          ZBox(
            title: 'plan erstellen (pro)',
            filled: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _body(
                  p,
                  'Beschreib dein Anliegen und lass dir direkt in der App '
                  'einen eigenen Plan zusammenstellen. Braucht ein Abo — oder '
                  'probier die kostenlose Variante darunter.',
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GenerateScreen(),
                    ),
                  ),
                  child: const Text('PLAN ERZEUGEN'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ZBox(
            title: 'plan erstellen (free)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _body(
                  p,
                  'Befolge ein paar Schritte und importier damit einen guten '
                  'Plan in deine Bibliothek.',
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => setState(() => _stepsOpen = !_stepsOpen),
                  child: Text(
                    _stepsOpen ? 'SCHRITTE AUSBLENDEN' : 'SCHRITTE ANZEIGEN',
                  ),
                ),
                if (_stepsOpen) ...[
                  const SizedBox(height: 20),
                  _Step(
                    number: 1,
                    title: 'Prompt kopieren',
                    body:
                        'Enthält das komplette Format. In ein LLM einfügen '
                        '(unsere Empfehlung und die Pro-Variante basieren auf '
                        'Claude von Anthropic) und dahinter in eigenen Worten '
                        'beschreiben, was du erreichen willst und wo es '
                        'klemmt — je genauer das Problem, desto besser die '
                        'Diagnose.',
                    action: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('PROMPT IN ZWISCHENABLAGE'),
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: kAiPromptTemplate),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('// PROMPT KOPIERT')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Step(
                    number: 2,
                    title: 'Antwort hier einfügen',
                    body:
                        'Das JSON aus der Antwort einfügen. Code-Zäune (```) '
                        'dürfen drinbleiben, die werden entfernt.',
                    action: Column(
                      children: [
                        TextField(
                          controller: _controller,
                          minLines: 6,
                          maxLines: 14,
                          style: TextStyle(
                            fontFamily: Metrics.mono,
                            fontSize: 11.5,
                            height: 1.5,
                            color: p.fg,
                          ),
                          decoration: const InputDecoration(
                            hintText: '{ "version": 1, "exercises": [ ... ] }',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.paste, size: 18),
                                label: const Text('EINFÜGEN'),
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  if (data?.text != null) {
                                    setState(
                                      () => _controller.text = data!.text!,
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy ? null : _import,
                                child: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('IMPORTIEREN'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: result.ok
                    ? scheme.primaryContainer
                    : scheme.errorContainer,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: (result.ok ? scheme.primary : scheme.error).withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        result.ok
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 18,
                        color: result.ok
                            ? scheme.onPrimaryContainer
                            : scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.message,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: result.ok
                                ? scheme.onPrimaryContainer
                                : scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Unvollständig — folgende Verweise gehen ins Leere:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final warning in result.warnings.take(8))
                      Text(
                        '• $warning',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Der Plan ist trotzdem importiert. Fehlende Übungen kannst '
                      'du nachliefern, indem du sie einzeln nachimportierst.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  if (result.ok && result.importedPrograms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final program in result.importedPrograms)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ProgramScreen(programId: program.id),
                            ),
                          ),
                          child: Text('"${program.name}" öffnen'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
          const SectionLabel('format'),
          Text(
            'Importiert wird ein Bundle aus Übungen, Listen und Programmen. '
            'Übungen landen in der gemeinsamen Bibliothek und stehen danach '
            'jedem weiteren Plan zur Verfügung. Gleiche IDs werden ersetzt, '
            'ein erneuter Import aktualisiert also, statt zu doppeln.',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10.5,
              height: 1.65,
              color: p.fgFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Palette p, String text) => Text(
    text,
    style: TextStyle(
      fontFamily: Metrics.mono,
      fontSize: 11,
      height: 1.7,
      color: p.fgDim,
    ),
  );
}

/// Ein nummerierter Schritt innerhalb des kostenlosen Weges.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.action,
  });

  final int number;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              color: p.fg,
              child: Text(
                '$number',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: p.bg,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: Metrics.trackWider,
                  height: 1.5,
                  color: p.fg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          body,
          style: TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 10.5,
            height: 1.7,
            color: p.fgDim,
          ),
        ),
        const SizedBox(height: 13),
        action,
      ],
    );
  }
}
