import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/plan_service.dart';
import '../main.dart';
import '../model/library.dart';
import '../model/patch.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Plan direkt in der App erzeugen lassen.
///
/// Der Ablauf hat bewusst einen Halt in der Mitte: der fertige Plan wird
/// vorgelegt, nicht eingebaut. Erst wer ihn annimmt, hat ihn in seiner
/// Bibliothek — und erst dann wandert er in die geteilte. Wer etwas anders
/// will, sagt es und bekommt eine Überarbeitung, die nur ändert, wovon die
/// Rede war.
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key, this.serviceFactory, this.registrar});

  /// Nur für Tests: einen Dienst mit vorgegebenen Antworten einsetzen.
  final PlanService Function(String token)? serviceFactory;

  /// Nur für Tests: die Geräteanmeldung ersetzen.
  final Future<String> Function()? registrar;

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _request = TextEditingController();
  final _feedback = TextEditingController();
  StreamSubscription<PlanEvent>? _run;

  String? _thinking;
  final _searches = <String>[];
  int _chars = 0;
  String? _error;
  Quota? _quota;
  bool _connecting = true;
  String? _connectError;

  /// Der vorgelegte, noch nicht angenommene Plan.
  Bundle? _draft;
  List<String> _reused = const [];
  List<String> _skipped = const [];
  bool _accepting = false;

  bool get _running => _run != null;

  @override
  void initState() {
    super.initState();
    // Erst nach dem ersten Frame: vorher gibt es kein AppScope im Kontext.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _run?.cancel();
    _request.dispose();
    _feedback.dispose();
    super.dispose();
  }

  PlanService _service(String token) =>
      (widget.serviceFactory ??
          (t) => PlanService(baseUrl: PlanService.defaultBaseUrl, token: t))(
        token,
      );

  /// Gerät anmelden (falls nötig) und das Kontingent holen.
  Future<void> _connect() async {
    if (!mounted) return;
    final state = AppScope.of(context);
    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      var token = state.deviceToken;
      if (token == null) {
        token = await (widget.registrar ?? _register)();
        await state.setDeviceToken(token);
      }
      final quota = await _service(token).quota();
      if (!mounted) return;
      setState(() {
        _quota = quota;
        _connecting = false;
      });
    } on PlanException catch (e) {
      if (!mounted) return;
      setState(() {
        _connectError = e.message;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectError = 'Verbindung fehlgeschlagen: $e';
        _connecting = false;
      });
    }
  }

  static Future<String> _register() => PlanService.register(
    baseUrl: PlanService.defaultBaseUrl,
    platform: defaultTargetPlatform.name,
  );

  /// Hört einen Lauf ab — Erzeugen und Überarbeiten unterscheiden sich nur im
  /// Strom, den sie liefern.
  void _listen(Stream<PlanEvent> stream) {
    setState(() {
      _error = null;
      _thinking = null;
      _searches.clear();
      _skipped = const [];
      _chars = 0;
    });

    final sub = stream.listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case PlanThinking(:final text):
            setState(() => _thinking = text);
          case PlanWriting(:final chars):
            setState(() => _chars = chars);
          case PlanSearching():
            setState(() => _searches.add(event.describe()));
          case PlanDone(:final bundle, :final reused):
            setState(() {
              _draft = bundle;
              _reused = reused;
            });
          case PlanRevised(:final patch):
            _applyRevision(patch);
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

  void _start() {
    final token = AppScope.of(context).deviceToken;
    if (token == null) {
      unawaited(_connect());
      return;
    }
    _listen(_service(token).generatePlan(_request.text));
  }

  void _revise() {
    final token = AppScope.of(context).deviceToken;
    final draft = _draft;
    if (token == null || draft == null) return;
    _listen(_service(token).revisePlan(draft, _feedback.text));
  }

  void _applyRevision(PlanPatch patch) {
    final draft = _draft;
    if (draft == null) return;
    final result = applyPatch(draft, patch);
    setState(() {
      _draft = result.bundle;
      _skipped = result.skipped;
      _feedback.clear();
    });
    // Eine Überarbeitung verbraucht einen Lauf.
    unawaited(_refreshQuota());
  }

  Future<void> _accept() async {
    final draft = _draft;
    final state = AppScope.of(context);
    final token = state.deviceToken;
    if (draft == null || token == null) return;

    setState(() => _accepting = true);
    final messenger = ScaffoldMessenger.of(context);

    await state.installBundle(draft);

    // Das Teilen darf nicht darüber entscheiden, ob der Nutzer seinen Plan
    // bekommt — er liegt schon in seiner Bibliothek. Geht es schief, ist das
    // eine Randnotiz, kein Fehler.
    var shared = true;
    try {
      await _service(token).acceptPlan(draft);
    } on Exception {
      shared = false;
    }

    if (!mounted) return;
    setState(() => _accepting = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? '// ANGENOMMEN · ÜBUNGEN IN DIE OFFENE BIBLIOTHEK'
              : '// ANGENOMMEN · TEILEN HAT NICHT GEKLAPPT',
        ),
      ),
    );

    final program = draft.programs.isEmpty ? null : draft.programs.first;
    if (program == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(programId: program.id),
      ),
    );
    if (mounted) setState(() => _draft = null);
  }

  void _discard() {
    setState(() {
      _draft = null;
      _reused = const [];
      _skipped = const [];
      _feedback.clear();
    });
  }

  Future<void> _refreshQuota() async {
    final token = AppScope.of(context).deviceToken;
    if (token == null) return;
    try {
      final quota = await _service(token).quota();
      if (mounted) setState(() => _quota = quota);
    } on Exception {
      // Der Zählerstand ist Beiwerk; ein Fehler hier darf nichts kippen.
    }
  }

  void _cancel() {
    _run?.cancel();
    setState(() => _run = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    if (_connecting) {
      return Scaffold(
        appBar: AppBar(title: const Text('PLAN ERZEUGEN')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_connectError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PLAN ERZEUGEN')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'nicht verbunden',
          message: _connectError!,
          action: OutlinedButton(
            onPressed: _connect,
            child: const Text('NOCHMAL VERSUCHEN'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_draft == null ? 'PLAN ERZEUGEN' : 'PLAN PRÜFEN'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 40),
        children: _draft == null ? _askView(p) : _reviewView(p, _draft!),
      ),
    );
  }

  // -- Anliegen beschreiben --------------------------------------------------

  List<Widget> _askView(Palette p) {
    final quota = _quota;
    final exhausted = quota != null && quota.exhausted;

    return [
      Text(
        'Beschreib, was du erreichen willst und wo es klemmt. Je genauer das '
        'Problem, desto besser die Diagnose — der Plan stellt auf die Ursache '
        'ab, nicht auf das Symptom.',
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
        enabled: !_running && !exhausted,
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 11.5,
          height: 1.6,
          color: p.fg,
        ),
        decoration: const InputDecoration(
          hintText:
              'Ich spiele gut Geige, kann aber Bach nicht vom Blatt lesen. '
              'Zwölf Wochen, etwa 45 Minuten am Tag.',
        ),
      ),
      const SizedBox(height: 14),
      if (_running)
        OutlinedButton(onPressed: _cancel, child: const Text('ABBRECHEN'))
      else
        FilledButton(
          onPressed: exhausted ? null : _start,
          child: const Text('PLAN ERZEUGEN'),
        ),
      ..._progressSection(p),
      const SectionLabel('kontingent'),
      _QuotaBox(quota: quota),
    ];
  }

  // -- Plan prüfen -----------------------------------------------------------

  List<Widget> _reviewView(Palette p, Bundle draft) {
    final program = draft.programs.isEmpty ? null : draft.programs.first;
    final note = draft.personalNote;

    return [
      if (note != null) ...[
        ZBox(
          title: 'für dich',
          filled: true,
          child: Text(
            note,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11,
              height: 1.7,
              color: p.fg,
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
      const SectionLabel('vorschlag'),
      if (program != null)
        ZBox(
          title: 'plan',
          trailing:
              '${program.phases.fold<int>(0, (s, ph) => s + ph.weeks)}W',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program.name,
                style: TextStyle(
                  fontFamily: Metrics.display,
                  fontSize: 23,
                  height: 1.15,
                  color: p.fg,
                ),
              ),
              if (program.description != null) ...[
                const SizedBox(height: 9),
                Text(
                  program.description!,
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 10.5,
                    height: 1.65,
                    color: p.fgDim,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final phase in program.phases)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· ${phase.name} — ${phase.weeks}W',
                    style: TextStyle(
                      fontFamily: Metrics.mono,
                      fontSize: 10.5,
                      height: 1.5,
                      color: p.fgDim,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '${draft.exercises.length} ÜBUNGEN · '
                '${draft.routines.length} LISTEN'
                '${_reused.isEmpty ? "" : " · ${_reused.length} ÜBERNOMMEN"}',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  color: p.fgFaint,
                ),
              ),
            ],
          ),
        ),
      if (_skipped.isNotEmpty) ...[
        const SectionLabel('nicht umgesetzt'),
        ZBox(
          title: 'übersprungen',
          accent: p.error,
          filled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in _skipped)
                Text(
                  '· $line',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 10,
                    height: 1.6,
                    color: p.error,
                  ),
                ),
            ],
          ),
        ),
      ],
      const SectionLabel('einspruch'),
      Text(
        'Passt etwas nicht? Sag es, und es wird geändert — nur das. Alles '
        'andere bleibt so, wie es hier steht.',
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 10.5,
          height: 1.65,
          color: p.fgDim,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _feedback,
        minLines: 3,
        maxLines: 8,
        enabled: !_running && !_accepting,
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 11.5,
          height: 1.6,
          color: p.fg,
        ),
        decoration: const InputDecoration(
          hintText:
              'Die Fingerübungen sind mir zu viel. Und Phase 2 darf länger '
              'sein.',
        ),
      ),
      const SizedBox(height: 12),
      if (_running)
        OutlinedButton(onPressed: _cancel, child: const Text('ABBRECHEN'))
      else
        OutlinedButton(
          onPressed: _accepting ? null : _revise,
          child: const Text('ÜBERARBEITEN'),
        ),
      ..._progressSection(p),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _running || _accepting ? null : _accept,
        child: Text(_accepting ? 'WIRD ÜBERNOMMEN…' : 'ANNEHMEN'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _running || _accepting ? null : _discard,
        child: const Text('VERWERFEN'),
      ),
      const SectionLabel('kontingent'),
      _QuotaBox(quota: _quota),
    ];
  }

  List<Widget> _progressSection(Palette p) {
    if (!_running && _thinking == null && _error == null) return const [];
    return [
      const SectionLabel('verlauf'),
      _Progress(
        running: _running,
        thinking: _thinking,
        searches: _searches,
        chars: _chars,
        error: _error,
      ),
    ];
  }
}

