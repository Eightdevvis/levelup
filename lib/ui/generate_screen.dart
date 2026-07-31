import 'dart:async';

import 'package:flutter/material.dart';

import '../data/claude_client.dart';
import '../main.dart';
import '../model/library.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Plan direkt in der App erzeugen lassen.
///
/// Der Weg über Kopieren und Einfügen bleibt daneben bestehen — er kostet
/// nichts und braucht keinen Schlüssel. Dieser hier ist der bequeme.
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key, this.clientFactory});

  /// Nur für Tests: einen Client mit vorgegebenen Antworten einsetzen.
  final ClaudeClient Function(String apiKey)? clientFactory;

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _request = TextEditingController();
  StreamSubscription<PlanEvent>? _run;

  String? _thinking;
  int _chars = 0;
  String? _error;
  PlanUsage? _usage;

  bool get _running => _run != null;

  @override
  void dispose() {
    _run?.cancel();
    _request.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final state = AppScope.of(context);
    final key = state.apiKey;
    if (key == null) {
      setState(() => _error = 'Kein API-Schlüssel hinterlegt.');
      return;
    }

    setState(() {
      _error = null;
      _thinking = null;
      _usage = null;
      _chars = 0;
    });

    final client = (widget.clientFactory ?? (k) => ClaudeClient(apiKey: k))(
      key,
    );
    final sub = client
        .generatePlan(_request.text)
        .listen(
          (event) {
            if (!mounted) return;
            switch (event) {
              case PlanThinking(:final text):
                setState(() => _thinking = text);
              case PlanWriting(:final chars):
                setState(() => _chars = chars);
              case PlanDone(:final bundle, :final usage):
                setState(() => _usage = usage);
                _install(bundle, usage);
            }
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error = '$e';
              _run = null;
            });
          },
          onDone: () {
            if (mounted) setState(() => _run = null);
          },
          cancelOnError: true,
        );

    setState(() => _run = sub);
  }

  Future<void> _install(Bundle bundle, PlanUsage usage) async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await state.installBundle(bundle);
    if (!mounted) return;

    final program = bundle.programs.isEmpty ? null : bundle.programs.first;
    messenger.showSnackBar(
      SnackBar(content: Text('// PLAN ERZEUGT · ${usage.describe()}')),
    );
    if (program == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(programId: program.id),
      ),
    );
  }

  void _cancel() {
    _run?.cancel();
    setState(() => _run = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final state = AppScope.of(context);

    if (!state.hasApiKey) {
      return Scaffold(
        appBar: AppBar(title: const Text('PLAN ERZEUGEN')),
        body: EmptyState(
          icon: Icons.key_outlined,
          title: 'kein schlüssel',
          message:
              'Für die direkte Erzeugung braucht die App einen '
              'Anthropic-API-Schlüssel. Ohne ihn bleibt der Weg über '
              'Prompt kopieren und JSON einfügen.',
          action: OutlinedButton(
            onPressed: () => _askForKey(context),
            child: const Text('SCHLÜSSEL EINTRAGEN'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAN ERZEUGEN'),
        actions: [
          IconButton(
            tooltip: 'Schlüssel ändern',
            icon: Icon(Icons.key_outlined, color: p.fgDim),
            onPressed: () => _askForKey(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 40),
        children: [
          Text(
            'Beschreib, was du erreichen willst und wo es klemmt. Je genauer '
            'das Problem, desto besser die Diagnose — Claude stellt den Plan '
            'auf die Ursache ab, nicht auf das Symptom.',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11,
              height: 1.65,
              color: p.fgDim,
            ),
          ),
          const SectionLabel('dein anliegen'),
          TextField(
            controller: _request,
            minLines: 5,
            maxLines: 12,
            enabled: !_running,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11.5,
              height: 1.6,
              color: p.fg,
            ),
            decoration: const InputDecoration(
              hintText:
                  'Ich spiele gut Geige, kann aber Bach nicht vom Blatt '
                  'lesen. Zwölf Wochen, etwa 45 Minuten am Tag.',
            ),
          ),
          const SizedBox(height: 14),
          if (_running)
            OutlinedButton(onPressed: _cancel, child: const Text('ABBRECHEN'))
          else
            FilledButton(onPressed: _start, child: const Text('PLAN ERZEUGEN')),
          if (_running || _thinking != null || _error != null) ...[
            const SectionLabel('verlauf'),
            _Progress(
              running: _running,
              thinking: _thinking,
              chars: _chars,
              usage: _usage,
              error: _error,
            ),
          ],
          const SectionLabel('kosten'),
          Text(
            'Läuft über deinen eigenen Schlüssel und wird direkt bei Anthropic '
            'abgerechnet. Ein vollständiger Plan kostet je nach Länge grob '
            '20 bis 50 Cent — das Denken macht den größten Teil aus. Die '
            'tatsächlichen Kosten stehen nach jedem Lauf oben im Verlauf.',
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

  Future<void> _askForKey(BuildContext context) async {
    final state = AppScope.of(context);
    final controller = TextEditingController(text: state.apiKey ?? '');

    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('API-SCHLÜSSEL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aus der Anthropic-Konsole. Wird im Klartext im App-Speicher '
              'abgelegt.',
              style: TextStyle(fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'sk-ant-...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('LÖSCHEN'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('SPEICHERN'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (key == null) return;
    await state.setApiKey(key);
    if (mounted) setState(() {});
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.running,
    required this.thinking,
    required this.chars,
    required this.usage,
    required this.error,
  });

  final bool running;
  final String? thinking;
  final int chars;
  final PlanUsage? usage;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final failed = error != null;

    return ZBox(
      title: failed
          ? 'fehlgeschlagen'
          : running
          ? (chars > 0 ? 'schreibt' : 'denkt')
          : 'fertig',
      trailing: usage?.describe(),
      accent: failed ? p.error : p.accent,
      filled: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed)
            Text(
              error!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11,
                height: 1.6,
                color: p.error,
              ),
            )
          else ...[
            if (thinking != null && thinking!.isNotEmpty)
              Text(
                thinking!,
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                  color: p.fgDim,
                ),
              ),
            if (chars > 0) ...[
              if (thinking != null) const SizedBox(height: 10),
              Text(
                '$chars ZEICHEN PLAN',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 9.5,
                  letterSpacing: 1.3,
                  color: p.fgFaint,
                ),
              ),
            ],
          ],
          if (running) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}
