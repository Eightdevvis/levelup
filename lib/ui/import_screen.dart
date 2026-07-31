import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_prompt.dart';
import '../main.dart';
import '../state/app_state.dart';
import 'generate_screen.dart';
import 'program_screen.dart';
import 'widgets.dart';

/// Der Weg von "ich hab ein Problem" zu "es steht als Plan in der App":
/// Prompt kopieren, in Claude einwerfen, Antwort hier einfügen.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  ImportResult? _result;
  bool _busy = false;

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
    final scheme = Theme.of(context).colorScheme;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Plan importieren')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _StepCard(
            step: 0,
            title: 'Claude direkt fragen',
            body:
                'Beschreib dein Anliegen, und die App holt den Plan selbst. '
                'Braucht einen eigenen API-Schlüssel und kostet pro Plan ein '
                'paar Cent. Ohne Schlüssel nimm die beiden Schritte darunter.',
            action: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GenerateScreen()),
              ),
              child: const Text('PLAN ERZEUGEN'),
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            step: 1,
            title: 'Prompt kopieren',
            body:
                'Enthält das komplette Format. In Claude einfügen und dahinter '
                'in eigenen Worten beschreiben, was du erreichen willst und wo '
                'es klemmt — je genauer das Problem, desto besser die Diagnose.',
            action: OutlinedButton.icon(
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Prompt in Zwischenablage'),
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: kAiPromptTemplate),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Prompt kopiert.')),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            step: 2,
            title: 'Antwort hier einfügen',
            body:
                'Das JSON aus der Antwort einfügen. Code-Zäune (```) dürfen '
                'drinbleiben, die werden entfernt.',
            action: Column(
              children: [
                TextField(
                  controller: _controller,
                  minLines: 6,
                  maxLines: 14,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: '{ "version": 1, "exercises": [ ... ] }',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.paste, size: 18),
                        label: const Text('Einfügen'),
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            setState(() => _controller.text = data!.text!);
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
                            : const Text('Importieren'),
                      ),
                    ),
                  ],
                ),
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
          SectionLabel('Format'),
          Text(
            'Importiert wird ein Bundle aus Übungen, Listen und Programmen. '
            'Übungen landen in der gemeinsamen Bibliothek und stehen danach '
            'jedem weiteren Plan zur Verfügung. Gleiche IDs werden ersetzt, '
            'ein erneuter Import aktualisiert also, statt zu doppeln.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.body,
    required this.action,
  });

  final int step;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    '$step',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}