class _QuotaBox extends StatelessWidget {
  const _QuotaBox({required this.quota});

  final Quota? quota;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final q = quota;

    final message = q == null
        ? 'Der Zählerstand ist gerade nicht bekannt.'
        : q.exhausted
        ? 'Dein Freikontingent ist aufgebraucht. Der Weg über Prompt kopieren '
              'und JSON einfügen bleibt offen und kostet nichts.'
        : 'Noch ${q.remaining} ${q.remaining == 1 ? "Lauf" : "Läufe"} frei, '
              'davon heute ${q.dailyRemaining}. Eine Überarbeitung zählt '
              'genauso wie eine Erzeugung. Abgerechnet wird nur, was auch '
              'ankommt — ein abgebrochener Lauf zählt nicht.';

    return ZBox(
      title: 'kontingent',
      trailing: q == null ? null : '${q.remaining} FREI',
      accent: q != null && q.exhausted ? p.error : p.accent,
      filled: false,
      child: Text(
        message,
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 10.5,
          height: 1.65,
          color: p.fgDim,
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.running,
    required this.thinking,
    required this.searches,
    required this.chars,
    required this.error,
  });

  final bool running;
  final String? thinking;
  final List<String> searches;
  final int chars;
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
            // Die Suchen sind das Sichtbarste am Wiederverwenden — sie zeigen,
            // dass nicht bei null angefangen wird.
            for (final line in searches) ...[
              const SizedBox(height: 8),
              Text(
                '→ $line',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10,
                  height: 1.5,
                  color: p.accent,
                ),
              ),
            ],
            if (chars > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$chars ZEICHEN',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
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
